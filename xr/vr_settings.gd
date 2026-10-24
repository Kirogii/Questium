extends RefCounted

var host: WeakRef
var workspace: RefCounted:
    get: return host.get_ref()
var categories: Array = []
var category := 0
var rows: Array = []
var detail_rows: Array = []
var details: Dictionary = {}
var backend_open := false
var backend_screen := ""
var details_title: Label
var details_list: VBoxContainer
var sidebar_scroll: ScrollContainer
var sidebar: VBoxContainer
var active_tab := 0
var tabs: HBoxContainer
var sync_open := false
var sync_state: Dictionary = {}

func _init(value: RefCounted) -> void:
    host = weakref(value)

func build(parent: Container) -> void:
    tabs = HBoxContainer.new()
    parent.add_child(tabs)
    for index in 2:
        var choice := index
        var tab: Button = workspace.button(tabs, ["Tachiyomi Settings", "Questium Settings"][index], func(): select_tab(choice))
        tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.visible = false
    var scroll := ScrollContainer.new()
    sidebar_scroll = scroll
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    parent.add_child(scroll)
    sidebar = VBoxContainer.new()
    sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sidebar.custom_minimum_size.x = 292
    sidebar.add_theme_constant_override("separation", 10)
    scroll.add_child(sidebar)
    scroll.visible = false
    details = workspace.panel(Vector2(0.72, 0.78), Vector2i(900, 980))
    details.background.add_theme_stylebox_override("panel", workspace.reader.ui.settings_surface())
    var header := HBoxContainer.new()
    details.content.add_child(header)
    details_title = workspace.label(header, "Settings", 30)
    details_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    workspace.reader.ui.icon_button(header, "back", func():
        close_backend()
        details.node.visible = false
    , Vector2(64, 64))
    workspace.button(header, "Back", func(): workspace.reader._request("settings_back"))
    var body := ScrollContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    details.content.add_child(body)
    details_list = VBoxContainer.new()
    details_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    details_list.add_theme_constant_override("separation", 14)
    body.add_child(details_list)
    details.node.visible = false

func open() -> void:
    close_backend()
    workspace.minimize_popups()
    var anchor: Container = workspace.gallery.get_parent().get_parent()
    if tabs.get_parent() != anchor:
        tabs.reparent(anchor)
        anchor.move_child(tabs, workspace.heading.get_parent().get_index() + 1)
    workspace.section = "Settings"
    workspace.library_actions.visible = false
    workspace.hud.background.add_theme_stylebox_override("panel", workspace.reader.ui.settings_surface(40))
    tabs.visible = true
    workspace.hud_back.icon = preload("res://icons/back.svg")
    workspace.hud_back.tooltip_text = "Back to main UI"
    workspace.hud.node.visible = true
    workspace.source_row.visible = false
    workspace.source_category_row.visible = false
    workspace.search_row.visible = false
    workspace.subtitle.visible = false
    for nav in workspace.nav_buttons.values(): nav.visible = false
    sidebar_scroll.visible = true
    sidebar_scroll.scroll_vertical = 0
    workspace.sidebar_spacer.visible = false
    workspace.heading.text = workspace.reader._label("Settings")
    workspace.message.text = ""
    workspace.reader._request("settings", {"category": category})
    select_tab(active_tab)

