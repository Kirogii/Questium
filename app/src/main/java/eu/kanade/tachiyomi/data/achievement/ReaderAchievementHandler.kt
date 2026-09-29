package eu.kanade.tachiyomi.data.achievement

import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import eu.kanade.tachiyomi.ui.reader.setting.ReadingMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import tachiyomi.domain.achievement.service.AchievementManager
import tachiyomi.domain.achievement.service.RotatingAchievementPool
import java.util.Calendar

/**
 * Modular handler that encapsulates Reader -> Achievement mapping.
 *
 * Previously this logic was inlined in [eu.kanade.tachiyomi.ui.reader.ReaderViewModel]
 * with direct `achievementManager.tryUnlockDirect("rtl_reader")` string literals
 * scattered across the ViewModel, violating single-responsibility and making
 * testing impossible. This handler centralizes:
 * - organic chapter read counting
 * - reading-mode specific achievements (LTR/RTL/vertical)
 * - manga completion vs caught-up branching
 * - reading-time batching
 *
 * ViewModel delegates to this handler, enabling unit testing and keeping
 * achievement IDs out of the ViewModel.
 */
@SingleIn(AppScope::class)
@Inject
class ReaderAchievementHandler(
    private val achievementManager: AchievementManager,
    // KMK --> Injected rather than reached for through globalAppGraph, which is what the rest
    // of this class exists to avoid. Direction matters: the pool already depends on the manager,
    // so the manager must not depend back on the pool - the rotating marks belong at the call
    // site for that reason, not just for tidiness.
    private val rotatingPool: RotatingAchievementPool,
) {
    // KMK --> Own scope: starting a chapter is what pulls an entry out of the stale-unstarted
    // backlog, and the query has to leave the reader's call site. refreshBacklog throttles
    // itself, so a page turn cannot run a library query.
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun onChapterRead(readingModeFlag: Int) {
        try {
            achievementManager.onOrganicChapterRead(0)
            // KMK --> Day state first, so the streak tiers see today, then the per-day binge
            // count. Both are the only path to streak_*/binge_* - nothing else counts a read.
            runCatching { achievementManager.onReadingDay() }
            runCatching { achievementManager.incrementDailyCounter("binge") }
            onReadingDayMarked()
            // Local hour and minute, so "read past 3 AM" and the 11:30-13:30 noon window mean the
            // user's clock rather than UTC. Resolved here rather than passed in: every caller is
            // a chapter-read, and all of them want the same window.
            runCatching {
                val now = Calendar.getInstance()
                val hour = now.get(Calendar.HOUR_OF_DAY)
                val minute = now.get(Calendar.MINUTE)
                achievementManager.onChapterReadAtHour(hour, minute)
                // KMK --> Lunch is a rotating daily too, and the window is already computed here.
                if ((hour == 11 && minute >= 30) || hour == 12 || (hour == 13 && minute <= 30)) {
                    mark("rotating_daily_extra_11")
                }
                if (hour < 6) mark("rotating_daily_morning_read")
                if (hour in 0..3) mark("rotating_daily_midnight_read")
                if (hour >= 23 || hour < 3) mark("rotating_weekly_night_owl")
            }
            // KMK --> Read tiers. All off the one read event, so no extra tracking is needed.
            mark("rotating_daily_read_5")
            mark("rotating_daily_read_15")
            mark("rotating_weekly_read_30")
            mark("rotating_weekly_read_75")
            when (readingModeFlag) {
                ReadingMode.LEFT_TO_RIGHT.flagValue -> {
                    achievementManager.onLtrFinished()
                    mark("rotating_weekly_ltr_3")
                }
                ReadingMode.RIGHT_TO_LEFT.flagValue -> achievementManager.tryUnlockDirect("rtl_reader")
                ReadingMode.VERTICAL.flagValue,
                ReadingMode.WEBTOON.flagValue,
                ReadingMode.CONTINUOUS_VERTICAL.flagValue,
                -> {
                    achievementManager.tryUnlockDirect("vertical_reader")
                    if (readingModeFlag != ReadingMode.VERTICAL.flagValue) mark("rotating_daily_webtoon_5")
                }
            }
            // Pager double-page spreads are handled separately via PagerConfig,
            // WebGPU spreads via WebGpuViewer — keep out of this handler.
            // KMK --> Throttled: not every chapter read needs a library query.
            scope.launch { runCatching { achievementManager.refreshBacklog() } }
            // KMK <--
        } catch (_: Exception) {
        }
    }

    fun onDoublePageDisplayed() {
        try {
            achievementManager.tryUnlockDirect("double_page")
            mark("rotating_daily_extra_5")
        } catch (_: Exception) {
        }
    }

    fun onMangaCompleted(status: Long, totalChapters: Long = 0L) {
        try {
            val isPermanent = achievementManager.isPermanentStatus(status)
            if (isPermanent) {
                achievementManager.onMangaFinished()
            } else {
                achievementManager.onMangaCaughtUp()
                achievementManager.onBacklogCleared(1)
                mark("rotating_daily_backlog_clear_1")
                mark("rotating_weekly_extra_4")
            }
            // KMK --> Both completion paths count: the description is "complete 7 manga in 7
            // days", and only permanent ones were being routed before.
            runCatching { achievementManager.onMangaFinishedOnDay() }
            // Length tiers are about the series, not the finish, so they take the chapter count
            // rather than the status. 0 means the caller did not know it - no tiers fire.
            runCatching { achievementManager.onMangaCompletedWithCount(totalChapters) }
            mark("rotating_daily_finish_1")
            mark("rotating_weekly_finish_3")
            if (totalChapters == 1L) mark("rotating_daily_extra_1")
            if (totalChapters >= 50L) mark("rotating_weekly_extra_10")
        } catch (_: Exception) {
        }
    }

    fun onReadingTimeMinutes(minutes: Long) {
        try {
            if (minutes > 0) achievementManager.onReadingTimeMinutes(minutes)
            // KMK --> The weekly tier is five hours, and the counter is in minutes, so this
            // advances by the amount read rather than one tick per call.
            if (minutes > 0) rotatingPool.markProgress("rotating_weekly_extra_7", minutes.toInt())
        } catch (_: Exception) {
        }
    }

    /** Counts the day a chapter was read, for the tiers that measure days rather than reads. */
    fun onReadingDayMarked() {
        markOnce("rotating_daily_streak_bonus")
        markOnce("rotating_weekly_extra_5")
    }

    private fun mark(id: String) {
        runCatching { rotatingPool.markProgress(id) }
    }

    private fun markOnce(id: String) {
        runCatching { rotatingPool.markOncePerDay(id) }
    }
}
