package eu.kanade.tachiyomi.data.coil

import android.graphics.Bitmap
import androidx.palette.graphics.Palette
import coil3.BitmapImage
import coil3.Image

/**
 * Extracts the colour a cover-seeded theme is built from.
 *
 * Two callers need it and they must agree on the answer, otherwise the manga details
 * screen and the reader can end up tinted from different colours for the same cover:
 *
 * - [MangaCoverMetadata.setRatioAndColors], off Coil's fetch scope, for every cover
 *   displayed anywhere in the app;
 * - `MangaScreenModel.onCoverPaletteAvailable`, from the bitmap the details screen has
 *   already decoded, so the theme appears without a second image request.
 *
 * Everything here is best-effort: covers arrive as hardware bitmaps, get recycled under
 * us, or are too large to sample cheaply, and none of that may crash a browse.
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
     * Overload for the callers that already hold the decoded bitmap, so they do not have to
     * wrap it in a [BitmapImage] only for this to unwrap it again.
     */
    fun vibrantColorOf(bitmap: Bitmap?): Int? = withPalette(bitmap) { it.getBestColor() }

    fun vibrantColorOf(image: Image): Int? = vibrantColorOf((image as? BitmapImage)?.bitmap)

    /**
     * Dominant swatch plus the title colour the library grid draws over it. Only
     * meaningful for in-library covers; the vibrant colour is tracked for every cover.
     */
    fun dominantColorOf(bitmap: Bitmap?): Pair<Int, Int>? =
        withPalette(bitmap) { it.dominantSwatch?.let { swatch -> swatch.rgb to swatch.titleTextColor } }

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
