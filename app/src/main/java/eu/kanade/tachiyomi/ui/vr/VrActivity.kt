package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.os.Bundle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.lifecycleScope
import eu.kanade.tachiyomi.ui.reader.ReaderViewModel
import kotlinx.coroutines.launch
import mihon.app.di.appGraph
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.xr.XRMode

class VrActivity : GodotActivity() {
    private val readers = ViewModelStore()
    private var contentBridge: HouriVrBridge? = null
    private var exiting = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        appGraph.preferenceStore.getBoolean(VrSettingKeys.ENABLED.key).set(true)
    }

    override fun getCommandLine(): MutableList<String> = super.getCommandLine().toMutableList().apply {
        // Select the Android OpenXR render surface; project.godot enables OpenXR.
        addAll(listOf("--main-pack", "res://vr.pck", XRMode.OPENXR.cmdLineArg))
    }

    override fun getHostPlugins(godot: Godot): Set<GodotPlugin> = setOf(
        contentBridge ?: HouriVrBridge(godot, this).also {
            contentBridge = it
        },
    )

    fun reader(mangaId: Long, chapterId: Long): ReaderViewModel {
        check(android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
        return ViewModelProvider(readers, appGraph.viewModelFactory, defaultViewModelCreationExtras)
            .get("vr-reader-$mangaId-$chapterId", ReaderViewModel::class.java)
    }

    fun exitVr() {
        runOnUiThread {
            if (exiting) return@runOnUiThread
            exiting = true
            appGraph.preferenceStore.getBoolean(VrSettingKeys.ENABLED.key).set(false)
            // Progress is flushed by the bridge before exiting. Remove the VR task
            // and its engine process so the next launch initializes a fresh engine.
            readers.clear()
            finishAndRemoveTask()
            android.os.Process.killProcess(android.os.Process.myPid())
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
        if (isFinishing && !exiting) exitVr()
    }
}
// KMK <--
