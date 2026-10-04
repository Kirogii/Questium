package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.content.Intent
import android.os.Bundle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.lifecycleScope
import eu.kanade.tachiyomi.ui.main.MainActivity
import eu.kanade.tachiyomi.ui.reader.ReaderViewModel
import kotlinx.coroutines.launch
import mihon.app.di.appGraph
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.xr.XRMode

class VrActivity : GodotActivity() {
    private val readers = ViewModelStore()
    private var readerManga = -1L
    private var contentBridge: HouriVrBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        appGraph.preferenceStore.getBoolean(VrSettingKeys.ENABLED.key).set(true)
    }

    override fun getCommandLine(): MutableList<String> = super.getCommandLine().toMutableList().apply {
        // Android's GL surface needs its own XR mode in addition to the engine flag.
        addAll(listOf("--main-pack", "res://vr.pck", XRMode.OPENXR.cmdLineArg, "--xr-mode", "on"))
    }

    override fun getHostPlugins(godot: Godot): Set<GodotPlugin> = setOf(
        contentBridge ?: HouriVrBridge(godot, this).also { contentBridge = it },
    )

    fun reader(mangaId: Long): ReaderViewModel {
        check(android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
        if (readerManga != mangaId) {
            readers.clear()
            readerManga = mangaId
        }
        return ViewModelProvider(readers, appGraph.viewModelFactory, defaultViewModelCreationExtras)
            .get("vr-reader-$mangaId", ReaderViewModel::class.java)
    }

    fun exitVr() {
        runOnUiThread {
            appGraph.preferenceStore.getBoolean(VrSettingKeys.ENABLED.key).set(false)
            // Godot cannot reliably initialize a second engine in the same process.
            // Restart into the normal activity after its readers have saved progress.
            readers.clear()
            triggerRebirth(null, Intent(this, MainActivity::class.java))
        }
    }

    override fun onGodotForceQuit(instance: Godot) {
        lifecycleScope.launch {
            contentBridge?.flushProgress()
            exitVr()
        }
    }

    override fun onDestroy() {
        contentBridge?.close()
        readers.clear()
        super.onDestroy()
    }
}
// KMK <--
