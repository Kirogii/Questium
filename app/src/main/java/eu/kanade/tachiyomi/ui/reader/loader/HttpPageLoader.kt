package eu.kanade.tachiyomi.ui.reader.loader

import eu.kanade.domain.source.service.SourcePreferences
import eu.kanade.tachiyomi.data.cache.ChapterCache
import eu.kanade.tachiyomi.data.database.models.toDomainChapter
import eu.kanade.tachiyomi.extension.reportingSourceErrorsOrNull
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.ui.reader.model.ReaderChapter
import eu.kanade.tachiyomi.ui.reader.model.ReaderPage
import eu.kanade.tachiyomi.ui.reader.model.segmentIndex
import eu.kanade.tachiyomi.ui.reader.model.segmentParentIndex
import eu.kanade.tachiyomi.ui.reader.setting.ReaderPreferences
import exh.source.isEhBasedSource
import exh.util.DataSaver
import exh.util.DataSaver.Companion.getImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.suspendCancellableCoroutine
import mihon.app.di.globalAppGraph
import mihon.core.concurrency.AppDispatchersHolder
import tachiyomi.core.common.util.lang.launchIO
import tachiyomi.core.common.util.lang.withIOContext
import tachiyomi.core.common.util.system.TallPageSplitter
import tachiyomi.core.common.util.system.logcat
import java.util.concurrent.PriorityBlockingQueue
import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlin.concurrent.atomics.incrementAndFetch
import kotlin.math.min

/** Cache-key suffix distinguishing a split segment from the image it was cut from. */
private const val SEGMENT_KEY_SUFFIX = "#segment-"

/**
 * Loader used to load chapters from an online source.
 */
