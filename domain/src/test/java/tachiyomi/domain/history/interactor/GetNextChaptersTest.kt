package tachiyomi.domain.history.interactor

import io.kotest.matchers.shouldBe
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.parallel.Execution
import org.junit.jupiter.api.parallel.ExecutionMode
import tachiyomi.domain.chapter.interactor.GetChaptersByMangaId
import tachiyomi.domain.chapter.interactor.GetMergedChaptersByMangaId
import tachiyomi.domain.chapter.model.Chapter
import tachiyomi.domain.history.model.HistoryWithRelations
import tachiyomi.domain.history.repository.HistoryRepository
import tachiyomi.domain.manga.interactor.GetManga
import tachiyomi.domain.manga.model.Manga
import tachiyomi.domain.manga.model.MangaCover
import java.util.Date

@Execution(ExecutionMode.CONCURRENT)
class GetNextChaptersTest {

    private val getChaptersByMangaId: GetChaptersByMangaId = mockk()
    private val getMergedChaptersByMangaId: GetMergedChaptersByMangaId = mockk()
    private val getManga: GetManga = mockk()
    private val historyRepository: HistoryRepository = mockk()

    private val interactor = GetNextChapters(
        getChaptersByMangaId,
        getMergedChaptersByMangaId,
        getManga,
        historyRepository,
    )

    private fun chapter(id: Long, mangaId: Long, read: Boolean, number: Double) = Chapter.create().copy(
        id = id,
        mangaId = mangaId,
        read = read,
        chapterNumber = number,
    )

    private fun history(mangaId: Long, chapterId: Long) = HistoryWithRelations(
        id = mangaId,
        chapterId = chapterId,
        mangaId = mangaId,
        ogTitle = "Manga $mangaId",
        chapterNumber = 1.0,
        read = true,
        lastPageRead = 5,
        totalCountCalculated = 2,
        readCountCalculated = 1,
        readAt = Date(0),
        readDuration = 0,
        coverData = MangaCover(
            mangaId = mangaId,
            sourceId = 1,
            isMangaFavorite = true,
            ogUrl = null,
            lastModified = 0,
        ),
    )

    private fun givenManga(id: Long) {
        coEvery { getManga.await(id) } returns Manga.create().copy(id = id, source = 1)
    }

    @Test
    fun `returns the chapter from the newest history entry`() = runTest {
        val newest = chapter(1L, 10L, read = false, number = 2.0)
        givenManga(10L)
        coEvery { getChaptersByMangaId.await(10L, applyFilter = true) } returns
            listOf(chapter(0L, 10L, read = true, number = 1.0), newest)
        coEvery { historyRepository.getRecentHistory(25) } returns listOf(history(10L, 0L))

        interactor.awaitFirstReadable() shouldBe newest
    }

    // KMK --> The bug: a fully caught-up newest entry must not end the search.
    @Test
    fun `falls back to an older entry when the newest is fully read`() = runTest {
        val older = chapter(3L, 20L, read = false, number = 5.0)
        givenManga(10L)
        givenManga(20L)
        coEvery { getChaptersByMangaId.await(10L, applyFilter = true) } returns
            listOf(chapter(1L, 10L, read = true, number = 1.0))
        coEvery { getChaptersByMangaId.await(20L, applyFilter = true) } returns
            listOf(chapter(2L, 20L, read = true, number = 4.0), older)
        coEvery { historyRepository.getRecentHistory(25) } returns
            listOf(history(10L, 1L), history(20L, 2L))

        interactor.awaitFirstReadable() shouldBe older
    }

    @Test
    fun `returns null only when no history entry has a chapter left`() = runTest {
        givenManga(10L)
        givenManga(20L)
        coEvery { getChaptersByMangaId.await(10L, applyFilter = true) } returns
            listOf(chapter(1L, 10L, read = true, number = 1.0))
        coEvery { getChaptersByMangaId.await(20L, applyFilter = true) } returns
            listOf(chapter(2L, 20L, read = true, number = 4.0))
        coEvery { historyRepository.getRecentHistory(25) } returns
            listOf(history(10L, 1L), history(20L, 2L))

        interactor.awaitFirstReadable() shouldBe null
    }

    @Test
    fun `stops at the scan limit rather than reading all of history`() = runTest {
        every { historyRepository.getRecentHistory(3) } returns emptyList()

        interactor.awaitFirstReadable(scanLimit = 3) shouldBe null
    }
    // KMK <--
}
