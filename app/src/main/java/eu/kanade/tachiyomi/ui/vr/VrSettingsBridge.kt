package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.FrameLayout
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.BroadcastFrameClock
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsOwner
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import cafe.adriel.voyager.navigator.Navigator
import eu.kanade.presentation.more.settings.Preference
import eu.kanade.presentation.more.settings.filterVisible
import eu.kanade.presentation.more.settings.isInteractive
import eu.kanade.presentation.more.settings.screen.SearchableSettings
import eu.kanade.presentation.more.settings.screen.SettingsCatalog
import eu.kanade.presentation.theme.TachiyomiTheme
import eu.kanade.presentation.util.LocalBackPress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import mihon.app.di.appGraph
import org.json.JSONArray
import org.json.JSONObject
import tachiyomi.i18n.kmk.KMR
import tachiyomi.presentation.core.i18n.stringResource

/** Runs shared preference models without displaying the Android settings interface. */
class VrSettingsBridge(private val host: VrActivity, private val send: (JSONObject) -> Unit) {
    private val screens = SettingsCatalog.searchableScreens.filter { it.isEnabled() }
    private var view: ComposeView? = null
    private var navigator: Navigator? = null
    private var revision by mutableIntStateOf(0)
    private val controls = mutableMapOf<String, Preference.PreferenceItem<*, *>>()
    private val androidOnlyControls = mutableSetOf<String>()
    private var lastSnapshot = ""
    private var detailSnapshot = ""
    private var inspector: Job? = null
    private val semanticControls = mutableMapOf<String, SemanticsNode>()
    private var dialogRoot: ViewGroup? = null
    private val frameClock = BroadcastFrameClock()
    private var recomposer: Recomposer? = null
    private var compositionJob: Job? = null

    suspend fun request(request: JSONObject) = withContext(Dispatchers.Main) {
        attach()
        when (request.getString("action")) {
            "settings" -> {
                val selected = request.optInt("category", 0).coerceIn(screens.indices)
                navigator?.replaceAll(screens[selected])
                revision++
            }
            "setting" -> {
                if (request.getString("id").startsWith("filter/")) {
                    changeFilter(request)
                    revision++
                    return@withContext
                }
                val item = controls[request.getString("id")] ?: return@withContext
                if (request.getString("id") in androidOnlyControls) return@withContext
                if (!item.enabled) return@withContext
                change(item, request)
                // Keep the Godot scene toggle (and other shared reader
                // preferences) live without requiring a settings reopen.
                publishFilters()
                revision++
            }
            "settings_back" -> {
                navigator?.pop()
                revision++
            }
            "settings_detail" -> publishDetails()
            "settings_dismiss" -> {
                dialogRoot?.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
                dialogRoot?.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
                if (navigator?.lastItem !is SearchableSettings) navigator?.pop()
                revision++
            }
            "settings_semantic" -> {
                if (request.getString("id").startsWith("theme/")) {
                    val shift = mapOf("red" to 16, "green" to 8, "blue" to 0)[request.getString("id").substringAfter('/')] ?: return@withContext
                    val prefs = host.appGraph.uiPreferences
                    prefs.colorTheme().set((prefs.colorTheme().get() and (255 shl shift).inv()) or (request.getInt("value").coerceIn(0, 255) shl shift))
                    prefs.appTheme().set(eu.kanade.domain.ui.model.AppTheme.CUSTOM)
                    revision++
                    publishDetails()
                    return@withContext
                }
                val node = semanticControls[request.getString("id")] ?: return@withContext
                when (request.optString("type")) {
                    "text" -> node.config.getOrNull(SemanticsActions.SetText)?.action?.invoke(AnnotatedString(request.getString("value")))
                    "slider" -> node.config.getOrNull(SemanticsActions.SetProgress)?.action?.invoke(request.getDouble("value").toFloat())
                    "scroll" -> node.config.getOrNull(SemanticsActions.ScrollBy)?.action?.invoke(0f, request.getDouble("value").toFloat())
                    else -> node.config.getOrNull(SemanticsActions.OnClick)?.action?.invoke()
                }
                revision++
            }
        }
    }

