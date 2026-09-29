package tachiyomi.domain.achievement.service

sealed interface AchievementEvent {
    data class OrganicChapterRead(val totalHint: Long = 0) : AchievementEvent
    data class ReadingTimeMinutes(val minutes: Long) : AchievementEvent
    data class LibraryCountChanged(val count: Long) : AchievementEvent
    data class MangaFinished(val isPermanent: Boolean) : AchievementEvent
    object MangaCaughtUp : AchievementEvent
    object LtrFinished : AchievementEvent
    // KMK --> Carries the count itself, not the two counters it used to be derived from.
    data class BacklogChanged(val staleUnstarted: Long) : AchievementEvent
    // KMK <--
    data class BacklogCleared(val count: Int = 1) : AchievementEvent
    data class Negative(val id: String) : AchievementEvent
    object EhBrowsed : AchievementEvent
    data class DirectUnlock(val id: String) : AchievementEvent
    data class TrackerConnected(val total: Int) : AchievementEvent
    data class Reread(val count: Int = 1) : AchievementEvent

    // KMK --> Secrets and negatives. Each carries only what the trigger needs, so the manager
    // keeps the rule and the call site stays a one-liner at an existing event.
    data class ChapterReadAtHour(val hour: Int, val minute: Int) : AchievementEvent
    data class AppOpenedAt(val hour: Int, val minute: Int) : AchievementEvent
    data class ReaderDirectionChanged(val direction: Int) : AchievementEvent
    data class ReaderSessionEnded(val durationMs: Long) : AchievementEvent
    data class MangaSpeedrun(val totalChapters: Long, val durationMs: Long) : AchievementEvent
    data class MangaFinishedOnDay(val dummy: Int = 0) : AchievementEvent
    // KMK <--
}

@dev.zacsweers.metro.Inject
class AchievementDispatcher(
    private val manager: AchievementManager,
    private val prefs: AchievementPreferences,
) {
    @Synchronized
    fun dispatch(event: AchievementEvent): List<String> {
        if (!prefs.achievementsEnabled().get()) return emptyList()
        return when (event) {
            is AchievementEvent.OrganicChapterRead -> manager.onOrganicChapterRead(event.totalHint)
            is AchievementEvent.ReadingTimeMinutes -> manager.onReadingTimeMinutes(event.minutes)
            is AchievementEvent.LibraryCountChanged -> manager.onLibraryCountChanged(event.count)
            is AchievementEvent.MangaFinished -> if (event.isPermanent) manager.onMangaFinished() else manager.onMangaCaughtUp()
            is AchievementEvent.MangaCaughtUp -> manager.onMangaCaughtUp()
            is AchievementEvent.LtrFinished -> manager.onLtrFinished()
            // KMK -->
            is AchievementEvent.BacklogChanged -> manager.onBacklogChanged(event.staleUnstarted)
            // KMK <--
            is AchievementEvent.BacklogCleared -> manager.onBacklogCleared(event.count)
            is AchievementEvent.Negative -> manager.onNegativeEvent(event.id)
            is AchievementEvent.EhBrowsed -> manager.onEhBrowsed()
            is AchievementEvent.DirectUnlock -> if (manager.tryUnlockDirect(event.id)) listOf(event.id) else emptyList()
            is AchievementEvent.TrackerConnected -> manager.onTrackerConnected(event.total)
            is AchievementEvent.Reread -> manager.onReread(event.count)
            // KMK -->
            is AchievementEvent.ChapterReadAtHour -> manager.onChapterReadAtHour(event.hour, event.minute)
            is AchievementEvent.AppOpenedAt -> manager.onAppOpenedAt(event.hour, event.minute)
            is AchievementEvent.ReaderDirectionChanged -> manager.onReaderDirectionChanged(event.direction)
            is AchievementEvent.ReaderSessionEnded -> manager.onReaderSessionEnded(event.durationMs)
            is AchievementEvent.MangaSpeedrun -> manager.onMangaSpeedrun(event.totalChapters, event.durationMs)
            is AchievementEvent.MangaFinishedOnDay -> manager.onMangaFinishedOnDay()
            // KMK <--
        }
    }

    fun dispatchAsync(event: AchievementEvent) {
        try {
            dispatch(event)
        } catch (_: Exception) {}
    }
}
