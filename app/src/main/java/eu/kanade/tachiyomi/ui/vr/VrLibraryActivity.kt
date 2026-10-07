package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.content.Intent
import android.os.Bundle
import eu.kanade.tachiyomi.ui.main.MainActivity
import eu.kanade.tachiyomi.ui.reader.ReaderActivity

/** The ordinary app UI, rendered on the private display owned by the VR panel. */
class VrLibraryActivity : MainActivity() {
    override fun startActivity(intent: Intent, options: Bundle?) {
        if (intent.component?.className == ReaderActivity::class.java.name && VrAndroidPanel.openChapter(intent)) {
            return
        }
        super.startActivity(intent, options)
    }
}
// KMK <--
