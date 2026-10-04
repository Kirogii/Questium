package eu.kanade.tachiyomi.data.coil

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.palette.graphics.Palette
import coil3.BitmapImage
import coil3.Image
import logcat.LogPriority
import tachiyomi.core.common.util.system.logcat

/**
 * Extracts the colour a cover-seeded theme is built from.
 *
 * Two callers need it and they must agree on the answer, otherwise the manga details
 * screen and the reader can end up tinted from different colours for the same cover:
 *
 * - [MangaCoverMetadata.setRatioAndColors], off Coil's fetch scope, for every cover
 *   displayed anywhere in the app;
 * - `MangaScreenModel.onCoverPaletteAvailable`, from the image the details screen has
 *   already decoded, so the theme appears without a second image request.
 *
 * Everything here is best-effort: covers arrive as hardware bitmaps, get recycled under
 * us, or are too large to sample cheaply, and none of that may crash a browse.
 *
 * ## One palette, two answers
 *
 * [colorsOf] returns both swatches from a single `Palette` build. `Palette.generate()` is the
 * expensive half - it quantises the image and scores every candidate - so exposing one getter per
 * swatch would make every favourite cover in the library pay for the whole thing twice just to read
 * two fields out of the same object.
 */
object CoverPaletteExtractor {

    /**
     * Covers are decoded at display size, which is already modest, but a panorama cover
     * spans the full screen width and a custom cover can be arbitrarily large. Scaling
     * before `Palette` runs keeps the cost flat regardless of source resolution, and
     * palette generation only needs region averages, so the result is unchanged.
     */
    private const val MAX_SAMPLED_EDGE = 512

    /**
     * The swatches a cover contributes.
     *
     * @param vibrant best available accent, tracked for every cover.
     * @param dominant dominant swatch plus the title colour the library grid draws over it,
     *   only meaningful for in-library covers.
     */
    data class CoverColors(
        val vibrant: Int?,
        val dominant: Pair<Int, Int>?,
    )

    /**
     * Both swatches from one palette build, or null when the cover cannot be sampled at all.
     *
     * Accepts an already-decoded bitmap so [MangaCoverMetadata] does not have to wrap it in a
     * [BitmapImage] only for this to unwrap it again.
     */
    fun colorsOf(bitmap: Bitmap?): CoverColors? =
        withPalette(bitmap) { CoverColors(it.getBestColor(), dominantOf(it)) }

    /**
     * The Coil overload.
     *
     * [coil3.Image] is a sealed-ish hierarchy rather than a bitmap: Coil 3 decodes into a
     * *hardware* bitmap by default, which arrives here as a `HardwareImage` rather than a
     * [BitmapImage]. Casting and giving up - which is what this did before - meant the cover
     * palette silently never resolved for any cover loaded through Coil without an explicit
     * `allowHardware(false)`, so cover-seeded theming was a no-op on most devices. A hardware
     * image is rendered into a software bitmap instead, which is cheap (the GPU already holds
     * the pixels) and is the only way `Palette` - which reads through `getPixels()` - can see it.
     */
    fun colorsOf(image: Image): CoverColors? {
        (image as? BitmapImage)?.let { return colorsOf(it.bitmap) }
        val rendered = renderSoftware(image) ?: return null
        // Owned by this function, unlike a BitmapImage's bitmap, which belongs to Coil.
        return try {
            colorsOf(rendered)
        } finally {
            rendered.recycle()
        }
    }

    private fun dominantOf(palette: Palette): Pair<Int, Int>? =
        palette.dominantSwatch?.let { swatch -> swatch.rgb to swatch.titleTextColor }

    /**
     * Draws [image] into a software bitmap small enough to quantise.
     *
     * Returns null when the image has no area or refuses to draw.
     */
    private fun renderSoftware(image: Image): Bitmap? {
        val width = image.width
        val height = image.height
        if (width <= 0 || height <= 0) return null
        return runCatching {
            // Scaled on the way out rather than after: `Palette` only ever reads a
            // MAX_SAMPLED_EDGE image, so materialising a panorama header at full size first
            // would allocate megabytes of ARGB_8888 on the IO dispatcher purely to throw all but
            // 512px of it away.
            val scale = minOf(
                1f,
                MAX_SAMPLED_EDGE.toFloat() / maxOf(width, height),
            )
            Bitmap.createBitmap(
                (width * scale).toInt().coerceAtLeast(1),
                (height * scale).toInt().coerceAtLeast(1),
                Bitmap.Config.ARGB_8888,
            ).also { rendered ->
                val canvas = Canvas(rendered)
                if (scale != 1f) canvas.scale(scale, scale)
                image.draw(canvas)
            }
        }.onFailure {
            logcat(LogPriority.ERROR, it) { "Could not render cover image for palette extraction" }
        }.getOrNull()
    }

    private inline fun <T> withPalette(bitmap: Bitmap?, select: (Palette) -> T?): T? {
        if (bitmap == null || bitmap.isRecycled || bitmap.width <= 0 || bitmap.height <= 0) return null
        return runCatching {
            val sampled = downsampleForPalette(bitmap)
            try {
                select(Palette.from(sampled).generate())
            } finally {
                if (sampled !== bitmap) sampled.recycle()
            }
        }.getOrNull()
    }

    private fun downsampleForPalette(bitmap: Bitmap): Bitmap {
        val software = if (bitmap.config == Bitmap.Config.HARDWARE) {
            // Palette reads through getPixels(), which a hardware bitmap cannot serve.
            runCatching { bitmap.copy(Bitmap.Config.ARGB_8888, false) }.getOrNull() ?: return bitmap
        } else {
            bitmap
        }

        if (software.width <= MAX_SAMPLED_EDGE && software.height <= MAX_SAMPLED_EDGE) return software

        val scale = minOf(
            MAX_SAMPLED_EDGE.toFloat() / software.width,
            MAX_SAMPLED_EDGE.toFloat() / software.height,
        )
        val scaled = Bitmap.createScaledBitmap(
            software,
            (software.width * scale).toInt().coerceAtLeast(1),
            (software.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (scaled !== software) software.recycle()
        return scaled
    }
}
