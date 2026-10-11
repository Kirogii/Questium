package eu.kanade.tachiyomi.ui.vr

internal object VrPageTextureSizing {
    // One RGBA page with mipmaps stays below 86 MiB, including AI output.
    private const val MAX_PIXELS = 16_777_216L

    fun sample(width: Int, height: Int, textureLimit: Int, factor: Float): Int {
        var sample = 1
        val limit = (textureLimit / factor).toInt().coerceAtLeast(1)
        while ((width.toLong() + sample - 1) / sample > limit ||
            (height.toLong() + sample - 1) / sample > limit ||
            ((width.toLong() + sample - 1) / sample) * ((height.toLong() + sample - 1) / sample) * factor * factor > MAX_PIXELS
        ) {
            sample *= 2
        }
        return sample
    }
}
