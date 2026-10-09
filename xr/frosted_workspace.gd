extends RefCounted

var reader: Node3D
var windows: Array[Dictionary] = []
var dock_poses: Array[Transform3D] = []
var dock_preview: MeshInstance3D
var hud: Dictionary
var badge: Dictionary
var badge_title: Label
var preview: Dictionary
var info: Dictionary
var keyboard: Dictionary
var sources: OptionButton
var search: LineEdit
var chapter_search: LineEdit
var keyboard_target: LineEdit
var grid: GridContainer
var chapter_list: VBoxContainer
var heading: Label
var subtitle: Label
var message: Label
var detail_title: Label
var description: Label
var source_row: HBoxContainer
var search_row: HBoxContainer
var gallery: VBoxContainer
var nav_buttons: Dictionary = {}
var starred: Array = []
var deleted_items: Array = []
var preferences := ConfigFile.new()
var save_button: Button
var read_button: Button
var cover_targets: Dictionary = {}
var cover_cache: Dictionary = {}
var library_items: Array = []
var history_items: Array = []
var source_items: Array = []
var chapters: Array = []
var selected_source := ""
var selected_manga := ""
var active_manga := ""
var resume_chapter := ""
var section := "Home"
var filter := "All Books"
var page := 1
var favorite := false
var previewing := false
var reading := false
var opening: Tween
var picker: Dictionary
var picker_list: VBoxContainer
var picker_search: LineEdit
var picker_status: Label
var installed_sources: Array = []
var extensions: Array = []
var browsing_extensions := false
var keyboard_requested_at := -1000
var keyboard_session := 0
var keyboard_field := ""
var active_book: SpatialBook
var enabled_languages: Array = ["en"]
var language_panel: Dictionary
var language_list: VBoxContainer
var repository_panel: Dictionary
var repository_url: LineEdit
var repository_status: Label
var repository_list: VBoxContainer
var repository_add: Button
var repositories: Array = []
var repository_pending := false
var hud_scale := 0.5
var gui_distance := 0.62
var popup_order := 10
var settings: RefCounted
var sidebar_spacer: Control

func raise_popup(node: Node3D, center: bool = true) -> void:
    if center and node != preview.node:
        place_popup(node)
    popup_order = mini(popup_order + 2, 120)
    node.set_meta("popup_priority", popup_order)
    for target in reader.panels:
        if target.node != node: continue
        target["popup"] = true
        for child in node.get_children():
            if not child is MeshInstance3D: continue
            var material: Material = child.material_override
            material.render_priority = popup_order + (1 if material is StandardMaterial3D else 0)
            if material is StandardMaterial3D:
                material.no_depth_test = true
            elif material is ShaderMaterial:
                var shader := Shader.new()
                shader.code = preload("res://glass.gdshader").code.replace("depth_draw_never;", "depth_draw_never, depth_test_disabled;")
                material.shader = shader
    node.visible = true

func place_popup(node: Node3D) -> void:
    var facing := facing_basis()
    var head := head_position()
    var target: Vector3 = hud.node.global_position if hud.node.visible else head - facing.z * gui_distance
    var distance := clampf(head.distance_to(target) - 0.16, 0.38, 0.56)
    node.global_transform = Transform3D(facing, head + (target - head).normalized() * distance)

func minimize_popups() -> void:
    reader.ui.close_options()
    # Keep each menu's contents and scroll state for the next open.
    var nodes := [info.node, picker.node, language_panel.node, repository_panel.node, reader.ui.options]
    if settings: nodes.append(settings.details.node)
    for node in nodes:
        node.visible = false

func toggle_info() -> void:
    if info.node.visible: info.node.visible = false
    else: raise_popup(info.node)

func popup_ray(start: Vector3, direction: Vector3) -> bool:
    for target in reader.panels:
        if not target.get("popup", false) or not target.node.is_visible_in_tree(): continue
        var local: Vector3 = target.node.to_local(start)
        var ray: Vector3 = target.node.global_basis.inverse() * direction
        if absf(ray.z) < 0.0001: continue
        var distance := -local.z / ray.z
        var point := local + ray * distance
        if distance >= 0 and distance <= 5 and absf(point.x) <= target.size.x * 0.5 and absf(point.y) <= target.size.y * 0.5: return true
    return false

func roots() -> Array:
    var nodes: Array = [hud.node, badge.node, preview.node, info.node, picker.node, language_panel.node, repository_panel.node, reader.ui.options]
    if settings: nodes.append(settings.details.node)
    for model in reader.books:
        if model.visible: nodes.append(model)
    return nodes

func move_depth(amount: float) -> void:
    var next := clampf(gui_distance + amount, 0.38, 1.4)
    var shift: Vector3 = -reader.camera.global_basis.z.normalized() * (next - gui_distance)
    gui_distance = next
    for node in roots(): node.global_position += shift

func set_hud_scale(value: float) -> void:
    hud_scale = clampf(value, 0.3, 1.0)
    hud.node.scale = Vector3.ONE * hud_scale
    preferences.set_value("workspace", "hud_scale", hud_scale)
    preferences.save("user://library.cfg")

func sync_badge() -> void:
    if not hud.node.visible or previewing: return
    var factor: float = hud.node.global_basis.x.length()
    var facing: Basis = hud.node.global_basis.orthonormalized()
    badge.node.global_transform = Transform3D(facing, hud.node.global_position + facing.y * (0.54 * factor + 0.035))

func _init(host: Node3D) -> void:
    reader = host

