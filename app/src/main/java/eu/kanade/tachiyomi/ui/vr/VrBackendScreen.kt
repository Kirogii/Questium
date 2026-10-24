package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.content.Context
import androidx.compose.runtime.Composable
import dev.icerock.moko.resources.StringResource
import eu.kanade.presentation.more.settings.screen.SettingsDataScreen
import eu.kanade.presentation.more.settings.screen.SettingsMainScreen
import eu.kanade.presentation.more.settings.screen.about.AboutScreen
import eu.kanade.presentation.util.Screen
import eu.kanade.tachiyomi.ui.browse.BrowseTab
import eu.kanade.tachiyomi.ui.browse.source.browse.BrowseSourceScreen
import eu.kanade.tachiyomi.ui.category.CategoryScreen
import eu.kanade.tachiyomi.ui.download.DownloadQueueScreen
import eu.kanade.tachiyomi.ui.history.HistoryTab
import eu.kanade.tachiyomi.ui.library.LibraryTab
import eu.kanade.tachiyomi.ui.libraryUpdateError.LibraryUpdateErrorScreen
import eu.kanade.tachiyomi.ui.more.MoreTab
import eu.kanade.tachiyomi.ui.stats.StatsScreen
import eu.kanade.tachiyomi.ui.updates.UpdatesTab
import exh.ui.batchadd.BatchAddScreen
import tachiyomi.i18n.MR
import tachiyomi.i18n.kmk.KMR
import tachiyomi.i18n.sy.SYMR
import cafe.adriel.voyager.core.screen.Screen as VoyagerScreen

/** Selects the original Android content; the bridge supplies its navigation context. */
internal class VrBackendScreen private constructor(
    val destination: String,
    val title: String,
    private val screen: VoyagerScreen,
) : Screen() {
    @Composable
    override fun Content() {
        screen.Content()
    }

    companion object {
        fun create(destination: String, context: Context, sourceId: Long? = null, query: String? = null, filtersJson: String? = null): VrBackendScreen? {
            val target: Pair<StringResource, VoyagerScreen> = when (destination) {
                "library", "favorites" -> MR.strings.label_library to LibraryTab
                "history" -> MR.strings.label_recent_manga to HistoryTab
                "updates" -> MR.strings.label_recent_updates to UpdatesTab
                "source" -> MR.strings.browse to BrowseSourceScreen(sourceId ?: return null, query, filtersJson)
                "browse", "sources", "extensions" -> MR.strings.browse to BrowseTab
                "more", "sidebar" -> MR.strings.label_more to MoreTab
                "categories" -> MR.strings.action_edit_categories to CategoryScreen()
                "downloads" -> MR.strings.label_download_queue to DownloadQueueScreen
                "statistics", "stats" -> MR.strings.label_stats to StatsScreen()
                "data", "storage" -> MR.strings.label_data_storage to SettingsDataScreen
                "settings" -> MR.strings.label_settings to SettingsMainScreen
                "about" -> MR.strings.pref_category_about to AboutScreen()
                "batch_add" -> SYMR.strings.batch_add to BatchAddScreen()
                "update_errors" -> KMR.strings.label_library_update_errors to LibraryUpdateErrorScreen()
                else -> return null
            }
            if (destination == "extensions") BrowseTab.showExtension()
            return VrBackendScreen(destination, target.first.getString(context), target.second)
        }
    }
}
// KMK <--
