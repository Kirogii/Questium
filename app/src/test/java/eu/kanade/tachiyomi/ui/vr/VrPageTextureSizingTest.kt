package eu.kanade.tachiyomi.ui.vr

import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Test

class VrPageTextureSizingTest {
    @Test
    fun `preserve source detail beyond the old page and strip limits`() {
        VrPageTextureSizing.sample(3000, 4500, 16384, 1f) shouldBe 1
        VrPageTextureSizing.sample(6000, 2048, 16384, 1f) shouldBe 1
        VrPageTextureSizing.sample(1600, 2400, 16384, 2f) shouldBe 1
    }

    @Test
    fun `respect GPU dimensions after inference and round decode sizes up`() {
        VrPageTextureSizing.sample(4097, 960, 4096, 1f) shouldBe 2
        VrPageTextureSizing.sample(4097, 960, 4096, 2f) shouldBe 4
    }

    @Test
    fun `bound page memory including AI output and oversized source images`() {
        VrPageTextureSizing.sample(8192, 8192, 16384, 1f) shouldBe 2
        VrPageTextureSizing.sample(4096, 4096, 16384, 2f) shouldBe 2
        VrPageTextureSizing.sample(100000, 100000, 16384, 1f) shouldBe 32
    }
}
