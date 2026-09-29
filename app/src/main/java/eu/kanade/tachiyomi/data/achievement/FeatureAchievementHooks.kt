package eu.kanade.tachiyomi.data.achievement

import eu.kanade.domain.connections.service.ConnectionsPreferences
import eu.kanade.domain.connections.service.WebhookPreferences
import eu.kanade.domain.ui.UiPreferences
import eu.kanade.tachiyomi.ui.reader.setting.ReaderPreferences
import exh.yakuyomi.TranslationPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import tachiyomi.core.common.preference.Preference
import tachiyomi.domain.achievement.service.AchievementManager
import tachiyomi.domain.achievement.service.AchievementPreferences
import tachiyomi.domain.library.model.LibraryDisplayMode
import tachiyomi.domain.library.service.LibraryPreferences

/**
 * Unlocks "you turned this on" achievements from the preference behind them.
 *
 * The reachability audit found these ids defined with no unlock site anywhere, so they could
 * never be earned. Each is a setting the user controls, which made one generic watcher cheaper
 * and less error prone than a bespoke call in every settings screen - and it also catches
 * values that only ever arrive from a backup restore or a migration.
 *
 * Fires on change rather than only on enable, so a value that arrived by restore before this
 * existed still unlocks when the preference is next written.
 */
class FeatureAchievementHooks(
    private val prefs: AchievementPreferences,
    private val manager: AchievementManager,
    private val uiPreferences: UiPreferences,
    private val connectionsPreferences: ConnectionsPreferences,
    private val webhookPreferences: WebhookPreferences,
    private val readerPreferences: ReaderPreferences,
    private val translationPreferences: TranslationPreferences,
    private val libraryPreferences: LibraryPreferences,
) {

    fun install(scope: CoroutineScope) {
        if (!prefs.achievementsEnabled().get()) return

        watch(scope, { uiPreferences.censorLewdManga() }, { it }, "censor_toggle")
        watch(scope, { connectionsPreferences.enableDiscordRPC() }, { it }, "discord_rpc")
        watch(scope, { readerPreferences.chapterCompletionSound() }, { it }, "moan_enabled")
        watch(scope, { translationPreferences.autoTranslateOnDownload() }, { it }, "mtl_auto_download")
        watch(scope, { webhookPreferences.enabled() }, { it }, "webhook")
        watch(scope, { libraryPreferences.smartScanlatorMerge() }, { it }, "smart_filter")
        watch(
            scope,
            { libraryPreferences.displayMode() },
            { it == LibraryDisplayMode.StaggeredGrid },
            "staggered_grid",
        )
        // A model path or glossary JSON is the only evidence either was ever configured.
        watch(scope, { translationPreferences.localModel() }, { it.isNotBlank() }, "mtl_local")
        watch(scope, { translationPreferences.glossaryJson() }, { it.isNotBlank() }, "mtl_glossary")
    }

    private fun <T> watch(
        scope: CoroutineScope,
        pref: () -> Preference<T>,
        satisfied: (T) -> Boolean,
        id: String,
    ) {
        scope.launch {
            runCatching {
                val p = pref()
                p.changes().collect { if (satisfied(it)) manager.tryUnlockDirect(id) }
            }
        }
    }
}
