package eu.kanade.presentation.more.settings.screen

// KMK -->
import android.content.Context
import android.content.Intent
import android.os.Build
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
        val supported = remember { context.isVrHeadset() }
        return VrSettingsHost.definitions.toItems(context.appGraph.preferenceStore) +
            Preference.PreferenceItem.TextPreference(
                title = stringResource(KMR.strings.pref_vr_enter),
                subtitle = stringResource(if (supported) KMR.strings.pref_vr_summary else KMR.strings.pref_vr_requires_quest),
                enabled = supported,
                grayOut = true,
                onClick = { context.startActivity(Intent(context, VrActivity::class.java)) },
            )
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
                val supported = remember { context.isVrHeadset() }
                Preference.PreferenceItem.SwitchPreference(
                    preference = enabled,
                    title = stringResource(KMR.strings.pref_vr_enable),
                    subtitle = stringResource(if (supported) KMR.strings.pref_vr_summary else KMR.strings.pref_vr_requires_quest),
                    enabled = gate && supported,
                    grayOut = true,
                    onValueChanged = { value ->
                        if (value) context.startActivity(Intent(context, VrActivity::class.java))
                        true
                    },
                )
            },
        ),
    )
}
private fun Context.isVrHeadset(): Boolean =
    packageManager.hasSystemFeature("android.hardware.vr.headtracking") ||
        Build.MANUFACTURER.equals("Oculus", ignoreCase = true) ||
        Build.MANUFACTURER.equals("Meta", ignoreCase = true) ||
        Build.MODEL.contains("Quest", ignoreCase = true)
// KMK <--
