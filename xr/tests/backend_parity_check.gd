extends SceneTree

class Bridge extends RefCounted:
    var requests: Array = []
    func request(value: String) -> void:
        requests.append(JSON.parse_string(value))
    func hideKeyboard(_field: String) -> void:
        pass

func _initialize() -> void:
    check.call_deferred()

func descendants(node: Node) -> Array:
    var result: Array = [node]
    for child in node.get_children(): result.append_array(descendants(child))
    return result

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    var bridge := Bridge.new()
    reader.bridge = bridge
    ui.settings.open_backend("history")
    assert(ui.settings.backend_open and bridge.requests[-1].screen == "history")
    ui.consume({"kind": "settings_detail", "scope": "backend", "title": "Filters", "items": [
        {"id": "reset", "type": "action", "title": "Reset", "x": 0, "y": 0, "width": 100, "height": 50},
        {"id": "apply", "type": "action", "title": "Filter", "x": 300, "y": 0, "width": 100, "height": 50},
        {"id": "tag", "type": "text", "title": "Tags", "value": "", "x": 0, "y": 70, "width": 400, "height": 50},
        {"id": "toggle", "type": "switch", "title": "Include", "value": false, "x": 0, "y": 140, "width": 400, "height": 50}
    ]})
    await process_frame
    var apply: Button
    var tag: LineEdit
    var toggle: CheckButton
    for control in descendants(ui.settings.details_list):
        if control is Button and control.text == "Filter": apply = control
        if control is LineEdit: tag = control
        if control is CheckButton: toggle = control
    assert(apply != null and apply.custom_minimum_size.y >= 64, "Native actions use readable Questium targets")
    assert(apply.scale == Vector2.ONE, "Phone coordinates cannot shrink native actions")
    apply.pressed.emit()
    assert(bridge.requests[-1].id == "apply")
    tag.text_changed.emit("fantasy")
    assert(bridge.requests[-1].id == "tag" and bridge.requests[-1].value == "fantasy")
    toggle.button_pressed = true
    assert(bridge.requests[-1].id == "toggle")
    ui.settings.close_backend()
    assert(bridge.requests[-1].action == "backend_close")
    ui.selected_source = "123"
    ui.source_filters = {"0": "tag"}
    ui.show_source_filters()
    assert(bridge.requests[-1].action == "source_filters" and bridge.requests[-1].source == "123")
    assert(ui.source_filter_panel.node.visible and not ui.settings.backend_open, "Filters use a dedicated source options popup")
    assert(ui.source_filters["0"] == "tag")
    ui.themes.entries = [{"id": "test", "title": "Test", "dark": {"primary": 4294901760, "surface": 4278190080}}]
    ui.themes.selected = "test"
    ui.themes.apply(false)
    assert(reader.ui.palette_id == "test")
    assert(reader.ui.theme_color("primary", Color.WHITE).is_equal_approx(Color.RED))
    ui.themes.selected = "questium_frost"
    ui.themes.apply(false)
    assert(reader.ui.theme_color("primary", Color.WHITE) == Color.WHITE)
    for panel in reader.panels:
        if panel.get("hand_attached", false):
            assert(not panel.has("drag_bar"), "Hand toolbar must not have a window drag rail")
            continue
        assert(panel.has("drag_bar"), "World windows have a bottom drag bar")
        assert(panel.drag_bar.position.y < -panel.size.y * 0.5)
    for panel in reader.panels: panel.node.visible = false
    ui.hud.node.visible = true
    reader.book.visible = false
    var bar = ui.hud.drag_bar
    var origin: Vector3 = bar.global_position + ui.hud.node.global_basis.z
    var direction: Vector3 = -ui.hud.node.global_basis.z
    assert(reader.window_drag.handle_ray(origin, direction).node == ui.hud.node)
    reader.tracked.right = {"pressed": false, "natural_hand": false}
    reader._pointer("right", origin, direction, true, true)
    assert(reader.window_holder == "right" and reader.held_window == ui.hud.node, "Controller trigger grabs bar")
    reader._pointer("right", origin, direction, false, true)
    assert(reader.window_holder.is_empty(), "Controller trigger release drops window")
    reader.bridge = null
    print("PASS readable native cards, dedicated source filters, theme restoration and world-window drag bars")
    reader.queue_free()
    await process_frame
    quit()