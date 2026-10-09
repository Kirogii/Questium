extends RefCounted

const ACTIONS = ["Next page", "Previous page", "Interact", "Grab", "Book Options", "Library", "Center", "Switch hands", "See through", "None"]
var reader: Node3D
var config := ConfigFile.new()
var config_path := "user://controls.cfg"
var options: Node3D
var content: VBoxContainer
var number: Label
var total: Label
var options_seeker: HSlider
var options_title: Label
var config_scroll: ScrollContainer
var footer: HBoxContainer
var layout_mode := "auto"
var hard_cover := false
var options_page := 0
var dots: HBoxContainer
var palm_options_requested := false
var swipe_start := Vector2.ZERO
var swiping := false
var swipe_eligible := false

func _init(host: Node3D) -> void:
    reader = host

func style(color: Color, radius: int, outline: bool = false) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.set_corner_radius_all(radius)
    box.content_margin_left = 16
    box.content_margin_right = 16
    box.content_margin_top = 10
    box.content_margin_bottom = 10
    if outline:
        box.set_border_width_all(2)
        box.border_color = Color(0.85, 0.86, 0.89)
    return box

func load_config() -> void:
    config.load(config_path)
    reader.preferred_hand = str(config.get_value("reader", "hand", "right"))
    reader.haptics = bool(config.get_value("reader", "haptics", true))
    layout_mode = str(config.get_value("reader", "layout", "auto"))
    hard_cover = bool(config.get_value("reader", "hard_cover", false))
    for key in reader.bindings:
        var saved := str(config.get_value("buttons", key, reader.bindings[key]))
        if saved in ACTIONS:
            reader.bindings[key] = saved

func save() -> void:
    for key in reader.bindings:
        config.set_value("buttons", key, reader.bindings[key])
    config.set_value("reader", "hand", reader.preferred_hand)
    config.set_value("reader", "haptics", reader.haptics)
    config.save(config_path)

func label(parent: Container, text: String, font_size: int = 24) -> Label:
    var node := Label.new()
    node.text = reader._label(text)
    node.add_theme_font_size_override("font_size", font_size)
    parent.add_child(node)
    return node

func line(parent: Container) -> void:
    parent.add_child(HSeparator.new())

func page_slider(parent: Container) -> HSlider:
    var slider := HSlider.new()
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size = Vector2(220, 40)
    theme_slider(slider)
    slider.step = 1
    slider.add_theme_icon_override("grabber", preload("res://icons/knob.svg"))
    slider.add_theme_icon_override("grabber_highlight", preload("res://icons/knob.svg"))
    parent.add_child(slider)
    slider.drag_ended.connect(func(changed: bool):
        if changed:
            haptic(reader.ui_hand)
            reader._seek(int(slider.value))
    )
    return slider

func icon_button(parent: Container, icon: String, callback: Callable, size: Vector2 = Vector2(100, 100)) -> Button:
    var button: Button = reader._button(parent, "", callback)
    button.icon = load("res://icons/" + icon + ".svg")
    button.expand_icon = true
    button.custom_minimum_size = size
    return button

func labeled_icon(parent: Container, icon: String, caption: String, callback: Callable, size: Vector2 = Vector2(80, 60)) -> Button:
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 3)
    parent.add_child(column)
    var button := icon_button(column, icon, callback, size)
    var text := label(column, caption, 17)
    text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text.modulate.a = 0
    text.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.mouse_entered.connect(func(): text.modulate.a = 1)
    button.mouse_exited.connect(func(): text.modulate.a = 0)
    button.focus_entered.connect(func(): text.modulate.a = 1)
    button.focus_exited.connect(func(): text.modulate.a = 0)
    button.tooltip_text = reader._label(caption)
    button.set_meta("hover_label", text)
    return button

func set_icon_label(button: Button, caption: String) -> void:
    button.text = ""
    button.tooltip_text = reader._label(caption)
    var text: Label = button.get_meta("hover_label", null)
    if is_instance_valid(text): text.text = reader._label(caption)

