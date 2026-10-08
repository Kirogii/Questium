package eu.kanade.tachiyomi.ui.vr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import eu.kanade.tachiyomi.ui.reader.setting.UpscalePreferences
import mihon.app.di.appGraph
import java.io.File

/** Explicit debug-only headset check; restores all user preferences in finally. */
internal object VrUpscaleProbe {
    suspend fun run(host: Context, family: UpscalePreferences.Model = UpscalePreferences.Model.REAL_CUGAN) {
        val prefs = host.appGraph.upscalePreferences
        val mangaId = Long.MAX_VALUE - 101
        val enabled = prefs.enabled().get()
        val mode = prefs.mode().get()
        val backend = prefs.backend().get()
        val model = prefs.model().get()
        val factor = prefs.upscaleFactor().get()
        val cache = prefs.cacheEnabled().get()
        val perManga = prefs.isMangaToggleEnabled(mangaId)
        val directory = File(host.cacheDir, "vr-upscale-probe").apply { mkdirs() }
        try {
            prefs.enabled().set(true)
            prefs.mode().set(UpscalePreferences.Mode.NATIVE.name)
            prefs.backend().set(UpscalePreferences.Backend.CPU.name)
            prefs.model().set(family.name)
            prefs.upscaleFactor().set(2f)
            prefs.cacheEnabled().set(false)
            prefs.setMangaToggleEnabled(mangaId, true)
            check(host.appGraph.upscaleEngine.isNativeAvailable()) { "ONNX runtime unavailable" }
            for (page in 0..1) {
                val width = if (page == 0) 64 else 70
                val height = if (page == 0) 64 else 99
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(if (page == 0) Color.WHITE else Color.LTGRAY)
                try {
                    val output = File(directory, "page-$page.png")
                    VrPageUpscaler.write(bitmap, mangaId, output)
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(output.absolutePath, bounds)
                    check(bounds.outWidth == width * 2 && bounds.outHeight == height * 2) { "AI two-page output fell back to original: $family" }
                } finally {
                    bitmap.recycle()
                }
            }
            val strip = Bitmap.createBitmap(64, 96, Bitmap.Config.ARGB_8888)
            strip.eraseColor(Color.WHITE)
            try {
                val output = File(directory, "strip.png")
                VrPageUpscaler.write(strip, mangaId, output, 16, 16)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(output.absolutePath, bounds)
                check(bounds.outWidth == 128 && bounds.outHeight == 128) { "AI long-page strip overlap/output mismatch" }
            } finally {
                strip.recycle()
            }
            android.util.Log.i("VRUpscale", "PASS: real $family ONNX inference through VR two-page and padded long-page processing")
        } finally {
            prefs.enabled().set(enabled)
            prefs.mode().set(mode)
            prefs.backend().set(backend)
            prefs.model().set(model)
            prefs.upscaleFactor().set(factor)
            prefs.cacheEnabled().set(cache)
            prefs.setMangaToggleEnabled(mangaId, perManga)
        }
    }
}