func panel(size: Vector2, pixels: Vector2i) -> Dictionary:
    var result: Dictionary = reader._panel(reader, size, pixels, Vector3.ZERO)
    result.background.add_theme_stylebox_override("panel", reader.ui.style(Color(0.40, 0.39, 0.37, 0.08), 40))
    result.content.position = Vector2(26, 24)
    result.content.size = Vector2(pixels) - Vector2(52, 48)
    return result

func build() -> void:
    preferences.load("user://library.cfg")
    enabled_languages = preferences.get_value("sources", "languages", ["en"])
    hud_scale = float(preferences.get_value("workspace", "hud_scale", 0.5))
    starred = preferences.get_value("library", "starred", [])
    deleted_items = preferences.get_value("library", "deleted", [])
    hud = panel(Vector2(1.86, 1.08), Vector2i(1520, 900))
    reader.library_panel = hud.node
    var layout := HBoxContainer.new()
    layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layout.add_theme_constant_override("separation", 28)
    hud.content.add_child(layout)
    var inset := PanelContainer.new()
    inset.custom_minimum_size.x = 320
    inset.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    var sidebar_background := Panel.new()
    sidebar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    sidebar_background.size = Vector2(360, 900)
    var sidebar_style: StyleBoxFlat = reader.ui.style(Color(0.12, 0.115, 0.105, 0.34), 40)
    sidebar_style.corner_radius_top_right = 0
    sidebar_style.corner_radius_bottom_right = 0
    sidebar_background.add_theme_stylebox_override("panel", sidebar_style)
    hud.viewport.add_child(sidebar_background)
    hud.viewport.move_child(sidebar_background, 0)
    layout.add_child(inset)
    var sidebar := VBoxContainer.new()
    sidebar.add_theme_constant_override("separation", 12)
    inset.add_child(sidebar)
    var hud_header := HBoxContainer.new()
    sidebar.add_child(hud_header)
    label(hud_header, "Questium", 32).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reader.ui.icon_button(hud_header, "close", func(): hud.node.visible = false, Vector2(48, 48))
    var gap := Control.new()
    gap.custom_minimum_size.y = 18
    sidebar.add_child(gap)
    settings = preload("res://vr_settings.gd").new(self)
    settings.build(sidebar)
    for name in ["All Books", "Recents", "History", "Favorites", "Recently Deleted"]:
        var choice: String = name
        var nav := navigation(sidebar, name, func():
            filter = choice
            show_section("Home")
        )
        nav_buttons[name] = nav
    reader.ui.line(sidebar)
    for name in ["Source Search", "Reader"]:
        var destination: String = name
        nav_buttons[name] = navigation(sidebar, name, func(): show_section(destination))
    var spacer := Control.new()
    sidebar_spacer = spacer
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    sidebar.add_child(spacer)
    button(sidebar, "Recenter", reader.recenter)
    var settings_button := button(sidebar, "Settings", func(): show_settings())
    settings_button.text = ""
    settings_button.tooltip_text = reader._label("Settings")
    var settings_center := CenterContainer.new()
    settings_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    settings_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    settings_button.add_child(settings_center)
    var settings_row := HBoxContainer.new()
    settings_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    settings_row.add_theme_constant_override("separation", 12)
    settings_center.add_child(settings_row)
    var settings_icon := TextureRect.new()
    settings_icon.texture = preload("res://icons/settings.svg")
    settings_icon.custom_minimum_size = Vector2(28, 28)
    settings_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    settings_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    settings_row.add_child(settings_icon)
    label(settings_row, "Settings", 24).mouse_filter = Control.MOUSE_FILTER_IGNORE
    settings_button.custom_minimum_size = Vector2(170, 50)
    settings_button.size_flags_horizontal = Control.SIZE_FILL
    settings_button.add_theme_stylebox_override("normal", reader.ui.style(Color(0.64, 0.63, 0.61, 0.22), 25))
    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 24)
    layout.add_child(body)
    heading = label(body, "All Books", 34)
    subtitle = label(body, "Your manga library", 20)
    source_row = HBoxContainer.new()
    body.add_child(source_row)
    sources = OptionButton.new()
    sources.visible = false
    sources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sources.custom_minimum_size.y = 54
    source_row.add_child(sources)
    button(source_row, "Choose Source", func(): show_sources(false))
    button(source_row, "Add Repository", show_repositories)
    var cog := button(source_row, "", show_languages)
    cog.icon = preload("res://icons/settings.svg")
    cog.tooltip_text = reader._label("Source languages")
    sources.item_selected.connect(func(index: int):
        selected_source = str(sources.get_item_metadata(index))
        run_search(1)
    )
    button(source_row, "Previous", func(): run_search(maxi(1, page - 1)))
    button(source_row, "Next", func(): run_search(page + 1))
    source_row.visible = false
    search_row = HBoxContainer.new()
    body.add_child(search_row)
    search_row.visible = false
    subtitle.visible = false
    search = edit(search_row, "Search your books")
    button(search_row, "Search", func():
        if section == "Source Search": run_search(1)
        else: render_grid()
    )
    search.text_changed.connect(func(_text: String):
        if section == "Home": render_grid()
    )
    search.text_submitted.connect(func(_text: String):
        if section == "Source Search": run_search(1)
    )
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    body.add_child(scroll)
    gallery = VBoxContainer.new()
    gallery.add_theme_constant_override("separation", 28)
    gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(gallery)
    grid = make_grid()
    gallery.add_child(grid)
    message = label(body, "Loading library…", 18)
    badge = panel(Vector2(0.23, 0.032), Vector2i(600, 84))
    badge_title = label(badge.content, "Questium", 36)
    badge_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    badge_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    preview = panel(Vector2(0.55, 0.12), Vector2i(660, 160))
    detail_title = label(preview.content, "", 22)
    detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    detail_title.visible = false
    detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    var actions := HBoxContainer.new()
    actions.alignment = BoxContainer.ALIGNMENT_CENTER
    preview.content.add_child(actions)
    reader.ui.labeled_icon(actions, "previous", "Back", func(): show_section(section))
    save_button = reader.ui.labeled_icon(actions, "library", "Save to Library", save_to_library)
    read_button = reader.ui.labeled_icon(actions, "book", "Read", read_selected)
    read_button.disabled = true
    reader.ui.labeled_icon(actions, "info", "Info", toggle_info)
    reader.ui.labeled_icon(actions, "close", "Close", reader.close_book)
    info = panel(Vector2(0.32, 0.48), Vector2i(504, 980))
    var info_header := HBoxContainer.new()
    info.content.add_child(info_header)
    label(info_header, "Book Info", 28).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reader.ui.icon_button(info_header, "close", func(): info.node.visible = false, Vector2(48, 48))
    var search_chapters := HBoxContainer.new()
    info.content.add_child(search_chapters)
    chapter_search = edit(search_chapters, "Find a chapter")
    chapter_search.text_changed.connect(func(_text: String): render_chapters())
    var scrolling := ScrollContainer.new()
    scrolling.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    info.content.add_child(scrolling)
    var chapter_body := VBoxContainer.new()
    chapter_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    chapter_body.add_theme_constant_override("separation", 20)
    scrolling.add_child(chapter_body)
    description = label(chapter_body, "Loading book details…", 20)
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label(chapter_body, "Chapters", 24)
    chapter_list = VBoxContainer.new()
    chapter_body.add_child(chapter_list)
    button(info.content, "Close", func(): info.node.visible = false)
    button(info.content, "Remove from Library", remove_from_library)
    keyboard = {"node": Node3D.new()}
    reader.add_child(keyboard.node)
    windows = [{"node": hud.node, "size": hud.size, "dock": 0}]
    dock_preview = MeshInstance3D.new()
    reader.add_child(dock_preview)
    dock_preview.visible = false
    preview.node.visible = false
    info.node.visible = false
    keyboard.node.visible = false
    picker = panel(Vector2(0.55, 0.70), Vector2i(720, 960))
    var picker_header := HBoxContainer.new()
    picker.content.add_child(picker_header)
    label(picker_header, "Choose Source", 28).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reader.ui.icon_button(picker_header, "close", func(): picker.node.visible = false, Vector2(48, 48))
    picker_search = edit(picker.content, "Search sources")
    picker_search.text_changed.connect(func(_text: String): render_sources())
    picker_status = label(picker.content, "", 20)
    picker_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var picker_scroll := ScrollContainer.new()
    picker_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    picker.content.add_child(picker_scroll)
    picker_list = VBoxContainer.new()
    picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    picker_scroll.add_child(picker_list)
    button(picker.content, "🛍 Install more extension sources", func(): show_sources(true))
    button(picker.content, "Add Repository", show_repositories)
    button(picker.content, "Close", func(): picker.node.visible = false)
    picker.node.visible = false
    language_panel = panel(Vector2(0.38, 0.48), Vector2i(480, 600))
    var language_header := HBoxContainer.new()
    language_panel.content.add_child(language_header)
    label(language_header, "Source languages", 28).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reader.ui.icon_button(language_header, "close", func(): language_panel.node.visible = false, Vector2(48, 48))
    var language_scroll := ScrollContainer.new()
    language_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    language_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    language_panel.content.add_child(language_scroll)
    language_list = VBoxContainer.new()
    language_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    language_scroll.add_child(language_list)
    button(language_panel.content, "Close", func(): language_panel.node.visible = false)
    language_panel.node.visible = false
    repository_panel = panel(Vector2(0.48, 0.55), Vector2i(680, 780))
    var repository_header := HBoxContainer.new()
    repository_panel.content.add_child(repository_header)
    label(repository_header, "Add Repository", 28).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reader.ui.icon_button(repository_header, "close", func(): repository_panel.node.visible = false, Vector2(48, 48))
    var repository_help := label(repository_panel.content, "Paste the extension repository URL.", 20)
    repository_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    repository_url = edit(repository_panel.content, "Repository URL")
    repository_url.text_submitted.connect(func(_value: String): add_repository())
    repository_add = button(repository_panel.content, "Add Repository", add_repository)
    repository_status = label(repository_panel.content, "", 20)
    repository_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label(repository_panel.content, "Installed repositories", 24)
    var repository_scroll := ScrollContainer.new()
    repository_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    repository_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    repository_panel.content.add_child(repository_scroll)
    repository_list = VBoxContainer.new()
    repository_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    repository_scroll.add_child(repository_list)
    button(repository_panel.content, "Close", func(): repository_panel.node.visible = false)
    repository_panel.node.visible = false
    reader.ui.options.reparent(reader, true)
    update_navigation()
    recenter()
    reader._request("sources")
    reader._request("library")