func build() -> void:
    var panel: Dictionary = reader._panel(reader.book, Vector2(0.34, 0.082), Vector2i(1000, 242), Vector3.ZERO)
    reader.toolbar_view = panel.viewport
    var column: VBoxContainer = panel.content
    reader.title = label(column, "Questium", 30)
    line(column)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    column.add_child(row)
    labeled_icon(row, "menu", "Library", reader.toggle_library)
    labeled_icon(row, "previous", "Previous", func(): reader._turn(-1))
    var seeking := VBoxContainer.new()
    seeking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(seeking)
    number = label(seeking, "1")
    number.visible = false
    number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    reader.seeker = page_slider(seeking)
    total = label(seeking, "0")
    total.visible = false
    total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    labeled_icon(row, "next", "Next", func(): reader._turn(1))
    labeled_icon(row, "book", "Book Options", func(): toggle(true))
    labeled_icon(row, "close", "Close", reader.close_book, Vector2(70, 60))
    reader.status = label(column, "Loading library…", 16)
    reader.status.visible = false
    build_options()

func build_options() -> void:
    var panel: Dictionary = reader._panel(reader.book, Vector2(0.32, 0.48), Vector2i(800, 1200), Vector3.ZERO)
    options = panel.node
    options.visible = false
    panel.background.add_theme_stylebox_override("panel", style(Color(0.40, 0.39, 0.37, 0.08), 62, true))
    var outer := VBoxContainer.new()
    panel.content.add_child(outer)
    outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    dots = HBoxContainer.new()
    dots.alignment = BoxContainer.ALIGNMENT_CENTER
    dots.add_theme_constant_override("separation", 16)
    outer.add_child(dots)
    for page in range(3):
        var choice := page
        var dot := Button.new()
        dot.custom_minimum_size = Vector2(24, 24)
        dot.tooltip_text = reader._label(["Book Options", "Layout", "System Settings"][page])
        dots.add_child(dot)
        dot.pressed.connect(func(): options_page = choice; show_book())
    var inset := PanelContainer.new()
    inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
    inset.add_theme_stylebox_override("panel", style(Color(0.11, 0.12, 0.15, 0.10), 42))
    outer.add_child(inset)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    inset.add_child(scroll)
    content = VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 16)
    scroll.add_child(content)
    footer = HBoxContainer.new()
    outer.add_child(footer)
    show_book()

func clear() -> void:
    for child in footer.get_children():
        footer.remove_child(child)
        child.queue_free()
    icon_button(footer, "close", close_options, Vector2(80, 70))
    for child in content.get_children():
        content.remove_child(child)
        child.queue_free()
    options_seeker = null
    options_title = null
    config_scroll = null

func heading(text: String) -> void:
    var row := HBoxContainer.new()
    content.add_child(row)
    var title := label(row, text, 36)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    icon_button(row, "close", close_options, Vector2(65, 65))