func select_tab(index: int) -> void:
    sync_open = false
    sidebar_scroll.visible = workspace.section == "Settings"
    sidebar_scroll.scroll_vertical = 0
    tabs.visible = workspace.section == "Settings"
    if index == 1: workspace.reader._request("settings_dismiss")
    active_tab = index
    details.node.visible = false
    for i in 2:
        tabs.get_child(i).modulate.a = 1.0 if i == index else 0.55
    workspace.clear(sidebar)
    workspace.clear(workspace.gallery)
    workspace.reader.ui.icon_button(sidebar, "back", func(): workspace.show_section("Home"), Vector2(64, 64))
    workspace.heading.text = ["Tachiyomi Settings", "Questium Settings"][index]
    if index == 1:
        workspace.navigation(sidebar, "Questium Sync", open_sync)
        workspace.navigation(sidebar, "Themes", open_themes)
        workspace.reader.ui.apply_book_settings()
        for page in 3:
            var caption: String = ["Book Options", "Layout", "System Settings"][page]
            var heading: Label = workspace.label(workspace.gallery, caption, 27)
            workspace.navigation(sidebar, caption, func():
                var scroll: ScrollContainer = workspace.gallery.get_parent()
                scroll.ensure_control_visible(heading)
            )
            workspace.reader.ui.render_book_options(workspace.gallery, page, true)
        workspace.button(workspace.gallery, "Recenter", workspace.reader.request_recenter)
        workspace.reader.ui.theme_settings(workspace.gallery)
        workspace.reader.ui.theme_settings(sidebar)
        workspace.reader.ui.theme_settings(tabs)
        return
    for entry in categories:
        var id := int(entry.id)
        var nav: Button = workspace.navigation(sidebar, str(entry.title), func():
            category = id
            workspace.reader._request("settings", {"category": id})
        )
        if id == category:
            nav.add_theme_stylebox_override("normal", workspace.reader.ui.style(Color(0.72, 0.71, 0.68, 0.28), 12))
    render(rows, workspace.gallery, false)
    workspace.reader.ui.theme_settings(sidebar)
    workspace.reader.ui.theme_settings(tabs)

func leave() -> void:
    close_backend()
    if workspace.section == "Settings": workspace.reader._request("settings_dismiss")
    tabs.visible = false
    workspace.hud.background.add_theme_stylebox_override("panel", workspace.reader.ui.style(Color(0.40, 0.39, 0.37, 0.08), 40))
    workspace.hud_back.icon = preload("res://icons/close.svg")
    workspace.hud_back.tooltip_text = "Close"
    sidebar_scroll.visible = false
    workspace.sidebar_spacer.visible = true
    for nav in workspace.nav_buttons.values(): nav.visible = true
    details.node.visible = false

func consume(data: Dictionary) -> bool:
    match str(data.get("kind", "")):
        "questium_sync":
            sync_state = data
            if workspace.section == "Settings" and sync_open: render_sync()
        "settings":
            categories = data.get("categories", [])
            category = int(data.get("category", 0))
            rows = data.get("items", [])
            if workspace.section != "Settings": return true
            if active_tab == 1: return true
            sidebar_scroll.visible = true
            tabs.visible = true
            workspace.clear(sidebar)
            workspace.button(sidebar, "Back", func(): workspace.show_section("Home"))
            for entry in categories:
                var id := int(entry.id)
                var nav: Button = workspace.navigation(sidebar, str(entry.title), func():
                    category = id
                    workspace.reader._request("settings", {"category": id})
                )
                if id == category:
                    nav.add_theme_stylebox_override("normal", workspace.reader.ui.style(Color(0.72, 0.71, 0.68, 0.28), 12))
            workspace.heading.text = str(data.get("title", "Settings"))
            var scroll: ScrollContainer = workspace.gallery.get_parent()
            var old := scroll.scroll_vertical
            workspace.clear(workspace.gallery)
            render(rows, workspace.gallery, false)
            workspace.reader.ui.theme_settings(sidebar)
            scroll.set_deferred("scroll_vertical", old)
        "settings_detail":
            var native_backend := str(data.get("scope", "settings")) == "backend"
            if native_backend and not backend_open: return true
            if not native_backend and (active_tab != 0 or workspace.section != "Settings"): return true
            details_title.text = str(data.get("title", "Settings"))
            detail_rows = data.get("items", [])
            var typing: bool = is_instance_valid(workspace.keyboard_target) and details_list.is_ancestor_of(workspace.keyboard_target) and workspace.keyboard_target.has_focus()
            if typing: return true
            workspace.clear(details_list)
            if native_backend: render_native(detail_rows, details_list)
            else: render(detail_rows, details_list, true)
            if native_backend or ((data.get("dialog", false) or data.get("nested", false)) and workspace.section == "Settings"): workspace.raise_popup(details.node, not details.node.visible)
            elif detail_rows.is_empty(): details.node.visible = false
        "error":
            if workspace.section != "Settings": return false
            workspace.message.text = str(data.get("message", ""))
        _:
            return false
    return true

