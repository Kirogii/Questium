extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    assert(reader.android_app == null and reader.android_layer == null, "Native VR HUD replaces Android app panel")
    reader.camera.rotation = Vector3(0.4, 0.8, 0.2)
    reader.recenter()
    await process_frame
    var target: Button = ui.nav_buttons["Source Search"]
    var pixel: Vector2 = target.get_global_rect().get_center()
    var local := Vector3((pixel.x / ui.hud.pixels.x - 0.5) * ui.hud.size.x, (0.5 - pixel.y / ui.hud.pixels.y) * ui.hud.size.y, 0)
    var point: Vector3 = ui.hud.node.to_global(local)
    var start: Vector3 = reader.camera.global_position
    var direction := (point - start).normalized()
    assert(reader._panel_input(start, direction, true, false))
    assert(not reader.ui_capture.is_empty(), "Ray press captures the native viewport")
    reader._panel_input(start, direction, false, true)
    await process_frame
    assert(ui.section == "Source Search" and ui.search_row.visible, "Ray selects source search")
    ui.show_keyboard(ui.search)
    ui.type_key("m")
    ui.type_key("a")
    assert(ui.search.text == "ma", "VR keyboard writes to the selected native search field")
    ui.type_key("BACKSPACE")
    assert(ui.search.text == "m")
    reader.queue_free()
    await process_frame
    print("PASS: native viewport ray input, capture, source navigation and VR keyboard")
    quit()