func show_book() -> void:
    clear()
    for index in range(dots.get_child_count()):
        dots.get_child(index).add_theme_stylebox_override("normal", style(Color(1, 1, 1, 0.90 if index == options_page else 0.22), 12))
    heading(["Book Options", "Layout", "System Settings"][options_page])
    options_title = label(content, reader.title.text, 24)
    options_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    options_title.clip_text = true
    line(content)
    if options_page == 0:
        switch_row(content, "Hard Cover", hard_cover, func(enabled: bool):
            hard_cover = enabled
            reader.book.set_hard_cover(enabled)
            config.set_value("reader", "hard_cover", enabled)
            config.save(config_path)
        )
        switch_row(content, "Upscale Manga", reader.book.upscale_enabled, func(enabled: bool):
            reader.book.upscale_enabled = enabled
            reader._request("upscale_book", {"token": reader.book.token, "enabled": enabled})
        )
        line(content)
        label(content, "Reading progress", 24)
        options_seeker = page_slider(content)
        options_seeker.max_value = maxi(0, reader.book.page_count - 1)
        options_seeker.value = reader.book.first_page
        var pages := HBoxContainer.new()
        content.add_child(pages)
        icon_button(pages, "previous", func(): reader._turn(-1), Vector2(100, 70))
        icon_button(pages, "next", func(): reader._turn(1), Vector2(100, 70))
        icon_button(pages, "book", func(): reader.book.settle_cover(reader.book.openness < 0.5), Vector2(100, 70))
    elif options_page == 1:
        for entry in [["Force two pages", "book"], ["Force long scroll", "scroll"]]:
            var forced: String = entry[1]
            switch_row(content, entry[0], reader.book.mode == forced, func(enabled: bool):
                layout_mode = forced if enabled else "auto"
                reader.book.set_mode(layout_mode)
                config.set_value("reader", "layout", layout_mode)
                config.save(config_path)
                reader._preload(reader.book.first_page)
                show_book.call_deferred()
            )
        line(content)
        for entry in [["Size", 0.5, 2.5, reader.book.scale.x], ["Tilt", -60, 45, rad_to_deg(reader.book.rotation.x)], ["Distance", 0.35, 2, reader.book.global_position.distance_to(reader.camera.global_position)]]:
            var kind: String = entry[0]
            label(content, kind, 22)
            var row := HBoxContainer.new()
            content.add_child(row)
            reader._slider(row, kind, entry[1], entry[2], entry[3], func(value: float):
                match kind:
                    "Size": reader.book.scale = Vector3.ONE * value
                    "Tilt": reader.book.rotation.x = deg_to_rad(value)
                    "Distance": reader.book.global_position = reader.camera.global_position - reader.camera.global_basis.z * value
            )
    else:
        switch_row(content, "Haptic feedback", reader.haptics, func(enabled: bool): reader.haptics = enabled; save())
        switch_row(content, "See through", reader.passthrough_enabled, reader._set_passthrough)
        reader._button(content, "Controller configuration", show_controllers)
        reader._button(content, "Switch hands", func(): perform("Switch hands"))
        reader._button(content, "Edit Settings", func(): reader.workspace.show_settings())
    reader._button(footer, "Recenter", reader.recenter)

func close_options() -> void:
    options.visible = false
    palm_options_requested = false

func switch_row(parent: Container, caption: String, value: bool, callback: Callable) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    label(row, caption, 26).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var toggle := CheckButton.new()
    theme_switch(toggle)
    toggle.button_pressed = value
    row.add_child(toggle)
    toggle.toggled.connect(callback)

func theme_switch(toggle: CheckButton) -> void:
    toggle.add_theme_icon_override("checked", preload("res://icons/switch_on.svg"))
    toggle.add_theme_icon_override("unchecked", preload("res://icons/switch_off.svg"))
    toggle.add_theme_icon_override("checked_disabled", preload("res://icons/switch_on.svg"))
    toggle.add_theme_icon_override("unchecked_disabled", preload("res://icons/switch_off.svg"))
    toggle.custom_minimum_size.y = 60

func theme_slider(slider: HSlider) -> void:
    var track := StyleBoxFlat.new()
    track.bg_color = Color(0.08, 0.08, 0.08, 0.34)
    track.set_corner_radius_all(14)
    track.content_margin_top = 9
    track.content_margin_bottom = 9
    slider.add_theme_stylebox_override("slider", track)
    slider.add_theme_icon_override("grabber", preload("res://icons/knob.svg"))
    slider.add_theme_icon_override("grabber_highlight", preload("res://icons/knob.svg"))
    slider.add_theme_icon_override("tick", preload("res://icons/tick.svg"))
    slider.tick_count = 9
    slider.ticks_on_borders = true

func update_palm_options(facing: bool, palm: Vector3) -> void:
    if not palm_options_requested: return
    options.visible = facing and not reader.chapter_token.is_empty()
    if options.visible:
        var right: Vector3 = reader.camera.global_basis.x.normalized()
        options.global_position = palm + Vector3.UP * 0.28 + right * 0.12
        options.look_at(reader.camera.global_position, Vector3.UP, true)