func label(parent: Container, text: String, font_size: int = 22) -> Label:
    var node: Label = reader.ui.label(parent, text, font_size)
    if font_size >= 26:
        var weight := FontVariation.new()
        weight.base_font = ThemeDB.fallback_font
        weight.variation_embolden = 0.6
        node.add_theme_font_override("font", weight)
    return node

func navigation(parent: Container, caption: String, callback: Callable) -> Button:
    var node := button(parent, "", callback)
    node.custom_minimum_size = Vector2(292, 62)
    var row := HBoxContainer.new()
    row.position = Vector2(14, 12)
    row.size = Vector2(264, 38)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.add_child(row)
    var icon := TextureRect.new()
    icon.texture = load("res://icons/" + ({"All Books": "book", "Recents": "recent", "History": "recent", "Favorites": "heart", "Recently Deleted": "trash", "Source Search": "search", "Reader": "book"}.get(caption, "book")) + ".svg")
    icon.custom_minimum_size = Vector2(30, 30)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.modulate = Color(0.77, 0.97, 0.15)
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(icon)
    var text := label(row, caption, 22)
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var count := label(row, "", 20)
    count.name = "Count"
    count.modulate.a = 0.70
    count.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node

func update_navigation() -> void:
    for name in nav_buttons:
        var selected: bool = (section == "Home" and name == filter) or section == name
        nav_buttons[name].add_theme_stylebox_override("normal", reader.ui.style(Color(0.86, 0.84, 0.79, 0.30 if selected else 0.0), 14))
        var count: Label = nav_buttons[name].find_child("Count", true, false)
        if name == "All Books": count.text = str(library_items.size())
        elif name == "History": count.text = str(history_items.size())
        elif name == "Recents": count.text = str(library_items.filter(func(item): return int(item.get("last_read", 0)) > 0).size())
        elif name == "Favorites": count.text = str(library_items.filter(func(item): return str(item.id) in starred).size())
        elif name == "Recently Deleted": count.text = str(deleted_items.size())

