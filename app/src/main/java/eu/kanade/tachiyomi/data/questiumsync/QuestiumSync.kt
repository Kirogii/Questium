package eu.kanade.tachiyomi.data.questiumsync

// KMK -->
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.AtomicFile
import androidx.core.content.ContextCompat
import eu.kanade.tachiyomi.data.backup.create.BackupCreator
import eu.kanade.tachiyomi.data.backup.create.BackupOptions
import eu.kanade.tachiyomi.data.backup.models.Backup
import eu.kanade.tachiyomi.data.backup.restore.restorers.CategoriesRestorer
import eu.kanade.tachiyomi.data.backup.restore.restorers.ExtensionStoreRestorer
import eu.kanade.tachiyomi.data.backup.restore.restorers.MangaRestorer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import mihon.app.di.appGraph
import tachiyomi.core.common.i18n.stringResource
import tachiyomi.domain.chapter.model.ChapterUpdate
import tachiyomi.domain.history.model.HistoryUpdate
import tachiyomi.i18n.kmk.KMR
import java.io.File
import java.net.NetworkInterface
import java.util.Date
import java.util.UUID

@Serializable
data class SyncState(
    val id: String = UUID.randomUUID().toString(),
    val secret: String = SyncWire.secret(),
    val peers: List<SyncPeer> = emptyList(),
    val authSecrets: Map<String, String> = emptyMap(),
    val epochs: Map<String, Long> = emptyMap(),
    val changes: List<ProgressChange> = emptyList(),
    val pendingRevert: String? = null,
    val knownBooks: Set<String> = emptySet(),
)

object SyncSettingKeys {
    const val ENABLED = "__APP_STATE_questium_sync_enabled"
    const val MAIN = "__APP_STATE_questium_sync_main"
    const val SELECTED = "__APP_STATE_questium_sync_devices"
}

class QuestiumSync private constructor(private val context: Context) {
    private val graph get() = context.appGraph
    private val folder = File(context.filesDir, "questium-sync").apply { mkdirs() }
    private val stateFile = AtomicFile(File(folder, "state.json"))
    private var state = if (stateFile.baseFile.exists() || File(folder, "state.json.bak").exists()) {
        // Never replace a damaged journal with an empty one: keep it for recovery.
        SyncWire.json.decodeFromString(SyncState.serializer(), stateFile.openRead().bufferedReader().use { it.readText() })
    } else {
        SyncState().also(::save)
    }
    private val mutation = Mutex()
    val status = MutableStateFlow(context.stringResource(KMR.strings.questium_sync_ready))
    val revision = MutableStateFlow(0L)
    val enabled get() = graph.preferenceStore.getBoolean(SyncSettingKeys.ENABLED, false)
    val main get() = graph.preferenceStore.getBoolean(SyncSettingKeys.MAIN, false)
    val selected get() = graph.preferenceStore.getStringSet(SyncSettingKeys.SELECTED, emptySet())

    @Volatile var listening = false
        internal set

    @Synchronized fun localState(): SyncState = state

    @Synchronized private fun save(value: SyncState) {
        val output = stateFile.startWrite()
        try {
            output.write(SyncWire.json.encodeToString(SyncState.serializer(), value).toByteArray())
            stateFile.finishWrite(output)
        } catch (error: Exception) {
            stateFile.failWrite(output)
            throw error
        }
    }

    @Synchronized private fun change(update: (SyncState) -> SyncState) {
        val next = update(state)
        save(next)
        state = next
        revision.value += 1
    }