func swipe_tabs(panel: Dictionary, pixel: Vector2, pressed: bool, previous: bool) -> bool:
    if panel.node != options: return false
    if pressed and not previous:
        swipe_start = pixel
        swiping = false
        swipe_eligible = true
        var hovered: Control = panel.viewport.gui_get_hovered_control()
        while is_instance_valid(hovered):
            if hovered is Range or hovered is OptionButton: swipe_eligible = false
            hovered = hovered.get_parent() as Control
    var travel := pixel - swipe_start
    if pressed and swipe_eligible and not swiping and absf(travel.x) > 95 and absf(travel.x) > absf(travel.y) * 1.6:
        swiping = true
        var cancel := InputEventMouseButton.new()
        cancel.button_index = MOUSE_BUTTON_LEFT
        cancel.pressed = false
        cancel.position = Vector2(-1000, -1000)
        panel.viewport.push_input(cancel, true)
    var consumed := swiping
    if not pressed:
        if swiping:
            options_page = posmod(options_page + (-1 if travel.x > 0 else 1), 3)
            show_book.call_deferred()
        swiping = false
        swipe_eligible = false
    return consumed

func show_settings() -> void:
    clear()
    heading("Reader Settings")
    reader._button(content, "Controller configuration", show_controllers)
    reader._button(content, "Switch hands", func(): perform("Switch hands"))
    label(content, reader._label("Pointer hand") + ": " + reader._label(reader.preferred_hand))
    var feedback := CheckButton.new()
    feedback.text = reader._label("Haptic feedback")
    feedback.button_pressed = reader.haptics
    content.add_child(feedback)
    feedback.toggled.connect(func(enabled: bool): reader.haptics = enabled; save(); haptic(reader.ui_hand))
    label(content, "Hand tracking: pinch to select; grab page bars to flip")
    reader._button(content, "See through", func(): reader._set_passthrough(true))
    reader._button(content, "LTR / RTL", func(): reader.book.cancel_turn(); reader.book.rtl = not reader.book.rtl; reader.book._refresh())
    reader._button(content, "Book Options", show_book)

func show_controllers() -> void:
    clear()
    heading("Quest 3 / 3S Controllers")
    var diagrams := HBoxContainer.new()
    content.add_child(diagrams)
    for hand in ["left", "right"]:
        var diagram := preload("res://controller_diagram.gd").new()
        diagram.hand = hand
        diagram.bindings = reader.bindings
        diagram.labels = reader.labels
        diagram.custom_minimum_size = Vector2(335, 195)
        diagrams.add_child(diagram)
    var scroll := ScrollContainer.new()
    config_scroll = scroll
    scroll.custom_minimum_size.y = 265
    content.add_child(scroll)
    var rows := VBoxContainer.new()
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(rows)
    for key in reader.bindings:
        var binding_key: String = key
        var row := HBoxContainer.new()
        rows.add_child(row)
        label(row, reader._label(key.get_slice(":", 0)) + " · " + button_name(key.get_slice(":", 1), key.get_slice(":", 0))).custom_minimum_size.x = 265
        var choice := OptionButton.new()
        choice.add_theme_font_size_override("font_size", 24)
        choice.custom_minimum_size = Vector2(220, 48)
        for action in ACTIONS:
            choice.add_item(reader._label(action))
        choice.select(ACTIONS.find(reader.bindings[key]))
        row.add_child(choice)
        choice.item_selected.connect(func(index: int):
            reader.bindings[binding_key] = ACTIONS[index]
            save()
            for diagram in diagrams.get_children():
                diagram.queue_redraw()
            haptic(reader.ui_hand)
        )
    label(content, "Left stick: move / turn; right stick: pages / vertical scroll", 14)
    var bottom := HBoxContainer.new()
    content.add_child(bottom)
    reader._button(bottom, "Switch hands", func(): perform("Switch hands"))
    reader._button(bottom, "Reset controls", reset_controls)
    reader._button(bottom, "Back", show_settings)

func reset_controls() -> void:
    reader._cancel_interactions()
    reader.bindings = {"left:trigger_click": "Previous page", "right:trigger_click": "Next page", "left:ax_button": "Interact", "right:ax_button": "Interact", "left:by_button": "Library", "right:by_button": "Book Options", "left:primary_click": "Switch hands", "right:primary_click": "Center", "left:menu_button": "Book Options", "left:grip_click": "Grab", "right:grip_click": "Grab"}
    reader.preferred_hand = "right"
    save()
    show_controllers()

