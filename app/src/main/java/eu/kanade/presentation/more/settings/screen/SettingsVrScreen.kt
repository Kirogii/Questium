package eu.kanade.presentation.more.settings.screen

// KMK -->
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import eu.kanade.presentation.more.settings.Preference
import eu.kanade.presentation.more.settings.framework.SettingDefinition
import eu.kanade.presentation.more.settings.framework.toItems
import eu.kanade.tachiyomi.ui.vr.VrActivity
import eu.kanade.tachiyomi.ui.vr.VrSettingKeys
import mihon.app.di.appGraph
import tachiyomi.core.common.preference.SettingHost
import tachiyomi.core.common.preference.SettingsRegistry
import tachiyomi.i18n.kmk.KMR
import tachiyomi.presentation.core.i18n.stringResource

object SettingsVrScreen : SearchableSettings {
    private fun readResolve(): Any = SettingsVrScreen

    @Composable
    @ReadOnlyComposable
    override fun getTitleRes() = KMR.strings.pref_vr_title

    @Composable
    override fun getPreferences(): List<Preference> {
        val context = LocalContext.current
        return VrSettingsHost.definitions.toItems(context.appGraph.preferenceStore)
    }
}

object VrSettingsHost : SettingHost {
    override val settingKeys = listOf(VrSettingKeys.ENABLED)

    init {
        SettingsRegistry.register(this)
    }

    val definitions = listOf(
        SettingDefinition(
            key = VrSettingKeys.ENABLED,
            titleRes = KMR.strings.pref_vr_enable,
            bind = { key -> getBoolean(key.key, key.default) },
            makeItem = { enabled, gate ->
                val context = LocalContext.current
                val supported = remember { context.packageManager.hasSystemFeature("android.hardware.vr.headtracking") }
                Preference.PreferenceItem.SwitchPreference(
                    preference = enabled,
                    title = stringResource(KMR.strings.pref_vr_enable),
                    subtitle = stringResource(if (supported) KMR.strings.pref_vr_summary else KMR.strings.pref_vr_requires_quest),
                    enabled = gate && supported,
                    onValueChanged = { value ->
                        if (value) context.startActivity(Intent(context, VrActivity::class.java))
                        true
                    },
                )
            },
        ),
    )
}
// KMK <--
