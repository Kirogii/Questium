package eu.kanade.tachiyomi.ui.reader.viewer

import eu.kanade.tachiyomi.ui.reader.model.ReaderPage
import eu.kanade.tachiyomi.ui.reader.setting.UpscaleReaderHook
import kotlinx.coroutines.CoroutineScope
import mihon.app.di.globalAppGraph
import tachiyomi.core.common.util.lang.launchIO
import tachiyomi.core.common.util.lang.withUIContext

/**
 * Shared entry point for MTL translation in the non-WebGPU readers (pager + webtoon).
 *
 * Unlike the WebGPU viewer (which bakes translated images into its own [ImagePage] pipeline),
 * these readers display pages through [ReaderPageImageView]; this helper runs the same
 * [exh.yakuyomi.TranslationManager] pipeline against the original encoded bytes and hands the
 * translated WEBP back on the main thread for the holder to swap in.
 */
object ReaderTranslation : PageTranslator {

    /**
     * Whether anything on the display path would consume [originalBytes] for [page].
     *
     * Callers use this to skip materialising the encoded page when neither MTL nor upscaling
     * can apply. Reading the page costs a full decode-size copy, so on the default path
     * (both features off) it is pure waste multiplied by every page scrolled past.
     */
    suspend fun needsOriginalBytes(page: ReaderPage): Boolean {
        val manager = globalAppGraph.translationManager
        val mangaId = page.chapter.chapter.manga_id ?: 0L
        if (manager.isEnabled() && !manager.isGated() && manager.isPerMangaEnabled(mangaId)) return true
        return UpscaleReaderHook.isUpscaleActive(mangaId)
    }

    /**
     * Kicks off translation for [page] if (and only if) translation is enabled globally,
     * not gated, enabled for this manga, and the AI models are installed. On success,
     * [onResult] is invoked on the main thread with the translated WEBP bytes.
     */
    override fun translate(
        scope: CoroutineScope,
        page: ReaderPage,
        originalBytes: ByteArray?,
        onResult: (ByteArray) -> Unit,
    ) {
        if (originalBytes == null || originalBytes.isEmpty()) return

        val manager = globalAppGraph.translationManager
        val statusStore = globalAppGraph.translationStatus
        val mangaId = page.chapter.chapter.manga_id ?: 0L
        if (!manager.isEnabled() || manager.isGated() || !manager.isPerMangaEnabled(mangaId)) return

        val chapterId = page.chapter.chapter.id ?: 0L
        val pageIndex = page.index

        // Declare the chapter's page count so chapter-list/overlay progress is accurate.
        manager.setChapterTotalPages(mangaId, chapterId, page.chapter.pages?.size ?: 0)

        // Avoid re-translating pages already processed in this session, but still serve any
        // stored translated bytes so the reader keeps showing the translated image on re-bind.
        val existing = statusStore.chapterStatus(mangaId, chapterId)?.pages?.get(pageIndex)
        when (existing?.state) {
            exh.yakuyomi.TranslationStatus.PageState.TRANSLATING,
            exh.yakuyomi.TranslationStatus.PageState.SKIPPED,
            -> return
            exh.yakuyomi.TranslationStatus.PageState.DONE,
            exh.yakuyomi.TranslationStatus.PageState.CACHED,
            -> {
                scope.launchIO {
                    try {
                        val bytes = manager.getTranslatedBytes(mangaId, chapterId, originalBytes, pageIndex)
                        if (bytes != null && bytes.isNotEmpty()) {
                            withUIContext { onResult(bytes) }
                            return@launchIO
                        }
                        // No stored copy (e.g. caches disabled): fall back to translatePage, which
                        // still serves a cache hit if one exists without re-running the pipeline.
                        val webp = manager.translatePage(mangaId, chapterId, originalBytes, pageIndex) ?: return@launchIO
                        withUIContext { onResult(webp) }
                    } catch (_: Exception) {
                    }
                }
                return
            }
            else -> Unit // ERROR or unknown → allow retry
        }

        scope.launchIO {
            try {
                if (!manager.shouldTranslateForManga(mangaId)) return@launchIO
                val webp = manager.translatePage(mangaId, chapterId, originalBytes, pageIndex) ?: return@launchIO
                withUIContext { onResult(webp) }
                countChapterOnceComplete(mangaId, chapterId)
            } catch (_: Exception) {
            }
        }
    }

    // Chapters already counted this session. pendingCount settles at 0 and stays there, so
    // without this the last page of a chapter would count once per remaining page.
    private val countedChapters = mutableSetOf<Pair<Long, Long>>()

    private fun countChapterOnceComplete(mangaId: Long, chapterId: Long) {
        runCatching {
            val status = globalAppGraph.translationStatus.chapterStatus(mangaId, chapterId) ?: return
            if (status.pendingCount != 0 || status.translatedCount == 0) return
            if (!countedChapters.add(mangaId to chapterId)) return
            globalAppGraph.achievementManager.incrementCounter("translated_chapters")
            globalAppGraph.rotatingAchievementPool.markProgress("rotating_daily_translate_2")
            globalAppGraph.rotatingAchievementPool.markProgress("rotating_weekly_translate_10")
        }
    }
}
