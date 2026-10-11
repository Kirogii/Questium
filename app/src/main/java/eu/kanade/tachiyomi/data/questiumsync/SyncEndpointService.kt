package eu.kanade.tachiyomi.data.questiumsync

// KMK -->
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import eu.kanade.tachiyomi.ui.main.MainActivity
import kotlinx.coroutines.runBlocking
import tachiyomi.core.common.i18n.stringResource
import tachiyomi.i18n.kmk.KMR
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class SyncEndpointService : Service() {
    @Volatile private var server: ServerSocket? = null

    @Volatile private var stopped = false
    private val sockets = java.util.Collections.synchronizedSet(mutableSetOf<Socket>())
    private val clients = ThreadPoolExecutor(0, 2, 30, TimeUnit.SECONDS, ArrayBlockingQueue(2))
    private val sync by lazy { QuestiumSync.get(this) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Questium Sync", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 0, Intent(this, javaClass).setAction(STOP), PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Questium Sync")
            .setContentText(this@SyncEndpointService.stringResource(KMR.strings.questium_sync_available_to_paired_devices_waiting))
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .addAction(0, this@SyncEndpointService.stringResource(KMR.strings.questium_sync_stop), stop)
            .build()
        ServiceCompat.startForeground(this, 37443, notification, if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0)
        Thread({
            try {
                val listener = ServerSocket(SyncWire.PORT).also { server = it }
                if (stopped) {
                    listener.close()
                    return@Thread
                }
                sync.listening = true
                sync.status.value = this@SyncEndpointService.stringResource(KMR.strings.questium_sync_waiting_for_paired_devices)
                while (!listener.isClosed) {
                    val socket = listener.accept()
                    sockets.add(socket)
                    try {
                        clients.execute {
                            socket.use {
                                runCatching {
                                    SyncWire.serve(it, { identity ->
                                        val state = sync.localState()
                                        if (identity.isEmpty()) state.secret else requireNotNull(state.authSecrets[identity])
                                    }) { request ->
                                        runBlocking {
                                            try {
                                                sync.receive(request, socket.inetAddress.hostAddress.orEmpty())
                                            } catch (error: Exception) {
                                                sync.status.value = error.message.orEmpty()
                                                throw error
                                            }
                                        }
                                    }
                                }
                            }
                            sockets.remove(socket)
                        }
                    } catch (_: java.util.concurrent.RejectedExecutionException) {
                        sockets.remove(socket)
                        socket.close()
                    }
                }
            } catch (error: Exception) {
                if (!stopped && server?.isClosed != true) {
                    sync.status.value = this@SyncEndpointService.stringResource(KMR.strings.questium_sync_endpoint_unavailable, error.message.orEmpty())
                    sync.enabled.set(false)
                    stopSelf()
                }
            } finally {
                sync.listening = false
            }
        }, "QuestiumSyncAccept").start()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP || !sync.enabled.get()) {
            sync.setEnabled(false)
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopped = true
        runCatching { server?.close() }
        synchronized(sockets) {
            sockets.forEach { runCatching { it.close() } }
            sockets.clear()
        }
        clients.shutdownNow()
        sync.listening = false
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "questium-sync"
        private const val STOP = "questium.sync.STOP"
    }
}
// KMK <--