func make_grid() -> GridContainer:
    var result := GridContainer.new()
    result.columns = 5
    result.add_theme_constant_override("h_separation", 20)
    result.add_theme_constant_override("v_separation", 28)
    result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return result

func toggle_star(id: String) -> void:
    if id in starred: starred.erase(id)
    else: starred.append(id)
    preferences.set_value("library", "starred", starred)
    preferences.save("user://library.cfg")
    render_grid()

func button(parent: Container, caption: String, callback: Callable) -> Button:
    var node: Button = reader._button(parent, caption, callback)
    node.add_theme_stylebox_override("normal", reader.ui.style(Color(0.72, 0.71, 0.68, 0.13), 24))
    node.add_theme_stylebox_override("hover", reader.ui.style(Color(0.85, 0.84, 0.80, 0.30), 24))
    node.add_theme_stylebox_override("pressed", reader.ui.style(Color(0.76, 0.94, 0.23, 0.24), 24))
    return node

func edit(parent: Container, placeholder: String) -> LineEdit:
    var node := LineEdit.new()
    node.placeholder_text = reader._label(placeholder)
    node.custom_minimum_size.y = 56
    node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    node.add_theme_font_size_override("font_size", 22)
    node.add_theme_stylebox_override("normal", reader.ui.style(Color(0.10, 0.10, 0.10, 0.32), 12))
    parent.add_child(node)
    node.virtual_keyboard_enabled = false
    node.focus_entered.connect(func(): show_keyboard(node))
    node.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
            show_keyboard(node)
    )
    return node

func glass(node: Node3D, size: Vector2) -> void:
    var mesh := MeshInstance3D.new()
    var quad := QuadMesh.new()
    quad.size = size
    mesh.mesh = quad
    mesh.position.z = -0.008
    var material := ShaderMaterial.new()
    material.shader = preload("res://glass.gdshader")
    material.set_shader_parameter("panel_size", size)
    mesh.material_override = material
    node.add_child(mesh)

func show_keyboard(target: LineEdit) -> void:
    if keyboard_target == target and target.has_meta("native_keyboard_open"): return
    if keyboard_target == target and Time.get_ticks_msec() - keyboard_requested_at < 350: return
    keyboard_requested_at = Time.get_ticks_msec()
    keyboard_target = target
    keyboard_session += 1
    keyboard_field = str(target.get_instance_id()) + ":" + str(keyboard_session)
    keyboard.node.visible = false
    if reader.bridge and reader.bridge.has_method("showKeyboard"):
        target.set_meta("native_keyboard_open", true)
        reader.bridge.call("showKeyboard", target.text, keyboard_field)
    elif DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
        DisplayServer.virtual_keyboard_show(target.text)

func show_sources(available: bool) -> void:
    browsing_extensions = available
    picker_search.text = ""
    picker.node.visible = true
    picker.node.global_transform = Transform3D(facing_basis(), head_position() + facing_basis() * Vector3(0.3, 0, -0.85))
    raise_popup(picker.node)
    if available:
        reader._request("extensions")
    else:
        reader._request("sources")
    render_sources()

func show_repositories() -> void:
    repository_panel.node.global_transform = Transform3D(facing_basis(), head_position() + facing_basis() * Vector3(0, 0, -gui_distance))
    raise_popup(repository_panel.node)
    reader._request("repositories")

func add_repository() -> void:
    if repository_pending: return
    var url := repository_url.text.strip_edges()
    if url.is_empty():
        repository_status.text = reader._label("Enter a repository URL.")
        return
    repository_pending = true
    repository_add.disabled = true
    repository_status.text = reader._label("Adding repository…")
    reader._request("add_repository", {"url": url})

func render_repositories() -> void:
    clear(repository_list)
    if repositories.is_empty(): label(repository_list, "No repositories added.", 20)
    for entry in repositories:
        var name_label := label(repository_list, str(entry.title), 22)
        name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var url_label := label(repository_list, str(entry.url), 16)
        url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        repository_list.add_child(HSeparator.new())