func send_value(row: Dictionary, value: Variant, semantic: bool) -> void:
    if str(row.id).begins_with("questium_sync:"):
        workspace.reader._request("questium_sync", {"operation": str(row.id).trim_prefix("questium_sync:"), "value": value})
        return
    workspace.reader._request("settings_semantic" if semantic else "setting", {"id": str(row.id), "type": str(row.type), "value": value})

func open_backend(screen: String, arguments: Dictionary = {}) -> void:
    backend_open = true
    backend_screen = screen
    details_title.text = "Loading…"
    workspace.clear(details_list)
    workspace.label(details_list, "Loading Android controls…", 20)
    workspace.raise_popup(details.node)
    var request := arguments.duplicate()
    request.screen = screen
    workspace.reader._request("backend_screen", request)

func close_backend() -> void:
    if backend_open: workspace.reader._request("backend_close")
    backend_open = false
    details.node.visible = false

func open_themes(refresh: bool = true) -> void:
    sync_open = false
    workspace.clear(workspace.gallery)
    workspace.heading.text = "Themes"
    workspace.themes.render(workspace.gallery)
    if refresh: workspace.reader._request("theme_palettes")

func open_sync() -> void:
    sync_open = true
    render_sync()
    workspace.reader._request("questium_sync")

func render_sync() -> void:
    workspace.clear(workspace.gallery)
    workspace.heading.text = "Questium Sync"
    workspace.label(workspace.gallery, str(sync_state.get("status", "Loading devices…")), 20)
    var items: Array = [
        {"id": "questium_sync:enabled", "type": "switch", "title": "Enable Questium Sync", "subtitle": "Available to paired devices on your local network.", "value": bool(sync_state.get("enabled", false))},
        {"id": "questium_sync:pair", "type": "text", "title": "Pairing link", "subtitle": "Paste the link from your main Questium Sync Android device and press Enter.", "value": ""},
    ]
    var entries: Array = []
    var keys: Array = []
    var selected: Array = []
    for device in sync_state.get("devices", []):
        entries.append(str(device.name) + (" • Main" if device.get("main", false) else ""))
        keys.append(str(device.id))
        if device.get("selected", false): selected.append(str(device.id))
    items.append({"id": "questium_sync:selected", "type": "multi", "title": "Devices", "entries": entries, "keys": keys, "value": selected})
    items.append({"id": "questium_sync:sync", "type": "action", "title": "Sync selected devices", "subtitle": "Sync runs on the main Android device. Furthest chapter progress wins; previous progress is saved in its Revert tab.", "enabled": bool(sync_state.get("enabled", false))})
    render(items, workspace.gallery, false)
    workspace.button(workspace.gallery, "Refresh devices", func(): workspace.reader._request("questium_sync"))

