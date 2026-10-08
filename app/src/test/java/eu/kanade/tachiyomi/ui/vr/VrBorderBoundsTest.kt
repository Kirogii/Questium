package eu.kanade.tachiyomi.ui.vr

import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Test

class VrBorderBoundsTest {
    @Test
    fun `uniform pages retain their full extent`() {
        VrBorderBounds.find(20, 20, IntArray(400) { -1 }).toList() shouldBe listOf(0f, 0f, 1f, 1f)
    }

    @Test
    fun `white margins are cropped with safety around the content`() {
        val pixels = IntArray(400) { -1 }
        for (y in 5 until 15) for (x in 6 until 14) pixels[y * 20 + x] = 0xff000000.toInt()
        VrBorderBounds.find(20, 20, pixels).toList() shouldBe listOf(0.25f, 0.2f, 0.5f, 0.6f)
    }

    @Test
    fun `content touching the edges stays visible`() {
        val pixels = IntArray(400) { -1 }
        for (y in 0 until 20) pixels[y * 20 + 10] = 0xff000000.toInt()
        val crop = VrBorderBounds.find(20, 20, pixels)
        crop[1] shouldBe 0f
        crop[3] shouldBe 1f
    }
}