func render_sources() -> void:
    clear(picker_list)
    picker_status.text = reader._label("No extensions available from configured repositories.") if browsing_extensions and extensions.is_empty() else ""
    for item in (extensions if browsing_extensions else installed_sources):
        if str(item.get("lang", "en")) not in enabled_languages: continue
        if not picker_search.text.is_empty() and not str(item.title).to_lower().contains(picker_search.text.to_lower()): continue
        var entry: Dictionary = item
        var row := HBoxContainer.new()
        picker_list.add_child(row)
        var icon := TextureRect.new()
        icon.custom_minimum_size = Vector2(54, 54)
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        icon.texture = preload("res://icons/book.svg")
        if not str(item.get("icon", "")).is_empty():
            var image := Image.new()
            if image.load(str(item.icon)) == OK: icon.texture = ImageTexture.create_from_image(image)
        row.add_child(icon)
        var choice := button(row, str(item.title), func():
            if browsing_extensions:
                reader._request("install_extension", {"package": str(entry.id)})
            else:
                selected_source = str(entry.id)
                picker.node.visible = false
                run_search(1)
        )
        choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        choice.clip_text = true

func show_languages() -> void:
    clear(language_list)
    var languages: Array = ["en"]
    for item in installed_sources + extensions:
        var code := str(item.get("lang", "en"))
        if code not in languages: languages.append(code)
    languages.sort()
    for language in languages:
        var code: String = language
        var toggle := CheckButton.new()
        toggle.text = TranslationServer.get_language_name(code) if code != "all" else reader._label("Multilingual")
        toggle.button_pressed = code in enabled_languages
        language_list.add_child(toggle)
        toggle.toggled.connect(func(enabled: bool):
            if enabled: enabled_languages.append(code)
            else: enabled_languages.erase(code)
            preferences.set_value("sources", "languages", enabled_languages)
            preferences.save("user://library.cfg")
            ensure_source_language()
            render_sources()
        )
    language_panel.node.global_transform = Transform3D(facing_basis(), head_position() + facing_basis() * Vector3(0, 0, -gui_distance))
    raise_popup(language_panel.node)

func ensure_source_language() -> void:
    var allowed := installed_sources.filter(func(item): return str(item.get("lang", "en")) in enabled_languages)
    if not allowed.any(func(item): return str(item.id) == selected_source):
        selected_source = str(allowed[0].id) if not allowed.is_empty() else ""
        source_items.clear()
        if not selected_source.is_empty(): run_search(1)
        elif section == "Source Search": render_grid()

func type_key(key: String) -> void:
    if not is_instance_valid(keyboard_target): return
    if key == "BACKSPACE": keyboard_target.delete_char_at_caret()
    elif key == "ENTER":
        keyboard_target.text_submitted.emit(keyboard_target.text)
        keyboard.node.visible = false
    else: keyboard_target.insert_text_at_caret(key)

func show_section(name: String) -> void:
    if settings: settings.leave()
    if opening and opening.is_running(): opening.kill()
    section = name
    previewing = false
    info.node.visible = false
    picker.node.visible = false
    repository_panel.node.visible = false
    keyboard.node.visible = false
    preview.node.visible = false
    badge.node.visible = name != "Reader"
    badge_title.text = "Questium"
    hud.node.visible = name != "Reader"
    if name == "Reader" and is_instance_valid(active_book) and not active_book.token.is_empty():
        reader.book.visible = false
        reader._activate_book(active_book)
    reader.book.visible = name == "Reader" and not reader.book.token.is_empty()
    if name == "Reader":
        reading = reader.book.visible
        if not reading:
            hud.node.visible = true
            message.text = reader._label("Choose a book and tap Read to open the Reader.")
        return
    reading = false
    source_row.visible = name == "Source Search"
    search_row.visible = source_row.visible
    subtitle.visible = source_row.visible
    heading.text = reader._label("Books") if source_row.visible else filter
    search.placeholder_text = reader._label("Search books in this source") if source_row.visible else "Search your books"
    search.text = ""
    if name == "Home": reader._request("history" if filter == "History" else "library")
    update_navigation()
    render_grid()

func render_grid() -> void:
    clear(gallery)
    cover_targets.clear()
    var entries: Array = source_items if section == "Source Search" else (history_items if filter == "History" else (deleted_items if filter == "Recently Deleted" else library_items))
    var shown := 0
    var groups: Dictionary = {}
    for item in entries:
        if not search.text.is_empty() and not str(item.title).to_lower().contains(search.text.to_lower()): continue
        if section == "Home" and filter == "Recents" and int(item.get("last_read", 0)) == 0: continue
        if section == "Home" and filter == "Favorites" and not str(item.id) in starred: continue
        var group := ""
        if section == "Home": group = date_group(item)
        if not groups.has(group): groups[group] = []
        groups[group].append(item)
    for group in ["Today", "Yesterday", "Earlier", "Your Books", ""]:
        if not groups.has(group): continue
        if not group.is_empty(): label(gallery, group, 26)
        grid = make_grid()
        gallery.add_child(grid)
        for item in groups[group]:
            add_card(item)
            shown += 1
    if groups.is_empty():
        grid = make_grid()
        gallery.add_child(grid)
    update_navigation()
    subtitle.text = "%d books" % shown
    message.text = "" if shown > 0 else reader._label("No books found. Choose a source and search." if section == "Source Search" else ("No reading history yet. Open a chapter to start reading." if filter == "History" else "Your library is empty. Find books in Source Search and save them here."))

func date_group(item: Dictionary) -> String:
    var stamp := int(item.get("last_read", 0))
    if stamp == 0: stamp = int(item.get("added", 0))
    if stamp == 0: return "Your Books"
    if stamp > 100000000000: stamp /= 1000
    var zone: int = int(Time.get_time_zone_from_system().bias) * 60
    var date := Time.get_date_string_from_unix_time(stamp + zone)
    var today := Time.get_date_string_from_system()
    var yesterday := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400 + zone)
    if date == today: return "Today"
    if date == yesterday: return "Yesterday"
    return "Earlier"

