extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    var badge_width: float = ui.badge.size.x
    assert(badge_width <= 0.24, "Title pill stays compact")
    ui.hud.node.global_position += Vector3(0.06, -0.04, 0)
    ui.sync_badge()
    assert(is_equal_approx(ui.badge.node.global_position.x, ui.hud.node.global_position.x), "Pill follows HUD rather than drifting")
    ui.show_settings()
    ui.consume({"kind": "settings", "title": "Reader", "category": 2, "categories": [{"id": 0, "title": "Appearance"}, {"id": 2, "title": "Reader"}], "items": [
        {"type": "group", "title": "Display"},
        {"id": "a", "type": "switch", "title": "Grayscale", "value": true},
        {"id": "b", "type": "slider", "title": "Hue", "value": 40, "min": -180, "max": 180},
        {"id": "c", "type": "list", "title": "Mode", "value": 1, "entries": ["Auto", "Two pages"]},
        {"id": "d", "type": "text", "title": "Text", "value": "Saved"}
    ]})
    assert(ui.section == "Settings" and ui.heading.text == "Reader")
    assert(ui.settings.sidebar.get_child_count() == 3 and ui.gallery.get_child_count() == 5)
    assert(not ui.nav_buttons["All Books"].visible, "Settings categories replace library navigation")
    ui.place_settings()
    var popup: Vector3 = reader.ui.options.global_position
    var distance: float = popup.distance_to(reader.camera.global_position)
    assert(distance >= 0.379 and distance <= 0.561, "Book settings are at reachable distance")
    assert(popup.direction_to(ui.hud.node.global_position).dot(-ui.facing_basis().z) > 0.9, "Popup is centered in front of HUD")
    ui.show_repositories()
    ui.show_languages()
    ui.begin_drag(ui.hud.node)
    assert(not reader.ui.options.visible and not ui.repository_panel.node.visible and not ui.language_panel.node.visible)
    ui.show_section("Home")
    assert(ui.nav_buttons["All Books"].visible and not ui.settings.sidebar.get_parent().visible)
    reader._response(JSON.stringify({"kind": "reader_filters", "enabled": true, "tint": 0x80402010, "hue": 45, "grayscale": true, "inverted": false, "brightness": -25}))
    var material: ShaderMaterial = reader.book.turning_material
    assert(material.get_shader_parameter("reader_grayscale") == true)
    assert(is_equal_approx(float(material.get_shader_parameter("reader_hue")), 45))
    assert(is_equal_approx(float(material.get_shader_parameter("reader_brightness")), 0.75))
    reader.queue_free()
    await process_frame
    print("PASS: shared settings controls, category sidebar, reachable centered popups, HUD minimization and reader filters")
    quit()
