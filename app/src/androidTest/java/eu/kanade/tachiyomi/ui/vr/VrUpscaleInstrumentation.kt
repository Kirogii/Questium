package eu.kanade.tachiyomi.ui.vr

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import kotlinx.coroutines.runBlocking

/** Runs without a VR activity, screen wake-up, or user input. */
class VrUpscaleInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val result = Bundle()
        try {
            runBlocking {
                eu.kanade.tachiyomi.ui.reader.setting.UpscalePreferences.Model.entries.forEach {
                    VrUpscaleProbe.run(targetContext, it)
                }
            }
            result.putString("stream", "PASS: real ONNX inference through VR two-page and padded long-page processing\n")
            finish(Activity.RESULT_OK, result)
        } catch (error: Throwable) {
            result.putString("stream", "FAIL: ${error.stackTraceToString()}\n")
            finish(Activity.RESULT_CANCELED, result)
        }
    }
}
