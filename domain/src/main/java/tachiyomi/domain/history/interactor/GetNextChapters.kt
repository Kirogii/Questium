package tachiyomi.domain.history.interactor

import dev.zacsweers.metro.Inject
import exh.source.MERGED_SOURCE_ID
import exh.source.isEhBasedManga
import tachiyomi.domain.chapter.interactor.GetChaptersByMangaId
import tachiyomi.domain.chapter.interactor.GetMergedChaptersByMangaId
import tachiyomi.domain.chapter.model.Chapter
import tachiyomi.domain.chapter.service.getChapterSort
import tachiyomi.domain.history.repository.HistoryRepository
import tachiyomi.domain.manga.interactor.GetManga
import kotlin.math.max

// KMK -->
/** Bounds [GetNextChapters.awaitFirstReadable] so a long History cannot make one tap scan it all. */
private const val DEFAULT_HISTORY_SCAN_LIMIT = 25L
// KMK <--

@Inject
class GetNextChapters(
    private val getChaptersByMangaId: GetChaptersByMangaId,
    // SY -->
    private val getMergedChaptersByMangaId: GetMergedChaptersByMangaId,
    // SY <--
    private val getManga: GetManga,
    private val historyRepository: HistoryRepository,
) {

    suspend fun await(onlyUnread: Boolean = true): List<Chapter> {
        val history = historyRepository.getLastHistory() ?: return emptyList()
        return await(history.mangaId, history.chapterId, onlyUnread)
    }

    // KMK -->
    /**
     * The next chapter to read, walking back through recent History until an entry has
     * something left. [await] only considers the single newest entry, so a fully caught-up
     * most-recent series would otherwise report no chapter.
     *
     * Only an unread chapter counts as having something left. The per-entry lookup drops just the
     * chapter its entry points at and keeps every chapter after it, read or not, and History holds
     * one row per chapter rather than per series - so a series you finished contributes a row per
     * chapter. Its second row down would hand back the final chapter you had already read and the
     * walk would stop there, instead of moving on to the next series.
     *
     * [scanLimit] bounds the walk so a long, fully-read History cannot turn one resume tap
     * into a full-table scan.
     */
    suspend fun awaitFirstReadable(scanLimit: Long = DEFAULT_HISTORY_SCAN_LIMIT): Chapter? {
        historyRepository.getRecentHistory(scanLimit).forEach { history ->
            val next = await(history.mangaId, history.chapterId, onlyUnread = false)
                .firstOrNull { !it.read }
            if (next != null) return next
        }
        return null
    }
    // KMK <--

    suspend fun await(mangaId: Long, onlyUnread: Boolean = true): List<Chapter> {
        val manga = getManga.await(mangaId) ?: return emptyList()

        // SY -->
        if (manga.source == MERGED_SOURCE_ID) {
            val chapters = getMergedChaptersByMangaId.await(mangaId, applyFilter = true)
                .sortedWith(getChapterSort(manga, sortDescending = false))

            return if (onlyUnread) {
                chapters.filterNot { it.read }
            } else {
                chapters
            }
        }
        if (manga.isEhBasedManga()) {
            val chapters = getChaptersByMangaId.await(mangaId, applyFilter = true)
                .sortedWith(getChapterSort(manga, sortDescending = false))

            return if (onlyUnread) {
                chapters.takeLast(1).takeUnless { it.firstOrNull()?.read == true }.orEmpty()
            } else {
                chapters
            }
        }
        // SY <--

        val chapters = getChaptersByMangaId.await(mangaId, applyFilter = true)
            .sortedWith(getChapterSort(manga, sortDescending = false))

        return if (onlyUnread) {
            chapters.filterNot { it.read }
        } else {
            chapters
        }
    }

    suspend fun await(
        mangaId: Long,
        fromChapterId: Long,
        onlyUnread: Boolean = true,
    ): List<Chapter> {
        val chapters = await(mangaId, onlyUnread)
        val currChapterIndex = chapters.indexOfFirst { it.id == fromChapterId }
        val nextChapters = chapters.subList(max(0, currChapterIndex), chapters.size)

        if (onlyUnread) {
            return nextChapters
        }

        // The "next chapter" is either:
        // - The current chapter if it isn't completely read
        // - The chapters after the current chapter if the current one is completely read
        val fromChapter = chapters.getOrNull(currChapterIndex)
        return if (fromChapter != null && !fromChapter.read) {
            nextChapters
        } else {
            nextChapters.drop(1)
        }
    }
}