func add_card(item: Dictionary) -> void:
    var card := PanelContainer.new()
    card.custom_minimum_size = Vector2(200, 340)
    card.add_theme_stylebox_override("panel", reader.ui.style(Color(0, 0, 0, 0), 24))
    grid.add_child(card)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    card.add_child(column)
    var cover := TextureButton.new()
    cover.custom_minimum_size = Vector2(180, 255)
    cover.ignore_texture_size = true
    cover.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
    var round_cover := ShaderMaterial.new()
    round_cover.shader = preload("res://cover_round.gdshader")
    cover.material = round_cover
    var image_box := Control.new()
    image_box.custom_minimum_size = Vector2(180, 255)
    column.add_child(image_box)
    cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    image_box.add_child(cover)
    var star := Button.new()
    star.text = "♥" if str(item.id) in starred else "♡"
    star.position = Vector2(10, 10)
    star.size = Vector2(38, 38)
    star.add_theme_font_size_override("font_size", 26)
    star.add_theme_stylebox_override("normal", reader.ui.style(Color(0.30, 0.29, 0.26, 0.52), 24))
    image_box.add_child(star)
    var star_id := str(item.id)
    star.pressed.connect(func(): toggle_star(star_id))
    cover.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", reader.ui.style(Color(0.72, 0.71, 0.67, 0.24), 24)))
    cover.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", reader.ui.style(Color(0, 0, 0, 0), 24)))
    var entry: Dictionary = item
    cover.pressed.connect(func(): select_book(entry, cover))
    var caption := button(column, str(item.title), func(): select_book(entry, cover))
    caption.add_theme_stylebox_override("normal", reader.ui.style(Color(0, 0, 0, 0), 16))
    caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    caption.alignment = HORIZONTAL_ALIGNMENT_LEFT
    caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    caption.custom_minimum_size.x = 180
    caption.add_theme_font_size_override("font_size", 20)
    if item.has("history_chapter"):
        label(column, str(item.history_chapter) + " · " + reader._label("Page") + " " + str(int(item.get("last_page", 0)) + 1), 16)
    var stamp := int(item.get("last_read", 0))
    if stamp == 0: stamp = int(item.get("added", 0))
    if stamp > 100000000000: stamp /= 1000
    if stamp > 0:
        var date := Time.get_datetime_dict_from_unix_time(stamp + int(Time.get_time_zone_from_system().bias) * 60)
        label(column, "%s, %02d:%02d" % [reader._label(date_group(item)), date.hour, date.minute], 16)
    var id := str(item.id)
    cover_targets[id] = cover
    if cover_cache.has(id): cover.texture_normal = cover_cache[id]
    else: reader._request("cover", {"manga": id})

func select_book(item: Dictionary, cover: Control = null) -> void:
    reader._cancel_interactions()
    reader.ui.close_options()
    reader.toolbar.visible = false
    for candidate in reader.books: candidate.visible = false
    if not reader.book.token.is_empty():
        var model: SpatialBook = reader.BookScript.new()
        reader.add_child(model)
        model.apply_reader_filters(reader.reader_filters)
        reader.books.append(model)
        model.spread_changed.connect(reader._spread_changed)
        reader._activate_book(model)
    if reading: return
    if not reader.book.token.is_empty(): reader.close_book(false)
    selected_manga = str(item.id)
    detail_title.text = str(item.title)
    badge_title.text = str(item.title)
    chapters = []
    chapter_search.text = ""
    description.text = reader._label("Loading book details…")
    reader.ui.set_icon_label(read_button, "Read")
    read_button.disabled = true
    favorite = section == "Home" and filter != "Recently Deleted" and filter != "History"
    update_save()
    resume_chapter = ""
    previewing = true
    badge.node.visible = true
    badge.node.global_transform = Transform3D(facing_basis(), head_position() + facing_basis() * Vector3(0, 0.26, -1.04))
    raise_popup(preview.node)
    info.node.visible = false
    var target := preview_book_pose()
    var start := target
    if is_instance_valid(cover):
        var pixel: Vector2 = cover.get_global_rect().get_center()
        var local := Vector3((pixel.x / hud.pixels.x - 0.5) * hud.size.x, (0.5 - pixel.y / hud.pixels.y) * hud.size.y, 0.02)
        start = Transform3D(hud.node.global_basis, hud.node.to_global(local))
    reader.book.global_transform = start
    reader.book.scale = Vector3.ONE * 0.65
    reader.book.set_mode("book")
    reader.book.set_open(0.0)
    reader.book.set_hard_cover(reader.ui.hard_cover)
    reader.book.set_cover(cover_cache.get(selected_manga))
    reader.book.visible = true
    reader.book.set_preview(true)
    if opening and opening.is_running(): opening.kill()
    opening = reader.create_tween().set_parallel(true)
    opening.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    opening.tween_property(reader.book, "global_position", target.origin, 0.48)
    opening.tween_property(reader.book, "quaternion", target.basis.get_rotation_quaternion(), 0.48)
    opening.tween_property(reader.book, "scale", Vector3.ONE * 1.05, 0.48)
    opening.chain().tween_callback(func(): hud.node.visible = false)
    reader._request("details", {"manga": selected_manga})
    reader._request("cover", {"manga": selected_manga})

func update_save() -> void:
    reader.ui.set_icon_label(save_button, "Saved to Library" if favorite else "Save to Library")
    save_button.disabled = favorite

func save_to_library() -> void:
    if not selected_manga.is_empty():
        deleted_items = deleted_items.filter(func(item): return str(item.id) != selected_manga)
        preferences.set_value("library", "deleted", deleted_items)
        preferences.save("user://library.cfg")
        save_button.disabled = true
        reader._request("favorite", {"manga": selected_manga, "enabled": true})

