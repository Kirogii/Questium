package eu.kanade.presentation.theme.colorscheme

import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.core.graphics.drawable.toBitmap
import androidx.palette.graphics.Palette
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import logcat.LogPriority
import mihon.app.di.globalAppGraph
import mihon.core.concurrency.AppDispatchersHolder
import tachiyomi.core.common.util.system.logcat

/**
 * Finds a seed colour from the wallpaper on releases that expose no system palette.
 *
 * `WallpaperManager.getWallpaperColors` is the cheap route, but it hands back whatever the system
 * extracted: null for live and third-party wallpapers until something has extracted them, and a
 * desaturated primary for wallpapers dominated by photographic or dark content. Sampling the
 * drawable ourselves always yields something, and quantising it finds the colour a person would
 * have picked by eye.
 *
 * Decoding and quantising a wallpaper is far too slow for composition, so it runs once on the IO
 * dispatcher and the result is published as Compose state. The theme reads that state and re-keys
 * its `remember` on it, so the app starts on the fallback and settles onto the wallpaper's own
 * colours a frame later instead of blocking the first frame or never updating at all.
 */
@Inject
@SingleIn(AppScope::class)
class WallpaperSeedSampler(private val context: Context) {

    private val _seed = mutableStateOf<Color?>(null)
    val seed: State<Color?> = _seed

    private val scope = CoroutineScope(Job() + AppDispatchersHolder.get().io)

    private val lock = Any()

    /**
     * Bumped whenever the wallpaper changes, so a sample that started against the previous one
     * cannot publish a colour the user has already replaced.
     */
    private var generation = 0L

    /** The wallpaper generation the published seed was sampled for. */
    private var sampledGeneration = -1L

    private var sampling = false

    private val wallpaperReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val resample: Boolean
            synchronized(lock) {
                generation++
                // Left to the in-flight sample to notice the generation moved, which is the only
                // path that can guarantee the published colour matches the wallpaper on screen.
                resample = !sampling
            }
            // Cleared rather than kept until the new colour lands: the theme already keys on this
            // value, so emptying it re-resolves through the cheap fallback and the sampled colour
            // arrives as a fresh update.
            _seed.value = null
            if (resample) ensureSampled()
        }
    }

    init {
        runCatching {
            val filter = IntentFilter(Intent.ACTION_WALLPAPER_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(wallpaperReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(wallpaperReceiver, filter)
            }
        }
    }

    /**
     * Samples the wallpaper unless its generation has already been sampled or is being sampled.
     *
     * Cheap to call repeatedly: both guards sit in a short synchronized block, so once a generation
     * is sampled this returns without touching the dispatcher.
     */
    fun ensureSampled() {
        // Android 12+ has a real system palette, so the wallpaper is not the source of truth there.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return

        val mine = synchronized(lock) {
            if (sampledGeneration == generation || sampling) return
            sampling = true
            generation
        }

        scope.launch {
            val sampled = runCatching { sample() }.getOrNull()
            val current = synchronized(lock) {
                sampling = false
                generation
            }
            if (current != mine) {
                // The wallpaper changed while this ran, so the colour is for one that has already
                // been replaced. Dropped, and the generation now on screen is sampled instead.
                ensureSampled()
                return@launch
            }
            if (sampled != null) {
                sampledGeneration = mine
                _seed.value = sampled
            } else {
                logcat(LogPriority.DEBUG) { "No seed could be sampled from the wallpaper" }
            }
        }
    }

    private fun sample(): Color? {
        val drawable = runCatching {
            WallpaperManager.getInstance(context).getDrawable(WallpaperManager.FLAG_SYSTEM)
        }.getOrNull() ?: return null

        val bitmap = drawable.toSampledBitmap() ?: return null
        val palette = runCatching {
            Palette.from(bitmap)
                .clearFilters()
                .maximumColorCount(32)
                .generate()
        }.getOrNull()
        bitmap.recycle()
        palette ?: return null

        val swatch = palette.vibrantSwatch
            ?: palette.lightVibrantSwatch
            ?: palette.darkVibrantSwatch
            ?: palette.mutedSwatch
            ?: palette.dominantSwatch
            ?: return null

        return Color(swatch.rgb)
    }
}

/**
 * Decodes the wallpaper small enough for the quantiser. Palette is doing a full-image histogram,
 * so a full-resolution bitmap buys nothing and costs a lot of allocation on low-end devices.
 */
private fun Drawable.toSampledBitmap(): Bitmap? {
    val source = runCatching { toBitmap() }.getOrNull() ?: return null

    val longest = maxOf(source.width, source.height)
    if (longest == 0) return null
    if (longest <= MAX_SAMPLE_EDGE) return source

    val scale = MAX_SAMPLE_EDGE.toFloat() / longest
    val scaled = Bitmap.createScaledBitmap(
        source,
        (source.width * scale).toInt().coerceAtLeast(1),
        (source.height * scale).toInt().coerceAtLeast(1),
        true,
    )
    if (scaled !== source) source.recycle()
    return scaled
}

private const val MAX_SAMPLE_EDGE = 256

/**
 * Starts sampling if needed and returns the seed as Compose state, so the caller can key a
 * `remember` on it and rebuild the scheme once the sample lands.
 */
@Composable
internal fun rememberWallpaperSeed(): Color? {
    val sampler = globalAppGraph.wallpaperSeedSampler
    LaunchedEffect(Unit) { sampler.ensureSampled() }
    return sampler.seed.value
}