    fun setEnabled(value: Boolean) {
        enabled.set(value)
        if (value) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, SyncEndpointService::class.java))
            } catch (error: Exception) {
                enabled.set(false)
                throw error
            }
        } else {
            context.stopService(Intent(context, SyncEndpointService::class.java))
        }
        revision.value += 1
    }

    suspend fun setMain(value: Boolean) = withContext(Dispatchers.IO) {
        mutation.withLock {
            check(!value || localState().peers.none { it.main }) { context.stringResource(KMR.strings.questium_sync_disable_the_current_main_device_first) }
            main.set(value)
            localState().peers.forEach { peer ->
                runCatching { SyncWire.call(peer, message("role")) }.onFailure {
                    status.value = context.stringResource(KMR.strings.questium_sync_main_device_role_changed_re_pair_offline_devices_before_syncing)
                }
            }
            revision.value += 1
        }
    }

    fun pairingLinks(): List<String> = NetworkInterface.getNetworkInterfaces().toList()
        .flatMap { it.inetAddresses.toList() }
        .filter { it.address.size == 4 && it.isSiteLocalAddress }
        .map { "questium-sync://${it.hostAddress}:${SyncWire.PORT}#${localState().secret}" }

    suspend fun pair(link: String) = withContext(Dispatchers.IO) {
        check(enabled.get() && listening) { context.stringResource(KMR.strings.questium_sync_enable_questium_sync_first) }
        val uri = Uri.parse(link.trim())
        require(uri.scheme == "questium-sync" && uri.host != null && uri.fragment != null) { context.stringResource(KMR.strings.questium_sync_paste_the_pairing_link_from_your_other_device) }
        val peer = SyncPeer("", "", uri.host!!, uri.port, uri.fragment!!)
        SyncWire.address(peer.host)
        val incomingKey = SyncWire.secret()
        val response = SyncWire.call(peer, message("pair").copy(port = SyncWire.PORT, secret = incomingKey))
        require(response.id != localState().id && response.id.isNotEmpty()) { context.stringResource(KMR.strings.questium_sync_choose_a_different_device) }
        require(response.secret.length == 43 && response.name.length <= 120)
        check(!(response.main && main.get())) { context.stringResource(KMR.strings.questium_sync_only_one_device_may_be_main) }
        change {
            it.copy(
                peers = it.peers.filterNot { old -> old.id == response.id } + peer.copy(id = response.id, name = response.name, main = response.main, secret = response.secret),
                authSecrets = it.authSecrets + (response.id to incomingKey),
            )
        }
        selected.set(selected.get() + response.id)
        status.value = context.stringResource(KMR.strings.questium_sync_paired, response.name)
    }

    private fun message(operation: String) = SyncMessage(operation, localState().id, Build.MODEL, main = main.get())

    suspend fun receive(request: SyncMessage, remoteHost: String): SyncMessage {
        require(request.id != localState().id && request.id.isNotBlank())
        if (request.operation == "pair") {
            require(request.port in 1024..65535 && request.secret.length == 43 && request.name.length <= 120)
            SyncWire.address(remoteHost)
            check(!(request.main && main.get())) { context.stringResource(KMR.strings.questium_sync_only_one_device_may_be_main) }
            val sessionKey = SyncWire.secret()
            change {
                it.copy(
                    secret = SyncWire.secret(),
                    peers = it.peers.filterNot { peer -> peer.id == request.id } + SyncPeer(request.id, request.name, remoteHost, request.port, request.secret, request.main),
                    authSecrets = it.authSecrets + (request.id to sessionKey),
                )
            }
            selected.set(selected.get() + request.id)
            return message("paired").copy(secret = sessionKey)
        }
        require(localState().peers.any { it.id == request.id }) { context.stringResource(KMR.strings.questium_sync_pair_this_device_first) }
        SyncWire.address(remoteHost)
        if (localState().peers.first { it.id == request.id }.host != remoteHost) {
            change { state -> state.copy(peers = state.peers.map { if (it.id == request.id) it.copy(host = remoteHost) else it }) }
        }
        return when (request.operation) {
            "role" -> {
                check(!request.main || !main.get()) { context.stringResource(KMR.strings.questium_sync_disable_the_current_main_device_first) }
                change { state -> state.copy(peers = state.peers.map { if (it.id == request.id) it.copy(main = request.main) else it }) }
                message("role_updated")
            }
            "snapshot" -> mutation.withLock { message("snapshot").copy(library = snapshot()) }
            "devices" -> message("devices").copy(devices = localState().peers.map { it.copy(secret = "") })
            "sync" -> {
                check(main.get()) { context.stringResource(KMR.strings.questium_sync_designate_a_main_device_in_questium_sync_on_android) }
                coordinate(request.selected.toSet() + request.id)
                message("complete")
            }
            "apply" -> mutation.withLock {
                check(!main.get() && localState().peers.singleOrNull { it.id == request.id }?.main == true) { context.stringResource(KMR.strings.questium_sync_only_the_designated_main_device_can_apply_a_library) }
                val library = requireNotNull(request.library)
                apply(library)
                message("applied")
            }
            else -> error(context.stringResource(KMR.strings.questium_sync_unsupported_sync_operation))
        }
    }

    suspend fun sync() = withContext(Dispatchers.IO) {
        if (main.get()) {
            coordinate(selected.get())
        } else {
            val primary = localState().peers.singleOrNull { it.main } ?: error(context.stringResource(KMR.strings.questium_sync_pair_with_exactly_one_main_android_device))
            status.value = context.stringResource(KMR.strings.questium_sync_syncing_on, primary.name)
            try {
                SyncWire.call(primary, message("sync").copy(selected = selected.get().toList()))
                status.value = context.stringResource(KMR.strings.questium_sync_synced)
            } catch (error: Exception) {
                status.value = error.message ?: context.stringResource(KMR.strings.questium_sync_sync_failed)
                throw error
            }
        }
    }

    suspend fun devices(): List<SyncPeer> = withContext(Dispatchers.IO) {
        val local = localState().peers
        if (main.get()) return@withContext local
        val primary = local.singleOrNull { it.main } ?: return@withContext local
        val available = SyncWire.call(primary, message("devices")).devices.filterNot { it.id == localState().id }
        (local + available).distinctBy { it.id }
    }

    private suspend fun coordinate(ids: Set<String>) = mutation.withLock {
        finishRevert()
        val peers = localState().peers.filter { it.id in ids }
        check(peers.isNotEmpty()) { context.stringResource(KMR.strings.questium_sync_select_at_least_one_paired_device) }
        check(peers.none { it.main }) { context.stringResource(KMR.strings.questium_sync_only_one_device_can_be_the_main_device) }
        status.value = context.stringResource(KMR.strings.questium_sync_reading_selected_libraries)
        try {
            // Pull every device before changing anything, so an offline device cannot cause a partial merge.
            val incoming = peers.map { requireNotNull(SyncWire.call(it, message("snapshot")).library) }
            val before = snapshot()
            val beforeMangas = before.backup.backupManga.associateBy(SyncMerge::key)
            val beforeProgress = before.backup.backupManga.associate { SyncMerge.key(it) to SyncMerge.progress(it) }
            val beforeHighest = before.backup.backupManga.associate { SyncMerge.key(it) to SyncMerge.resume(it) }
            val merged = SyncMerge.merge(before, incoming)
            val changes = merged.backup.backupManga.mapNotNull { manga ->
                val key = SyncMerge.key(manga)
                val old = beforeProgress[key] ?: return@mapNotNull null
                if (!SyncMerge.advanced(old, SyncMerge.progress(manga)) && SyncMerge.latestHistory(beforeMangas.getValue(key))?.url == SyncMerge.latestHistory(manga)?.url) return@mapNotNull null
                ProgressChange(UUID.randomUUID().toString(), key, manga.title, System.currentTimeMillis(), old, beforeHighest.getValue(key), SyncMerge.highest(manga), history = beforeMangas.getValue(key).history)
            }
            // Save the rollback before the first database write, including interrupted syncs.
            if (changes.isNotEmpty()) change { it.copy(changes = it.changes + changes) }
            status.value = context.stringResource(KMR.strings.questium_sync_applying_library_on_main_device)
            apply(merged)
            peers.forEach { peer ->
                status.value = context.stringResource(KMR.strings.questium_sync_updating, peer.name)
                SyncWire.call(peer, message("apply").copy(library = merged))
            }
            status.value = context.stringResource(KMR.strings.questium_sync_synced_devices, peers.size)
        } catch (error: Exception) {
            status.value = context.stringResource(KMR.strings.questium_sync_incomplete, error.message.orEmpty())
            throw error
        }
        revision.value += 1
    }

    private suspend fun snapshot(): SyncLibrary {
        val creator = BackupCreator(context, false)
        val options = BackupOptions(appSettings = false, sourceSettings = false, tracking = false, savedSearchesFeeds = false)
        val mangas = graph.getFavorites.await() + graph.mangaRepository.getReadMangaNotInLibrary()
        val entries = creator.backupMangas(mangas.distinctBy { it.id }, options)
        return SyncLibrary(
            Backup(entries, creator.backupCategories(options), creator.backupSources(entries), backupExtensionStores = creator.backupExtensionStores(options)),
            localState().epochs,
            localState().knownBooks - entries.map(SyncMerge::key).toSet(),
        )
    }

    private suspend fun apply(library: SyncLibrary) {
        library.backup.backupExtensionStores.forEach { ExtensionStoreRestorer()(it) }
        val categories = CategoriesRestorer()(library.backup.backupCategories)
        val restorer = MangaRestorer(isSync = true)
        library.backup.backupManga.forEach { entry ->
            if ((library.epochs[SyncMerge.key(entry)] ?: 0L) > (localState().epochs[SyncMerge.key(entry)] ?: 0L)) {
                graph.getMangaByUrlAndSourceId.await(entry.url, entry.source)?.let {
                    graph.historyRepository.resetHistoryByMangaIds(listOf(it.id))
                }
            }
            restorer.restore(entry, library.backup.backupCategories, categories)
            val manga = graph.getMangaByUrlAndSourceId.await(entry.url, entry.source) ?: error(context.stringResource(KMR.strings.questium_sync_restore_failed, entry.title))
            // The usual backup restore ORs favorites and chooses newer versions; sync's main device is authoritative.
            restorer.updateManga(entry.getMangaImpl().copy(id = manga.id))
            if (entry.categories.isEmpty() && entry.categoryIds.isEmpty()) {
                graph.mangaRepository.setMangaCategories(manga.id, emptyList())
            }
        }
        val favorites = graph.getFavorites.await().associateBy { "${it.source}|${it.url}" }
        library.removed.forEach { key ->
            favorites[key]?.let { manga ->
                restorer.updateManga(manga.copy(favorite = false))
            }
        }
        change { it.copy(epochs = library.epochs, knownBooks = it.knownBooks + library.backup.backupManga.map(SyncMerge::key) + library.removed) }
    }

    fun forget(id: String) {
        change { it.copy(peers = it.peers.filterNot { peer -> peer.id == id }, authSecrets = it.authSecrets - id) }
        selected.set(selected.get() - id)
    }

    suspend fun revert(id: String) = mutation.withLock {
        check(main.get()) { context.stringResource(KMR.strings.questium_sync_revert_changes_on_the_main_android_device) }
        finishRevert()
        val record = localState().changes.single { it.id == id && !it.reverted }
        change { state ->
            state.copy(
                pendingRevert = id,
                epochs = state.epochs + (record.mangaKey to ((state.epochs[record.mangaKey] ?: 0L) + 1)),
            )
        }
        finishRevert()
        status.value = context.stringResource(KMR.strings.questium_sync_restored, record.title, record.from)
    }

    private suspend fun finishRevert() {
        val id = localState().pendingRevert ?: return
        val change = localState().changes.single { it.id == id && !it.reverted }
        val manga = graph.getMangaByUrlAndSourceId.await(change.mangaKey.substringAfter('|'), change.mangaKey.substringBefore('|').toLong())
            ?: error(context.stringResource(KMR.strings.questium_sync_this_manga_is_no_longer_available))
        val saved = change.before.associateBy { it.url }
        val updates = graph.getChaptersByMangaId.await(manga.id).map { chapter ->
            val prior = saved[chapter.url]
            ChapterUpdate(chapter.id, read = prior?.read ?: false, lastPageRead = prior?.page ?: 0L)
        }
        graph.chapterRepository.updateAll(updates)
        graph.historyRepository.resetHistoryByMangaIds(listOf(manga.id))
        val chapters = graph.getChaptersByMangaId.await(manga.id).associateBy { it.url }
        graph.historyRepository.upsertHistory(
            change.history.mapNotNull { history ->
                chapters[history.url]?.let { HistoryUpdate(it.id, Date(history.lastRead), 0) }
            },
        )
        change { state ->
            state.copy(
                pendingRevert = null,
                changes = state.changes.map { if (it.id == id) it.copy(reverted = true) else it },
            )
        }
    }

    suspend fun backup(): File = withContext(Dispatchers.IO) {
        val file = File(context.cacheDir, "questium-sync-backup-${System.currentTimeMillis()}.tachibk").apply { createNewFile() }
        BackupCreator(context, false).backup(Uri.fromFile(file), BackupOptions(privateSettings = false))
        file
    }

    companion object {
        @Volatile private var instance: QuestiumSync? = null
        fun get(context: Context): QuestiumSync = instance ?: synchronized(this) {
            instance ?: QuestiumSync(context.applicationContext).also { instance = it }
        }
    }
}
// KMK <--
