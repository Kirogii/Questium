package eu.kanade.tachiyomi.ui.reader.model

import eu.kanade.tachiyomi.source.model.Page
import java.io.InputStream

open class ReaderPage(
    index: Int,
    url: String = "",
    imageUrl: String? = null,
    // SY -->
    /** Value to check if this page is used to as if it was too wide */
    var shiftedPage: Boolean = false,
    /** Value to check if a page is can be doubled up, but can't because the next page is too wide */
    var isolatedPage: Boolean = false,
    // SY <--
    var stream: (() -> InputStream)? = null,

) : Page(index, url, imageUrl, null), ReaderItem {

    open lateinit var chapter: ReaderChapter

    /** Value to check if a page is too wide to be doubled up */
    var fullPage: Boolean = false
        set(value) {
            field = value
            if (value) shiftedPage = false
        }

    // KMK -->
    /**
     * True for the extra pages a too-tall image was split into.
     *
     * Such a page is one vertical slice of a source page, so it never pairs into a spread and its
     * [index] is a synthetic value rather than a position in the chapter's list.
     */
    var splitSegment: Boolean = false

    /**
     * True once this page has been replaced by the segments of its own split.
     *
     * A superseded page is no longer in its chapter's list, but a viewer may still be holding it
     * with a decoded surface attached, which is what draws the old strip over its replacement.
     * Recording the state on the page itself lets a viewer reject one without having to go back to
     * the chapter to ask whether it is still real.
     */
    var supersededBySplit: Boolean = false
    // KMK <--
}