@OptIn(DelicateCoroutinesApi::class)
internal class HttpPageLoader(
    private val chapter: ReaderChapter,
    private val source: HttpSource,
    private val chapterCache: ChapterCache = globalAppGraph.chapterCache,
    // SY -->
    private val readerPreferences: ReaderPreferences = globalAppGraph.readerPreferences,
    private val sourcePreferences: SourcePreferences = globalAppGraph.sourcePreferences,
    // SY <--
) : PageLoader() {

    private val scope = CoroutineScope(SupervisorJob() + AppDispatchersHolder.get().readers)

    /**
     * Tallest page the readers will decode, in pixels.
     *
     * The decoder rejects anything past 16384px on a side and the WebGPU renderer's resize path
     * caps at 8192px, so a segment is held to the stricter of the two.
     */
    private val maxSegmentHeight = 8192

    /**
     * A queue used to manage requests one by one while allowing priorities.
     */
    private val queue = PriorityBlockingQueue<PriorityPage>()

    /**
     * Serialises the oversized-page split for this chapter. See [splitOversizedPage] for why the
     * check and the insert have to happen together.
     */
    private val splitLock = Any()

    private val preloadSize = /* SY --> */ readerPreferences.preloadSize().get() // SY <--

    // SY -->
    private val dataSaver = DataSaver(source, sourcePreferences)
    // SY <--

    init {
        // EXH -->
        repeat(readerPreferences.readerThreads().get()) {
            // EXH <--
            scope.launchIO {
                flow {
                    while (true) {
                        emit(runInterruptible { queue.take() }.page)
                    }
                }
                    .filter { it.status == Page.State.Queue }
                    .collect(::internalLoadPage)
            }
            // EXH -->
        }
        // EXH <--
    }

    override var isLocal: Boolean = false

    /**
     * Returns the page list for a chapter. It tries to return the page list from the local cache,
     * otherwise fallbacks to network.
     */
    override suspend fun getPages(): List<ReaderPage> {
        val pages = try {
            chapterCache.getPageListFromCache(chapter.chapter.toDomainChapter()!!)
        } catch (e: Throwable) {
            if (e is CancellationException) {
                throw e
            }
            // KMK -->
            reportingSourceErrorsOrNull(source) { source.getPageList(chapter.chapter) }.orEmpty()
            // KMK <--
        }
        // SY -->
        val rp = pages.mapIndexed { index, page ->
            // Don't trust sources and use our own indexing
            ReaderPage(index, page.url, page.imageUrl)
        }
        if (readerPreferences.aggressivePageLoading().get()) {
            rp.forEach {
                if (it.status == Page.State.Queue) {
                    queue.offer(PriorityPage(it, 0))
                }
            }
        }
        return rp
        // SY <--
    }

    /**
     * Loads a page through the queue. Handles re-enqueueing pages if they were evicted from the cache.
     */
    override suspend fun loadPage(page: ReaderPage) = withIOContext {
        val imageUrl = page.imageUrl

        // Check if the image has been deleted
        if (page.status == Page.State.Ready && imageUrl != null && !chapterCache.isImageInCache(imageUrl)) {
            page.status = Page.State.Queue
        }

        // Automatically retry failed pages when subscribed to this page
        if (page.status is Page.State.Error) {
            page.status = Page.State.Queue
        }

        val queuedPages = mutableListOf<PriorityPage>()
        if (page.status == Page.State.Queue) {
            queuedPages += PriorityPage(page, 1).also { queue.offer(it) }
        }
        queuedPages += preloadNextPages(page, preloadSize)

        suspendCancellableCoroutine<Nothing> { continuation ->
            continuation.invokeOnCancellation {
                queuedPages.forEach {
                    if (it.page.status == Page.State.Queue) {
                        queue.remove(it)
                    }
                }
            }
        }
    }

    /**
     * Retries a page. This method is only called from user interaction on the viewer.
     */
    override fun retryPage(page: ReaderPage) {
        if (page.status is Page.State.Error) {
            page.status = Page.State.Queue
        }
        // EXH -->
        // Grab a new image URL on EXH sources
        if (source.isEhBasedSource()) {
            page.imageUrl = null
        }

        if (readerPreferences.readerInstantRetry().get()) { // EXH <--
            boostPage(page)
        } else {
            // EXH <--
            queue.offer(PriorityPage(page, 2))
        }
    }

    override fun recycle() {
        super.recycle()
        scope.cancel()
        queue.clear()

        // Cache current page list progress for online chapters to allow a faster reopen
        chapter.pages?.let { pages ->
            launchIO {
                try {
                    // Convert to pages without reader information
                    val pagesToSave = unSplit(pages)
                    chapterCache.putPageListToCache(chapter.chapter.toDomainChapter()!!, pagesToSave)
                } catch (e: Throwable) {
                    if (e is CancellationException) {
                        throw e
                    }
                }
            }
        }
    }

    /**
     * [pages] with every run of split segments folded back into the single page it replaced.
     *
     * The cached list is what `getPages` hands back on the next open, and it is read as a plain list
     * of source pages: a segment's `imageUrl` is a derived cache key that only means anything to this
     * loader, and its `splitSegment` flag is not part of [Page]. Saving the split list as-is therefore
     * restores each segment as if it were a source page, and every one of them splits again on load -
     * turning one strip into as many segment pages as it had segments squared.
     */
    private fun unSplit(pages: List<ReaderPage>): List<Page> {
        val result = mutableListOf<Page>()
        var index = 0
        while (index < pages.size) {
            val page = pages[index]
            val parentIndex = page.segmentParentIndex
            if (parentIndex == null) {
                result += Page(page.index, page.url, page.imageUrl)
                index++
                continue
            }
            // The whole run shares one parent index, so this collapses exactly the pages a single
            // split inserted - two parents whose images happen to share a URL cannot merge.
            result += Page(parentIndex, page.url, page.imageUrl?.substringBefore(SEGMENT_KEY_SUFFIX))
            while (index < pages.size && pages[index].segmentParentIndex == parentIndex) {
                index++
            }
        }
        return result
    }

    /**
     * Preloads the given [amount] of pages after the [currentPage] with a lower priority.
     *
     * @return a list of [PriorityPage] that were added to the [queue]
     */
    private fun preloadNextPages(currentPage: ReaderPage, amount: Int): List<PriorityPage> {
        val pages = currentPage.chapter.pages ?: return emptyList()
        val position = currentPage.chapter.positionOf(currentPage)
        if (position < 0) return emptyList()

        return pages
            .subList(position + 1, min(position + 1 + amount, pages.size))
            .mapNotNull {
                if (it.status == Page.State.Queue) {
                    PriorityPage(it, 0).apply { queue.offer(this) }
                } else {
                    null
                }
            }
    }

    /**
     * Loads the page, retrieving the image URL and downloading the image if necessary.
     * Downloaded images are stored in the chapter cache.
     *
     * @param page the page whose source image has to be downloaded.
     */
    private suspend fun internalLoadPage(page: ReaderPage) {
        try {
            if (page.imageUrl.isNullOrEmpty()) {
                page.status = Page.State.LoadPage
                page.imageUrl = source.getImageUrl(page)
            }
            // page.imageUrl keeps naming the whole source image even after a split: only the source
            // can be asked for it, while the segment files live under derived cache keys and are
            // read through page.stream instead.
            val imageUrl = page.imageUrl!!.substringBefore(SEGMENT_KEY_SUFFIX)

            // Before the segment branch, and not after it: the source image is what a segment has
            // to be re-cut from, and the cache is an LRU that evicts it independently of the
            // segment files. Returning early left a re-cut reading a file that was no longer there,
            // which TallPageSplitter reports as "fits as-is" and the page then drew as the whole
            // strip - or as nothing, since the strip is the very image the decoder refuses.
            if (!chapterCache.isImageInCache(imageUrl)) {
                page.status = Page.State.DownloadImage
                // Repointing at the bare image URL is a repair, for a page list cached by a build
                // that stored segment keys as if they were source URLs. A segment page must keep
                // its own: the suffix is the only record of which slice it is, and dropping it
                // sends every segment of the strip to segment 0.
                if (!page.splitSegment) page.imageUrl = imageUrl
                val imageResponse = source.getImage(page, dataSaver)
                chapterCache.putImageToCache(imageUrl, imageResponse)
            }

            if (page.splitSegment) {
                loadSegment(page, imageUrl)
                return
            }

            val firstKey = splitOversizedPage(page, imageUrl) ?: imageUrl
            page.stream = { chapterCache.getImageFile(firstKey).inputStream() }
            page.status = Page.State.Ready
        } catch (e: Throwable) {
            page.status = Page.State.Error(e)
            if (e is CancellationException) {
                throw e
            }
        }
    }

    /**
     * Points an injected segment page at its own cache file, re-cutting just that segment if its
     * file was evicted. Segment keys are derived from the image and the segment's position in it,
     * so the same cut always lands on the same key.
     */
    private fun loadSegment(page: ReaderPage, imageUrl: String) {
        val index = page.imageUrl!!.substringAfter(SEGMENT_KEY_SUFFIX, "").toIntOrNull() ?: 0
        val key = ensureSegment(imageUrl, index) ?: imageUrl
        page.stream = { chapterCache.getImageFile(key).inputStream() }
        page.status = Page.State.Ready
    }

    /**
     * Cache key for segment [index] of [imageUrl], re-cutting if it was evicted. Null when the cut
     * no longer produces that segment, so the caller can fall back to the whole image instead of
     * pointing at a file that is not there.
     */
    private fun ensureSegment(imageUrl: String, index: Int): String? {
        val key = segmentKey(imageUrl, index)
        if (chapterCache.isImageInCache(key)) return key

        // KMK --> Same lock as the initial cut. Two segments of one strip that were evicted together
        // come back as two independent loader tasks, and both re-cut the whole image: interleaved,
        // one pass's `produced` count can stop short of the other's while the "drop the stale
        // remainder" loop below deletes keys the other pass has already written - which sends a
        // segment page to a file that is no longer there. One cut per image at a time removes the
        // interleaving entirely, and it is the same lock the initial split already holds across its
        // own cut, so the two paths cannot disagree.
        synchronized(splitLock) {
            if (chapterCache.isImageInCache(key)) return key

            // The cut produces every segment, and all of them are written rather than just the one
            // asked for: the cache is an LRU, so segments are evicted one at a time, and restoring only
            // the requested one would cost a full re-split for each of them in turn.
            var produced = 0
            val split = TallPageSplitter.split(
                imageFile = chapterCache.getImageFile(imageUrl),
                maxSegmentHeight = maxSegmentHeight,
            ) { i, bytes ->
                produced = i + 1
                chapterCache.putImageToCache(segmentKey(imageUrl, i), bytes)
            }
            // The image fits as it stands, which means a shorter one replaced the strip this segment
            // was cut from. The whole file is then the right thing for the page to read.
            if (!split) return null

            // Anything past what this cut produced belongs to an earlier, longer split of the same
            // image. Left in the cache it still answers isImageInCache, so a segment page from that
            // older split would decode an image that no longer matches its position.
            var stale = produced
            while (chapterCache.removeImageFromCache(segmentKey(imageUrl, stale))) {
                stale++
            }

            // A region the decoder could not read is skipped rather than reported, so `produced` counts
            // the last index attempted, not the segments on disk. Verified here instead: returning the
            // key anyway would send the reader to a file that was never written.
            check(chapterCache.isImageInCache(key)) {
                "Segment $index missing after re-cutting ${imageUrl.takeLast(48)}"
            }
            return key
        }
        // KMK <--
    }

    /**
     * Replaces a page too tall for the decoder with cached vertical segments, taking the parent's
     * place in the chapter's page list, and returns the cache key of its first segment. Returns null
     * when the image fits as-is.
     *
     * The segments are new [ReaderPage]s rather than extra entries on [page] because a page holds a
     * single image; the chapter's list grows instead, which the viewers pick up because they
     * re-read [ReaderChapter.pages] and key their page cache on identity rather than position.
     */
    private fun splitOversizedPage(page: ReaderPage, imageUrl: String): String? =
        // Atomic check-and-insert. The loader serves one chapter and its queue can hold the same
        // page more than once - aggressive preloading offers every page up front, and a re-queue
        // after a cache miss offers it again - so two workers could both read "no segments yet",
        // both cut the image and both append their extras. Each append rebuilt the list from
        // `updated`, so the two copies interleaved and the chapter grew a little more on every
        // pass. That is the runaway duplication the long-strip reader showed.
        synchronized(splitLock) {
            val chapterPages = page.chapter.pages ?: return null
            val position = page.chapter.positionOf(page)
            if (position < 0) return null

            // A page still in the list is uncut: the split removes this instance as it inserts the
            // segments. Identity is therefore the whole test. A flag on the page, or its source URL,
            // would be coarser - a second live page sharing that image could then claim the first
            // one's segments.
            val keys = mutableListOf<String>()
            val split = TallPageSplitter.split(
                imageFile = chapterCache.getImageFile(imageUrl),
                maxSegmentHeight = maxSegmentHeight,
            ) { index, bytes ->
                val key = segmentKey(imageUrl, index)
                chapterCache.putImageToCache(key, bytes)
                keys += key
            }
            if (!split || keys.isEmpty()) return null

            // The parent is REPLACED by its segments, not kept alongside them. Keeping it and
            // repointing its stream at segment 0 left the original page object alive in every
            // viewer's cache under PageKey.Reader(chapterId, parentIndex) while the segments were
            // also laid out - so the strip was drawn twice, once whole and once in pieces, which is
            // what the long-strip reader was showing. Removing it means a split page has exactly
            // one representation.
            //
            // Segment numbering is the real one (0..k-1), matching both segmentKey and the index
            // loadSegment recovers from the key, so a segment page resolves to the same segment
            // whichever path re-reads it.
            val segments = keys.mapIndexed { segmentNumber, key ->
                ReaderPage(index = segmentIndex(page, segmentNumber), url = page.url, imageUrl = key).apply {
                    chapter = page.chapter
                    splitSegment = true
                    splitSourcePage = page
                    status = Page.State.Ready
                    stream = { chapterCache.getImageFile(key).inputStream() }
                }
            }

            val updated = ArrayList<ReaderPage>(chapterPages.size - 1 + segments.size).apply {
                addAll(chapterPages)
                removeAt(position)
                segments.forEachIndexed { offset, segment -> add(position + offset, segment) }
            }

            // Announced before the list is swapped, not after. A viewer woken by the version bump
            // reads this flag straight away, and a write that follows the announcement is not
            // ordered against it - the viewer would reconcile against a page it still believes is
            // live, and the strip would be drawn over its own replacement all the same.
            page.supersededBySplit = true
            page.chapter.replacePages(updated)

            logcat { "Split page ${page.index} (${keys.size} segments), chapter now ${updated.size} pages" }
            return keys.first()
        }

    private fun segmentKey(imageUrl: String, index: Int) = "$imageUrl$SEGMENT_KEY_SUFFIX$index"

    // EXH -->
    fun boostPage(page: ReaderPage) {
        if (page.status == Page.State.Queue) {
            scope.launchIO {
                loadPage(page)
            }
        }
    }
    // EXH <--
}

/**
 * Data class used to keep ordering of pages in order to maintain priority.
 */
@OptIn(ExperimentalAtomicApi::class)
private class PriorityPage(
    val page: ReaderPage,
    val priority: Int,
) : Comparable<PriorityPage> {
    companion object {
        private val idGenerator = AtomicInt(0)
    }

    private val identifier = idGenerator.incrementAndFetch()

    override fun compareTo(other: PriorityPage): Int {
        val p = other.priority.compareTo(priority)
        return if (p != 0) p else identifier.compareTo(other.identifier)
    }
}
