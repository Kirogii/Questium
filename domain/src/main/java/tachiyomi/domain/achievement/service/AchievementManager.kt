package tachiyomi.domain.achievement.service

import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import tachiyomi.domain.achievement.interactor.GetStaleUnstartedBacklog
import tachiyomi.domain.achievement.model.AchievementStats
import tachiyomi.domain.achievement.model.Achievements

@SingleIn(AppScope::class)
@Inject
class AchievementManager(
    private val prefs: AchievementPreferences,
    // KMK -->
    // Non-null: Metro treats `Type? = null` as an *optional* binding satisfied only by a
    // nullable binding, so the old nullable param silently resolved to null and webhooks
    // never fired. Non-null forces a compile-time graph error instead of silent loss.
    private val notifier: AchievementUnlockNotifier,
    // KMK <--
    // KMK --> Only source of the backlog number now; the two counters it used to subtract
    // described a different population and could not tell "never started" from "not finished".
    private val getStaleUnstartedBacklog: GetStaleUnstartedBacklog,
    // KMK <--
) {
    @Synchronized
    fun onOrganicChapterRead(totalRead: Long): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        if (totalRead < 0) return emptyList()
        prefs.incrementOrganicRead()
        val count = prefs.organicChaptersRead().get().coerceAtLeast(0L)
        val r = checkThresholds(count)
        if (r.isNotEmpty()) notifyIfNeeded(r)
        checkUltimateProgress()
        return r
    }

    @Synchronized
    fun onReadingTimeMinutes(minutes: Long): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        if (minutes <= 0) return emptyList()
        prefs.addReadingTimeMinutes(minutes)
        val total = prefs.totalReadingTimeMinutes().get().coerceAtLeast(0L)
        val unlocked = mutableListOf<String>()
        if (total >= 60) tryUnlock("reading_time_1h", unlocked)
        if (total >= 600) tryUnlock("reading_time_10h", unlocked)
        if (total >= 3000) tryUnlock("reading_time_50h", unlocked)
        if (total >= 6000) tryUnlock("reading_time_100h", unlocked)
        if (total >= 30000) tryUnlock("reading_time_500h", unlocked)
        if (total >= 60000) tryUnlock("reading_time_1000h", unlocked)
        if (total >= 120000) tryUnlock("ultimate_time_dilation", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        checkUltimateProgress()
        return unlocked
    }

    // KMK -->
    /**
     * Recomputes the stale-unstarted backlog and re-evaluates its thresholds. The count is a
     * library query, so it is cached in prefs for the synchronous [AchievementPreferences.computeStats].
     *
     * Not `@Synchronized`: it suspends across the query and must not hold the monitor. Only the
     * pref writes and the unlock evaluation are guarded, by [onBacklogChanged].
     *
     * [force] skips [REFRESH_THROTTLE_MS]. Callers that fire on ordinary reading pass false so a
     * chapter-turn cannot run a full library query; the ones that must be exact (library
     * changes, the startup pass that catches the 30-day threshold) pass true.
     */
    suspend fun refreshBacklog(force: Boolean = false): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val now = System.currentTimeMillis()
        if (!force && now - prefs.backlogLastRefresh().get() < REFRESH_THROTTLE_MS) return emptyList()
        val stale = getStaleUnstartedBacklog.await()
        prefs.setStaleUnstartedCount(stale)
        prefs.backlogLastRefresh().set(now)
        return onBacklogChanged(stale)
    }
    // KMK <--

    // KMK -->
    /**
     * Records today as a reading day and unlocks the streak tiers it now satisfies. This is the
     * only thing that can ever unlock `streak_3/7/30/100`: they previously had no call site and
     * no day state behind them, so they were unreachable.
     */
    @Synchronized
    fun onReadingDay(): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val today = currentEpochDay()
        prefs.markReadingDay(today)
        val days = prefs.readDays()
        var streak = 0
        for (i in days.indices.reversed()) {
            if (today - days[i] > STREAK_GRACE_DAYS) break
            streak++
        }
        val unlocked = mutableListOf<String>()
        if (streak >= 3) tryUnlock("streak_3", unlocked)
        if (streak >= 7) tryUnlock("streak_7", unlocked)
        if (streak >= 30) tryUnlock("streak_30", unlocked)
        if (streak >= 100) tryUnlock("streak_100", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    /** Longest run of reading days in the recorded window, breaking a gap of over [STREAK_GRACE_DAYS]. */
    fun longestStreak(): Int {
        val days = prefs.readDays()
        var best = 0
        var run = 0
        for (i in days.indices) {
            val expected = if (i == 0) days[0] else days[i - 1] + 1
            run = if (days[i] - expected <= STREAK_GRACE_DAYS) run + 1 else 1
            if (run > best) best = run
        }
        return best
    }
    // KMK <--

    // KMK -->
    /**
     * Counts one occurrence of [name] and unlocks every tier it now reaches. Tiers are declared
     * here rather than at each call site so the numbers, the ids and the progress bars
     * ([AchievementProgress.thresholds]) cannot drift apart - the audit found these ids
     * defined with no unlock site at all, spread over half the catalogue.
     */
    @Synchronized
    fun incrementCounter(name: String, amount: Int = 1): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        prefs.incrementCounter(name, amount)
        return evaluateCounter(name, prefs.counter(name).get())
    }

    /**
     * Same, for a counter that resets at the day boundary. [name] must be listed in
     * [DAILY_COUNTER_TIERS]; anything else is ignored so a stray call cannot create junk prefs.
     */
    @Synchronized
    fun incrementDailyCounter(name: String, amount: Int = 1): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        if (name !in DAILY_COUNTER_TIERS) return emptyList()
        if (amount <= 0) return emptyList()
        var count = 0L
        repeat(amount.coerceIn(1, 1000)) { count = prefs.bumpDailyCounter(name, currentEpochDay()) }
        return evaluateCounter(name, count)
    }

    private fun evaluateCounter(name: String, count: Long): List<String> {
        val tiers = COUNTER_TIERS[name] ?: return emptyList()
        val unlocked = mutableListOf<String>()
        for ((at, id) in tiers) {
            if (count >= at) tryUnlock(id, unlocked)
        }
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }
    // KMK <--

    @Synchronized
    fun onBacklogChanged(staleUnstarted: Long): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val backlog = staleUnstarted.coerceAtLeast(0L)
        val finishedCount = prefs.mangaFinishedCount().get()
        val unlocked = mutableListOf<String>()
        if (backlog >= 10) tryUnlock("backlog_10", unlocked)
        if (backlog >= 25) tryUnlock("backlog_25", unlocked)
        if (backlog >= 50) tryUnlock("backlog_50", unlocked)
        if (backlog >= 100) tryUnlock("backlog_100", unlocked)
        if (backlog >= 250) tryUnlock("backlog_250", unlocked)
        if (backlog >= 500) {
            tryUnlock("negative_hoarder_shame", unlocked)
            if (finishedCount == 0L) tryUnlock("negative_abandoned", unlocked)
        }
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun onBacklogCleared(count: Int = 1): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        repeat(count.coerceIn(1, 1000)) { prefs.incrementBacklogCleared() }
        val total = prefs.backlogClearedCount().get().coerceAtLeast(0L)
        val unlocked = mutableListOf<String>()
        if (total >= 10) tryUnlock("backlog_cleared_10", unlocked)
        if (total >= 100) tryUnlock("backlog_cleared_100", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        checkUltimateProgress()
        return unlocked
    }

    @Synchronized
    fun onLtrFinished(): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        prefs.incrementLtrFinished()
        val unlocked = mutableListOf<String>()
        tryUnlock("ltr_reader", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun onNegativeEvent(id: String): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val allowed = setOf(
            "negative_binge_guilt",
            "negative_abandoned",
            "negative_midnight_oil",
            "negative_spoiled",
            "negative_hoarder_shame",
            "negative_rage_quit",
            "negative_do_not_disturb",
        )
        if (id !in allowed) return emptyList()
        val unlocked = mutableListOf<String>()
        tryUnlock(id, unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun onEhBrowsed(): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val unlocked = mutableListOf<String>()
        tryUnlock("eh_browsed", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun onMangaFinished(): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        if (prefs.suppressOrganicForImport) return emptyList()
        prefs.incrementMangaFinished()
        val count = prefs.mangaFinishedCount().get().coerceAtLeast(0L)
        val unlocked = mutableListOf<String>()
        if (count >= 1) tryUnlock("first_manga_finished", unlocked)
        if (count >= 5) tryUnlock("five_manga_finished", unlocked)
        if (count >= 10) tryUnlock("ten_manga_finished", unlocked)
        if (count >= 20) tryUnlock("twenty_manga_finished", unlocked)
        if (count >= 50) tryUnlock("fifty_manga_finished", unlocked)
        onBacklogCleared(1)
        // KMK --> No backlog recompute here: finishing implies the entry was already started, so
        // it cannot be in the stale-unstarted set. refreshBacklog covers the other triggers.
        // KMK <--
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        checkUltimateProgress()
        return unlocked
    }

    @Synchronized
    fun onMangaCaughtUp(): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        if (prefs.suppressOrganicForImport) return emptyList()
        prefs.incrementMangaCaughtUp()
        val count = prefs.mangaCaughtUpCount().get().coerceAtLeast(0L)
        val unlocked = mutableListOf<String>()
        if (count >= 1) tryUnlock("first_manga_caught_up", unlocked)
        if (count >= 5) tryUnlock("five_manga_caught_up", unlocked)
        if (count >= 10) tryUnlock("ten_manga_caught_up", unlocked)
        if (count >= 20) tryUnlock("twenty_manga_caught_up", unlocked)
        if (count >= 50) tryUnlock("fifty_manga_caught_up", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        checkUltimateProgress()
        return unlocked
    }

    fun isPermanentStatus(status: Long): Boolean {
        return when (status.toInt()) {
            eu.kanade.tachiyomi.source.model.SManga.COMPLETED,
            eu.kanade.tachiyomi.source.model.SManga.CANCELLED,
            eu.kanade.tachiyomi.source.model.SManga.PUBLISHING_FINISHED,
            eu.kanade.tachiyomi.source.model.SManga.LICENSED,
            -> true
            else -> false
        }
    }

    @Synchronized
    fun onLibraryCountChanged(count: Long): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val safe = count.coerceIn(0L, 10_000L)
        prefs.setLibraryCount(safe)
        val unlocked = mutableListOf<String>()
        if (safe >= 1) tryUnlock("library_1", unlocked)
        if (safe >= 5) tryUnlock("library_5", unlocked)
        if (safe >= 10) tryUnlock("library_10", unlocked)
        if (safe >= 25) tryUnlock("library_25", unlocked)
        if (safe >= 50) tryUnlock("library_50", unlocked)
        if (safe >= 100) tryUnlock("library_100", unlocked)
        if (safe >= 250) tryUnlock("library_250", unlocked)
        if (safe >= 500) tryUnlock("library_500", unlocked)
        if (safe >= 1000) tryUnlock("library_1000", unlocked)
        // KMK --> Library membership changed, so the stale-unstarted set did too - but that needs
        // a query, and this entry point is synchronous and called from the library's own flows.
        // The caller refreshes with force = true instead.
        // KMK <--
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        checkUltimateProgress()
        return unlocked
    }

    @Synchronized
    fun onTrackerConnected(totalTrackers: Int): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val safe = totalTrackers.coerceIn(0, 20)
        val unlocked = mutableListOf<String>()
        if (safe >= 1) tryUnlock("tracker_connected", unlocked)
        if (safe >= 2) tryUnlock("tracker_two", unlocked)
        if (safe >= 3) tryUnlock("tracker_three", unlocked)
        if (safe >= 5) tryUnlock("tracker_five", unlocked)
        if (safe >= 8) tryUnlock("tracker_all", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun onReread(count: Int = 1): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val safe = count.coerceIn(1, 10_000)
        val unlocked = mutableListOf<String>()
        tryUnlock("rereader", unlocked)
        if (safe >= 5) tryUnlock("reread_five", unlocked)
        if (safe >= 20) tryUnlock("reread_twenty", unlocked)
        if (safe >= 100) tryUnlock("reread_hundred", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun onTranslated(count: Long): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val safe = count.coerceIn(0L, 10_000L)
        val unlocked = mutableListOf<String>()
        if (safe >= 1) tryUnlock("translator", unlocked)
        if (safe >= 5) tryUnlock("translator_five", unlocked)
        if (safe >= 10) tryUnlock("translator_ten", unlocked)
        if (safe >= 50) tryUnlock("translator_fifty", unlocked)
        if (safe >= 100) tryUnlock("translator_hundred", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun onUpscaled(count: Long): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val safe = count.coerceIn(0L, 1_000_000L)
        val unlocked = mutableListOf<String>()
        if (safe >= 1) tryUnlock("upscale_first", unlocked)
        if (safe >= 10) tryUnlock("upscale_ten", unlocked)
        if (safe >= 100) tryUnlock("upscale_hundred", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        return unlocked
    }

    @Synchronized
    fun tryUnlockDirect(id: String): Boolean {
        if (!prefs.achievementsEnabled().get()) return false
        val out = mutableListOf<String>()
        tryUnlock(id, out)
        if (out.isNotEmpty()) notifyIfNeeded(out)
        return out.isNotEmpty()
    }

    @Synchronized
    fun onJxlDecoded(): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        val unlocked = mutableListOf<String>()
        tryUnlock("secret_jxl", unlocked)
        if (unlocked.isNotEmpty()) notifyIfNeeded(unlocked)
        checkUltimateProgress()
        return unlocked
    }

    private fun checkThresholds(count: Long): List<String> {
        val unlocked = mutableListOf<String>()
        if (count >= 1) tryUnlock("first_chapter", unlocked)
        if (count >= 10) tryUnlock("ten_chapters", unlocked)
        if (count >= 25) tryUnlock("twenty_five", unlocked)
        if (count >= 50) tryUnlock("fifty_chapters", unlocked)
        if (count >= 100) tryUnlock("hundred_chapters", unlocked)
        if (count >= 250) tryUnlock("two_fifty", unlocked)
        if (count >= 500) tryUnlock("five_hundred", unlocked)
        if (count >= 1000) tryUnlock("thousand", unlocked)
        if (count >= 2000) tryUnlock("two_thousand", unlocked)
        if (count >= 5000) tryUnlock("five_thousand", unlocked)
        if (count >= 10000) tryUnlock("ten_thousand", unlocked)
        if (count >= 20000) tryUnlock("ultimate_ink_god", unlocked)
        return unlocked
    }

    private fun checkUltimateProgress() {
        val countable = prefs.getUnlockedIds().count { Achievements.forId(it)?.countsTowardsProgress == true }
        if (countable >= 200) tryUnlockDirect("ultimate_perfection")
        val library = prefs.libraryMangaCount().get()
        if (library >= 2000) tryUnlockDirect("ultimate_eternal_library")
    }

    private fun tryUnlock(id: String, out: MutableList<String>) {
        if (!prefs.achievementsEnabled().get()) return
        if (prefs.unlock(id)) out.add(id)
    }

    private fun notifyIfNeeded(unlocked: List<String>) {
        if (unlocked.isNotEmpty()) {
            // KMK --> notifier is non-null so unlocks always fan out to webhooks
            notifier.onUnlocked(unlocked)
            // KMK <--
        }
    }

    fun getStats(): AchievementStats = prefs.computeStats(Achievements.all.size)

    // KMK -->
    private companion object {
        const val REFRESH_THROTTLE_MS = 15L * 60L * 1000L
        // A single missed day does not end a streak, so "read N days in a row" tolerates one gap.
        const val STREAK_GRACE_DAYS = 1L

        fun currentEpochDay(): Long =
            java.util.concurrent.TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis())

        /** Counter name -> ordered (count, achievement id) tiers. */
        val COUNTER_TIERS: Map<String, List<Pair<Long, String>>> = mapOf(
            "downloads" to listOf(
                1L to "download_one",
                10L to "download_ten",
                100L to "download_hundred",
                1000L to "download_thousand",
            ),
            "custom_covers" to listOf(10L to "cover_ten"),
            "categories" to listOf(5L to "category_master", 10L to "category_ten"),
            "sources" to listOf(5L to "sources_five", 10L to "sources_ten"),
            "subcategories" to listOf(
                1L to "subcategory_creator",
                5L to "subcategory_five",
                20L to "subcategory_twenty",
            ),
            "tracker_updates" to listOf(10L to "track_status"),
        )

        /** Counters that reset at the day boundary; same tier shape. */
        val DAILY_COUNTER_TIERS: Map<String, List<Pair<Long, String>>> = mapOf(
            "binge" to listOf(10L to "binge_10", 50L to "binge_50", 100L to "binge_100"),
        )
    }
    // KMK <--

    fun getUnlockedWithMeta(): List<Pair<String, Long>> {
        val map = prefs.getUnlockedWithTimestamps()
        return map.entries.map { it.key to it.value }.sortedBy { it.second }
    }

    fun wipeWithConfirmation(firstConfirmed: Boolean, secondConfirmed: Boolean): Boolean {
        if (!firstConfirmed || !secondConfirmed) return false
        prefs.wipe()
        return true
    }
}
