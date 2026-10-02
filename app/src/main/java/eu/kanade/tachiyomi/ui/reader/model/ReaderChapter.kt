package eu.kanade.tachiyomi.ui.reader.model

import eu.kanade.domain.chapter.model.toDbChapter
import eu.kanade.tachiyomi.data.database.models.Chapter
import eu.kanade.tachiyomi.ui.reader.loader.PageLoader
import kotlinx.coroutines.flow.MutableStateFlow
import tachiyomi.core.common.util.system.logcat

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
     * Position of [page] in the current page list, or -1 when it is not in it.
     *
     * [Page.index] cannot answer this: it is assigned when the list is built and is immutable,
     * so a page inserted later (a split segment) sits at a position its index does not name. Match
     * by identity, since two distinct pages can legitimately share an index across a chapter swap.
     */
    fun positionOf(page: ReaderPage): Int = pages?.indexOfFirst { it === page } ?: -1

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
