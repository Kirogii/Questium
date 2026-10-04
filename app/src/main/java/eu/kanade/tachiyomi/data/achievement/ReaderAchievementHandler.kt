package eu.kanade.tachiyomi.data.achievement

import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import eu.kanade.tachiyomi.ui.reader.setting.ReadingMode
import exh.log.xLogE
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import tachiyomi.domain.achievement.service.AchievementManager
import tachiyomi.domain.achievement.service.RotatingAchievementPool
import java.util.Calendar

/**
 * The single place where "something happened in the reader" becomes "advance the
 * achievement counters", keeping achievement ids out of [eu.kanade.tachiyomi.ui.reader.ReaderViewModel].
 *
 * Every step is guarded individually. The previous version wrapped each whole handler in one
 * `try { ... } catch (_: Exception) {}`, which meant a single failure - a preferences backend
 * error, a malformed counter name - silently discarded every step after it in the same event.
 * A chapter read could therefore count the chapter and lose the streak, the binge tier and
 * the reading-mode achievement together, with nothing logged.
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

    fun onChapterRead(readingModeFlag: Int, incognito: Boolean = false) {
        step("organic read") { achievementManager.onOrganicChapterRead(0) }
        if (incognito) {
            step("incognito read") { achievementManager.incrementCounter("incognito_reads") }
            mark("rotating_daily_extra_4")
        }
        // KMK --> Day state first, so the streak tiers see today, then the per-day binge count.
        // Both are the only path to streak_*/binge_* - nothing else counts a read.
        step("reading day") { achievementManager.onReadingDay() }
        step("binge") { achievementManager.incrementDailyCounter("binge") }
        step("rotating day marks") { onReadingDayMarked() }

        // Local hour and minute, so "read past 3 AM" and the 11:30-13:30 noon window mean the
        // user's clock rather than UTC. Resolved here rather than passed in: every caller is a
        // chapter read, and all of them want the same window.
        val now = Calendar.getInstance()
        val hour = now.get(Calendar.HOUR_OF_DAY)
        val minute = now.get(Calendar.MINUTE)
        step("time-of-day tiers") { achievementManager.onChapterReadAtHour(hour, minute) }
        if ((hour == 11 && minute >= 30) || hour == 12 || (hour == 13 && minute <= 30)) {
            mark("rotating_daily_extra_11")
        }
        if (hour < 6) mark("rotating_daily_morning_read")
        if (hour in 0..3) mark("rotating_daily_midnight_read")
        if (hour >= 23 || hour < 3) mark("rotating_weekly_night_owl")

        // Read tiers, all off the one read event, so no extra tracking is needed.
        mark("rotating_daily_read_5")
        mark("rotating_daily_read_15")
        mark("rotating_weekly_read_30")
        mark("rotating_weekly_read_75")

        when (readingModeFlag) {
            ReadingMode.LEFT_TO_RIGHT.flagValue -> {
                step("ltr finished") { achievementManager.onLtrFinished() }
                mark("rotating_weekly_ltr_3")
            }
            ReadingMode.RIGHT_TO_LEFT.flagValue -> step("rtl reader") {
                achievementManager.tryUnlockDirect("rtl_reader")
            }
            ReadingMode.VERTICAL.flagValue,
            ReadingMode.WEBTOON.flagValue,
            ReadingMode.CONTINUOUS_VERTICAL.flagValue,
            -> {
                step("vertical reader") { achievementManager.tryUnlockDirect("vertical_reader") }
                if (readingModeFlag != ReadingMode.VERTICAL.flagValue) mark("rotating_daily_webtoon_5")
            }
        }

        // Pager double-page spreads are handled separately via PagerConfig,
        // WebGPU spreads via WebGpuViewer — keep out of this handler.
        scope.launch { runCatching { achievementManager.refreshBacklog() } }
    }

    fun onDoublePageDisplayed() {
        step("double page") { achievementManager.tryUnlockDirect("double_page") }
        mark("rotating_daily_extra_5")
    }

    fun onMangaCompleted(status: Long, totalChapters: Long = 0L) {
        // KMK --> Both branches count a cleared backlog entry themselves: onMangaFinished and
        // onMangaCaughtUp each end in onBacklogClearedQuiet(). Calling onBacklogCleared(1) here
        // as well used to be *how* the count happened; leaving it in after that refactor
        // incremented the lifetime counter twice per completed manga and re-created the second
        // toast batch the composition was meant to eliminate.
        step("manga completion") {
            if (achievementManager.isPermanentStatus(status)) {
                achievementManager.onMangaFinished()
            } else {
                achievementManager.onMangaCaughtUp()
                mark("rotating_daily_backlog_clear_1")
                mark("rotating_weekly_extra_4")
            }
        }
        // KMK --> Both completion paths count: the description is "complete 7 manga in 7 days",
        // and only permanent ones were being routed before.
        step("finished-on-day") { achievementManager.onMangaFinishedOnDay() }
        // Length tiers are about the series, not the finish, so they take the chapter count
        // rather than the status. 0 means the caller did not know it - no tiers fire.
        step("completion length tiers") { achievementManager.onMangaCompletedWithCount(totalChapters) }
        mark("rotating_daily_finish_1")
        mark("rotating_weekly_finish_3")
        if (totalChapters == 1L) mark("rotating_daily_extra_1")
        if (totalChapters >= 50L) mark("rotating_weekly_extra_10")
    }

    fun onReadingTimeMinutes(minutes: Long) {
        if (minutes <= 0) return
        step("reading time") { achievementManager.onReadingTimeMinutes(minutes) }
        // KMK --> The weekly tier is five hours and the counter is in minutes, so this advances
        // by the amount read rather than one tick per call.
        mark("rotating_weekly_extra_7", minutes.toInt())
    }

    /** Counts the day a chapter was read, for the tiers that measure days rather than reads. */
    fun onReadingDayMarked() {
        markOnce("rotating_daily_streak_bonus")
        markOnce("rotating_weekly_extra_5")
    }

    private inline fun step(name: String, block: () -> Unit) {
        runCatching(block).onFailure { xLogE("Achievement step failed: $name", it) }
    }

    private fun mark(id: String, progress: Int = 1) {
        runCatching { rotatingPool.markProgress(id, progress) }
            .onFailure { xLogE("Rotating achievement mark failed: $id", it) }
    }

    private fun markOnce(id: String) {
        runCatching { rotatingPool.markOncePerDay(id) }
            .onFailure { xLogE("Rotating daily mark failed: $id", it) }
    }
}