func remove_from_library() -> void:
    if not favorite or selected_manga.is_empty(): return
    var matches: Array = library_items.filter(func(item): return str(item.id) == selected_manga)
    if not matches.is_empty(): deleted_items.append(matches[0].duplicate())
    preferences.set_value("library", "deleted", deleted_items)
    preferences.save("user://library.cfg")
    reader._request("favorite", {"manga": selected_manga, "enabled": false})
    reader._request("library")
    favorite = false
    update_save()

func read_selected() -> void:
    if chapters.is_empty(): return
    var id: String = resume_chapter if not resume_chapter.is_empty() else str(chapters[0].id)
    open_chapter(id)

func open_chapter(id: String) -> void:
    active_manga = selected_manga
    reader._request("open", {"manga": selected_manga, "chapter": id})
    read_button.disabled = true
    reader.ui.set_icon_label(read_button, "Loading…")

func chapter_opened() -> void:
    active_book = reader.book
    reading = true
    previewing = false
    hud.node.visible = false
    preview.node.visible = false
    info.node.visible = false
    badge.node.visible = false
    keyboard.node.visible = false
    reader.book.set_preview(false)
    reader.book.set_cover(cover_cache.get(active_manga))
    reader.book.set_mode(reader.ui.layout_mode)
    reader.book.settle_cover(true)
    var size := Vector3.ONE * 0.85
    reader.book.global_transform = Transform3D(facing_basis(), head_position() + facing_basis() * Vector3(0, -0.10, -0.85)).scaled_local(size)
    read_button.disabled = false
    reader.ui.set_icon_label(read_button, "Read")

func render_chapters() -> void:
    clear(chapter_list)
    for chapter in chapters:
        if not chapter_search.text.is_empty() and not str(chapter.title).to_lower().contains(chapter_search.text.to_lower()): continue
        var id := str(chapter.id)
        var row := button(chapter_list, ("✓ " if chapter.get("read", false) else "") + str(chapter.title), func(): open_chapter(id))
        row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        row.custom_minimum_size.x = 440

func run_search(new_page: int) -> void:
    if selected_source.is_empty(): return
    page = new_page
    message.text = reader._label("Searching…")
    reader._request("source_search", {"source": selected_source, "query": search.text, "page": page})

func consume(data: Dictionary) -> bool:
    if settings and settings.consume(data): return true
    match str(data.get("kind", "")):
        "history":
            history_items = data.get("items", [])
            if section == "Home" and filter == "History" and not previewing: render_grid()
        "library":
            library_items = data.get("items", [])
            if section == "Home" and not previewing: render_grid()
        "sources":
            installed_sources = data.get("items", [])
            render_sources()
            sources.clear()
            for item in data.get("items", []):
                sources.add_item(str(item.title))
                sources.set_item_metadata(sources.item_count - 1, str(item.id))
            if sources.item_count > 0:
                ensure_source_language()
                run_search(1)
            else: message.text = reader._label("No installed sources. Install a source extension to search.")
        "extensions":
            extensions = data.get("items", [])
            render_sources()
        "repositories":
            repositories = data.get("items", [])
            render_repositories()
        "repository_status":
            repository_pending = false
            repository_add.disabled = false
            repository_status.text = reader._label(str(data.message))
            if data.get("success", false): repository_url.text = ""
        "keyboard_text":
            if is_instance_valid(keyboard_target) and str(data.get("field", "")) == keyboard_field:
                keyboard_target.text = str(data.text)
                keyboard_target.caret_column = keyboard_target.text.length()
                keyboard_target.text_changed.emit(keyboard_target.text)
                if reader.bridge and reader.bridge.has_method("keyboardProbeEnabled") and reader.bridge.call("keyboardProbeEnabled"):
                    reader.bridge.call("keyboardProbeResult", keyboard_target.text)
                if data.get("submitted", false) or data.get("closed", false):
                    keyboard_target.remove_meta("native_keyboard_open")
                    if data.get("submitted", false): keyboard_target.text_submitted.emit(keyboard_target.text)
                    keyboard_target.release_focus()
                    keyboard_field = ""
        "install_status":
            message.text = str(data.message)
            picker_status.text = reader._label(str(data.message))
        "source_results":
            if str(data.source) != selected_source or int(data.page) != page: return true
            source_items = data.get("items", [])
            if section == "Source Search": render_grid()
        "details":
            if str(data.manga) != selected_manga: return true
            detail_title.text = str(data.title)
            description.text = str(data.description)
            favorite = bool(data.favorite)
            update_save()
        "chapters":
            if str(data.manga) != selected_manga: return true
            chapters = data.get("items", [])
            resume_chapter = str(data.get("resume", ""))
            reader.ui.set_icon_label(read_button, "Resume" if not resume_chapter.is_empty() else "Read")
            read_button.disabled = chapters.is_empty()
            render_chapters()
        "cover":
            var image := Image.new()
            if image.load(str(data.path)) == OK:
                image.generate_mipmaps()
                var texture := ImageTexture.create_from_image(image)
                var id := str(data.manga)
                cover_cache[id] = texture
                var target = cover_targets.get(id)
                if is_instance_valid(target): target.texture_normal = texture
                if id == selected_manga and previewing: reader.book.set_cover(texture)
        "error":
            if repository_pending:
                repository_pending = false
                repository_add.disabled = false
                repository_status.text = str(data.get("message", "Unable to add repository."))
            message.text = str(data.get("message", "Unable to load content"))
            description.text = message.text
            reader.ui.set_icon_label(read_button, "Resume" if not resume_chapter.is_empty() else "Read")
            read_button.disabled = chapters.is_empty()
            save_button.disabled = favorite
            return false
        _: return false
    return true