func button_name(action: String, hand: String) -> String:
    match action:
        "trigger_click": return reader._label("Trigger")
        "grip_click": return reader._label("Grip")
        "ax_button": return "X" if hand == "left" else "A"
        "by_button": return "Y" if hand == "left" else "B"
        "primary_click": return reader._label("Stick click")
        "menu_button": return reader._label("Menu")
    return action

func toggle(from_palm: bool = false) -> void:
    if options.visible:
        close_options()
        return
    palm_options_requested = from_palm and reader.tracked.values().any(func(value): return value.get("natural_hand", false))
    options.visible = true
    show_book()
    if reader.workspace: reader.workspace.place_settings()

func update_pages(index: int) -> void:
    number.text = str(index + 1)
    total.text = str(reader.book.page_count)
    if is_instance_valid(options_seeker):
        options_seeker.max_value = maxi(0, reader.book.page_count - 1)
        options_seeker.value = index

func update_title() -> void:
    if is_instance_valid(options_title):
        options_title.text = reader.title.text

func haptic(hand: String) -> void:
    if reader.haptics and reader.tracked.has(hand) and reader.tracked[hand].has("controller") and reader.tracked[hand].controller.get_is_active():
        reader.tracked[hand].controller.trigger_haptic_pulse("haptic", 0.0, 0.35, 0.035, 0.0)

func perform(action: String) -> void:
    match action:
        "Next page": reader._turn(1)
        "Previous page": reader._turn(-1)
        "Book Options":
            reader.toolbar_forced = not reader.toolbar_forced
            if not reader.toolbar_forced:
                close_options()
        "Library": reader.toggle_library()
        "Center": reader.recenter()
        "See through": reader._set_passthrough(not reader.passthrough_enabled)
        "Switch hands":
            reader._cancel_interactions()
            reader.preferred_hand = "left" if reader.preferred_hand == "right" else "right"
            save()
            reader.status.text = reader._label("Pointer hand") + ": " + reader._label(reader.preferred_hand)
        "Exit VR": reader._request("exit")

func controller_input(hand: String, controller: XRController3D) -> bool:
    var pressed := false
    var current: Dictionary = {}
    reader.tracked[hand].can_grab = false
    reader.tracked[hand].can_ui = reader.library_panel.visible or hand == reader.preferred_hand
    for key in reader.bindings:
        if not key.begins_with(hand + ":"):
            continue
        var input_name: String = key.get_slice(":", 1)
        var down := controller.is_button_pressed(input_name)
        current[input_name] = down
        var action: String = reader.bindings[key]
        if action == "Grab":
            reader.tracked[hand].can_grab = down
            if down:
                reader.tracked[hand].can_ui = false
            pressed = pressed or down
        elif (action == "Interact" and (reader.library_panel.visible or hand == reader.preferred_hand)) or (action in ["Next page", "Previous page"] and reader.library_panel.visible):
            pressed = pressed or down
        elif down and not reader.tracked[hand].get("buttons", {}).get(input_name, false):
            haptic(hand)
            perform(action)
    reader.tracked[hand].buttons = current
    var stick := controller.get_vector2("primary")
    if absf(stick.y) > 0.2:
        if is_instance_valid(config_scroll) and options.visible:
            config_scroll.scroll_vertical -= int(stick.y * reader.get_process_delta_time() * 700)
        elif reader.workspace and reader.workspace.scroll_ui(stick.y * reader.get_process_delta_time()):
            pass
        elif hand == "right" and reader.book.scroll_mode:
            reader._scroll_reader(-stick.y * reader.get_process_delta_time() * 0.8)
    var stick_down := hand == "right" and absf(stick.x) > 0.7
    if stick_down and not reader.tracked[hand].get("stick_down", false):
        reader._turn(1 if stick.x > 0 else -1)
        haptic(hand)
    reader.tracked[hand].stick_down = stick_down
    return pressed
