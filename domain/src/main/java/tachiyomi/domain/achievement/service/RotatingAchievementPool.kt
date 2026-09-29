package tachiyomi.domain.achievement.service

import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import tachiyomi.domain.achievement.model.Achievement
import tachiyomi.domain.achievement.model.Achievements
import java.util.concurrent.TimeUnit
import kotlin.random.Random

@SingleIn(AppScope::class)
@Inject
class RotatingAchievementPool(
    private val prefs: AchievementPreferences,
    private val manager: AchievementManager,
) {
    fun getActiveDaily(): List<Achievement> {
        val now = System.currentTimeMillis()
        val epoch = TimeUnit.MILLISECONDS.toDays(now)
        val storedEpoch = prefs.rotatingLastDailyEpoch().get()
        val storedIds = prefs.rotatingDailyIds().get()
        if (storedEpoch == epoch && storedIds.isNotBlank()) {
            return storedIds.split(",").mapNotNull { Achievements.forId(it.trim()) }
        }
        val pool = Achievements.rotating.filter { it.id.startsWith("rotating_daily") }
        val unlocked = prefs.getUnlockedIds()
        val available = pool.filter { it.id !in unlocked }
        val candidates = if (available.size >= 3) available else pool
        val selected = candidates.shuffled(Random(epoch)).take(3)
        prefs.rotatingLastDailyEpoch().set(epoch)
        prefs.rotatingDailyIds().set(selected.joinToString(",") { it.id })
        pruneProgress()
        return selected
    }

    fun getActiveWeekly(): List<Achievement> {
        val now = System.currentTimeMillis()
        val epoch = TimeUnit.MILLISECONDS.toDays(now) / 7
        val storedEpoch = prefs.rotatingLastWeeklyEpoch().get()
        val storedIds = prefs.rotatingWeeklyIds().get()
        if (storedEpoch == epoch && storedIds.isNotBlank()) {
            return storedIds.split(",").mapNotNull { Achievements.forId(it.trim()) }
        }
        val pool = Achievements.rotating.filter { it.id.startsWith("rotating_weekly") }
        val unlocked = prefs.getUnlockedIds()
        val available = pool.filter { it.id !in unlocked }
        val candidates = if (available.size >= 4) available else pool
        val selected = candidates.shuffled(Random(epoch + 1000)).take(4)
        prefs.rotatingLastWeeklyEpoch().set(epoch)
        prefs.rotatingWeeklyIds().set(selected.joinToString(",") { it.id })
        pruneProgress()
        return selected
    }

    /**
     * Drops progress for ids that are no longer in either period's active set. Rotating progress
     * is keyed per achievement id, so without this a count earned in one period is still sitting
     * there when the same id comes back around and the bar starts part-finished.
     *
     * Keeps the union of the stored daily and weekly sets, so it is safe whichever period's
     * getter triggered it - pruning on the daily set alone would wipe the weekly progress.
     * Only called from an epoch rollover, after the caller's own ids have been stored.
     */
    private fun pruneProgress() {
        val raw = prefs.rotatingProgress().get()
        if (raw.isBlank()) return
        val kept = parseProgress(raw).filterKeys { it in activeIds() }
        if (kept.size != parseProgress(raw).size) {
            prefs.rotatingProgress().set(kept.entries.joinToString(",") { "${it.key}:${it.value}" })
        }
    }

    private fun parseProgress(raw: String): Map<String, Int> =
        raw.splitToSequence(',')
            .mapNotNull { entry ->
                val id = entry.substringBefore(':').trim()
                val value = entry.substringAfter(':', "").trim().toIntOrNull()
                if (id.isEmpty() || value == null) null else id to value
            }
            .toMap()

    fun getAllActive(): List<Achievement> = getActiveDaily() + getActiveWeekly()

    fun markProgress(id: String, progress: Int = 1) {
        val ach = Achievements.forId(id) ?: return
        if (!ach.isRotating) return
        if (prefs.getUnlockedIds().contains(id)) return
        val raw = prefs.rotatingProgress().get()
        val map = parseProgress(raw).toMutableMap()
        val cur = (map[id] ?: 0) + progress
        map[id] = cur
        prefs.rotatingProgress().set(map.entries.joinToString(",") { "${it.key}:${it.value}" })
        val threshold = rotatingThreshold(id)
        if (cur >= threshold) {
            manager.tryUnlockDirect(id)
            map.remove(id)
            prefs.rotatingProgress().set(map.entries.joinToString(",") { "${it.key}:${it.value}" })
        }
    }

    fun getProgress(id: String): Int = parseProgress(prefs.rotatingProgress().get())[id] ?: 0

    /**
     * Marks [id] at most once per calendar day, for tiers that count days rather than events.
     * A plain [markProgress] here would let a single sitting fill a seven-day tier.
     */
    @Synchronized
    fun markOncePerDay(id: String) {
        val epoch = TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis())
        val stamps = parseDayStamps(prefs.rotatingDayStamps().get()).toMutableMap()
        if (stamps[id] == epoch) return
        stamps[id] = epoch
        val kept = stamps.filterKeys { it in activeIds() }
        prefs.rotatingDayStamps().set(kept.entries.joinToString(",") { "${it.key}:${it.value}" })
        markProgress(id)
    }

    private fun parseDayStamps(raw: String): Map<String, Long> =
        raw.splitToSequence(',')
            .mapNotNull { entry ->
                val key = entry.substringBefore(':').trim()
                val day = entry.substringAfter(':', "").trim().toLongOrNull()
                if (key.isEmpty() || day == null) null else key to day
            }
            .toMap()

    private fun activeIds(): Set<String> =
        (prefs.rotatingDailyIds().get() + ',' + prefs.rotatingWeeklyIds().get())
            .splitToSequence(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()

    private fun rotatingThreshold(id: String): Int = when (id) {
        "rotating_daily_read_15" -> 15
        "rotating_weekly_read_30" -> 30
        "rotating_weekly_read_75" -> 75
        "rotating_weekly_library_10" -> 10
        "rotating_weekly_finish_3" -> 3
        "rotating_weekly_translate_10" -> 10
        "rotating_weekly_upscale_20" -> 20
        "rotating_weekly_data_saver_20" -> 20
        "rotating_daily_tracker_update_3" -> 3
        "rotating_weekly_tracker_5" -> 5
        "rotating_weekly_night_owl" -> 3
        "rotating_weekly_reread_2" -> 2
        "rotating_weekly_ltr_3" -> 3
        "rotating_weekly_category_2" -> 2
        "rotating_weekly_upload_cover_3" -> 3
        "rotating_weekly_backup" -> 1
        "rotating_daily_extra_4" -> 2
        "rotating_daily_extra_10" -> 10
        "rotating_weekly_extra_4" -> 5
        "rotating_weekly_extra_5" -> 7
        "rotating_weekly_extra_6" -> 2
        "rotating_weekly_extra_7" -> 300
        "rotating_weekly_extra_8" -> 15
        "rotating_daily_read_5",
        "rotating_daily_library_add_3",
        "rotating_daily_translate_2",
        "rotating_daily_search_5",
        "rotating_daily_finish_1",
        "rotating_daily_backlog_clear_1",
        "rotating_daily_morning_read",
        "rotating_daily_midnight_read",
        "rotating_daily_streak_bonus",
        "rotating_daily_webtoon_5",
        "rotating_daily_data_saver_5",
        "rotating_daily_genre_explore",
        "rotating_daily_extra_1",
        "rotating_daily_extra_2",
        "rotating_daily_extra_3",
        "rotating_daily_extra_4",
        "rotating_daily_extra_5",
        "rotating_daily_extra_6",
        "rotating_daily_extra_7",
        "rotating_daily_extra_8",
        "rotating_daily_extra_9",
        "rotating_daily_extra_10",
        "rotating_daily_extra_11",
        "rotating_weekly_extra_1",
        "rotating_weekly_extra_2",
        -> 1
        else -> when {
            id.endsWith("_read_5") -> 5
            id.endsWith("_read_15") -> 15
            id.endsWith("_read_30") -> 30
            id.endsWith("_read_75") -> 75
            id.endsWith("_translate_10") -> 10
            id.endsWith("_translate_2") -> 2
            id.contains("upscale_20") -> 20
            id.contains("data_saver_20") -> 20
            else -> 1
        }
    }

    fun refreshIfNeeded() {
        getActiveDaily()
        getActiveWeekly()
    }
}
