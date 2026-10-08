// Mihon -->
package eu.kanade.tachiyomi.ui.reader.viewer.webgpu

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PointF
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import ca.mpreg.webgpuviewer.ImageView
import ca.mpreg.webgpuviewer.filter.FilterBrightnessContrast
import ca.mpreg.webgpuviewer.filter.FilterGrayscale
import ca.mpreg.webgpuviewer.filter.FilterHlg
import ca.mpreg.webgpuviewer.filter.FilterLut3d
import ca.mpreg.webgpuviewer.reader.OnReaderStateChanged
import ca.mpreg.webgpuviewer.reader.PageAnchor
import ca.mpreg.webgpuviewer.reader.ReaderState
import ca.mpreg.webgpuviewer.reader.SettingsImpact
import ca.mpreg.webgpuviewer.renderer.UpscalerArtCnn
import ca.mpreg.webgpuviewer.renderer.UpscalerCatmullRom
import ca.mpreg.webgpuviewer.transition.TransitionBasic
import ca.mpreg.webgpuviewer.transition.TransitionCube
import ca.mpreg.webgpuviewer.transition.TransitionCubeOuter
import ca.mpreg.webgpuviewer.transition.TransitionFade
import ca.mpreg.webgpuviewer.transition.TransitionFadeWhite
import ca.mpreg.webgpuviewer.transition.TransitionFlip
import ca.mpreg.webgpuviewer.transition.TransitionFlipLeft
import ca.mpreg.webgpuviewer.transition.TransitionFlipRight
import ca.mpreg.webgpuviewer.transition.TransitionNone
import ca.mpreg.webgpuviewer.transition.TransitionSphere
import ca.mpreg.webgpuviewer.transition.TransitionStackDown
import ca.mpreg.webgpuviewer.transition.TransitionStackLeft
import ca.mpreg.webgpuviewer.transition.TransitionStackRight
import ca.mpreg.webgpuviewer.transition.TransitionStackUp
import ca.mpreg.webgpuviewer.viewer.ImagePage
import com.google.android.material.color.MaterialColors
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.ui.reader.ReaderActivity
import eu.kanade.tachiyomi.ui.reader.model.ReaderChapter
import eu.kanade.tachiyomi.ui.reader.model.ReaderPage
import eu.kanade.tachiyomi.ui.reader.model.ViewerChapters
import eu.kanade.tachiyomi.ui.reader.setting.ReaderPreferences
import eu.kanade.tachiyomi.ui.reader.setting.ReaderPreferences.TransitionAnimation
import eu.kanade.tachiyomi.ui.reader.viewer.ReaderPageImageView
import eu.kanade.tachiyomi.ui.reader.viewer.Viewer
import eu.kanade.tachiyomi.ui.reader.viewer.ViewerNavigation.NavigationRegion
import eu.kanade.tachiyomi.util.system.createReaderThemeContext
import eu.kanade.tachiyomi.util.system.readerBackgroundColor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import logcat.LogPriority
import mihon.app.di.globalAppGraph
import mihon.core.concurrency.AppDispatchersHolder
import tachiyomi.core.common.util.system.logcat
import java.util.TreeSet
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.min
import kotlin.time.Duration.Companion.milliseconds

/** Edge pages of an adjacent chapter to reserve shells for up front (see preloadChapterThenRetry). */
private const val CHAPTER_EDGE_PRELOAD = 4

/** Sentinel for "this chapter slot has never been reconciled", and for an absent neighbour. */
private const val UNSEEN_VERSION = -1

/** How far either side of the anchor [continuousPage] will cache; wider asks walk uncached. */
private const val CONTINUOUS_PAGE_CACHE_RADIUS = 64

