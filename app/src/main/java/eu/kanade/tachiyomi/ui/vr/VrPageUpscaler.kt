package eu.kanade.tachiyomi.ui.vr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import eu.kanade.tachiyomi.ui.reader.setting.UpscaleReaderHook
import java.io.ByteArrayOutputStream
import java.io.File

/** Display-only processing: chapter downloads and source images are never rewritten. */
internal object VrPageUpscaler {
    suspend fun write(bitmap: Bitmap, mangaId: Long?, file: File, topPadding: Int = 0, bottomPadding: Int = 0) {
        var processed: Bitmap? = null
        var cropped: Bitmap? = null
        try {
            if (UpscaleReaderHook.isUpscaleActive(mangaId)) {
                val bytes = ByteArrayOutputStream().use {
                    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                    it.toByteArray()
                }
                UpscaleReaderHook.upscaleDisplayBytes(mangaId, bytes)?.let {
                    processed = BitmapFactory.decodeByteArray(it, 0, it.size)
                }
            }
            val output = processed ?: bitmap
            val top = (topPadding.toFloat() * output.height / bitmap.height).toInt()
            val bottom = (bottomPadding.toFloat() * output.height / bitmap.height).toInt()
            val height = (output.height - top - bottom).coerceAtLeast(1)
            val final = if (top > 0 || bottom > 0) {
                Bitmap.createBitmap(output, 0, top, output.width, height).also { cropped = it }
            } else {
                output
            }
            file.outputStream().use { check(final.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        } finally {
            cropped?.takeIf { it !== processed && it !== bitmap }?.recycle()
            processed?.takeIf { it !== bitmap }?.recycle()
        }
    }
}