func render(items: Array, parent: Container, semantic: bool) -> void:
    for row in items:
        var type := str(row.get("type", "info"))
        if type == "group":
            if not str(row.get("title", "")).is_empty(): workspace.label(parent, str(row.title), 27)
            continue
        var card := PanelContainer.new()
        var surface: StyleBoxFlat = workspace.reader.ui.style(Color(0.46, 0.45, 0.43, 0.12), 22)
        for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: surface.set_content_margin(edge, 16)
        card.add_theme_stylebox_override("panel", surface)
        parent.add_child(card)
        var column := VBoxContainer.new()
        column.add_theme_constant_override("separation", 10)
        card.add_child(column)
        var header := HBoxContainer.new()
        header.add_theme_constant_override("separation", 24)
        column.add_child(header)
        var text := VBoxContainer.new()
        text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        header.add_child(text)
        var title := str(row.get("title", ""))
        if not title.is_empty() and not (semantic and type == "action"):
            var caption: Label = workspace.label(text, title, 22)
            caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var help := str(row.get("subtitle", ""))
        if not help.is_empty() and help != "%s":
            var caption: Label = workspace.label(text, help, 17)
            caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            caption.modulate.a = 0.7
        if row.has("state_description") and not str(row.state_description).is_empty():
            workspace.label(column, str(row.state_description), 17).modulate.a = 0.75
        var enabled := bool(row.get("enabled", true))
        match type:
            "switch":
                var toggle := CheckButton.new()
                workspace.reader.ui.theme_switch(toggle)
                toggle.custom_minimum_size.y = 54
                toggle.button_pressed = bool(row.value)
                toggle.disabled = not enabled
                header.add_child(toggle)
                toggle.toggled.connect(func(value: bool): send_value(row, value, semantic))
            "slider":
                var slider := HSlider.new()
                workspace.reader.ui.theme_slider(slider)
                slider.custom_minimum_size.y = 56
                slider.min_value = float(row.min)
                slider.max_value = maxf(float(row.max), slider.min_value + 0.001)
                slider.step = float(row.get("step", 1))
                slider.value = float(row.value)
                slider.editable = enabled
                column.add_child(slider)
                var value_label: Label = workspace.label(header, str(row.value), 18)
                slider.value_changed.connect(func(value: float): value_label.text = str(snappedf(value, 0.01)))
                slider.drag_ended.connect(func(changed: bool):
                    if changed: send_value(row, slider.value, semantic)
                )
            "list":
                var option := OptionButton.new()
                option.custom_minimum_size.y = 56
                header.add_child(option)
                option.custom_minimum_size.x = 160
                option.clip_text = true
                for entry in row.entries: option.add_item(str(entry))
                option.select(int(row.value))
                option.disabled = not enabled
                option.item_selected.connect(func(index: int): send_value(row, index, semantic))
            "multi":
                var selected: Array = row.value.duplicate()
                for index in row.entries.size():
                    var key := str(row.keys[index])
                    var toggle := CheckBox.new()
                    toggle.text = str(row.entries[index])
                    toggle.custom_minimum_size.y = 52
                    toggle.button_pressed = key in selected
                    toggle.disabled = not enabled
                    column.add_child(toggle)
                    toggle.toggled.connect(func(value: bool):
                        if value: selected.append(key)
                        else: selected.erase(key)
                        send_value(row, selected, semantic)
                    )
            "text":
                var edit: LineEdit = workspace.edit(column, title)
                edit.text = str(row.value)
                edit.editable = enabled
                if semantic: edit.text_changed.connect(func(value: String): send_value(row, value, true))
                edit.text_submitted.connect(func(value: String):
                    send_value(row, value, semantic)
                    if semantic and "ime" in row.get("actions", []):
                        workspace.reader._request("settings_semantic", {"id": str(row.id), "type": "ime"})
                )
            "custom":
                workspace.button(column, "Edit Settings", func():
                    workspace.reader._request("settings_detail")
                    workspace.raise_popup(details.node)
                )
            "action":
                var action_title := title if not title.is_empty() else "Open"
                if row.has("selected"): action_title = ("✓ " if bool(row.selected) else "○ ") + action_title
                var action: Button = workspace.button(column, action_title, func(): send_value(row, "", semantic))
                action.custom_minimum_size.y = 64
                action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
                action.disabled = not enabled
            "scroll":
                var actions := HBoxContainer.new()
                column.add_child(actions)
                workspace.button(actions, "Previous", func(): send_value(row, -600, semantic))
                workspace.button(actions, "Next", func(): send_value(row, 600, semantic))
        if semantic and bool(row.get("long_click", false)):
            workspace.button(column, "Select / More", func():
                workspace.reader._request("settings_semantic", {"id": str(row.id), "type": "long_click"})
            ).disabled = not enabled
        if semantic:
            for custom in row.get("custom_actions", []):
                workspace.button(column, str(custom.title), func():
                    workspace.reader._request("settings_semantic", {"id": str(row.id), "type": "custom_action", "index": int(custom.index)})
                ).disabled = not enabled
    workspace.reader.ui.theme_settings(parent)

# Android coordinates describe a phone viewport, not the size of VR targets.
# Keep the semantic reading order and original actions in responsive Questium cards.
func render_native(items: Array, parent: Container) -> void:
    var controls: Array = []
    for row in items:
        var type := str(row.get("type", "info"))
        if type == "info" and str(row.get("title", "")).is_empty(): continue
        controls.append(row)
    render(controls, parent, true)
