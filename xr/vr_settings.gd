extends RefCounted

var host: WeakRef
var workspace: RefCounted:
    get: return host.get_ref()
var categories: Array = []
var category := 0
var rows: Array = []
var detail_rows: Array = []
var details: Dictionary = {}
var details_list: VBoxContainer
var sidebar: VBoxContainer

func _init(value: RefCounted) -> void:
    host = weakref(value)

func build(parent: Container) -> void:
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    parent.add_child(scroll)
    sidebar = VBoxContainer.new()
    sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(sidebar)
    scroll.visible = false
    details = workspace.panel(Vector2(0.40, 0.48), Vector2i(800, 960))
    var header := HBoxContainer.new()
    details.content.add_child(header)
    workspace.label(header, "Settings", 30).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    workspace.reader.ui.icon_button(header, "close", func():
        details.node.visible = false
        workspace.reader._request("settings_dismiss")
    , Vector2(64, 64))
    workspace.button(header, "Back", func(): workspace.reader._request("settings_back"))
    var body := ScrollContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    details.content.add_child(body)
    details_list = VBoxContainer.new()
    details_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(details_list)
    details.node.visible = false

func open() -> void:
    workspace.minimize_popups()
    workspace.section = "Settings"
    workspace.hud.node.visible = true
    workspace.source_row.visible = false
    workspace.search_row.visible = false
    workspace.subtitle.visible = false
    for nav in workspace.nav_buttons.values(): nav.visible = false
    sidebar.get_parent().visible = true
    workspace.sidebar_spacer.visible = false
    workspace.heading.text = workspace.reader._label("Settings")
    workspace.message.text = ""
    workspace.reader._request("settings", {"category": category})

func leave() -> void:
    sidebar.get_parent().visible = false
    workspace.sidebar_spacer.visible = true
    for nav in workspace.nav_buttons.values(): nav.visible = true
    details.node.visible = false

func consume(data: Dictionary) -> bool:
    match str(data.get("kind", "")):
        "settings":
            categories = data.get("categories", [])
            category = int(data.get("category", 0))
            rows = data.get("items", [])
            if workspace.section != "Settings": return true
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
            scroll.set_deferred("scroll_vertical", old)
        "settings_detail":
            detail_rows = data.get("items", [])
            workspace.clear(details_list)
            render(detail_rows, details_list, true)
            if (data.get("dialog", false) or data.get("nested", false)) and workspace.section == "Settings": workspace.raise_popup(details.node)
            elif detail_rows.is_empty(): details.node.visible = false
        "error":
            if workspace.section != "Settings": return false
            workspace.message.text = str(data.get("message", ""))
        _:
            return false
    return true

func send_value(row: Dictionary, value: Variant, semantic: bool) -> void:
    workspace.reader._request("settings_semantic" if semantic else "setting", {"id": str(row.id), "type": str(row.type), "value": value})

func render(items: Array, parent: Container, semantic: bool) -> void:
    for row in items:
        var type := str(row.get("type", "info"))
        if type == "group":
            workspace.label(parent, str(row.title), 27)
            continue
        var card := PanelContainer.new()
        card.add_theme_stylebox_override("panel", workspace.reader.ui.style(Color(0.23, 0.22, 0.20, 0.27), 18))
        parent.add_child(card)
        var column := VBoxContainer.new()
        column.add_theme_constant_override("separation", 10)
        card.add_child(column)
        var title := str(row.get("title", ""))
        if not title.is_empty():
            var caption: Label = workspace.label(column, title, 22)
            caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var help := str(row.get("subtitle", ""))
        if not help.is_empty() and help != "%s":
            var caption: Label = workspace.label(column, help, 17)
            caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            caption.modulate.a = 0.7
        var enabled := bool(row.get("enabled", true))
        match type:
            "switch":
                var toggle := CheckButton.new()
                workspace.reader.ui.theme_switch(toggle)
                toggle.text = workspace.reader._label("Enabled")
                toggle.custom_minimum_size.y = 54
                toggle.button_pressed = bool(row.value)
                toggle.disabled = not enabled
                column.add_child(toggle)
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
                var value_label: Label = workspace.label(column, str(row.value), 18)
                slider.value_changed.connect(func(value: float): value_label.text = str(snappedf(value, 0.01)))
                slider.drag_ended.connect(func(changed: bool):
                    if changed: send_value(row, slider.value, semantic)
                )
            "list":
                var option := OptionButton.new()
                option.custom_minimum_size.y = 56
                column.add_child(option)
                for entry in row.entries: option.add_item(str(entry))
                option.select(int(row.value))
                option.disabled = not enabled
                option.item_selected.connect(func(index: int): send_value(row, index, semantic))
            "multi":
                var selected: Array = row.value.duplicate()
                for index in row.entries.size():
                    var key := str(row.keys[index])
                    var toggle := CheckButton.new()
                    workspace.reader.ui.theme_switch(toggle)
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
                edit.text_submitted.connect(func(value: String): send_value(row, value, semantic))
            "custom":
                workspace.button(column, "Edit Settings", func():
                    workspace.reader._request("settings_detail")
                    workspace.raise_popup(details.node)
                )
            "action":
                workspace.button(column, title if not title.is_empty() else "Open", func(): send_value(row, "", semantic)).disabled = not enabled
            "scroll":
                var actions := HBoxContainer.new()
                column.add_child(actions)
                workspace.button(actions, "Previous", func(): send_value(row, -600, semantic))
                workspace.button(actions, "Next", func(): send_value(row, 600, semantic))
