package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.content.Intent
import android.content.pm.PackageManager
import eu.kanade.tachiyomi.data.updater.AppUpdateChecker
import eu.kanade.tachiyomi.extension.util.ExtensionInstaller
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.ProgressListener
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.network.newCachelessCallWithProgress
import eu.kanade.tachiyomi.util.storage.getUriCompat
import eu.kanade.tachiyomi.util.storage.saveTo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import mihon.app.di.appGraph
import org.json.JSONObject
import tachiyomi.core.common.i18n.stringResource
import tachiyomi.domain.release.interactor.GetApplicationRelease
import tachiyomi.domain.release.model.Release
import tachiyomi.i18n.kmk.KMR
import java.io.File
import java.net.URI

/** Keeps the offer on the VR surface; Android handles the final installation approval. */
class VrAppUpdater(private val host: VrActivity, private val send: (JSONObject) -> Unit) {
    private var release: Release? = null
    private var checked = false
    private val download = Mutex()

    suspend fun check() {
        if (checked) return
        checked = true
        try {
            val result = withTimeout(15000) { AppUpdateChecker().checkForUpdate(host, forceCheck = true) }
            if (result is GetApplicationRelease.Result.NewUpdate) {
                val uri = URI(result.release.downloadLink)
                require(uri.scheme == "https" && uri.host == "github.com" && uri.path.startsWith("/Kirogii/Questium/releases/download/"))
                release = result.release
                send(
                    JSONObject().put("kind", "app_update").put("version", result.release.version)
                        .put("message", host.stringResource(KMR.strings.questium_update_offer, result.release.version)),
                )
            }
        } catch (error: kotlinx.coroutines.TimeoutCancellationException) {
            // An unavailable update server must never block opening the library.
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Offline and repositories without a published release simply continue into the app.
        }
    }

    suspend fun install(beforeInstall: suspend () -> Unit) {
        val update = release ?: return
        if (!download.tryLock()) return
        val file = File(host.cacheDir, "questium-update.apk")
        try {
            val listener = object : ProgressListener {
                private var previous = -1
                override fun update(bytesRead: Long, contentLength: Long, done: Boolean) {
                    val progress = if (contentLength > 0) (100 * bytesRead / contentLength).toInt().coerceIn(0, 100) else 0
                    if (progress != previous) {
                        previous = progress
                        send(
                            JSONObject().put("kind", "app_update_status").put("busy", true)
                                .put("message", host.stringResource(KMR.strings.questium_update_downloading, progress)),
                        )
                    }
                }
            }
            host.appGraph.networkHelper.client.newCachelessCallWithProgress(GET(update.downloadLink), listener)
                .awaitSuccess().use { response -> response.body.source().saveTo(file) }
            val flags = PackageManager.GET_SIGNING_CERTIFICATES
            val apk = requireNotNull(host.packageManager.getPackageArchiveInfo(file.path, flags))
            val installed = host.packageManager.getPackageInfo(host.packageName, flags)
            require(apk.packageName == host.packageName && apk.longVersionCode >= installed.longVersionCode) {
                host.stringResource(KMR.strings.questium_update_wrong_package)
            }
            val signers = requireNotNull(apk.signingInfo).apkContentsSigners.toSet()
            require(signers.isNotEmpty() && signers == installed.signingInfo?.apkContentsSigners?.toSet()) {
                host.stringResource(KMR.strings.questium_update_wrong_signature)
            }
            beforeInstall()
            host.appGraph.databaseHandler.checkpoint()
            withContext(Dispatchers.Main) {
                host.startActivity(
                    Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(file.getUriCompat(host), ExtensionInstaller.APK_MIME)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    },
                )
            }
            send(
                JSONObject().put("kind", "app_update_status").put("busy", false)
                    .put("message", host.stringResource(KMR.strings.questium_update_confirm_install)),
            )
        } catch (error: CancellationException) {
            file.delete()
            throw error
        } catch (error: Exception) {
            file.delete()
            send(
                JSONObject().put("kind", "app_update_status").put("busy", false)
                    .put("message", host.stringResource(KMR.strings.questium_update_failed, error.message.orEmpty())),
            )
        } finally {
            download.unlock()
        }
    }
}
// KMK <--
