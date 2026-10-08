package eu.kanade.tachiyomi.ui.reader.viewer.webgpu

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.matchers.nulls.shouldBeNull
import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.parallel.Execution
import org.junit.jupiter.api.parallel.ExecutionMode

/**
 * The two pieces of per-chapter state the continuous render walk depends on.
 *
 * [ContinuousPageWindow] is asked for every page in the window on every frame, and its slots are
 * addressed by a signed offset from the anchor, so its two failure modes are both about the edge:
 * an index one past the end throws from inside the render walk, and a slot marked known while
 * holding no page renders nothing. The second is the subtler one - `known` and the stored page
 * are deliberately separate, because a split leaves a hole where a page used to be, and a window
 * that reported "not known" for a hole would walk straight past it.
 *
 * [PageListWatch] decides whether the loader has replaced the page list under the viewer. It has
 * to compare three chapters, not just the current one, and it has to compare by content: a fresh
 * array holding the same three versions is not a change.
 */
@Execution(ExecutionMode.CONCURRENT)
class ContinuousPageWindowTest {

    // ---------- window bounds ----------

    @Test
    fun `a fresh window knows nothing`() {
        val window = ContinuousPageWindow(radius = 4)
        for (index in -4..4) {
            window.isKnown(index) shouldBe false
            window.get(index).shouldBeNull()
        }
        window.anchor.shouldBeNull()
    }

    @Test
    fun `the reachable range is exactly plus or minus the radius`() {
        val window = ContinuousPageWindow(radius = 3)
        window.isKnown(-3) shouldBe false
        window.isKnown(3) shouldBe false
        // One past either end is a caller bug, and it must fail loudly rather than read a
        // neighbour's slot or write out of bounds.
        shouldThrow<IndexOutOfBoundsException> { window.isKnown(4) }
        shouldThrow<IndexOutOfBoundsException> { window.isKnown(-4) }
        shouldThrow<IndexOutOfBoundsException> { window.get(4) }
        shouldThrow<IndexOutOfBoundsException> { window.put(4, null) }
        shouldThrow<IndexOutOfBoundsException> { window.put(-4, null) }
    }

    @Test
    fun `a radius of zero addresses only the anchor slot`() {
        val window = ContinuousPageWindow(radius = 0)
        window.isKnown(0) shouldBe false
        shouldThrow<IndexOutOfBoundsException> { window.isKnown(1) }
        shouldThrow<IndexOutOfBoundsException> { window.isKnown(-1) }
    }

    // ---------- known versus populated ----------

    @Test
    fun `writing null marks the slot known while leaving it empty`() {
        val window = ContinuousPageWindow(radius = 2)
        window.put(0, null)
        // The distinction that matters: the walk has been here, and found nothing. Reporting
        // "unknown" would send it round again, and reporting a page would draw one.
        window.isKnown(0) shouldBe true
        window.get(0).shouldBeNull()
        // Neighbours are untouched - one write must not imply the whole window.
        window.isKnown(1) shouldBe false
        window.isKnown(-1) shouldBe false
    }

    @Test
    fun `writing null twice stays known`() {
        val window = ContinuousPageWindow(radius = 1)
        window.put(1, null)
        window.put(1, null)
        window.isKnown(1) shouldBe true
    }

    @Test
    fun `reset forgets every slot`() {
        val window = ContinuousPageWindow(radius = 2)
        window.put(-2, null)
        window.put(0, null)
        window.put(2, null)
        window.isKnown(-2) shouldBe true
        window.isKnown(2) shouldBe true

        window.reset(null)
        for (index in -2..2) {
            window.isKnown(index) shouldBe false
        }
    }

    @Test
    fun `reset with a null anchor still clears, since a split passes one`() {
        val window = ContinuousPageWindow(radius = 2)
        window.put(0, null)
        // syncPageList invalidates the window by handing it null rather than the page it had,
        // because the page it anchored on may be the very one the split removed.
        window.reset(null)
        window.isKnown(0) shouldBe false
        window.anchor.shouldBeNull()
    }

    // ---------- the page-list watch ----------

    @Test
    fun `an unwatched trio of versions is the unseen sentinel`() {
        // A fresh watch starts at -1 per slot, which is what pageListVersions reports for an
        // absent neighbour, so the first real snapshot does not read as a change.
        val watch = PageListWatch()
        watch.isUnchanged(intArrayOf(-1, -1, -1)) shouldBe true
        watch.isUnchanged(intArrayOf(0, 0, 0)) shouldBe false
    }

    @Test
    fun `the comparison is by content, not by array identity`() {
        val watch = PageListWatch()
        watch.reset(intArrayOf(3, 4, 5))
        watch.isUnchanged(intArrayOf(3, 4, 5)) shouldBe true
        // A different array holding the same numbers is not a change; the viewer builds a fresh
        // one every time it checks.
        val fresh = intArrayOf(3, 4, 5)
        watch.isUnchanged(fresh) shouldBe true
    }

    @Test
    fun `one moved slot is enough to report a change`() {
        val watch = PageListWatch()
        watch.reset(intArrayOf(1, 2, 3))
        // The strip spans prev/current/next, and the chapter most likely to be split is one the
        // reader is only part-way into - so a change outside the current slot must still count.
        watch.isUnchanged(intArrayOf(9, 2, 3)) shouldBe false
        watch.isUnchanged(intArrayOf(1, 9, 3)) shouldBe false
        watch.isUnchanged(intArrayOf(1, 2, 9)) shouldBe false
    }

    @Test
    fun `reset moves the watch forward`() {
        val watch = PageListWatch()
        watch.reset(intArrayOf(1, 1, 1))
        watch.reset(intArrayOf(2, 2, 2))
        watch.isUnchanged(intArrayOf(2, 2, 2)) shouldBe true
        watch.isUnchanged(intArrayOf(1, 1, 1)) shouldBe false
    }

    @Test
    fun `a differently sized snapshot never compares equal`() {
        val watch = PageListWatch()
        watch.reset(intArrayOf(1, 2, 3))
        watch.isUnchanged(intArrayOf(1, 2)) shouldBe false
        watch.isUnchanged(intArrayOf(1, 2, 3, 4)) shouldBe false
    }

    @Test
    fun `the cache radius is the one the walk is sized around`() {
        // Changing this silently changes how many neighbour pages the viewer must hold decoded.
        CONTINUOUS_PAGE_CACHE_RADIUS shouldBe 64
    }
}
