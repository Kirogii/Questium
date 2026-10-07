package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.app.Activity
import android.app.ActivityOptions
import android.app.Application
import android.app.Presentation
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.os.Bundle
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Surface
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inspector.WindowInspector
import androidx.activity.ComponentActivity
import androidx.annotation.Keep
import org.json.JSONObject
import tachiyomi.core.common.util.system.logcat

/** No screen capture: Android renders its own windows directly into the OpenXR surface. */
@Keep
object VrAndroidPanel {
    private var host: VrActivity? = null
    private var bridge: HouriVrBridge? = null
    private var display: VirtualDisplay? = null
    private var bootstrapWindow: Presentation? = null
    private val activities = mutableListOf<Activity>()
    private var touchRoot: View? = null
    private var downTime = 0L
    private var cursorRoot: View? = null
    private val cursor = object : Drawable() {
        var x = 0f
        var y = 0f
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun draw(canvas: Canvas) {
            paint.color = Color.BLACK
            canvas.drawCircle(x, y, 12f, paint)
            paint.color = Color.WHITE
            canvas.drawCircle(x, y, 8f, paint)
        }
        override fun setAlpha(alpha: Int) = Unit
        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    @Volatile private var failure = ""

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, state: Bundle?) {
            if (activity.display?.displayId == display?.display?.displayId) {
                activities.add(activity)
                bootstrapWindow?.dismiss()
                bootstrapWindow = null
            }
        }
        override fun onActivityResumed(activity: Activity) {
            if (activity in activities) {
                activities.remove(activity)
                activities.add(activity)
            }
        }
        override fun onActivityDestroyed(activity: Activity) {
            activities.remove(activity)
        }
        override fun onActivityStarted(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    }

    fun attach(activity: VrActivity, content: HouriVrBridge) {
        host = activity
        bridge = content
        activity.application.registerActivityLifecycleCallbacks(lifecycle)
    }

    @JvmStatic
    fun start(surface: Surface, width: Int, height: Int) {
        val activity = host ?: return
        activity.runOnUiThread {
            if (display != null) return@runOnUiThread
            try {
                display = activity.getSystemService(DisplayManager::class.java).createVirtualDisplay(
                    "Houri VR app",
                    width,
                    height,
                    200,
                    surface,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY or DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION,
                ) ?: error("Android could not create the VR app display")
                // Android requires the caller to already own a window on an untrusted
                // display before it can launch an embedded activity there.
                bootstrapWindow = Presentation(activity, display!!.display).apply { show() }
                val options = ActivityOptions.makeBasic().apply { launchDisplayId = display!!.display.displayId }
                activity.startActivity(
                    Intent(activity, VrLibraryActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK),
                    options.toBundle(),
                )
                logcat { "VR Android panel started on display ${display!!.display.displayId}" }
            } catch (error: Exception) {
                failure = error.message ?: error.javaClass.simpleName
                logcat { "VR Android panel failed: $failure" }
                bootstrapWindow?.dismiss()
                bootstrapWindow = null
                display?.release()
                display = null
            }
        }
    }

    @JvmStatic
    fun error(): String = failure

    private fun roots(): List<View> = WindowInspector.getGlobalWindowViews().filter {
        it.display?.displayId == display?.display?.displayId && it.isShown
    }

    @JvmStatic
    fun hover(x: Float, y: Float) {
        host?.runOnUiThread {
            val root = touchRoot ?: roots().lastOrNull() ?: return@runOnUiThread
            if (cursorRoot !== root) {
                cursorRoot?.overlay?.remove(cursor)
                cursorRoot = root
                root.overlay.add(cursor)
            }
            val location = IntArray(2)
            root.getLocationOnScreen(location)
            cursor.x = x - location[0]
            cursor.y = y - location[1]
            cursor.setBounds(0, 0, root.width, root.height)
            cursor.invalidateSelf()
        }
    }

    @JvmStatic
    fun touch(x: Float, y: Float, action: Int) {
        host?.runOnUiThread {
            if (action == MotionEvent.ACTION_DOWN) {
                downTime = SystemClock.uptimeMillis()
                touchRoot = roots().lastOrNull()
                logcat { "VR panel touch down at $x,$y; root=${touchRoot?.javaClass?.simpleName}, size=${touchRoot?.width}x${touchRoot?.height}" }
            }
            val root = touchRoot ?: return@runOnUiThread
            val location = IntArray(2)
            root.getLocationOnScreen(location)
            val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x - location[0], y - location[1], 0)
            event.source = InputDevice.SOURCE_TOUCHSCREEN
            val handled = root.dispatchTouchEvent(event)
            if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_UP) {
                logcat { "VR panel touch action=$action handled=$handled" }
            }
            event.recycle()
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) touchRoot = null
        }
    }

    @JvmStatic
    fun key(text: String) {
        host?.runOnUiThread {
            val root = roots().lastOrNull() ?: return@runOnUiThread
            val focused = root.findFocus() ?: return@runOnUiThread
            val editor = EditorInfo()
            val connection = focused.onCreateInputConnection(editor)
            when (text) {
                "BACKSPACE" -> connection?.deleteSurroundingText(1, 0)
                "ENTER" -> {
                    val action = editor.imeOptions and EditorInfo.IME_MASK_ACTION
                    if (action == EditorInfo.IME_ACTION_NONE || action == EditorInfo.IME_ACTION_UNSPECIFIED) {
                        connection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                        connection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                    } else {
                        connection?.performEditorAction(action)
                    }
                }
                else -> connection?.commitText(text, 1)
            }
        }
    }

    @JvmStatic
    fun back() {
        host?.runOnUiThread {
            val root = roots().lastOrNull() ?: return@runOnUiThread
            val activity = activities.lastOrNull() ?: return@runOnUiThread
            if (root !== activity.window.decorView) {
                root.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
                root.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
            } else {
                (activity as? ComponentActivity)?.onBackPressedDispatcher?.onBackPressed()
            }
        }
    }

    fun openChapter(intent: Intent): Boolean {
        val content = bridge ?: return false
        val manga = intent.getLongExtra("manga", -1)
        val chapter = intent.getLongExtra("chapter", -1)
        if (manga < 0 || chapter < 0) return false
        content.request(JSONObject().put("action", "open").put("manga", manga.toString()).put("chapter", chapter.toString()).toString())
        return true
    }

    fun close() {
        val activity = host ?: return
        activity.runOnUiThread {
            activity.application.unregisterActivityLifecycleCallbacks(lifecycle)
            activities.toList().forEach { it.finish() }
            activities.clear()
            bootstrapWindow?.dismiss()
            bootstrapWindow = null
            display?.release()
            display = null
            touchRoot = null
            cursorRoot?.overlay?.remove(cursor)
            cursorRoot = null
            failure = ""
            bridge = null
            host = null
        }
    }
}
// KMK <--
