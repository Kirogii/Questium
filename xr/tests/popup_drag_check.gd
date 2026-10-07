extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    reader.tracked.right = {"pressed": false, "natural_hand": true, "fist": true, "was_fist": false, "can_grab": true, "can_ui": false}
    var start: Vector3 = ui.hud.node.global_position
    reader._pointer("right", start, Vector3.FORWARD, true, true)
    assert(reader.window_holder == "right" and reader.held_window == ui.hud.node, "Clenching inside the main HUD captures it")
    reader.tracked.right.was_fist = true
    reader._pointer("right", start + Vector3(0.1, 0.05, 0), Vector3.FORWARD, true, true)
    assert(ui.hud.node.global_position.is_equal_approx(start + Vector3(0.1, 0.05, 0)), "HUD follows the held fist without jumping")
    reader.tracked.right.fist = false
    reader._pointer("right", start, Vector3.FORWARD, true, true)
    assert(reader.window_holder.is_empty(), "Opening the hand releases the HUD even if fingers remain pinched")
    ui.show_sources(false)
    ui.show_languages()
    ui.picker.node.global_transform = ui.language_panel.node.global_transform
    var popup: Vector3 = ui.language_panel.node.global_position
    assert(ui.handle_at(popup) == ui.language_panel.node, "Newest popup wins overlapping grabs")
    reader.tracked.right.pressed = false
    reader.tracked.right.fist = true
    reader.tracked.right.was_fist = false
    reader._pointer("right", popup, Vector3.FORWARD, true, true)
    assert(reader.held_window == ui.language_panel.node, "Fist captures popup content rather than underlying HUD")
    reader.tracked.right.fist = false
    reader._pointer("right", popup, Vector3.FORWARD, false, true)
    reader.book.visible = true
    reader.book.set_preview(false)
    reader.book.global_position = popup + Vector3(0, 0, 0.1)
    reader.ui_capture.clear()
    reader._panel_input(popup + Vector3(0, 0, 0.3), Vector3.FORWARD, true, false)
    assert(reader.ui_capture.panel.node == ui.language_panel.node, "Topmost popup captures input even with a book in front")
    reader.ui.toggle()
    assert(reader.ui.options.get_parent() == reader, "Options remain independent of hidden or moving books")
    assert(reader.ui.footer.get_child_count() >= 1, "Options always have a fixed Close button")
    reader.queue_free()
    await process_frame
    print("PASS: fist HUD and popup dragging, open-hand release, topmost popup input, independent options and fixed Close button")
    quit()