    private fun attach() {
        if (view != null) return
        val root = host.window.decorView as ViewGroup
        val engine = Recomposer(host.lifecycleScope.coroutineContext + frameClock)
        recomposer = engine
        compositionJob = host.lifecycleScope.launch(frameClock) { engine.runRecomposeAndApplyChanges() }
        view = ComposeView(host).apply {
            // Only the model metadata crosses into VR. This view is never visible or touchable.
            alpha = 0f
            isClickable = false
            setParentCompositionContext(engine)
            root.addView(this, FrameLayout.LayoutParams(720, 1000))
            setContent {
                TachiyomiTheme {
                    Navigator(screens.first()) { nav ->
                        navigator = nav
                        CompositionLocalProvider(
                            LocalBackPress provides {
                                nav.pop()
                                revision++
                            },
                        ) {
                            val version = revision
                            val screen = nav.lastItem
                            if (screen is SearchableSettings) {
                                with(screen) { Row { AppBarAction() } }
                                val categories = JSONArray()
                                screens.forEachIndexed { index, category ->
                                    categories.put(JSONObject().put("id", index).put("title", stringResource(category.getTitleRes())))
                                }
                                val items = screen.getPreferences().filterVisible()
                                val rows = JSONArray()
                                val bindings = mutableMapOf<String, Preference.PreferenceItem<*, *>>()
                                items.forEachIndexed { index, item ->
                                    if (item is Preference.PreferenceGroup) {
                                        rows.put(JSONObject().put("type", "group").put("title", item.title))
                                        item.preferenceItems.forEachIndexed { child, preference ->
                                            export(preference, "${screen.key}/$index/$child/${preference.title}", rows, bindings, screen === eu.kanade.presentation.more.settings.screen.SettingsReaderScreen)
                                        }
                                    } else if (item is Preference.PreferenceItem<*, *>) {
                                        export(item, "${screen.key}/$index/${item.title}", rows, bindings, screen === eu.kanade.presentation.more.settings.screen.SettingsReaderScreen)
                                    }
                                }
                                if (screen === eu.kanade.presentation.more.settings.screen.SettingsReaderScreen) addFilters(rows)
                                val snapshot = JSONObject().put("kind", "settings").put("categories", categories)
                                    .put("category", screens.indexOf(screen)).put("title", stringResource(screen.getTitleRes()))
                                    .put("items", rows).put("revision", version)
                                SideEffect {
                                    publishFilters()
                                    controls.clear()
                                    controls.putAll(bindings)
                                    if (snapshot.toString() != lastSnapshot) {
                                        lastSnapshot = snapshot.toString()
                                        send(snapshot)
                                    }
                                }
                            } else if (screen !is eu.kanade.presentation.more.settings.screen.appearance.AppCustomThemeColorPickerScreen) {
                                // Nested specialized screens retain their own state and actions.
                                // The semantics adapter exports their controls into frosted VR cards.
                                Column(Modifier.requiredSize(720.dp, 1000.dp)) { screen.Content() }
                            }
                        }
                    }
                }
            }
        }
        inspector = host.lifecycleScope.launch {
            var lastInspection = 0L
            while (true) {
                delay(16)
                Snapshot.sendApplyNotifications()
                frameClock.sendFrame(System.nanoTime())
                if (android.os.SystemClock.uptimeMillis() - lastInspection >= 250) {
                    view?.let { target ->
                        if (target.isLayoutRequested) {
                            target.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY))
                            target.layout(0, 0, 720, 1000)
                        }
                    }
                    publishDetails()
                    lastInspection = android.os.SystemClock.uptimeMillis()
                }
            }
        }
    }

    private fun owners(node: View): List<SemanticsOwner> {
        val own = runCatching {
            node.javaClass.methods.firstOrNull { it.name == "getSemanticsOwner" && it.parameterCount == 0 }
                ?.invoke(node) as? SemanticsOwner
        }.getOrNull()
        return if (own != null) {
            listOf(own)
        } else if (node is ViewGroup) {
            (0 until node.childCount).flatMap { owners(node.getChildAt(it)) }
        } else {
            emptyList()
        }
    }

    private fun publishDetails() {
        var rows = JSONArray()
        val bindings = mutableMapOf<String, SemanticsNode>()
        var dialog = false
        dialogRoot = null
        if (navigator?.lastItem is eu.kanade.presentation.more.settings.screen.appearance.AppCustomThemeColorPickerScreen) {
            val packed = host.appGraph.uiPreferences.colorTheme().get()
            listOf("red" to KMR.strings.vr_color_red, "green" to KMR.strings.vr_color_green, "blue" to KMR.strings.vr_color_blue)
                .forEachIndexed { index, (id, title) ->
                    rows.put(
                        JSONObject().put("id", "theme/$id").put("type", "slider").put("title", title.getString(host))
                            .put("min", 0).put("max", 255).put("value", packed ushr (16 - index * 8) and 255).put("step", 1),
                    )
                }
        }
        fun visit(node: SemanticsNode, prefix: String) {
            val config = node.config
            val id = "$prefix/${node.id}"
            val text = config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text }
                ?: config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ").orEmpty()
            val click = config.getOrNull(SemanticsActions.OnClick)
            val edit = config.getOrNull(SemanticsActions.SetText)
            val progress = config.getOrNull(SemanticsProperties.ProgressBarRangeInfo)
            val scroll = config.getOrNull(SemanticsActions.ScrollBy)
            if (click != null || edit != null || progress != null || scroll != null) {
                val row = JSONObject().put("id", id).put("title", text.ifBlank { click?.label.orEmpty() })
                    .put("enabled", config.getOrNull(SemanticsProperties.Disabled) == null)
                when {
                    edit != null -> row.put("type", "text").put("value", config.getOrNull(SemanticsProperties.EditableText)?.text.orEmpty())
                    progress != null -> row.put("type", "slider").put("value", progress.current)
                        .put("min", progress.range.start).put("max", progress.range.endInclusive).put("step", 0.01)
                    scroll != null && click == null -> row.put("type", "scroll")
                    else -> row.put("type", "action")
                }
                rows.put(row)
                bindings[id] = node
            } else if (text.isNotBlank()) {
                rows.put(JSONObject().put("type", "info").put("title", text))
            }
            node.children.forEach { visit(it, prefix) }
        }
        view?.let { owners(it).forEachIndexed { index, owner -> visit(owner.rootSemanticsNode, "custom$index") } }
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            WindowInspector.getGlobalWindowViews().filter { it !== host.window.decorView && it.context is android.content.ContextWrapper }
                .forEachIndexed { index, root ->
                    val found = owners(root)
                    if (found.isNotEmpty()) {
                        // Android preference dialogs provide logic; their visible controls are rebuilt in VR.
                        root.alpha = 0f
                        dialogRoot = root as? ViewGroup
                        dialog = true
                        rows = JSONArray()
                        bindings.clear()
                        found.forEach { visit(it.rootSemanticsNode, "dialog$index") }
                    }
                }
        }
        val snapshot = JSONObject().put("kind", "settings_detail").put("dialog", dialog)
            .put("nested", navigator?.lastItem !is SearchableSettings).put("items", rows)
        semanticControls.clear()
        semanticControls.putAll(bindings)
        if (snapshot.toString() != detailSnapshot) {
            detailSnapshot = snapshot.toString()
            send(snapshot)
        }
    }

    @Composable
    private fun export(
        item: Preference.PreferenceItem<*, *>,
        id: String,
        rows: JSONArray,
        bindings: MutableMap<String, Preference.PreferenceItem<*, *>>,
        readerScreen: Boolean = false,
    ) {
        val row = JSONObject().put("id", id).put("title", if (item is Preference.PreferenceItem.TrackerPreference) item.tracker.name else item.title)
            .put("subtitle", item.subtitle?.toString().orEmpty()).put("enabled", item.isInteractive())
        bindings[id] = item
        if (readerScreen) {
            val key = when (item) {
                is Preference.PreferenceItem.SwitchPreference -> item.preference.key()
                is Preference.PreferenceItem.ListPreference<*> -> item.preference.key()
                else -> null
            }
            val spatialKeys = setOf(
                "pref_keep_screen_on_key", "pref_default_reading_mode_key", "pref_reader_theme_key",
                "pref_image_scale_type_key", "crop_borders", "crop_borders_webtoon", "crop_borders_continues_vertical",
                "pref_enable_transitions_pager_key", "skip_read", "skip_filtered", "skip_dupe",
                "pref_show_page_number_key", "pref_webtoon_scale_type_key", "eh_preload_size",
            )
            val spatialSlider = item is Preference.PreferenceItem.SliderPreference && item.title in setOf(
                tachiyomi.i18n.MR.strings.pref_webtoon_side_padding.getString(host),
                KMR.strings.pref_webgpu_contrast.getString(host),
            )
            if (item !is Preference.PreferenceItem.InfoPreference && key !in spatialKeys && !spatialSlider) {
                row.put("enabled", false).put("subtitle", KMR.strings.vr_android_reader_only.getString(host))
                androidOnlyControls.add(id)
            } else {
                androidOnlyControls.remove(id)
            }
        }
        when (item) {
            is Preference.PreferenceItem.SwitchPreference -> row.put("type", "switch").put("value", item.preference.get())
            is Preference.PreferenceItem.SliderPreference -> row.put("type", "slider").put("value", item.value)
                .put("min", item.valueRange.first).put("max", item.valueRange.last).put("step", item.valueRange.step)
            is Preference.PreferenceItem.ListPreference<*> -> {
                val entries = item.entries.entries.toList()
                row.put("type", "list").put("entries", JSONArray(entries.map { it.value }))
                    .put("value", entries.indexOfFirst { it.key == item.preference.get() })
            }
            is Preference.PreferenceItem.BasicListPreference -> row.put("type", "list")
                .put("entries", JSONArray(item.entries.values.toList())).put("value", item.entries.keys.indexOf(item.value))
            is Preference.PreferenceItem.MultiSelectListPreference -> row.put("type", "multi")
                .put("entries", JSONArray(item.entries.values.toList())).put("keys", JSONArray(item.entries.keys.toList()))
                .put("value", JSONArray(item.preference.get().toList()))
            is Preference.PreferenceItem.EditTextPreference -> row.put("type", "text").put("value", item.preference.get())
            is Preference.PreferenceItem.CustomPreference -> {
                row.put("type", "custom")
                Column(Modifier.requiredSize(720.dp, 480.dp)) { item.content() }
            }
            is Preference.PreferenceItem.InfoPreference -> row.put("type", "info")
            is Preference.PreferenceItem.TextPreference -> row.put("type", if (item.onClick == null) "info" else "action")
            else -> row.put("type", "action")
        }
        rows.put(row)
    }

    private suspend fun change(item: Preference.PreferenceItem<*, *>, request: JSONObject) {
        when (item) {
            is Preference.PreferenceItem.SwitchPreference -> request.getBoolean("value").let {
                if (item.onValueChanged(it)) item.preference.set(it)
            }
            is Preference.PreferenceItem.SliderPreference -> item.onValueChanged(request.getInt("value").coerceIn(item.valueRange.first, item.valueRange.last))
            is Preference.PreferenceItem.ListPreference<*> -> item.entries.keys.elementAt(request.getInt("value")).let {
                if (it != null && item.internalOnValueChanged(it)) item.internalSet(it)
            }
            is Preference.PreferenceItem.BasicListPreference -> item.onValueChanged(item.entries.keys.elementAt(request.getInt("value")))
            is Preference.PreferenceItem.MultiSelectListPreference -> request.getJSONArray("value").let { array ->
                val values = (0 until array.length()).map { array.getString(it) }.toSet().intersect(item.entries.keys)
                if (item.onValueChanged(values)) item.preference.set(values)
            }
            is Preference.PreferenceItem.EditTextPreference -> request.getString("value").let {
                if (((item.allowEmpty && it.isEmpty()) || item.validator(it)) && item.onValueChanged(it)) item.preference.set(it)
            }
            is Preference.PreferenceItem.TextPreference -> item.onClick?.invoke()
            is Preference.PreferenceItem.TrackerPreference -> if (item.tracker.isLoggedIn) item.logout() else item.login()
            is Preference.PreferenceItem.ConnectionPreference -> if (item.service.isLogged) item.openSettings() else item.login()
            else -> Unit
        }
    }

    private fun addFilters(rows: JSONArray) {
        val prefs = host.appGraph.readerPreferences
        fun toggle(id: String, title: String, value: Boolean) {
            rows.put(JSONObject().put("id", "filter/$id").put("title", title).put("type", "switch").put("value", value))
        }
        fun slider(id: String, title: String, value: Int, min: Int = 0, max: Int = 255) {
            rows.put(
                JSONObject().put("id", "filter/$id").put("title", title).put("type", "slider")
                    .put("value", value).put("min", min).put("max", max).put("step", 1),
            )
        }
        rows.put(JSONObject().put("type", "group").put("title", KMR.strings.vr_color_filters.getString(host)))
        toggle("enabled", KMR.strings.vr_color_filter.getString(host), prefs.colorFilter().get())
        val tint = prefs.colorFilterValue().get()
        slider("red", KMR.strings.vr_color_red.getString(host), tint ushr 16 and 255)
        slider("green", KMR.strings.vr_color_green.getString(host), tint ushr 8 and 255)
        slider("blue", KMR.strings.vr_color_blue.getString(host), tint and 255)
        slider("alpha", KMR.strings.vr_color_opacity.getString(host), tint ushr 24)
        rows.put(
            JSONObject().put("id", "filter/mode").put("type", "list").put("title", KMR.strings.vr_color_blend.getString(host))
                .put("value", prefs.colorFilterMode().get()).put("entries", JSONArray(eu.kanade.tachiyomi.ui.reader.setting.ReaderPreferences.ColorFilterMode.map { it.first.getString(host) })),
        )
        slider("hue", KMR.strings.vr_color_hue.getString(host), host.appGraph.preferenceStore.getInt("vr_reader_hue", 0).get(), -180, 180)
        toggle("grayscale", KMR.strings.vr_color_grayscale.getString(host), prefs.grayscale().get())
        toggle("inverted", KMR.strings.vr_color_inverted.getString(host), prefs.invertedColors().get())
        toggle("brightness_enabled", KMR.strings.vr_color_brightness_enabled.getString(host), prefs.customBrightness().get())
        slider("brightness", KMR.strings.vr_color_brightness.getString(host), prefs.customBrightnessValue().get(), -75, 100)
    }

    private fun changeFilter(request: JSONObject) {
        val prefs = host.appGraph.readerPreferences
        when (val id = request.getString("id").removePrefix("filter/")) {
            "enabled" -> prefs.colorFilter().set(request.getBoolean("value"))
            "grayscale" -> prefs.grayscale().set(request.getBoolean("value"))
            "inverted" -> prefs.invertedColors().set(request.getBoolean("value"))
            "brightness_enabled" -> prefs.customBrightness().set(request.getBoolean("value"))
            "brightness" -> prefs.customBrightnessValue().set(request.getInt("value").coerceIn(-75, 100))
            "mode" -> prefs.colorFilterMode().set(request.getInt("value").coerceIn(0, 5))
            "hue" -> host.appGraph.preferenceStore.getInt("vr_reader_hue", 0).set(request.getInt("value").coerceIn(-180, 180))
            else -> {
                val shift = mapOf("alpha" to 24, "red" to 16, "green" to 8, "blue" to 0)[id] ?: return
                val value = request.getInt("value").coerceIn(0, 255)
                prefs.colorFilterValue().set((prefs.colorFilterValue().get() and (255 shl shift).inv()) or (value shl shift))
            }
        }
        publishFilters()
    }

    fun publishFilters() {
        val prefs = host.appGraph.readerPreferences
        send(
            JSONObject().put("kind", "reader_filters").put("enabled", prefs.colorFilter().get())
                .put("mode", prefs.colorFilterMode().get())
                .put("tint", prefs.colorFilterValue().get()).put("grayscale", prefs.grayscale().get())
                .put("inverted", prefs.invertedColors().get())
                .put("hue", host.appGraph.preferenceStore.getInt("vr_reader_hue", 0).get())
                .put("brightness", if (prefs.customBrightness().get()) prefs.customBrightnessValue().get() else 0)
                .put("contrast", prefs.webgpuContrast().get())
                .put("preload", prefs.preloadSize().get().coerceIn(2, 10))
                .put("side_padding", prefs.webtoonSidePadding().get())
                .put("scroll_ratio", prefs.webtoonScaleType().get().ratio)
                .put("page_numbers", prefs.showPageNumber().get())
                .put("page_transitions", prefs.pageTransitionsPager().get())
                .put("scale_type", prefs.imageScaleType().get())
                .put("theme", prefs.readerTheme().get())
                .put("crop_pager", prefs.cropBorders().get())
                .put("crop_scroll", prefs.cropBordersWebtoon().get() || prefs.cropBordersContinuousVertical().get())
                .put("stretch_to_fit", host.appGraph.preferenceStore.getBoolean(VrSettingKeys.STRETCH_TO_FIT.key, VrSettingKeys.STRETCH_TO_FIT.default).get())
                .put("scenes", host.appGraph.preferenceStore.getBoolean(VrSettingKeys.SCENES.key, VrSettingKeys.SCENES.default).get()),
        )
        host.runOnUiThread {
            if (prefs.keepScreenOn().get()) {
                host.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                host.window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    fun close() {
        inspector?.cancel()
        recomposer?.cancel()
        compositionJob?.cancel()
        view?.disposeComposition()
        view?.let { (it.parent as? ViewGroup)?.removeView(it) }
        view = null
    }

    fun keyboardRoot(): ViewGroup? = dialogRoot
}
// KMK <--
