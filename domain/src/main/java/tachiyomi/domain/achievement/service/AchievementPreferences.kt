package tachiyomi.domain.achievement.service

import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import tachiyomi.core.common.preference.PreferenceStore
import tachiyomi.domain.achievement.model.Achievements

@SingleIn(AppScope::class)
@Inject
class AchievementPreferences(
    private val preferenceStore: PreferenceStore,
) {
    // KMK --> Longest streak tier is 100, so 200 days of history covers it with slack and keeps
    // the stored list small.
    private companion object {
        const val READING_DAY_WINDOW = 200
    }
    fun achievementsEnabled() = preferenceStore.getBoolean("pref_achievements_enabled", true)
    fun achievementToastsEnabled() = preferenceStore.getBoolean("pref_achievement_toasts_enabled", true)
    fun achievementSoundsEnabled() = preferenceStore.getBoolean("pref_achievement_sounds_enabled", false)

    fun unlockedAchievements() = preferenceStore.getString("pref_unlocked_achievements", "")
    fun organicChaptersRead() = preferenceStore.getLong("pref_organic_chapters_read", 0)
    fun mangaFinishedCount() = preferenceStore.getLong("pref_achievement_manga_finished", 0)
    fun mangaCaughtUpCount() = preferenceStore.getLong("pref_achievement_manga_caught_up", 0)
    fun libraryMangaCount() = preferenceStore.getLong("pref_achievement_library_count", 0)
    fun achievementsData() = preferenceStore.getString("pref_achievements_data", "")
    fun unlockedTimestamps() = preferenceStore.getString("pref_achievement_timestamps", "")
    fun totalReadingTimeMinutes() = preferenceStore.getLong("pref_achievement_reading_time_minutes", 0)
    fun backlogClearedCount() = preferenceStore.getLong("pref_achievement_backlog_cleared", 0)
    // KMK --> Cached because computeStats is synchronous and the count needs a library query;
    // AchievementManager.refreshBacklog owns writing it.
    fun staleUnstartedCount() = preferenceStore.getLong("pref_achievement_stale_unstarted", 0)
    fun backlogLastRefresh() = preferenceStore.getLong("pref_achievement_backlog_refresh", 0)
    // KMK <--
    // KMK --> Day epochs (UTC) on which a chapter was read, comma separated, oldest first.
    // Bounded to the trailing window the longest streak needs, so it cannot grow without limit.
    fun readingDays() = preferenceStore.getString("pref_achievement_reading_days", "")

    // Direction-switch streak for the flip-phone secret: the last direction and its run length.
    fun directionStreakDir() = preferenceStore.getInt("pref_achievement_dir_streak_dir", -1)
    fun directionStreakCount() = preferenceStore.getInt("pref_achievement_dir_streak_count", 0)

    @Synchronized
    fun markReadingDay(epochDay: Long) {
        val days = readDays()
        if (days.contains(epochDay)) return
        val updated = (days + epochDay).sorted().takeLast(READING_DAY_WINDOW)
        readingDays().set(updated.joinToString(","))
    }

    fun readDays(): List<Long> =
        readingDays().get().split(",").mapNotNull { it.trim().toLongOrNull() }

    // Chapters read in the current Sat+Sun window, and the Saturday's epoch day as the key. Both
    // reset together, so a new weekend starts from zero without a scheduled cleanup.
    fun weekendReadKey() = preferenceStore.getLong("pref_achievement_weekend_key", 0L)
    fun weekendReadCount() = preferenceStore.getLong("pref_achievement_weekend_count", 0L)

    /**
     * Named lifetime counter, keyed off a shared prefix so a new counter needs no accessor.
     * Only the names in AchievementManager.COUNTER_TIERS are read; anything else is ignored.
     */
    fun counter(name: String) = preferenceStore.getLong("pref_achievement_ctr_$name", 0)

    /** Day-stamped counters (binge) reset when [dayEpoch] no longer matches the stored one. */
    fun dailyCounter(name: String) = preferenceStore.getLong("pref_achievement_day_$name", 0)
    fun dailyCounterDay() = preferenceStore.getLong("pref_achievement_day_epoch", 0)

    @Synchronized
    fun incrementCounter(name: String, amount: Int = 1) {
        if (amount <= 0) return
        val cur = counter(name).get()
        if (cur < 10_000_000L) counter(name).set(cur + amount)
    }

    /**
     * Returns the day's count, resetting first when the stored day is not [dayEpoch]. Returns 0
     * after a reset so a caller can treat "count before increment" and "count after" the same.
     */
    @Synchronized
    fun bumpDailyCounter(name: String, dayEpoch: Long): Long {
        if (dailyCounterDay().get() != dayEpoch) {
            dailyCounterDay().set(dayEpoch)
            dailyCounter(name).set(0)
        }
        val cur = dailyCounter(name).get()
        val next = cur + 1
        dailyCounter(name).set(next)
        return next
    }
    // KMK <--
    fun ltrMangaFinishedCount() = preferenceStore.getLong("pref_achievement_ltr_finished", 0)
    fun animationsEnabled() = preferenceStore.getBoolean("pref_achievement_animations_enabled", true)
    fun rotatingLastDailyEpoch() = preferenceStore.getLong("pref_achievement_rotating_daily_epoch", 0)
    fun rotatingLastWeeklyEpoch() = preferenceStore.getLong("pref_achievement_rotating_weekly_epoch", 0)
    fun rotatingDailyIds() = preferenceStore.getString("pref_achievement_rotating_daily_ids", "")
    fun rotatingWeeklyIds() = preferenceStore.getString("pref_achievement_rotating_weekly_ids", "")
    fun rotatingProgress() = preferenceStore.getString("pref_achievement_rotating_progress", "")
    // KMK --> Day stamps for the "once per day" rotating ids, so a page turn cannot fill a
    // multi-day tier on its own. Format is id:epochDay,id:epochDay.
    fun rotatingDayStamps() = preferenceStore.getString("pref_achievement_rotating_day_stamps", "")
    fun upscalesServed() = preferenceStore.getLong("pref_achievement_upscales_served", 0)
    fun upscalePageCounts() = preferenceStore.getString("pref_achievement_upscale_page_counts", "")

    @Synchronized
    fun incrementOrganicRead() {
        if (suppressOrganicForImport) return
        val cur = organicChaptersRead().get()
        if (cur < 1_000_000L) organicChaptersRead().set(cur + 1)
    }

    @Synchronized
    fun incrementMangaFinished() {
        if (suppressOrganicForImport) return
        val cur = mangaFinishedCount().get()
        if (cur < 1_000_000L) mangaFinishedCount().set(cur + 1)
    }

    @Synchronized
    fun incrementMangaCaughtUp() {
        if (suppressOrganicForImport) return
        val cur = mangaCaughtUpCount().get()
        if (cur < 1_000_000L) mangaCaughtUpCount().set(cur + 1)
    }

    @Synchronized
    fun setLibraryCount(count: Long) {
        libraryMangaCount().set(count.coerceIn(0L, 10_000L))
    }

    @Synchronized
    fun addReadingTimeMinutes(minutes: Long) {
        if (minutes <= 0) return
        if (suppressOrganicForImport) return
        val cur = totalReadingTimeMinutes().get()
        totalReadingTimeMinutes().set((cur + minutes).coerceIn(0L, 10_000_000L))
    }

    @Synchronized
    fun incrementBacklogCleared() {
        val cur = backlogClearedCount().get()
        if (cur < 1_000_000L) backlogClearedCount().set(cur + 1)
    }

    // KMK -->
    @Synchronized
    fun setStaleUnstartedCount(count: Long) {
        staleUnstartedCount().set(count.coerceIn(0L, 10_000L))
    }
    // KMK <--

    @Synchronized
    fun incrementLtrFinished() {
        val cur = ltrMangaFinishedCount().get()
        if (cur < 1_000_000L) ltrMangaFinishedCount().set(cur + 1)
    }

    @Synchronized
    fun incrementUpscalesServed(): Long {
        val next = (upscalesServed().get() + 1).coerceIn(0L, 1_000_000L)
        upscalesServed().set(next)
        return next
    }

    @Synchronized
    fun incrementUpscalePageCount(cacheKey: String): Int {
        if (cacheKey.isBlank()) return 0
        val counts = linkedMapOf<String, Int>()
        upscalePageCounts().get().split(",")
            .mapNotNull { entry ->
                val parts = entry.split(":", limit = 2)
                val key = parts.getOrNull(0)?.trim().orEmpty()
                val count = parts.getOrNull(1)?.toIntOrNull()
                if (key.isBlank() || key.length > 64 || count == null || count <= 0) {
                    null
                } else {
                    key to count
                }
            }
            .forEach { (key, count) -> counts[key] = count }
        val next = ((counts[cacheKey] ?: 0) + 1).coerceIn(1, 10_000)
        counts[cacheKey] = next
        while (counts.size > 200) {
            counts.remove(counts.keys.first())
        }
        upscalePageCounts().set(counts.entries.joinToString(",") { "${it.key}:${it.value}" })
        return next
    }

    @Synchronized
    fun unlock(id: String): Boolean {
        if (id.isBlank() || id.length > 64) return false
        if (tachiyomi.domain.achievement.model.Achievements.forId(id) == null) return false
        if (isUnlocked(id)) return false
        val current = unlockedAchievements().get()
        val set = if (current.isBlank()) mutableSetOf<String>() else current.split(",").map { it.trim() }.filter { it.isNotBlank() }.toMutableSet()
        if (set.size >= 300) return false
        if (!set.add(id)) return false
        unlockedAchievements().set(set.joinToString(","))
        val ts = unlockedTimestamps().get()
        val entry = "$id:${System.currentTimeMillis()}"
        val newTs = if (ts.isBlank()) entry else "$ts,$entry"
        if (newTs.length > 16_000) {
            val trimmed = newTs.split(",").takeLast(200).joinToString(",")
            unlockedTimestamps().set(trimmed)
        } else {
            unlockedTimestamps().set(newTs)
        }
        return true
    }

    @Synchronized
    fun isUnlocked(id: String): Boolean {
        val current = unlockedAchievements().get()
        if (current.isBlank()) return false
        // KMK --> Membership without building the list. Every tier check calls this, and a
        // chapter read runs ~30 of them, so each was allocating a split copy of the whole
        // unlocked set to answer a yes/no. Suffixing both sides turns the stored CSV into an
        // unambiguous delimited token match - no id contains a comma, and the same answer comes
        // out for hand-edited or restored values, which split() would also have missed.
        // KMK <--
        return ",$current,".contains(",$id,")
    }

    @Synchronized
    fun getUnlockedIds(): Set<String> {
        val current = unlockedAchievements().get()
        if (current.isBlank()) return emptySet()
        return current.split(",").map { it.trim() }.filter { it.isNotBlank() && it.length <= 64 && Achievements.forId(it) != null }.toSet()
    }

    @Synchronized
    fun getUnlockedWithTimestamps(): Map<String, Long> {
        val raw = unlockedTimestamps().get()
        if (raw.isBlank()) return emptyMap()
        return raw.split(",").mapNotNull {
            val parts = it.split(":", limit = 2)
            if (parts.size != 2) return@mapNotNull null
            val id = parts[0].trim()
            if (id.isBlank() || id.length > 64 || Achievements.forId(id) == null) return@mapNotNull null
            val ts = parts[1].toLongOrNull() ?: return@mapNotNull null
            if (ts <= 0L || ts > System.currentTimeMillis() + 86_400_000L) return@mapNotNull null
            id to ts
        }.toMap()
    }

    @Volatile
    var suppressOrganicForImport: Boolean = false

    @Synchronized
    fun computeStats(totalAchievements: Int): tachiyomi.domain.achievement.model.AchievementStats {
        val ids = getUnlockedIds()
        val countableIds = ids.filter { tachiyomi.domain.achievement.model.Achievements.forId(it)?.countsTowardsProgress == true }
        val unlocked = countableIds.size
        val secretUnlocked = ids.count { tachiyomi.domain.achievement.model.Achievements.forId(it)?.isSecret == true }
        val negatives = ids.count { tachiyomi.domain.achievement.model.Achievements.forId(it)?.isNegative == true }
        val backlog = staleUnstartedCount().get().coerceAtLeast(0L)
        return tachiyomi.domain.achievement.model.AchievementStats(
            organicChaptersRead = organicChaptersRead().get().coerceAtLeast(0L),
            mangaFinished = mangaFinishedCount().get().coerceAtLeast(0L),
            mangaCaughtUp = mangaCaughtUpCount().get().coerceAtLeast(0L),
            libraryCount = libraryMangaCount().get().coerceAtLeast(0L),
            totalAchievements = totalAchievements.coerceAtLeast(0),
            unlockedCount = unlocked,
            secretUnlocked = secretUnlocked,
            readingTimeMinutes = totalReadingTimeMinutes().get().coerceAtLeast(0L),
            backlogCount = backlog,
            negativeUnlocked = negatives,
        )
    }

    @Synchronized
    fun wipe() {
        unlockedAchievements().set("")
        organicChaptersRead().set(0)
        mangaFinishedCount().set(0)
        mangaCaughtUpCount().set(0)
        libraryMangaCount().set(0)
        totalReadingTimeMinutes().set(0)
        backlogClearedCount().set(0)
        // KMK -->
        staleUnstartedCount().set(0)
        backlogLastRefresh().set(0)
        readingDays().set("")
        // KMK <--
        ltrMangaFinishedCount().set(0)
        upscalesServed().set(0)
        upscalePageCounts().set("")
        rotatingDailyIds().set("")
        rotatingWeeklyIds().set("")
        rotatingProgress().set("")
        rotatingDayStamps().set("")
        rotatingLastDailyEpoch().set(0)
        rotatingLastWeeklyEpoch().set(0)
        achievementsData().set("")
        unlockedTimestamps().set("")
    }

    fun isEnabled(): Boolean = achievementsEnabled().get()

    fun hasCompletedOnboarding(): Boolean = preferenceStore.getBoolean("pref_achievements_onboarded", false).get()

    fun setOnboarded() {
        preferenceStore.getBoolean("pref_achievements_onboarded", false).set(true)
    }
}
