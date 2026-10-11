extends SceneTree

class KeyboardBridge extends RefCounted:
    var requests: Array = []
    var field := ""
    var text := ""
    var state := {}
    func request(value: String) -> void:
        requests.append(JSON.parse_string(value))
    func showKeyboard(value: String, selected: String) -> void:
        field = selected
        text = value
    func hideKeyboard(_field: String) -> void:
        pass
    func keyboardSnapshot() -> String:
        return JSON.stringify(state)
    func keyboardProbeEnabled() -> bool:
        return false

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    ui.selected_source = "1"
    var filters := [{"index": 0, "key": "0", "type": "group", "name": "Tags", "children": [
        {"index": 0, "key": "0.0", "type": "checkbox", "name": "Action", "state": true},
        {"index": 1, "key": "0.1", "type": "group", "name": "Nested", "children": [
            {"index": 0, "key": "0.1.0", "type": "tristate", "name": "Drama", "state": 2},
            {"index": 1, "key": "0.1.1", "type": "select", "name": "Status", "state": 1, "values": ["Any", "Complete"]},
            {"index": 2, "key": "0.1.2", "type": "autocomplete", "name": "Genres", "state": ["Action"], "values": ["Action", "Drama"]}
        ]}
    ]}]
    var filter_bridge := KeyboardBridge.new()
    reader.bridge = filter_bridge
    ui.show_source_filters()
    assert(filter_bridge.requests.size() == 1 and filter_bridge.requests[0].action == "source_filters", "Opening Filters requests the source's current tag list without running a search")
    assert(ui.source_filter_body.get_child(0).text == "Loading…")
    await create_timer(0.25).timeout
    ui._process(1.01)
    assert(filter_bridge.requests.size() >= 2, "The open sheet refreshes extension tag caches after asynchronous loading")
    ui.consume({"kind": "source_filters", "source": "1", "request_id": ui.filter_revision - 1, "items": filters})
    assert(ui.source_filter_defs.is_empty(), "An older filter response cannot replace a newer refresh")
    ui.consume({"kind": "source_filters", "source": "1", "request_id": ui.filter_revision, "items": filters})
    ui.consume({"kind": "source_filters", "source": "1", "items": []})
    assert(ui.source_filter_defs == filters, "An older search snapshot cannot erase the open sheet's refreshed tags")
    ui._process(0.06)
    var sheet: Node3D = ui.source_filter_panel.node
    assert(sheet.get_meta("popup_priority") > 120, "Filter sheet must render and hit ahead of protected HUD")
    for child in sheet.get_children():
        if child is MeshInstance3D:
            assert(child.material_override.render_priority > 120)
    assert(ui.source_filter_body.get_child_count() == 8, "Nested source filters expose real child choices")
    if DisplayServer.get_name() != "headless":
        for frame in 5: await process_frame
        await RenderingServer.frame_post_draw
        ui.source_filter_panel.viewport.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/source-tags-panel.png")
    var action: CheckBox = ui.source_filter_body.get_child(1)
    action.button_pressed = false
    assert(ui.source_filters["0.0"] == false)
    var drama: CheckBox = ui.source_filter_body.get_child(7)
    drama.button_pressed = true
    assert(ui.source_filters["0.1.2"] == ["Action", "Drama"], "Autocomplete toggle preserves default selected tags")
    var same_action: Node = ui.source_filter_body.get_child(1)
    ui.consume({"kind": "source_filters", "source": "1", "request_id": ui.filter_revision, "items": filters.duplicate(true)})
    assert(ui.source_filter_body.get_child(1) == same_action, "Unchanged refreshes leave the user's active controls intact")
    var expanded := filters.duplicate(true)
    expanded[0].children.append({"index": 2, "key": "0.2", "type": "checkbox", "name": "Newly loaded tag", "state": false})
    ui.consume({"kind": "source_filters", "source": "1", "request_id": ui.filter_revision, "items": expanded})
    assert(ui.source_filter_body.get_child_count() == 9 and not ui.source_filter_body.get_child(1).button_pressed)
    assert(ui.source_filters["0.1.2"] == ["Action", "Drama"], "New tag choices preserve the user's selected filters")
    ui._process(8.0)
    var request_count := filter_bridge.requests.size()
    ui._process(1.1)
    assert(filter_bridge.requests.size() == request_count, "Filter refresh has a bounded budget")
    ui.source_filters.clear()
    ui.render_source_filters()
    assert(ui.source_filter_body.get_child(1).button_pressed, "Clear restores backend defaults")
    request_count = filter_bridge.requests.size()
    ui.source_category_row.get_child(2).pressed.emit()
    assert(filter_bridge.requests.size() == request_count + 1 and filter_bridge.requests[-1].action == "source_filters", "Search by tags opens actual source choices without submitting an empty search")
    ui.hud.node.position += Vector3(0.2, 0.1, 0.05)
    ui.hud.node.rotate_y(0.3)
    ui.hud.node.scale = Vector3.ONE * 0.7
    ui._process(0.06)
    assert(sheet.global_transform.is_equal_approx(ui.source_filter_pose(ui.source_filter_offset)), "Sheet follows HUD position, rotation and scale during its animation")
    assert(is_equal_approx(sheet.global_basis.x.length(), 0.7))
    var head: Vector3 = reader.camera.global_position
    reader._panel_input(head, (sheet.global_position - head).normalized(), true, false)
    assert(reader.ui_capture.panel.node == sheet, "Overlapping filter sheet receives ray input before HUD")
    reader._panel_input(head, (sheet.global_position - head).normalized(), false, true)
    ui.keyboard_target = ui.search
    ui.keyboard_field = "test:1"
    var submissions := []
    ui.search.text_submitted.connect(func(value): submissions.append(value))
    ui.consume_keyboard({"field": "test:1", "text": "search", "submitted": true, "closed": true})
    ui.consume_keyboard({"field": "test:1", "text": "stale", "submitted": true})
    assert(ui.search.text == "search" and submissions == ["search"], "Terminal IME snapshot submits once and rejects stale session")
    ui.keyboard_target = ui.chapter_search
    ui.keyboard_field = "second:2"
    ui.keyboard_revision = -1
    ui.consume_keyboard({"field": "second:2", "text": "Composing 日本", "revision": 20})
    ui.consume_keyboard({"field": "second:2", "text": "old", "revision": 19})
    ui.consume_keyboard({"field": "test:1", "text": "wrong box", "revision": 22})
    assert(ui.chapter_search.text == "Composing 日本", "Late events and old fields cannot replace the selected textbox")
    assert(ui.search.text == "search", "Selecting another textbox preserves the previous text")
    ui.consume_keyboard({"field": "second:2", "text": "Final 日本", "revision": 21, "closed": true})
    assert(ui.chapter_search.text == "Final 日本", "Closing preserves the final IME composition without submitting")
    var native := KeyboardBridge.new()
    reader.bridge = native
    ui.picker_search.text = "seed"
    ui.show_keyboard(ui.picker_search)
    assert(native.field == ui.keyboard_field and native.text == "seed", "Selected Sources field opens the native bridge with its text and session")
    native.state = {"kind": "keyboard_text", "field": native.field, "text": "isekai", "revision": 100}
    ui._process(0.06)
    assert(ui.picker_search.text == "isekai", "Native keyboard polling updates the selected Sources textbox")
    var native_submissions := []
    ui.picker_search.text_submitted.connect(func(value): native_submissions.append(value))
    native.state.merge({"revision": 101, "submitted": true, "closed": true}, true)
    ui._process(0.06)
    ui._process(0.06)
    assert(native_submissions == ["isekai"] and ui.keyboard_field.is_empty(), "Native Enter submits and closes exactly once")
    reader.bridge = null
    reader.queue_free()
    await process_frame
    print("PASS: nested filter choices, defaults, foreground ray priority, HUD-follow and IME terminal session")
    quit()