func clear(container: Container) -> void:
    for child in container.get_children():
        container.remove_child(child)
        child.queue_free()

func facing_basis(head_basis: Variant = null) -> Basis:
    var orientation: Basis = reader.camera.global_basis if head_basis == null else head_basis
    var forward: Vector3 = -orientation.z.normalized()
    # Preserve gaze elevation while removing headset roll. At the poles the
    # camera's up vector avoids the singularity of a world-up look-at basis.
    var up := Vector3.UP
    if absf(forward.dot(up)) > 0.999:
        up = orientation.y.normalized()
    return Basis.looking_at(forward, up)

func head_position() -> Vector3:
    return reader.camera.global_position

func scroll_ui(amount: float) -> bool:
    for target in [hud, info]:
        if not target.node.is_visible_in_tree(): continue
        var hovered: Control = target.viewport.gui_get_hovered_control()
        while is_instance_valid(hovered):
            if hovered is ScrollContainer:
                hovered.scroll_vertical -= int(amount * 900)
                return true
            hovered = hovered.get_parent() as Control
    return false

func drag_scroll(target: Dictionary, pixel: Vector2, pressed: bool, previous: bool) -> bool:
    if pressed and not previous:
        var hovered: Control = target.viewport.gui_get_hovered_control()
        while is_instance_valid(hovered):
            if hovered is ScrollContainer:
                reader.ui_capture.scroll = hovered
                reader.ui_capture.scroll_start = pixel
                reader.ui_capture.scroll_y = hovered.scroll_vertical
                break
            hovered = hovered.get_parent() as Control
    var capture: Dictionary = reader.ui_capture
    if capture.is_empty() or not is_instance_valid(capture.get("scroll")): return false
    if pressed and pixel.distance_to(capture.scroll_start) > 16 and not capture.get("scroll_drag", false):
        capture.scroll_drag = true
        # Cancel the card press before transferring the gesture to its scroll view.
        var cancel := InputEventMouseButton.new()
        cancel.position = Vector2(-1000, -1000)
        cancel.global_position = cancel.position
        cancel.button_index = MOUSE_BUTTON_LEFT
        cancel.pressed = false
        target.viewport.push_input(cancel, true)
    if capture.get("scroll_drag", false):
        capture.scroll.scroll_vertical = int(capture.scroll_y + capture.scroll_start.y - pixel.y)
        return true
    return false

func place_settings() -> void:
    var facing := facing_basis()
    reader.ui.options.global_transform = Transform3D(facing, head_position() + facing * Vector3(0.26, 0.02, -0.48))
    raise_popup(reader.ui.options, false)

func show_settings() -> void:
    settings.open()

func preview_book_pose() -> Transform3D:
    var facing := facing_basis()
    return Transform3D(facing, head_position() + facing * Vector3(-0.147, 0, -1.05))

func recenter(head_pose: Variant = null) -> void:
    var head: Vector3 = head_position() if head_pose == null else head_pose.origin
    var facing := facing_basis(null if head_pose == null else head_pose.basis)
    hud.node.global_transform = Transform3D(facing, head + facing * Vector3(0, 0, -gui_distance)).scaled_local(Vector3.ONE * hud_scale)
    badge.node.global_transform = Transform3D(facing, head + facing * Vector3(0, 0.54 * hud_scale + 0.035, -gui_distance))
    preview.node.global_transform = Transform3D(facing, head + facing * Vector3(0, -0.30, -0.94))
    keyboard.node.global_transform = Transform3D(facing, head + facing * Vector3(0, -0.65, -1.15))
    for node in [info.node, picker.node, language_panel.node, repository_panel.node, reader.ui.options]:
        if node.visible: place_popup(node)
    if previewing:
        badge.node.global_transform = Transform3D(facing, head + facing * Vector3(0, 0.26, -1.04))
        if opening and opening.is_running(): opening.kill()
        reader.book.global_transform = Transform3D(facing, head + facing * Vector3(-0.147, 0, -1.05)).scaled_local(Vector3.ONE * 1.05)
        hud.node.visible = false
    elif reading:
        hud.node.visible = true
        badge.node.visible = true
        var size: Vector3 = reader.book.scale
        reader.book.global_transform = Transform3D(facing, head + facing * Vector3(0.68, -0.08, -maxf(0.85, gui_distance))).scaled_local(size)
    dock_poses = [hud.node.global_transform]

func dock_pose(index: int) -> Transform3D:
    return dock_poses[mini(index, dock_poses.size() - 1)]

func handle_at(point: Vector3) -> Node3D:
    var hits: Array = []
    for target in reader.panels:
        if target.node not in roots() or not target.node.is_visible_in_tree(): continue
        var local: Vector3 = target.node.to_local(point)
        if absf(local.x) <= target.size.x * 0.5 and absf(local.y) <= target.size.y * 0.5 and absf(local.z) <= 0.12:
            hits.append({"node": target.node, "priority": int(target.node.get_meta("popup_priority", 0)), "depth": absf(local.z)})
    hits.sort_custom(func(a, b): return a.priority > b.priority if a.priority != b.priority else a.depth < b.depth)
    return hits[0].node if not hits.is_empty() else null

func handle_ray(_start: Vector3, _direction: Vector3) -> Dictionary:
    return {}

func preview_snap(_node: Node3D) -> int:
    return -1

func begin_drag(node: Node3D) -> void:
    if node == hud.node: minimize_popups()
    else: raise_popup(node, false)

func finish_drag(_node: Node3D) -> void:
    pass