open class WebGpuViewer(
    val activity: ReaderActivity,
    val isReversed: Boolean,
    override val isVertical: Boolean,
    val pager: ImageView = ImageView(activity, isVertical = isVertical, isReversed = isReversed),
) : Viewer {

    private val positionStore by lazy { WebGpuReadingPositionStore(activity) }

    // KMK -->
    private var pendingContinuousRestoreChapterId: Long? = null
    private var pendingPagedRestoreChapterId: Long? = null

    /** Last Ready anchor from the viewer state; drive progress/save display from this. */
    @Volatile
    var currentAnchor: PageAnchor = PageAnchor(pageIndex = 0)
        private set
    // KMK <--

    open val isContinuous: Boolean = false

    val readerPreferences by lazy { globalAppGraph.readerPreferences }
    internal val translationManager by lazy {
        try {
            globalAppGraph.translationManager
        } catch (_: Exception) {
            null
        }
    }

    // KMK -->
    /** Resolved once: render() asks per frame, and createReaderThemeContext builds Resources. */
    @Volatile
    private var cachedBackgroundColor: Int? = null

    @Volatile
    private var cachedOnBackgroundColor: Int? = null
    // KMK <--

    // KMK -->
    private val darkModeFilter = WebGpuDarkModeFilter()

    private val brightnessContrastFilter = FilterBrightnessContrast()

    private val hlgFilter = FilterHlg()

    private val lutFilter = FilterLut3d()

    private val einkGrayscaleFilter = FilterGrayscale(saturation = 1f)

    @Volatile
    private var appliedLutKey: String? = null

    @Volatile
    private var lutResolveGeneration = 0

    @Volatile
    private var perfHudView: TextView? = null

    @Volatile
    private var perfHudLastUpdate = 0L
    // KMK <--

    // KMK -->
    private var artCnnUpscaler: UpscalerArtCnn? = null
    // KMK <--

    // KMK -->
    private val trimCallbacks = object : ComponentCallbacks2 {
        override fun onConfigurationChanged(newConfig: Configuration) = Unit
        override fun onLowMemory() = shrinkCacheOnTrim()

        @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
        override fun onTrimMemory(level: Int) {
            // KMK --> Screen-off is TRIM_MEMORY_UI_HIDDEN (20), and this guard used to require
            // MODERATE (60) - so every sleep held the whole decoded working set. The numeric
            // order is not the urgency order: RUNNING_CRITICAL (15) matters more than UI_HIDDEN
            // (20), so a single `>=` cannot express this set.
            if (
                level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL
            ) {
                shrinkCacheOnTrim()
            }
            // KMK <--
        }
    }
    // KMK <--

    private val deviceLostListener =
        ca.mpreg.webgpuviewer.renderer.WebGpuRenderer.Companion.DeviceLostListener { _, _ ->
            if (isDestroyed) return@DeviceLostListener
            // KMK --> Counted on the loss itself, not on a successful recovery: a device loss
            // on a phone is usually the app being backgrounded and the GPU going away, and
            // recovery routinely succeeds either way, so waiting for success would under-count.
            runCatching { mihon.app.di.globalAppGraph.achievementManager.incrementCounter("webgpu_rescues") }
            scope.launch {
                try {
                    val recovered = pager.state.recoverFromDeviceLoss()
                    if (!recovered) {
                        logcat(LogPriority.ERROR) { "WebGPU device lost and recovery failed" }
                    }
                    resetDecodedPagesAfterDeviceLoss()
                    try {
                        pager.state.invalidate()
                    } catch (_: Exception) {
                    }
                } catch (_: Exception) {
                }
            }
        }

    private fun resetDecodedPagesAfterDeviceLoss() {
        try {
            ProgressPage.destroyPineappleTexture()
        } catch (_: Exception) {
        }
        synchronized(lock) {
            if (isDestroyed) return
            decodeQueue.clear()
            stuckSignal.trySend(Unit)
            val snapshot = pageCache.values.toList()
            snapshot.forEach {
                it.state = PageState.IDLE
                (it as? ViewerReaderPage)?.let { readerPage ->
                    try {
                        resetSpreadHeightRetry(readerPage)
                    } catch (_: Exception) {
                    }
                    try {
                        readerPage.spreadPage?.cleanup()
                    } catch (_: Exception) {
                    }
                    readerPage.spreadBytes = null
                    readerPage.rescaleInFlight = false
                    readerPage.cleanupCompare()
                }
                try {
                    it.imagePage.cleanup()
                } catch (_: Exception) {
                }
            }
            pageCache.clear()
            stuckRecords.clear()
            loneIndices.clear()
            val previous = currentPage
            currentPage = (previous as? ViewerReaderPage)?.page?.let { getPage(it, previous) }
                ?: (previous as? ViewerTransitionPage)?.let {
                    getPage(it.prevChapter, it.nextChapter, previous)
                }
            currentPage?.let { preloadPages(it) }
        }
    }

    // KMK -->
    /** Resolved once: decodeReaderPage runs per page on the decode thread. */
    internal val isLowRamDevice: Boolean by lazy {
        try {
            eu.kanade.tachiyomi.util.system.DeviceUtil.isLowRamDevice(activity)
        } catch (_: Exception) {
            false
        }
    }
    // KMK <--

    internal fun readerBackgroundColor(): Int =
        cachedBackgroundColor ?: activity.baseContext.readerBackgroundColor(config.theme)
            .also { cachedBackgroundColor = it }

    internal fun readerOnBackgroundColor(): Int = cachedOnBackgroundColor ?: MaterialColors.getColor(
        activity.createReaderThemeContext(),
        com.google.android.material.R.attr.colorOnBackground,
        Color.WHITE,
    ).also { cachedOnBackgroundColor = it }

    internal val scope = MainScope()

    @Volatile
    internal var isDestroyed = false

    // Dedicated thread for decode worker to avoid blocking Dispatchers.Default pool
    private val decodeExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "WebGpuViewer-Decode").apply { isDaemon = true }
    }
    internal val decodeDispatcher = decodeExecutor.asCoroutineDispatcher()

    // Single lock for all page cache and queue operations
    @Suppress("PLATFORM_CLASS_MAPPED_TO_KOTLIN")
    internal val lock = Object()

    // Page cache - keyed by stable PageKey for O(1) lookup
    internal val pageCache = LinkedHashMap<PageKey, ViewerPage>()

    /**
     * How the liveness sweep has had to recover each page, keyed like [pageCache] so a shell that is
     * torn down and rebuilt cannot reset its own record by being replaced.
     *
     * Deliberately viewer-level rather than a field on the shell: the escalation this drives
     * rebuilds the page, and a counter living on the shell would start over on the new one, which is
     * precisely the loop it exists to stop.
     */
    internal val stuckRecords = HashMap<PageKey, StuckPageRecord>()

    // Decode queue - pages waiting to be decoded, processed LIFO (last = highest priority)
    internal val decodeQueue = ArrayDeque<ViewerReaderPage>()

    /**
     * Requests a stuck-page sweep. Conflated, so signalling during a burst of evictions costs one
     * scan. Emitted from the sites that can strand a page in an in-flight state without work behind
     * it; see the collector in `init`.
     */
    internal val stuckSignal = Channel<Unit>(Channel.CONFLATED)

    // KMK -->
    private val chapterPreloadGuard = ChapterPreloadGuard()
    // KMK <--

    /**
     * Indices of the pages that take a spread to themselves, by chapter - see [spreadStartIndex].
     * Outlives [pageCache]: every page after one of these depends on it, long since evicted.
     */
    private val loneIndices = HashMap<Long?, TreeSet<Int>>()

    /** Above this, an untagged page is a spread already, not half of one. */
    internal val wideAspect = 1.2f

    /** How far two untagged pages' aspect ratios may differ and still pair. */
    private val pairAspectTolerance = 0.1f

    /** Read live: these pages are built before the surface has a size, and outlive a rotation. */
    internal fun viewportPageWidth(half: Boolean): Int {
        val w = try {
            pager.state.width
        } catch (_: Exception) {
            0
        }
        if (w < 8) return 8
        return if (half) (w / 2).coerceAtLeast(8) else w.coerceAtLeast(8)
    }

    private val anchorPosition get() = if (isReversed xor config.invertDoublePages) SpreadPosition.RIGHT else SpreadPosition.LEFT

    private val partnerPosition get() = if (isReversed xor config.invertDoublePages) SpreadPosition.LEFT else SpreadPosition.RIGHT

    /**
     * Which half a page falls on when nothing tags the file: alternating from its spread's start,
     * anchor then partner. SINGLE outside dual page mode, so nothing pairs while one page fills
     * the viewer.
     */
    internal fun derivedSpreadPosition(page: ReaderPage): SpreadPosition {
        if (!isDualPageMode()) return SpreadPosition.SINGLE
        if (page.splitSegment) return SpreadPosition.SINGLE
        val offset = page.index - spreadStartIndex(page.chapter.chapter.id, page.index)
        return if (offset >= 0 && offset % 2 == 0) anchorPosition else partnerPosition
    }

    /**
     * Where the spread holding [index] starts: just past the last page before it that took one to
     * itself, so the page after a detected spread opens the next one instead of inheriting a parity
     * that page broke. Defaults to 1 - page 0 is the cover, and pairs with nothing.
     */
    private fun spreadStartIndex(chapterId: Long?, index: Int): Int {
        val base = synchronized(lock) { loneIndices[chapterId]?.lower(index) }?.plus(1) ?: 1
        // Shifted pairing starts one page earlier, so the cover pairs instead
        // of standing solo — the WebGPU equivalent of the legacy pager's
        // shift button. Lone-page segmentation is preserved either way.
        return if (config.shiftDoublePage) (base - 1).coerceAtLeast(0) else base
    }

    /** Registers whether [page] stands alone, for [spreadStartIndex]. Must hold [lock]. */
    internal fun noteIfLone(page: ViewerReaderPage) {
        if (page.page.splitSegment) return
        val indices = loneIndices.getOrPut(page.page.chapter.chapter.id) { TreeSet() }
        if (page.standsAlone) indices.add(page.page.index) else indices.remove(page.page.index)
    }

    /**
     * Whether these two may share a spread, beyond their positions agreeing. Both tagged is taken
     * as read; a pair resting on page order needs the same shape - halves of one sheet scan alike.
     * Undecoded pairs anyway, or a loading page draws its ring mid-screen.
     */
    internal fun canPairShapes(anchor: ViewerReaderPage, partner: ViewerReaderPage): Boolean {
        if (anchor.taggedSpreadPosition != null && partner.taggedSpreadPosition != null) return true
        val a = anchor.aspectRatio ?: return true
        val b = partner.aspectRatio ?: return true
        return abs(a - b) <= pairAspectTolerance
    }

    internal fun findInCache(key: PageKey): ViewerPage? = pageCache[key]

    /** Check if a page is in the cache by identity. O(1) via key lookup. */
    internal fun pageInCache(page: ViewerPage): Boolean = pageCache[pageKey(page)] === page

    /**
     * Drops cached shells for pages a split has replaced, and reports the page the viewer should
     * land on if it was showing one of them.
     *
     * A page too tall for the decoder is replaced by its segments after this viewer has already
     * built its page graph. The parent shell stays cached under its own [PageKey.Reader] and keeps
     * rendering the segment its stream now points at, while the chapter's list also holds that
     * segment - so the strip was drawn twice, the whole and the pieces overlapping. Nothing else
     * evicts it: it is not idle, not farthest, and its key still looks valid.
     *
     * Returns the shell that was on screen when a split removed it, or null when nothing the viewer
     * was showing was removed.
     */
    private fun evictReplacedPages(): ViewerReaderPage? {
        var dropped: ViewerReaderPage? = null
        synchronized(lock) {
            val orphaned = pageCache.values.filterIsInstance<ViewerReaderPage>()
                .filter { it.page.supersededBySplit }
            if (orphaned.isEmpty()) return null
            orphaned.forEach { shell ->
                pageCache.remove(pageKey(shell))
                decodeQueue.remove(shell)
                stuckSignal.trySend(Unit)
                runCatching {
                    shell.spreadPage?.cleanup()
                    shell.spreadBytes = null
                    shell.imagePage.cleanup()
                }
            }
            // Read through a local: currentPage is a var, so the compiler will not smart-cast it past
            // the check below, and the shell is the only thing still holding the page once it is
            // out of the cache.
            val shown = currentPage
            if (shown is ViewerReaderPage && shown in orphaned) {
                dropped = shown
                currentPage = null
            }
        }
        return dropped
    }

    /**
     * Last [ReaderChapter.pageListVersion] reconciled against, per chapter slot.
     *
     * All three slots, not just the current chapter: the strip spans prev/current/next, and the
     * chapter that gets split mid-session is as likely to be one the reader is only part-way into
     * as the one they are on. Watching the current chapter alone left those splits unreconciled,
     * which is the in-between-chapters case.
     *
     * A flat list rather than one packed int because each chapter counts independently, so any
     * packing scheme eventually folds two distinct triples onto the same value and hides a change.
     */
    private var seenPageListVersions = intArrayOf(UNSEEN_VERSION, UNSEEN_VERSION, UNSEEN_VERSION)

    /** Page-list versions of the three chapters a strip spans, in slot order. */
    private fun ViewerChapters.pageListVersions(): IntArray = intArrayOf(
        currChapter.pageListVersion,
        prevChapter?.pageListVersion ?: UNSEEN_VERSION,
        nextChapter?.pageListVersion ?: UNSEEN_VERSION,
    )

    /**
     * Reconciles against a page list the loader replaced underneath us.
     *
     * Cheap when nothing changed: three volatile int compares. Returns true when the viewer had to
     * move off a page the split removed, so the caller should stop - it was about to walk outward
     * from a node that no longer exists, and re-anchoring has already queued the right pages.
     */
    internal fun syncPageList(chapters: ViewerChapters): Boolean {
        val version = chapters.pageListVersions()
        if (version.contentEquals(seenPageListVersions)) return false
        seenPageListVersions = version
        val discarded = evictReplacedPages() ?: return false
        // Re-enter from whatever now stands in the discarded page's place - not from the chapter's
        // resume target, which is where the chapter was opened and can be pages away from where the
        // reader actually was.
        val replacement = discarded.page.chapter.splitReplacementOf(discarded.page) ?: discarded.page
        moveToPage(getSpreadAnchor(getPage(replacement, discarded)))
        return true
    }

    init {
        // KMK --> Shed off-screen decoded pages on system memory pressure.
        try {
            activity.registerComponentCallbacks(trimCallbacks)
        } catch (_: Exception) {}
        // KMK <--
        try {
            ca.mpreg.webgpuviewer.renderer.WebGpuRenderer.addDeviceLostListener(deviceLostListener)
        } catch (_: Exception) {}
        // Decode worker thread - processes pages from the queue. Hardened: respects scope
        // cancellation, handles spurious wakeups, avoids tight-loop on evicted pages, and
        // surfaces OOM as a retryable error page instead of killing the worker.
        scope.launch(decodeDispatcher) {
            try {
                while (!isDestroyed) {
                    val page: ViewerReaderPage? = synchronized(lock) {
                        while (decodeQueue.isEmpty() && !isDestroyed) {
                            try {
                                lock.wait(1000)
                            } catch (_: InterruptedException) {
                                Thread.currentThread().interrupt()
                                return@launch
                            }
                        }
                        if (decodeQueue.isEmpty()) return@synchronized null
                        decodeQueue.removeLast().apply { state = PageState.DECODING }
                    }
                    if (page == null) continue

                    val shouldProcess = synchronized(lock) {
                        pageInCache(page) && page.state == PageState.DECODING && !page.isDecoded
                    }

                    if (!shouldProcess) {
                        synchronized(lock) {
                            if (pageInCache(page) && page.state == PageState.DECODING) {
                                page.state = PageState.IDLE
                            }
                        }
                        continue
                    }

                    try {
                        decodeReaderPage(page)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: OutOfMemoryError) {
                        logcat(LogPriority.ERROR) { "decodeReaderPage OOM: ${e.message}" }
                        System.gc()
                        synchronized(lock) {
                            if (pageInCache(page) && !page.isDecoded && !page.imagePage.destroyed) {
                                val oldImagePage = page.imagePage
                                page.imagePage = ErrorPage(this@WebGpuViewer, "Out of memory", page.spreadPosition)
                                page.state = PageState.IDLE
                                oldImagePage.cleanup()
                                page.imagePage.invalidate()
                            } else if (pageInCache(page)) {
                                page.state = PageState.IDLE
                            }
                        }
                    } catch (e: Throwable) {
                        if (e is CancellationException) throw e
                        val isLinkage = e is LinkageError || e is NoClassDefFoundError || e is UnsatisfiedLinkError
                        logcat(LogPriority.ERROR, e) { "decodeReaderPage${if (isLinkage) " linkage" else ""}: ${e.message}" }
                        synchronized(lock) {
                            if (pageInCache(page) && !page.isDecoded && !page.imagePage.destroyed) {
                                val oldImagePage = page.imagePage
                                val errorMessage = when {
                                    isLinkage -> "Decoder not available on this device"
                                    e.message?.isNotBlank() == true -> e.message!!
                                    else -> "Failed to decode image"
                                }
                                page.imagePage = ErrorPage(this@WebGpuViewer, errorMessage, page.spreadPosition)
                                page.state = PageState.IDLE
                                oldImagePage.cleanup()
                                page.imagePage.invalidate()
                            } else if (pageInCache(page)) {
                                page.state = PageState.IDLE
                            }
                        }
                    } finally {
                        // KMK --> DECODING must never outlive the attempt. The catch arms above all
                        // end in an ErrorPage or an IDLE reset, but decodeReaderPage also returns
                        // normally on several paths (destroyed viewer, stream unavailable, already
                        // decoded, evicted mid-flight) - and a plain return skips every catch, so
                        // the page kept DECODING with nothing left to move it. queueForDecode treats
                        // DECODING as in-flight and ignores it, so the shell then spun forever.
                        // Resetting here makes "the worker is not on this page anymore" the single
                        // invariant every exit path agrees on.
                        // KMK <--
                        synchronized(lock) {
                            if (pageInCache(page) && page.state == PageState.DECODING) {
                                page.state = PageState.IDLE
                            }
                        }
                        // The worker leaving a page is what makes any leftover in-flight state
                        // detectable, so this is the natural point to look.
                        stuckSignal.trySend(Unit)
                    }
                }
            } catch (e: CancellationException) {
                // Scope cancelled — normal shutdown
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } catch (e: Exception) {
                logcat(LogPriority.ERROR, e) { "Decode worker died" }
            }
        }

        // KMK --> Liveness net. Every state a page can sit in is owned by one of a small number of
        // writers, and a missed reset on any path (a cancelled load, an early return, a future
        // branch) leaves the shell in a state queueForDecode treats as in-flight - so it is never
        // re-queued and spins forever.
        //
        // Driven by signal rather than a timer because the orphan condition - QUEUED but absent from
        // the queue, or LOADING whose bytes have since arrived - cannot arise on its own: it needs a
        // structural change to the queue or cache, and only a few sites perform one. A timer would
        // pay a lock acquisition and a scan of every live shell for the whole session to find a
        // condition those sites create anyway.
        //
        // Conflated so a burst of evictions costs one scan rather than one per eviction.
        scope.launch {
            for (signal in stuckSignal) {
                if (isDestroyed) break
                try {
                    val orphans = synchronized(lock) {
                        pageCache.values.filterIsInstance<ViewerReaderPage>().filter { page ->
                            if (page.isDecoded || page.imagePage.destroyed) return@filter false
                            when (page.state) {
                                // Queued but absent from the queue: nothing will ever pop it.
                                PageState.QUEUED -> !decodeQueue.contains(page)
                                // LOADING is only released when the bytes are already there: a page
                                // genuinely fetching must keep its state, and queueForDecode will
                                // promote it the moment it reports Ready.
                                PageState.LOADING -> page.page.status == Page.State.Ready
                                // The terminal case: not being worked on at all. The renderer
                                // reached this page (fetchPage called ensureDecoding), so it is on
                                // screen or prewarmed, and nothing else will schedule it - a decode
                                // that bailed mid-flight, or a state left IDLE by an exit path,
                                // strands it behind its placeholder indefinitely. Checking
                                // wantedByRender is what keeps this from queueing speculative shells
                                // that only a preload walk ever touched.
                                PageState.IDLE -> page.wantedByRender && page.imagePage is ProgressPage
                                else -> false
                            }
                        }
                    }
                    if (orphans.isEmpty()) continue
                    // A page inside its cooldown is not an event: logging it would be the spew this
                    // sweep is meant to stop, and re-driving it is what could not terminate.
                    var reArm = false
                    val acted = ArrayList<ViewerReaderPage>(orphans.size)
                    orphans.forEach { page ->
                        when (requeueStuckPage(page)) {
                            StuckRecovery.REDRIVEN, StuckRecovery.REBUILT -> acted += page
                            StuckRecovery.DEFERRED -> reArm = true
                            StuckRecovery.GONE -> Unit
                        }
                    }
                    if (acted.isEmpty()) {
                        // Every orphan was cooling down. The signal that woke this pass is spent, so
                        // nothing would come back to retry them - re-arm once the cooldown is up,
                        // which is what keeps a slow page still being retried rather than dropped.
                        if (reArm) {
                            delay(STUCK_REDRIVE_COOLDOWN_MS)
                            stuckSignal.trySend(Unit)
                        }
                        continue
                    }
                    logcat(LogPriority.WARN) {
                        "Re-driving ${acted.size} stuck page(s): " +
                            acted.joinToString { "${it.page.chapter.chapter.id}/${it.page.index}=${it.state}" }
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                }
            }
        }

        // KMK -->
        // Drives the live spin of the ProgressPage pineapple while a page is loading.
        // ProgressPage is time-based; without periodic invalidate the viewer would render
        // it once and the animation would freeze.
        scope.launch {
            while (!isDestroyed) {
                try {
                    val progress = currentPage?.imagePage as? ProgressPage
                    if (progress == null) {
                        // Nothing to animate: suspend until a ProgressPage becomes current, rather
                        // than waking every 250ms for the rest of the session - 4 CPU wakeups a
                        // second the reader cannot use, for most of a long reading session. The
                        // flow emission wakes this on its own.
                        if (config.perfHud) syncPerfHud()
                        // Suspends without consuming CPU until a page whose image is a ProgressPage
                        // becomes current. first{} also passes straight through if the current page
                        // already qualifies, so the spin starts on the same iteration.
                        currentPageFlow.first { (it as? ViewerReaderPage)?.imagePage is ProgressPage }
                        continue
                    }
                    progress.invalidate()
                    delay(33.milliseconds)
                    if (config.perfHud) syncPerfHud()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // A failed spin frame must not kill the loop, or the indicator freezes forever.
                    delay(250.milliseconds)
                }
            }
        }
        // KMK <--
    }

    /**
     * Configuration used by the pager, like allow taps, scale mode on images, page transitions...
     */
    val config = WebGpuConfig(this, scope, readerPreferences)

    // KMK -->
    private fun applyPageOffset() {
        try {
            val offset = config.pageOffset
            if (offset == 0) {
                pager.translationX = 0f
                return
            }
            val w = if (pager.width > 0) pager.width else activity.resources.displayMetrics.widthPixels
            pager.translationX = w * offset / 100f * 0.5f
        } catch (_: Exception) {
        }
    }
    // KMK <--

    // KMK -->
    /**
     * Re-resolves spread pairing after [WebGpuConfig.shiftDoublePage] toggles.
     * Positions derive live, so a re-fetch is enough to re-pair everything.
     */
    fun refreshSpreads() {
        if (isDestroyed) return
        try {
            pager.state.invalidate()
        } catch (_: Exception) {
        }
    }
    // KMK <--

    // Read from the render and decode threads, via the prevChapter/nextChapter getters.
    @Volatile
    var viewerChapters: ViewerChapters? = null

    val pages: List<ReaderPage>? get() = (currentPage as? ViewerReaderPage)?.page?.chapter?.pages

    /** Mirrors [currentPage] so a coroutine can suspend on it instead of polling. */
    internal var currentPageFlow = MutableStateFlow<ViewerPage?>(null)

    /** The page the reader is on. Mirrored into [currentPageFlow] so observers can suspend on it. */
    @Volatile
    var currentPage: ViewerPage? = null
        set(value) {
            field = value
            // Every writer already sets this under the viewer's lock, so mirroring here keeps the
            // flow and the field consistent without each call site having to do both.
            currentPageFlow.value = value
            if (continuousPageAnchor !== value) {
                continuousPageAnchor = value
                continuousPageKnown.fill(false)
            }
        }

    // KMK --> Page-lookup cache for continuous mode. The render walk asks fetchPage for every page
    // in the window on every frame, and each ask walked the neighbour chain from the anchor - so a
    // window reaching six pages below cost 1+2+3+4+5+6 chain steps, all of it on the main thread
    // inside the viewer's lock. Filled in as the walk goes, so the whole window costs one pass.
    // Invalidated whenever the anchor moves; entries hold page identities, and a decode swaps a
    // page's image rather than its identity, so a shell landing mid-frame is still seen.
    private val continuousPageSlots = arrayOfNulls<ViewerPage>(2 * CONTINUOUS_PAGE_CACHE_RADIUS + 1)
    private val continuousPageKnown = BooleanArray(2 * CONTINUOUS_PAGE_CACHE_RADIUS + 1)

    @Volatile
    private var continuousPageAnchor: ViewerPage? = null

    private fun continuousPage(index: Int): ViewerPage? {
        if (index !in -CONTINUOUS_PAGE_CACHE_RADIUS..CONTINUOUS_PAGE_CACHE_RADIUS) {
            return walkContinuousPage(index)
        }
        val slot = index + CONTINUOUS_PAGE_CACHE_RADIUS
        if (continuousPageKnown[slot]) return continuousPageSlots[slot]

        val anchor = continuousPageAnchor ?: currentPage ?: return null
        if (continuousPageAnchor !== anchor) {
            continuousPageAnchor = anchor
            continuousPageKnown.fill(false)
        }
        continuousPageSlots[CONTINUOUS_PAGE_CACHE_RADIUS] = anchor
        continuousPageKnown[CONTINUOUS_PAGE_CACHE_RADIUS] = true

        // Walks outward from the anchor, recording every index it passes so a later ask for a
        // nearby index is a cache hit instead of a fresh chain walk.
        var page: ViewerPage? = anchor
        val step = if (index > 0) 1 else -1
        var at = 0
        while (at != index) {
            page = if (step > 0) page?.next else page?.prev
            at += step
            val atSlot = at + CONTINUOUS_PAGE_CACHE_RADIUS
            if (page == null) {
                continuousPageSlots[atSlot] = null
                continuousPageKnown[atSlot] = true
                return null
            }
            continuousPageSlots[atSlot] = page
            continuousPageKnown[atSlot] = true
        }
        return page
    }

    private fun walkContinuousPage(index: Int): ViewerPage? {
        var page: ViewerPage? = currentPage ?: return null
        val step = if (index > 0) 1 else -1
        repeat(abs(index)) {
            page = (if (step > 0) page?.next else page?.prev) ?: return null
        }
        return page
    }

    // KMK --> User-tunable preload window; continuous takes max() with live reach.
    open val preloadAhead get() = config.preloadAhead
    open val preloadBehind get() = config.preloadBehind
    // KMK <--

    /**
     * Everything [preloadPages] reaches, plus slack. Sized exactly, a chapter transition page - or
     * in dual mode a spread partner - evicts a page the next fetch asks for, and it decodes again.
     */
    open val cacheSize get() = 1 + preloadAhead + preloadBehind + if (isDualPageMode()) 3 else 1

    /**
     * Kicks off loading [chapter] and, once its pages actually show up, re-runs
     * [preloadPages] from the current page - [ReaderActivity]'s viewModel.preload isn't
     * guaranteed to have finished loading by the time it returns, so a single immediate
     * retry can race it and silently never queue the adjacent chapter's edge page for
     * decode. Gives up after 5 seconds if the chapter never finishes loading.
     *
     * Guarded by [chapterPreloadGuard]: this method is reached through the prev/next
     * getters, which the pager library re-evaluates on every render snapshot and gesture
     * frame while nearing a boundary. Unguarded, each hit spawned its own preload +
     * polling cycle - many concurrent ChapterLoader runs and preload walks that showed
     * up as freezing/choppiness at chapter transitions.
     */
    internal fun preloadChapterThenRetry(chapter: ReaderChapter) {
        if (isDestroyed) return
        val key = chapter.chapter.url.takeIf { it.isNotBlank() } ?: "chapter-${chapter.chapter.id}"
        // Reserve placeholder ProgressPage shells immediately so contentHeight reflects true length and scroll doesn't wrap
        val pages = chapter.pages
        // Reference eviction from the page the user is actually reading. Without this, getPage
        // falls back to using the newly created shell as the eviction reference and background
        // preload evicts the current chapter's pages - including the page on screen - which
        // reverts the reader to a loading screen (black flash) until the next chapter is decoded.
        val evictionReference = currentPage
        // Only reserve the edge window: creating a shell for every page of the
        // adjacent chapter blows the small page cache and evicts the pages being
        // read, which then redraw as placeholders (flicker). Four covers the
        // continuous reach, the pager preload window, and the transition page.
        val edgePages = when {
            pages == null -> emptyList()
            chapter === viewerChapters?.prevChapter -> pages.takeLast(CHAPTER_EDGE_PRELOAD)
            else -> pages.take(CHAPTER_EDGE_PRELOAD)
        }
        for (pg in edgePages) {
            try {
                val shell = getPage(pg, evictionReference)
                preloadPage(shell, prioritize = false)
            } catch (_: Exception) {}
        }
        if (!chapterPreloadGuard.tryBegin(key)) {
            // If already in-flight but decodeQueue no longer contains its edge page, allow requeue (stale guard).
            // The queue probe is chapter-qualified: bare index matching collides across chapters
            // (every chapter has an index 0..3), which read the guard as stale on every boundary
            // approach and refired the whole preload cycle in a loop.
            val isStale = edgePages.firstOrNull()?.let { pg ->
                val k = PageKey.Reader(chapter.chapter.id, pg.index)
                val chapterId = chapter.chapter.id
                synchronized(lock) {
                    findInCache(k) == null ||
                        decodeQueue.none { it.page.chapter.chapter.id == chapterId && it.page.index == pg.index }
                }
            } ?: false
            if (!isStale) return
            chapterPreloadGuard.end(key)
            if (!chapterPreloadGuard.tryBegin(key)) return
        }

        scope.launch(AppDispatchersHolder.get().default) {
            try {
                if (isDestroyed) return@launch
                activity.viewModel.preload(chapter)
                repeat(100) {
                    if (isDestroyed) return@launch
                    if (chapter.state is ReaderChapter.State.Loaded) {
                        val loadedPages = chapter.pages
                        val loadedEdgePages = when {
                            loadedPages == null -> emptyList()
                            chapter === viewerChapters?.prevChapter -> loadedPages.takeLast(CHAPTER_EDGE_PRELOAD)
                            else -> loadedPages.take(CHAPTER_EDGE_PRELOAD)
                        }
                        for (pg in loadedEdgePages) {
                            try {
                                val shell = getPage(pg, evictionReference)
                                preloadPage(shell, prioritize = false)
                            } catch (_: Exception) {}
                        }
                        chapterPreloadGuard.end(key)
                        currentPage?.let { if (!isDestroyed) preloadPages(it) }
                        return@launch
                    }
                    delay(50.milliseconds)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                logcat(LogPriority.ERROR, e) { "Chapter preload retry failed: $key" }
            } finally {
                chapterPreloadGuard.end(key)
            }
        }
    }

    init {
        pager.state.apply {
            // KMK --> Feed currentAnchor from coalesced Ready emissions (Idle/Released ignored).
            onReaderStateChanged = OnReaderStateChanged { state ->
                if (state is ReaderState.Ready) currentAnchor = state.anchor
            }
            // KMK <--
            fetchPage = fetch@{ index ->
                val current = currentPage ?: return@fetch null

                // KMK --> Continuous never forms spreads: getSpreadAnchor and
                // buildSpreadPage both early-return the page's own imagePage, so
                // skip them outright instead of re-proving it on every frame walk.
                // (Pager mode keeps the full pipeline, including the existing()
                // identity reuse inside buildSpreadPage.)
                if (isContinuous) {
                    val page = continuousPage(index)
                    if (page == null) return@fetch null
                    ensureDecoding(page)
                    return@fetch page.imagePage
                }
                // KMK <--

                // For index 0, return the current spread
                if (index == 0) {
                    val anchor = getSpreadAnchor(current)
                    ensureDecoding(anchor)
                    return@fetch buildSpreadPage(anchor)
                }

                // Navigate by spreads from current
                var page = current
                val step = if (index > 0) 1 else -1
                repeat(abs(index)) {
                    page = nextPage(page, step) ?: return@fetch null
                }

                val anchor = getSpreadAnchor(page)
                ensureDecoding(anchor)
                return@fetch buildSpreadPage(anchor)
            }

            onTap = { offset ->
                val current = currentPage as? ViewerReaderPage
                if (current != null && current.imagePage is ErrorPage) {
                    // KMK -->
                    // Tap on an error page retries the decode/load.
                    synchronized(lock) {
                        current.imagePage.cleanup()
                        current.imagePage = ProgressPage(this@WebGpuViewer)
                        current.state = PageState.IDLE
                    }
                    queueForDecode(current, prioritize = true)
                    pager.state.invalidate()
                    // KMK <--
                } else {
                    when (config.navigator.getAction(PointF(offset.x, offset.y))) {
                        NavigationRegion.MENU -> activity.toggleMenu()
                        NavigationRegion.NEXT -> if (isReversed) moveToPrevious() else moveToNext()
                        NavigationRegion.PREV -> if (isReversed) moveToNext() else moveToPrevious()
                        NavigationRegion.RIGHT -> if (isReversed) moveLeft() else moveRight()
                        NavigationRegion.LEFT -> if (isReversed) moveRight() else moveLeft()
                    }
                }
            }

            onLongTap = { _ ->
                if (activity.viewModel.state.value.menuVisible || config.longTapEnabled) {
                    (currentPage as? ViewerReaderPage)?.let { activity.onPageLongTap(it.page) }
                }
            }
        }

        // KMK --> Single settings channel: SettingsDiff.highest picks rebuild vs live.
        config.onSettingsChanged = listener@{ diff ->
            if (isDestroyed) return@listener
            pager.state.doubleTapZoomEnabled = config.resolveDoubleTapZoom()

            if (diff.previous.doubleTapZoom != diff.current.doubleTapZoom ||
                diff.previous.disableZoomIn != diff.current.disableZoomIn
            ) {
                synchronized(lock) {
                    if (isDestroyed) return@listener
                    pageCache.values.toList().forEach { page ->
                        (page as? ViewerReaderPage)?.let { readerPage ->
                            (readerPage.imagePage as? ImagePage.ImageSingle)?.let { applyDoubleTapZoomPolicy(it) }
                            readerPage.spreadPage?.let { spread ->
                                (spread.left as? ImagePage.ImageSingle)?.let { applyDoubleTapZoomPolicy(it) }
                                (spread.right as? ImagePage.ImageSingle)?.let { applyDoubleTapZoomPolicy(it) }
                            }
                        }
                    }
                }
            }

            if (diff.highest >= SettingsImpact.REDECODE) {
                applyImageState()
                synchronized(lock) {
                    if (isDestroyed) return@listener
                    decodeQueue.clear()
                    // Snapshot to avoid ConcurrentModification if cleanup triggers callbacks
                    val snapshot = pageCache.values.toList()
                    snapshot.forEach {
                        it.state = PageState.IDLE
                        // KMK -->
                        (it as? ViewerReaderPage)?.let { readerPage ->
                            try {
                                readerPage.spreadPage?.cleanup()
                            } catch (_: Exception) {
                            }
                            readerPage.spreadBytes = null
                            readerPage.rescaleInFlight = false
                            readerPage.cleanupCompare()
                        }
                        // KMK <--
                        try {
                            it.imagePage.cleanup()
                        } catch (_: Exception) {
                        }
                    }
                    pageCache.clear()
                    stuckRecords.clear()
                    loneIndices.clear()

                    currentPage = (currentPage as? ViewerReaderPage)?.page?.let { getPage(it) }
                        ?: (currentPage as? ViewerTransitionPage)?.let {
                            getPage(it.prevChapter, it.nextChapter)
                        }

                    currentPage?.let { preloadPages(it) }
                }

                try {
                    pager.state.invalidate()
                } catch (_: Exception) {
                }
            } else {
                applyImageState()
                try {
                    applyPageOffset()
                } catch (_: Exception) {
                }
                try {
                    pager.state.invalidate()
                } catch (_: Exception) {
                }
            }
        }

        config.navigationModeChangedListener = {
            val showOnStart = config.navigationOverlayOnStart || config.forceNavigationOverlay
            activity.binding.navigationOverlay.setNavigation(config.navigator, showOnStart)
        }

        pager.state.doubleTapZoomEnabled = config.resolveDoubleTapZoom()
        pager.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            applyPageOffset()
            syncPerfHud()
        }
        scope.launch {
            try {
                readerPreferences.webgpuPageOffset().changes().collect { applyPageOffset() }
            } catch (_: Exception) {}
        }
        applyPageOffset()
        applyImageState()
        // KMK <--
    }

    // KMK -->
    private fun resolveLutFilter() {
        val preset = config.lutPreset
        val path = config.lutCustomPath
        val key = "$preset|$path"
        if (appliedLutKey == key) return
        if (preset == WEBGPU_LUT_PRESET_NONE) {
            appliedLutKey = key
            lutFilter.lut = null
            return
        }
        val builtIn = webgpuBuiltInLut(preset)
        if (builtIn != null) {
            appliedLutKey = key
            lutFilter.lut = builtIn
            return
        }
        if (preset == WEBGPU_LUT_PRESET_CUSTOM && path.isNotBlank()) {
            val generation = ++lutResolveGeneration
            scope.launch(decodeDispatcher) {
                try {
                    val parsed = webgpuParseCustomLut(path)
                    if (generation != lutResolveGeneration || isDestroyed) return@launch
                    appliedLutKey = key
                    lutFilter.lut = parsed
                    try {
                        pager.state.invalidate()
                    } catch (_: Exception) {
                    }
                } catch (_: Exception) {
                }
            }
            return
        }
        appliedLutKey = key
        lutFilter.lut = null
    }

    private fun applyTranslationCompare() {
        val showOriginal = config.compareTranslation
        synchronized(lock) {
            if (isDestroyed) return
            pageCache.values.toList().forEach { page ->
                val readerPage = page as? ViewerReaderPage ?: return@forEach
                if (!readerPage.hasTranslation) return@forEach
                val original = readerPage.compareOriginal ?: return@forEach
                if (original.destroyed) return@forEach
                if (showOriginal) {
                    val displayed = readerPage.imagePage
                    if (displayed !== original && displayed is ImagePage.ImageSingle) {
                        readerPage.compareTranslated?.let {
                            if (it !== displayed) {
                                try {
                                    it.cleanup()
                                } catch (_: Exception) {
                                }
                            }
                        }
                        readerPage.compareTranslated = displayed
                        readerPage.imagePage = original
                    }
                } else {
                    val parked = readerPage.compareTranslated ?: return@forEach
                    if (parked.destroyed) {
                        readerPage.compareTranslated = null
                        return@forEach
                    }
                    if (readerPage.imagePage !== parked) {
                        readerPage.imagePage = parked
                        readerPage.compareTranslated = null
                    }
                }
            }
        }
        try {
            pager.state.invalidate()
        } catch (_: Exception) {
        }
    }

    private fun syncPerfHud() {
        val want = config.perfHud && eu.kanade.tachiyomi.util.system.isDebugBuildType && !isDestroyed
        try {
            ca.mpreg.webgpuviewer.renderer.WebGpuRenderer.profilingEnabled = want
        } catch (_: Exception) {
        }
        if (!want) {
            try {
                perfHudView?.visibility = View.GONE
            } catch (_: Exception) {
            }
            return
        }
        val parent = pager.parent as? ViewGroup ?: return
        val hud = try {
            perfHudView ?: TextView(pager.context).apply {
                setBackgroundColor(0x99000000.toInt())
                setTextColor(0xFF00FF00.toInt())
                textSize = 11f
                typeface = android.graphics.Typeface.MONOSPACE
                setPadding(12, 8, 12, 8)
                visibility = View.GONE
                perfHudView = this
            }
        } catch (_: Exception) {
            null
        } ?: return
        if (hud.parent !== parent) {
            try {
                (hud.parent as? ViewGroup)?.removeView(hud)
                parent.addView(
                    hud,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        android.view.Gravity.TOP or android.view.Gravity.START,
                    ),
                )
            } catch (_: Exception) {
                return
            }
        }
        try {
            hud.visibility = View.VISIBLE
            hud.bringToFront()
            val now = android.os.SystemClock.uptimeMillis()
            if (now - perfHudLastUpdate < 500) return
            perfHudLastUpdate = now
            val renderer = ca.mpreg.webgpuviewer.renderer.WebGpuRenderer
            val poolKb = try {
                pager.state.filters.poolBytes() / 1024
            } catch (_: Exception) {
                -1L
            }
            hud.text = "avg %.1fms · fps %.0f · tile %dKB".format(
                renderer.recentAvgFrameTimeMs,
                renderer.estimatedFps,
                poolKb,
            )
        } catch (_: Exception) {
        }
    }
    // KMK <--

    // KMK -->
    /**
     * Applies state-only reader settings (transition, cutout, zoom floors, gap,
     * theme colors) without touching decoded pages. Prefs that change what a decode
     * produces (crop, dual-page geometry, match-heights, theme background baking)
     * still rebuild via [config.onSettingsChanged] when SettingsDiff.highest is
     * REDECODE or above.
     */
    private fun applyImageState() {
        if (isDestroyed) return
        // KMK --> A theme change comes through here.
        cachedBackgroundColor = null
        cachedOnBackgroundColor = null
        // KMK <--
        // KMK -->
        // Post-process color filters apply live with no page re-decode: uniforms
        // update in place and the chain reconciles attach/detach every state change.
        try {
            darkModeFilter.amoled = config.webgpuDarkModeAmoled
            darkModeFilter.tolerance = config.darkModeTolerance
            darkModeFilter.chunkRange = config.darkModeChunkRange
            darkModeFilter.enabled = config.webgpuDarkMode
            val effectiveContrast = if (config.einkPreset) {
                maxOf(config.contrast, 1.15f)
            } else {
                config.contrast
            }
            brightnessContrastFilter.brightness = config.brightness
            brightnessContrastFilter.contrast = effectiveContrast
            brightnessContrastFilter.enabled =
                config.brightness != 0f || effectiveContrast != 1f
            hlgFilter.exposure = config.hlgExposure
            hlgFilter.enabled = config.hlgEnabled
            einkGrayscaleFilter.saturation = if (config.einkPreset) 0f else 1f
            einkGrayscaleFilter.enabled = config.einkPreset
            lutFilter.intensity = config.lutIntensity
            lutFilter.enabled = true
            resolveLutFilter()
            val lutActive = lutFilter.lut != null && config.lutIntensity > 0f &&
                config.lutPreset != WEBGPU_LUT_PRESET_NONE
            val desired = buildList {
                if (brightnessContrastFilter.enabled) add(brightnessContrastFilter)
                if (hlgFilter.enabled) add(hlgFilter)
                if (lutActive) add(lutFilter)
                if (einkGrayscaleFilter.enabled) add(einkGrayscaleFilter)
                if (darkModeFilter.enabled) add(darkModeFilter)
            }
            val current = pager.state.filters.filters
            if (current != desired) {
                pager.state.filters.filters = desired
            } else {
                pager.state.invalidate()
            }
        } catch (_: Exception) {
        }
        try {
            applyTranslationCompare()
        } catch (_: Exception) {
        }
        try {
            syncPerfHud()
        } catch (_: Exception) {
        }
        // KMK <--
        // KMK -->
        // Swap the tile upscaler only on a real change: assigning drops every
        // generated tile, so an unconditional set here would re-gen tiles on
        // each state-only change. The cached instance is reused because the
        // setter is identity-guarded. Unsupported devices fall back to
        // Catmull-Rom inside the tile path by themselves.
        try {
            val wantArtCnn = config.artCnnUpscaler
            val hasArtCnn = pager.state.upscaler is UpscalerArtCnn
            if (wantArtCnn != hasArtCnn) {
                pager.state.upscaler = if (wantArtCnn) {
                    (artCnnUpscaler ?: UpscalerArtCnn().also { artCnnUpscaler = it })
                } else {
                    UpscalerCatmullRom()
                }
            }
        } catch (_: Exception) {
        }
        // KMK <--
        // KMK -->
        // Fast render skips the tile cache on decoded pages (direct mipmap draw);
        // flipping back reuses the same path once, tiles regenerate on demand.
        try {
            val fast = config.fastRender
            synchronized(lock) {
                pageCache.values.forEach {
                    (it.imagePage as? ImagePage.ImageSingle)?.let { single ->
                        if (!single.isAnimated) single.highQuality = !fast
                    }
                }
            }
            pager.state.invalidate()
        } catch (_: Exception) {
        }
        // KMK <--
        pager.state.apply {
            val isDual = isDualPageMode()
            transition = if (config.einkPreset) {
                if (isVertical) TransitionNone.Vertical else TransitionNone
            } else {
                when (if (isDual) config.transitionAnimationDual else config.transitionAnimation) {
                    // KMK -->
                    TransitionAnimation.NONE -> if (isVertical) TransitionNone.Vertical else TransitionNone
                    // KMK <--
                    TransitionAnimation.BASIC -> if (isVertical) TransitionBasic.Vertical else TransitionBasic
                    TransitionAnimation.FLIP -> TransitionFlip
                    TransitionAnimation.FLIP_LEFT -> TransitionFlipLeft
                    TransitionAnimation.FLIP_RIGHT -> TransitionFlipRight
                    TransitionAnimation.STACK_LEFT -> TransitionStackLeft
                    TransitionAnimation.STACK_RIGHT -> TransitionStackRight
                    TransitionAnimation.STACK_UP -> TransitionStackUp
                    TransitionAnimation.STACK_DOWN -> TransitionStackDown
                    TransitionAnimation.SPHERE -> TransitionSphere
                    TransitionAnimation.CUBE_INSIDE -> TransitionCube
                    TransitionAnimation.CUBE_OUTSIDE -> TransitionCubeOuter
                    TransitionAnimation.FADE -> TransitionFade
                    TransitionAnimation.FADE_WHITE -> TransitionFadeWhite
                }
            }

            when (if (isDual) config.cutoutModeDual else config.cutoutMode) {
                ReaderPreferences.CutoutMode.IGNORE -> avoidCutout = false

                ReaderPreferences.CutoutMode.AVOID -> {
                    avoidCutout = true
                    alwaysAvoidCutout = false
                }

                ReaderPreferences.CutoutMode.SHIFT -> {
                    avoidCutout = true
                    alwaysAvoidCutout = true
                }
            }

            (this as? ca.mpreg.webgpuviewer.viewer.ImageViewerContinuousState)?.let {
                // KMK -->
                // WEBTOON (long strip, no gap) always locks zoom-out to the strip
                // width; CONTINUOUS_VERTICAL follows the disable-zoom-out pref.
                val isWebtoonStrip = (this@WebGpuViewer as? WebGpuViewerContinuous)?.useGap == false
                val lockToStrip = isWebtoonStrip || config.zoomOutDisabled
                homeScale = config.continuousMinWidth / 100f
                minScale = if (lockToStrip) 0f else 0.1f
                // Never clobber the reader's zoom here: these listeners fire on
                // state-only changes too. Only lift out of an illegal range
                // (homeScale's own setter already lifts scale when the floor
                // itself rises).
                if (lockToStrip && scale < homeScale) scale = homeScale

                if ((this@WebGpuViewer as? WebGpuViewerContinuous)?.useGap == true) {
                    pageGap = config.continuousGap / 100f
                } else {
                    // WEBTOON (useGap = false) must pin the gap to 0 rather than leave it. The
                    // strip clears to transparent black (ImageViewerState.renderPass), so any gap
                    // the state still holds paints a hard black band between every page.
                    pageGap = 0f
                }
                // KMK <--
            }
        }
    }
    // KMK <--

    override fun destroy() {
        try {
            (currentPage as? ViewerReaderPage)?.let { reportPageSelected(it, force = true) }
        } catch (_: Exception) {}
        synchronized(lock) {
            if (isDestroyed) return
            isDestroyed = true
        }
        config.onSettingsChanged = null
        config.navigationModeChangedListener = null
        // KMK -->
        try {
            pager.state.onReaderStateChanged = null
        } catch (_: Exception) {}
        // KMK <--
        try {
            ca.mpreg.webgpuviewer.renderer.WebGpuRenderer.profilingEnabled = false
        } catch (_: Exception) {}
        try {
            perfHudView?.let { (it.parent as? ViewGroup)?.removeView(it) }
        } catch (_: Exception) {}
        perfHudView = null
        // KMK -->
        try {
            activity.unregisterComponentCallbacks(trimCallbacks)
        } catch (_: Exception) {}
        try {
            ca.mpreg.webgpuviewer.renderer.WebGpuRenderer.removeDeviceLostListener(deviceLostListener)
        } catch (_: Exception) {}
        // KMK <--
        try {
            scope.cancel()
        } catch (_: Exception) {
        }

        try {
            decodeExecutor.shutdownNow()
        } catch (_: Exception) {
        }
        try {
            decodeDispatcher.close()
        } catch (_: Exception) {
        }

        // KMK --> The shared pineapple spinner texture outlives pages (cached per
        // GPU device in ProgressPage); destroy it here so it never leaks the
        // old device across viewer teardown.
        try {
            ProgressPage.destroyPineappleTexture()
        } catch (_: Exception) {
        }
        // KMK <--
        synchronized(lock) {
            decodeQueue.clear()
            val snapshot = pageCache.values.toList()
            snapshot.forEach {
                it.state = PageState.IDLE
                (it as? ViewerReaderPage)?.let { readerPage ->
                    try {
                        resetSpreadHeightRetry(readerPage)
                    } catch (_: Exception) {
                    }
                    try {
                        readerPage.spreadPage?.cleanup()
                    } catch (_: Exception) {
                    }
                    readerPage.spreadBytes = null
                    readerPage.rescaleInFlight = false
                    readerPage.cleanupCompare()
                }
                try {
                    it.imagePage.cleanup()
                } catch (_: Exception) {
                }
            }
            pageCache.clear()
            stuckRecords.clear()
            loneIndices.clear()
            try {
                lock.notifyAll()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Returns the view this viewer uses.
     */
    override fun getView(): View = pager

    // KMK -->
    /**
     * Retry translating the currently displayed page after a failure (or when the
     * user explicitly requests it). Reads the source bytes again from the page stream
     * and re-runs the translation pipeline.
     */
    override fun retryTranslation() {
        retryCurrentPageTranslation()
    }

    fun retryCurrentPageTranslation() {
        if (isDestroyed) return
        val mgr = translationManager ?: return
        if (!mgr.isEnabled() || mgr.isGated()) return
        val page = currentPage as? ViewerReaderPage ?: return
        if (page.isDecoded) {
            scheduleTranslation(page, page.sourceBytes())
        }
    }
    // KMK <--

    /**
     * Reports the active [page] to the activity. When the page forms a spread in dual-page mode,
     * marks it as having an extra page so the counter shows "N-N+1" instead of just "N".
     */
    private fun reportPageSelected(page: ViewerReaderPage, force: Boolean = false) {
        val hasExtraPage = isDualPageMode() && canFormSpread(page)
        activity.onPageSelected(page.page, hasExtraPage)
        try {
            val cid = page.page.chapter.chapter.id
            if (cid != null && cid != -1L) {
                // KMK --> A deferred resume restore is pending for this chapter: the
                // viewport is not there yet, so saving now would clobber it with 0.
                if (isContinuous && pendingContinuousRestoreChapterId == cid) return
                if (!isContinuous && pendingPagedRestoreChapterId == cid) return
                // KMK <--
                // Live position, not Page.index: an anchor is restored with
                // coerceIn(0, pages.lastIndex), so a split segment's out-of-range index would
                // clamp to the chapter's last page and resume the reader at the end. This is what the
                // running session and the progress display are measured against.
                val position = page.page.chapter.positionOf(page.page)
                if (position < 0) return
                pager.state.seedPageIndex(position)
                val anchor = try {
                    pager.state.captureAnchor().copy(pageIndex = position)
                } catch (_: Exception) {
                    PageAnchor(pageIndex = position)
                }
                currentAnchor = anchor
                // Stored in the coordinates the chapter has on the next open instead: the loader
                // folds the segments away when it persists the page list, so a live position names a
                // later page once that has happened. Only the copy on disk is converted - the live
                // anchor above stays in the list the reader is actually paging through.
                val saved = page.page.chapter.savedIndexOf(page.page)
                positionStore.saveAnchor(
                    cid,
                    if (saved >= 0) anchor.copy(pageIndex = saved) else anchor,
                    force = force,
                )
            }
        } catch (_: Exception) {}
    }

    /**
     * Tells this viewer to set the given [chapters] as active. Mirrors
     * [eu.kanade.tachiyomi.ui.reader.viewer.pager.PagerViewer.setChapters] for modular parity.
     */
    override fun setChapters(chapters: ViewerChapters) = setChaptersInternal(chapters)

    private fun pageBelongsToChapters(page: ViewerPage, chapters: ViewerChapters): Boolean = when (page) {
        is ViewerReaderPage ->
            page.page.chapter == chapters.prevChapter ||
                page.page.chapter == chapters.currChapter ||
                page.page.chapter == chapters.nextChapter
        is ViewerTransitionPage ->
            page.prevChapter == chapters.prevChapter || page.prevChapter == chapters.currChapter ||
                page.prevChapter == chapters.nextChapter || page.nextChapter == chapters.prevChapter ||
                page.nextChapter == chapters.currChapter || page.nextChapter == chapters.nextChapter
        else -> false
    }

    private fun setChaptersInternal(chapters: ViewerChapters) {
        // KMK --> Empty too: lastIndex would be -1, and the requested page is read from it.
        val pages = chapters.currChapter.pages
        if (pages.isNullOrEmpty()) return
        // KMK <--

        this.viewerChapters = chapters

        // Baseline for syncPageList: it exists to catch pages replaced after this point, and
        // without recording the current versions the initial load reads as a change.
        seenPageListVersions = chapters.pageListVersions()

        val chapterId = chapters.currChapter.chapter.id
        val stored = if (chapterId != null && chapterId != -1L) positionStore.load(chapterId) else null
        val targetIndex = stored?.pageIndex?.coerceIn(0, pages.lastIndex)
            ?: min(chapters.currChapter.requestedPage, pages.lastIndex)
        val requestedPage = pages[targetIndex]

        // Get the page and align to spread anchor if needed
        // Captured before reassignment: a non-null previous page already inside the
        // new chapters means seamless scroll entry (see restore guard below). A stale
        // page from an unrelated chapter (explicit jump before moveToPage lands)
        // resolves null neighbors in every direction, so only a linked page is reused.
        val previousPage = currentPage
        val page = previousPage?.takeIf { pageBelongsToChapters(it, chapters) }
            ?: getPage(requestedPage)
        currentPage = getSpreadAnchor(page)
        // KMK --> Seamless scroll entry: the user is already reading inside the new
        // chapter (previousPage resolved there via onPageChange before the chapter
        // switch landed). Restoring the stored offset now would yank the viewport
        // to a stale position. Fresh and explicit opens still restore below.
        val alreadyInsideNewChapter =
            (previousPage as? ViewerReaderPage)?.page?.chapter == chapters.currChapter
        val needsDeferredRestore = stored != null && isContinuous && !alreadyInsideNewChapter
        // KMK --> Arm before reporting: the report below must not save docY=0 over
        // the stored resume the restore is about to apply.
        pendingContinuousRestoreChapterId = if (needsDeferredRestore) chapterId else null
        // KMK <--
        // KMK --> Paged parity: a stored zoom/offset must survive a process kill
        // the same way continuous documentY does. Armed here so the report below
        // cannot clobber it with the fresh 1f default before restore lands.
        val needsPagedRestore = stored != null && !isContinuous && !alreadyInsideNewChapter &&
            (stored.zoom != 1f || stored.offsetX != 0f)
        pendingPagedRestoreChapterId = if (needsPagedRestore) chapterId else null
        // KMK <--
        // KMK --> Report the spread's lastmost page, not the anchor.
        progressPage(currentPage!!)?.let { reportPageSelected(it) }
        // KMK <--
        preloadPages(currentPage!!)
        // needsDeferredRestore already implies stored != null; takeIf keeps that
        // in one place and gives the restore coroutine a smart-cast value.
        val deferredStored = stored?.takeIf { needsDeferredRestore }
        if (deferredStored != null) {
            // Restoring now would measure against ProgressPage placeholders
            // (viewport-height each), landing the viewport in empty space once
            // real heights decode: black screen, then phantom page walks on the
            // first scroll. Wait for the target page to decode, then restore
            // once against real heights. Aborts if the user scrolls, navigates,
            // or the chapter changes first.
            try {
                val cont = pager as? ca.mpreg.webgpuviewer.ImageViewContinuous
                val st = cont?.state
                if (st != null) {
                    val restoreChapterId = chapterId
                    val anchorPage = currentPage
                    val startDocY = try {
                        st.documentY
                    } catch (_: Exception) {
                        0f
                    }
                    scope.launch {
                        try {
                            var ready = false
                            var waited = 0
                            while (waited < 100) {
                                if (isDestroyed) return@launch
                                if (viewerChapters?.currChapter?.chapter?.id != restoreChapterId) return@launch
                                val target = synchronized(lock) {
                                    findInCache(PageKey.Reader(restoreChapterId, targetIndex)) as? ViewerReaderPage
                                }
                                val surfaceReady = try {
                                    pager.state.width > 0 && pager.state.height > 0
                                } catch (_: Exception) {
                                    false
                                }
                                if (surfaceReady && (target?.isDecoded == true || target?.imagePage is ErrorPage)) {
                                    ready = true
                                    break
                                }
                                kotlinx.coroutines.delay(100)
                                waited++
                            }
                            if (!ready || isDestroyed) return@launch
                            if (viewerChapters?.currChapter?.chapter?.id != restoreChapterId) return@launch
                            if (currentPage !== anchorPage) return@launch
                            val nowDocY = try {
                                st.documentY
                            } catch (_: Exception) {
                                startDocY
                            }
                            if (!nowDocY.isFinite() || !startDocY.isFinite() || abs(nowDocY - startDocY) > 2f) return@launch
                            // KMK --> pageIndexHint is relative to the state's anchor page, not
                            // absolute - resolveDocumentYForRestore hands it to documentYForPageIndex,
                            // which subtracts the anchor's own index from it. The deferred restore
                            // only runs when the anchor was rebuilt from the saved page itself
                            // (!alreadyInsideNewChapter, see needsDeferredRestore), so the saved page
                            // IS the anchor and the hint is 0. Passing the stored absolute index
                            // instead made the walk step `absolute - anchor` pages in the wrong
                            // direction - wrong position, and an O(absolute) chain walk.
                            st.restorePosition(
                                ca.mpreg.webgpuviewer.viewer.ImageViewerContinuousState.ContinuousPosition(
                                    documentY = deferredStored.offsetRatio,
                                    scale = deferredStored.zoom,
                                    offsetX = deferredStored.offsetX,
                                    pageIndexHint = 0,
                                    fractionWithinPage = deferredStored.fraction,
                                ),
                                animate = false,
                            )
                            // KMK <--
                            try {
                                pager.state.invalidate()
                            } catch (_: Exception) {}
                        } finally {
                            if (pendingContinuousRestoreChapterId == restoreChapterId) {
                                pendingContinuousRestoreChapterId = null
                            }
                        }
                    }
                } else {
                    pendingContinuousRestoreChapterId = null
                }
            } catch (_: Exception) {
                pendingContinuousRestoreChapterId = null
            }
        }
        // KMK --> Paged zoom+offset restore: mirrors the continuous deferred
        // restore above (abort on user nav/chapter change, clamp to the live
        // page bounds). Restoring before decode would measure against the
        // ProgressPage placeholder, so wait for the real page like continuous.
        if (needsPagedRestore) {
            try {
                val restoreChapterId = chapterId
                val anchorPage = currentPage
                val wantZoom = stored.zoom
                val wantX = stored.offsetX
                scope.launch {
                    try {
                        var ready = false
                        var waited = 0
                        while (waited < 100) {
                            if (isDestroyed) return@launch
                            if (viewerChapters?.currChapter?.chapter?.id != restoreChapterId) return@launch
                            val target = synchronized(lock) {
                                findInCache(PageKey.Reader(restoreChapterId, targetIndex)) as? ViewerReaderPage
                            }
                            val surfaceReady = try {
                                pager.state.width > 0 && pager.state.height > 0
                            } catch (_: Exception) {
                                false
                            }
                            if (surfaceReady && (target?.isDecoded == true || target?.imagePage is ErrorPage)) {
                                ready = true
                                break
                            }
                            kotlinx.coroutines.delay(100)
                            waited++
                        }
                        if (!ready || isDestroyed) return@launch
                        if (viewerChapters?.currChapter?.chapter?.id != restoreChapterId) return@launch
                        if (currentPage !== anchorPage) return@launch
                        try {
                            val page = pager.state.getPage(0)
                            if (page != null && wantZoom.isFinite()) {
                                page.scale = wantZoom.coerceIn(page.minScale, page.maxScale)
                                if (wantX.isFinite() && wantX != 0f) {
                                    val minX = page.minX(page.scale)
                                    val maxX = page.maxX(page.scale)
                                    page.animateTo(targetX = wantX.coerceIn(minX, maxX), targetY = page.y)
                                }
                            }
                        } catch (_: Exception) {
                        }
                        try {
                            pager.state.invalidate()
                        } catch (_: Exception) {}
                    } finally {
                        if (pendingPagedRestoreChapterId == restoreChapterId) {
                            pendingPagedRestoreChapterId = null
                        }
                    }
                }
            } catch (_: Exception) {
                pendingPagedRestoreChapterId = null
            }
        }
        // KMK <--

        pager.state.apply {
            onPageChange = onPageChange@{ delta ->
                activity.hideMenu()

                // The viewer already showed the page at fetchPage(delta).
                // We need to update currentPage to match that.
                val current = currentPage ?: return@onPageChange

                // Navigate the same way fetchPage does
                var page = current
                val step = if (delta > 0) 1 else -1
                repeat(abs(delta)) {
                    page = nextPage(page, step) ?: return@onPageChange
                }

                currentPage = page
                // KMK --> Report the spread's lastmost page, not the anchor.
                progressPage(page)?.let { reportPageSelected(it) }
                // KMK <--
                preloadPages(page)

                (page as? ViewerTransitionPage)?.let { viewerTransitionPage ->
                    if (viewerTransitionPage.prevChapter == null || viewerTransitionPage.nextChapter == null) {
                        activity.showMenu()
                    }
                }
            }

            invalidate()
        }
    }

    /**
     * Tells this viewer to move to the given [page].
     * In dual page mode, aligns to the start of the spread containing the page.
     */
    override fun moveToPage(page: ReaderPage) {
        // Get the page and align to spread anchor based on image position
        moveToPage(getSpreadAnchor(getPage(page)))
    }

    private fun moveToPage(newPage: ViewerPage) {
        val previousPage = currentPage

        currentPage = newPage
        // KMK --> Report the spread's lastmost page, not the anchor.
        progressPage(newPage)?.let { reportPageSelected(it) }
        // KMK <--
        preloadPages(newPage)

        (newPage as? ViewerTransitionPage)?.let { viewerTransitionPage ->
            if (viewerTransitionPage.prevChapter == null || viewerTransitionPage.nextChapter == null) {
                activity.showMenu()
            }
        }

        if (previousPage == null) return

        val direction = when (previousPage) {
            is ViewerReaderPage if newPage is ViewerReaderPage -> if (previousPage.page.chapter ==
                newPage.page.chapter
            ) {
                (newPage.page.index - previousPage.page.index).coerceIn(-1, 1)
            } else if (previousPage.page.chapter == newPage.prevChapter) {
                1
            } else {
                -1
            }

            is ViewerTransitionPage if newPage is ViewerReaderPage -> if (previousPage.nextChapter ==
                newPage.page.chapter
            ) {
                1
            } else {
                -1
            }

            is ViewerReaderPage if newPage is ViewerTransitionPage -> if (previousPage.page.chapter ==
                newPage.prevChapter
            ) {
                1
            } else {
                -1
            }

            else -> 0
        }

        if (direction != 0) {
            pager.state.transitionFromPage = buildSpreadPage(previousPage)
            pager.state.animatePageTurn(if (isReversed) direction else -direction)
        } else {
            pager.state.invalidate()
        }
    }

    /**
     * Moves to the next page.
     */
    override fun moveToNext() {
        moveRight()
    }

    /**
     * Moves to the previous page.
     */
    fun moveToPrevious() {
        moveLeft()
    }

    /**
     * Moves to the page at the right.
     */
    protected open fun moveRight() {
        pager.state.getPage(0)?.let { page ->
            if (config.navigateToPan) {
                val minX = page.minX(page.scale)
                val maxX = page.maxX(page.scale)
                // Where a running pan is headed, else where it sits.
                val currentX = page.animationTargetX ?: page.x

                val c = if (isVertical && config.imageZoomType == ReaderPageImageView.ZoomStartPosition.RIGHT) -1 else 1
                val x = (currentX - c / page.scale).coerceIn(minX, maxX)
                if (x != page.x) {
                    if (page.animationJob?.isActive == true && page.animationTargetX == x) {
                        page.animationJob?.cancel()
                    } else {
                        page.animateTo(targetX = x, targetY = page.y)
                        return
                    }
                }
            }

            navigateSpread(1)
        }
    }

    /**
     * Moves to the page at the left.
     */
    protected open fun moveLeft() {
        pager.state.getPage(0)?.let { page ->
            if (config.navigateToPan) {
                val minX = page.minX(page.scale)
                val maxX = page.maxX(page.scale)
                val currentX = page.animationTargetX ?: page.x

                val c = if (isVertical && config.imageZoomType == ReaderPageImageView.ZoomStartPosition.RIGHT) -1 else 1
                val x = (currentX + c / page.scale).coerceIn(minX, maxX)
                if (x != page.x) {
                    if (page.animationJob?.isActive == true && page.animationTargetX == x) {
                        page.animationJob?.cancel()
                    } else {
                        page.animateTo(targetX = x, targetY = page.y)
                        return
                    }
                }
            }

            navigateSpread(-1)
        }
    }

    /** Target anchor page one spread past [from], in [direction] (positive = forward). */
    private fun nextPage(from: ViewerPage, direction: Int): ViewerPage? {
        var page = getSpreadAnchor(from)

        page = if (direction > 0) {
            if (page is ViewerReaderPage && spreadPartner(page) != null) {
                page.next?.next ?: return null
            } else {
                page.next ?: return null
            }
        } else {
            page.prev ?: return null
        }

        return getSpreadAnchor(page)
    }

    /**
     * Navigate by spreads from current page.
     * @param direction Positive = forward in page numbers, negative = backward
     */
    private fun navigateSpread(direction: Int) {
        val target = currentPage?.let { nextPage(it, direction) } ?: return
        moveToPage(target)
    }

    /**
     * Moves to the page at the top (or previous).
     */
    protected fun moveUp() {
        moveToPrevious()
    }

    /**
     * Moves to the page at the bottom (or next).
     */
    protected fun moveDown() {
        moveToNext()
    }

    /**
     * Called from the containing activity when a key [event] is received. It should return true
     * if the event was handled, false otherwise.
     */
    override fun handleKeyEvent(event: KeyEvent): Boolean {
        val isUp = event.action == KeyEvent.ACTION_UP
        val ctrlPressed = event.metaState.and(KeyEvent.META_CTRL_ON) > 0
        when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                if (!config.volumeKeysEnabled || activity.viewModel.state.value.menuVisible) {
                    return false
                } else if (isUp) {
                    if (!config.volumeKeysInverted) moveDown() else moveUp()
                }
            }

            KeyEvent.KEYCODE_VOLUME_UP -> {
                if (!config.volumeKeysEnabled || activity.viewModel.state.value.menuVisible) {
                    return false
                } else if (isUp) {
                    if (!config.volumeKeysInverted) moveUp() else moveDown()
                }
            }

            KeyEvent.KEYCODE_DPAD_RIGHT -> if (isUp) if (ctrlPressed) moveToNext() else moveRight()
            KeyEvent.KEYCODE_DPAD_LEFT -> if (isUp) if (ctrlPressed) moveToPrevious() else moveLeft()
            KeyEvent.KEYCODE_DPAD_DOWN -> if (isUp) moveDown()
            KeyEvent.KEYCODE_DPAD_UP -> if (isUp) moveUp()
            KeyEvent.KEYCODE_PAGE_DOWN -> if (isUp) moveDown()
            KeyEvent.KEYCODE_PAGE_UP -> if (isUp) moveUp()
            KeyEvent.KEYCODE_MENU -> if (isUp) activity.toggleMenu()
            else -> return false
        }
        return true
    }

    /**
     * Called from the containing activity when a generic motion [event] is received. It should
     * return true if the event was handled, false otherwise.
     */
    override fun handleGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.source and InputDevice.SOURCE_CLASS_POINTER != 0) {
            when (event.action) {
                MotionEvent.ACTION_SCROLL -> {
                    if (event.getAxisValue(MotionEvent.AXIS_VSCROLL) < 0.0f) {
                        moveDown()
                    } else {
                        moveUp()
                    }
                    return true
                }
            }
        }
        return false
    }
}
// Mihon <--
