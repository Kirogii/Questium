package eu.kanade.tachiyomi.ui.reader.model

import eu.kanade.domain.chapter.model.toDbChapter
import eu.kanade.tachiyomi.data.database.models.Chapter
import eu.kanade.tachiyomi.ui.reader.loader.PageLoader
import kotlinx.coroutines.flow.MutableStateFlow
import tachiyomi.core.common.util.system.logcat
import java.util.concurrent.atomic.AtomicInteger

data class ReaderChapter(val chapter: Chapter) {

    val stateFlow = MutableStateFlow<State>(State.Wait)
    var state: State
        get() = stateFlow.value
        set(value) {
            stateFlow.value = value
        }

    val pages: List<ReaderPage>?
        get() = (state as? State.Loaded)?.pages

    /**
     * Bumped every time the loaded page list is replaced wholesale.
     *
     * The loader grows this list after the viewers have already built theirs: a page too tall for
     * the decoder is cut into segments and the result swapped in mid-session, which is long after
     * `setChapters` snapshotted it. Both viewers enumerate pages by walking that snapshot, so
     * without a signal they never learn the list changed - the split is simply invisible, and the
     * pages the viewer is still holding for the removed parent stay laid out next to the segments
     * that replaced it.
     *
     * Identity rather than a hash of the list, so it is a cheap read on the render path and cannot
     * collide. Callers compare it against the value they last built from.
     */
    val pageListVersion: Int get() = pageListVersionCounter.get()

    /**
     * Atomic rather than a plain counter, because the writers are not guaranteed to be one thread.
     * A split runs on a loader worker while a fresh
     * [eu.kanade.tachiyomi.ui.reader.loader.ChapterLoader] load runs on its own, so two of them can
     * touch the same chapter - and a non-atomic `++` on a volatile int loses one of the two
     * increments, leaving a viewer to reconcile against a version it has already seen and never
     * notice the list it missed.
     */
    private val pageListVersionCounter = AtomicInteger()

    /**
     * Replaces the loaded page list and announces it. Every writer that changes the list's contents
     * or length must go through here, or the viewers will keep rendering the previous one.
     */
    fun replacePages(newPages: List<ReaderPage>) {
        state = State.Loaded(newPages)
        pageListVersionCounter.incrementAndGet()
    }

    /**
     * Position of [page] in the current page list, or -1 when it is not in it.
     *
     * [Page.index] cannot answer this: it is assigned when the list is built and is immutable,
     * so a page inserted later (a split segment) sits at a position its index does not name. Match
     * by identity, since two distinct pages can legitimately share an index across a chapter swap.
     */
    fun positionOf(page: ReaderPage): Int = pages?.indexOfFirst { it === page } ?: -1

    /**
     * The page that now stands where [page] used to, or null when [page] is still in the list.
     *
     * A split removes the page it cuts and inserts its segments in its place, so a viewer that was
     * showing [page] has to land on the first of them. Falling back to the chapter's resume target
     * instead would teleport the reader to wherever the chapter was opened, which for a page they
     * had already turned to is somewhere else entirely.
     *
     * Identity, like [positionOf]: the segments record the page they came from, so two pages sharing
     * one image cannot hand each other's replacement over.
     */
    fun splitReplacementOf(page: ReaderPage): ReaderPage? = pages?.firstOrNull { it.splitSourcePage === page }

    /**
     * Position to store for [page], in the coordinates the page list has before any split.
     *
     * [positionOf] counts positions in the list as it stands, which is what the reader pages through
     * and what the progress bar has to show. It is not what to *persist*: a split inserts pages, so
     * every position after one shifts by however many segments came before it, and the list that
     * survives a close is the un-split one the loader restores. A stored position therefore names a
     * different page on the next open than it did on the way out.
     *
     * Every segment of one strip maps to the same stored position, which is the point - reading any
     * slice of a long image has to resume the image, not some later page. Unlisted pages fall back to
     * [Page.index], the coordinate they had before anything could shift them.
     */
    fun savedIndexOf(page: ReaderPage): Int {
        val list = pages ?: return page.index
        val position = positionOf(page)
        if (position < 0) return page.index
        val run = page.segmentParentIndex
        var saved = 0
        var index = 0
        while (index < position) {
            val parent = list[index].segmentParentIndex
            if (parent == null) {
                saved++
                index++
                continue
            }
            // Stops on the run [page] belongs to, before counting it: a page inside a run answers
            // with the slot that run occupies, not with the slot after it. Every other run is
            // skipped whole and costs one position, matching how it restores.
            if (run != null && parent == run) break
            saved++
            while (index < position && list[index].segmentParentIndex == parent) {
                index++
            }
        }
        return saved
    }

    /**
     * 1-based number to show the reader for [page].
     *
     * [Page.number] is derived from the immutable [Page.index], so it cannot report a position for
     * a page inserted after the list was built. Falls back to the index when [page] is unlisted,
     * which is what every page looked like before this existed.
     */
    fun displayNumber(page: ReaderPage): Int {
        val position = positionOf(page)
        return if (position >= 0) position + 1 else page.index + 1
    }

    var pageLoader: PageLoader? = null

    var requestedPage: Int = 0

    private var references = 0

    constructor(chapter: tachiyomi.domain.chapter.model.Chapter) : this(chapter.toDbChapter())

    fun ref() {
        references++
    }

    fun unref() {
        references--
        if (references == 0) {
            if (pageLoader != null) {
                logcat { "Recycling chapter ${chapter.name}" }
            }
            pageLoader?.recycle()
            pageLoader = null
            state = State.Wait
        }
    }

    sealed interface State {
        data object Wait : State
        data object Loading : State
        data class Error(val error: Throwable) : State
        data class Loaded(val pages: List<ReaderPage>) : State
    }
}
