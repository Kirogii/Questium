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
    var target: Button = ui.nav_buttons["Browse"]
    var pixel: Vector2 = target.get_global_rect().get_center()
    var local := Vector3((pixel.x / ui.hud.pixels.x - 0.5) * ui.hud.size.x, (0.5 - pixel.y / ui.hud.pixels.y) * ui.hud.size.y, 0)
    var point: Vector3 = ui.hud.node.to_global(local)
    var start: Vector3 = reader.camera.global_position
    var direction := (point - start).normalized()
    assert(reader._panel_input(start, direction, true, false))
    assert(not reader.ui_capture.is_empty(), "Ray press captures the native viewport")
    reader._panel_input(start, direction, false, true)
    await process_frame
    assert(ui.section == "Source Search" and ui.search_row.visible, "Ray selects browse source page")
    ui.show_keyboard(ui.search)
    ui.type_key("m")
    ui.type_key("a")
    assert(ui.search.text == "ma", "VR keyboard writes to the selected native search field")
    ui.type_key("BACKSPACE")
    assert(ui.search.text == "m")
    assert(reader.hud_composition == null, "Desktop keeps the mesh fallback")
    assert(ui.hud.surface.visible)
    reader.hud_composition = OpenXRCompositionLayerQuad.new()
    reader.origin.add_child(reader.hud_composition)
    reader._build_hud_composition_view()
    reader.hud_composition.layer_viewport = reader.hud_composition_view
    ui.minimize_popups()
    reader.origin.position = Vector3(0.3, 0, -0.2)
    reader.origin.rotation.y = 0.4
    ui.hud.node.scale = Vector3.ONE * 0.7
    reader._sync_hud_composition()
    assert(reader.hud_composition.global_position.is_equal_approx(ui.hud.node.global_position))
    assert(reader.hud_composition.quad_size.is_equal_approx(ui.hud.size * 0.7))
    assert(reader.hud_composition.global_basis.is_equal_approx(ui.hud.node.global_basis.orthonormalized()))
    assert(ui.hud.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
    assert(reader.hud_composition_view.size == ui.hud.viewport.size)
    assert(reader.hud_composition_view.get_child(0).texture == ui.hud.viewport.get_texture())
    ui.show_sources(false)
    reader._sync_hud_composition()
    assert(not reader.hud_composition.visible and ui.hud.surface.visible)
    assert(reader.hud_composition_view.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
    ui.picker.node.hide()
    reader._sync_hud_composition()
    assert(reader.hud_composition.visible and not ui.hud.surface.visible)
    ui.hud.node.hide()
    reader._sync_hud_composition()
    assert(not reader.hud_composition.visible)
    assert(ui.hud.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
    ui.hud.node.show()
    reader._sync_hud_composition()
    assert(reader.hud_composition.visible)
    assert(ui.hud.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
    reader.queue_free()
    await process_frame
    print("PASS: native viewport ray input, capture, source navigation, VR keyboard and composition pose/scale/visibility")
    quit()
