package eu.kanade.presentation.more.settings.screen

// KMK -->
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import eu.kanade.presentation.more.settings.Preference
import eu.kanade.presentation.more.settings.framework.SettingDefinition
import eu.kanade.presentation.more.settings.framework.toItems
import eu.kanade.tachiyomi.data.questiumsync.QuestiumSync
import eu.kanade.tachiyomi.data.questiumsync.SyncPeer
import eu.kanade.tachiyomi.data.questiumsync.SyncSettingKeys
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import mihon.app.di.appGraph
import tachiyomi.core.common.preference.SettingHost
import tachiyomi.core.common.preference.SettingKey
import tachiyomi.core.common.preference.SettingsRegistry
import tachiyomi.i18n.kmk.KMR
import tachiyomi.presentation.core.i18n.stringResource

object SettingsQuestiumSyncScreen : SearchableSettings {
    private fun readResolve(): Any = SettingsQuestiumSyncScreen

    @Composable
    @ReadOnlyComposable
    override fun getTitleRes() = KMR.strings.questium_sync

    @Composable
    override fun getPreferences(): List<Preference> {
        val context = LocalContext.current
        val sync = remember { QuestiumSync.get(context) }
        return QuestiumSyncSettingsHost.definitions.toItems(context.appGraph.preferenceStore) + Preference.PreferenceItem.CustomPreference(
            title = stringResource(KMR.strings.questium_sync_devices),
            content = { SyncControls(sync) },
        )
    }
}

object QuestiumSyncSettingsHost : SettingHost {
    private val enabledKey = SettingKey(SyncSettingKeys.ENABLED, false)
    private val mainKey = SettingKey(SyncSettingKeys.MAIN, false)
    override val settingKeys = listOf(enabledKey, mainKey)

    init {
        SettingsRegistry.register(this)
    }

    val definitions = listOf(
        SettingDefinition(enabledKey, KMR.strings.questium_sync_enable, bind = { getBoolean(it.key, it.default) }, makeItem = { preference, gate ->
            val sync = QuestiumSync.get(LocalContext.current)
            Preference.PreferenceItem.SwitchPreference(
                preference,
                title = stringResource(KMR.strings.questium_sync_enable),
                subtitle = stringResource(KMR.strings.questium_sync_idle),
                enabled = gate,
                onValueChanged = {
                    runCatching {
                        sync.setEnabled(it)
                        true
                    }.onFailure { error -> sync.status.value = error.message.orEmpty() }.getOrDefault(false)
                },
            )
        }),
        SettingDefinition(mainKey, KMR.strings.questium_sync_main, bind = { getBoolean(it.key, it.default) }, makeItem = { preference, gate ->
            val sync = QuestiumSync.get(LocalContext.current)
            Preference.PreferenceItem.SwitchPreference(
                preference,
                title = stringResource(KMR.strings.questium_sync_main),
                subtitle = stringResource(KMR.strings.questium_sync_priority),
                enabled = gate,
                onValueChanged = {
                    runCatching {
                        sync.setMain(it)
                        true
                    }.onFailure { error -> sync.status.value = error.message.orEmpty() }.getOrDefault(false)
                },
            )
        }),
    )
}

@Composable
private fun SyncControls(sync: QuestiumSync) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val status by sync.status.collectAsState()
    val revision by sync.revision.collectAsState()
    var tab by remember { mutableIntStateOf(0) }
    var link by remember { mutableStateOf("") }
    var peers by remember { mutableStateOf(emptyList<SyncPeer>()) }
    var busy by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf(sync.selected.get()) }
    fun action(block: suspend () -> Unit) {
        if (busy) return
        scope.launch {
            busy = true
            try {
                withContext(Dispatchers.IO) { block() }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                sync.status.value = error.message ?: context.getString(KMR.strings.questium_sync_failed.resourceId)
            } finally {
                busy = false
            }
        }
    }
    LaunchedEffect(revision) {
        selected = sync.selected.get()
        try {
            peers = sync.devices()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            peers = sync.localState().peers
        }
    }
    Column(Modifier.fillMaxWidth().padding(16.dp)) {
        Text(status)
        Row {
            listOf(KMR.strings.questium_sync_devices, KMR.strings.questium_sync_revert, KMR.strings.questium_sync_cloud).forEachIndexed { index, label ->
                TextButton(onClick = { tab = index }) { Text(stringResource(label)) }
            }
        }
        when (tab) {
            0 -> {
                OutlinedTextField(link, { link = it }, label = { Text(stringResource(KMR.strings.questium_sync_link)) }, singleLine = true)
                TextButton(enabled = !busy && link.isNotBlank(), onClick = { action { sync.pair(link) } }) { Text(stringResource(KMR.strings.questium_sync_pair)) }
                TextButton(enabled = sync.enabled.get(), onClick = {
                    val clipboard = context.getSystemService(ClipboardManager::class.java)
                    clipboard.setPrimaryClip(ClipData.newPlainText("Questium Sync", sync.pairingLinks().firstOrNull().orEmpty()))
                }) { Text(stringResource(KMR.strings.questium_sync_copy)) }
                sync.pairingLinks().forEach { Text(it.substringBefore('#')) }
                peers.forEach { peer ->
                    Row {
                        Checkbox(peer.id in selected, enabled = !busy, onCheckedChange = { checked ->
                            selected = if (checked) selected + peer.id else selected - peer.id
                            sync.selected.set(selected)
                        })
                        Text(peer.name + if (peer.main) " • " + stringResource(KMR.strings.questium_sync_main_label) else "")
                        if (sync.localState().peers.any { it.id == peer.id }) {
                            TextButton(enabled = !busy, onClick = { sync.forget(peer.id) }) { Text(stringResource(KMR.strings.questium_sync_forget)) }
                        }
                    }
                }
                TextButton(enabled = !busy && sync.enabled.get(), onClick = { action { sync.sync() } }) { Text(stringResource(KMR.strings.questium_sync_now)) }
            }
            1 -> {
                Text(stringResource(KMR.strings.questium_sync_revert_help))
                sync.localState().changes.asReversed().forEach { change ->
                    Text("${change.title}: ${change.from} → ${change.to}")
                    TextButton(enabled = !busy && sync.main.get() && !change.reverted, onClick = { action { sync.revert(change.id) } }) {
                        Text(stringResource(if (change.reverted) KMR.strings.questium_sync_reverted else KMR.strings.questium_sync_revert))
                    }
                }
            }
            2 -> {
                Text(stringResource(KMR.strings.questium_sync_cloud_help))
                listOf("Google Drive" to "com.google.android.apps.docs", "Proton Drive" to "me.proton.android.drive").forEach { (name, pkg) ->
                    TextButton(enabled = !busy, onClick = {
                        action {
                            val file = sync.backup()
                            val uri = FileProvider.getUriForFile(context, "${context.packageName}.provider", file)
                            val intent = Intent(Intent.ACTION_SEND).setType("application/octet-stream").setPackage(pkg)
                                .putExtra(Intent.EXTRA_STREAM, uri)
                                .apply {
                                    clipData = ClipData.newRawUri(file.name, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                            withContext(Dispatchers.Main) { context.startActivity(intent) }
                        }
                    }) { Text(name) }
                }
            }
        }
    }
}
// KMK <--
