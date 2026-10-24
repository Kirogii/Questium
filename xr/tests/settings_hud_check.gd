extends SceneTree

class SettingsBridge extends RefCounted:
    var requests: Array = []
    func request(value: String) -> void:
        requests.append(JSON.parse_string(value))
    func hideKeyboard(_field: String) -> void:
        pass

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
        {"id": "d", "type": "text", "title": "Text", "value": "Saved"},
        {"id": "e", "type": "multi", "title": "Options", "value": ["a"], "keys": ["a", "b"], "entries": ["Automatic", "Manual"]}
    ]})
    assert(ui.section == "Settings" and ui.heading.text == "Reader")
    assert(ui.settings.sidebar.get_child_count() == 3 and ui.gallery.get_child_count() == 6)
    var toggle: CheckButton = ui.gallery.get_child(1).get_child(0).get_child(0).get_child(1)
    var slider: HSlider = ui.gallery.get_child(2).get_child(0).get_child(1)
    var choice: OptionButton = ui.gallery.get_child(3).get_child(0).get_child(0).get_child(1)
    var multi: CheckBox = ui.gallery.get_child(5).get_child(0).get_child(2)
    assert(toggle.text.is_empty() and toggle.has_theme_icon_override("checked"), "Native settings use the same right-aligned green switch as book settings")
    assert(choice.has_theme_stylebox_override("normal") and choice.get_popup().has_theme_stylebox_override("panel"), "Option pills and their popup lists both use the shared design")
    assert(multi.has_theme_icon_override("checked") and slider.has_theme_stylebox_override("slider"))
    var bridge := SettingsBridge.new()
    reader.bridge = bridge
    assert(ui.sync_to_main.button_pressed, "New library additions sync to main by default")
    ui.selected_manga = "123"
    ui.sync_to_main.button_pressed = false
    ui.save_to_library()
    assert(bridge.requests[-1].action == "favorite" and bridge.requests[-1].sync_to_main == false, "Unchecked choice adds the book locally")
    ui.sync_to_main.button_pressed = true
    ui.save_to_library()
    assert(bridge.requests[-1].sync_to_main == true, "Checked choice forwards the addition to main")
    toggle.button_pressed = false
    assert(bridge.requests[-1].id == "a" and bridge.requests[-1].value == false)
    slider.value = 80
    slider.drag_ended.emit(true)
    assert(bridge.requests[-1].id == "b" and bridge.requests[-1].value == 80)
    choice.item_selected.emit(0)
    assert(bridge.requests[-1].id == "c" and bridge.requests[-1].value == 0)
    multi.button_pressed = true
    assert(bridge.requests[-1].id == "e" and bridge.requests[-1].value == ["a", "b"], "Checkbox styling preserves multi-select values")
    reader.bridge = null
    if DisplayServer.get_name() != "headless":
        for frame in 10: await process_frame
        await RenderingServer.frame_post_draw
        ui.hud.viewport.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/uniform-native-settings.png")
        choice.show_popup()
        for frame in 4: await process_frame
        assert(choice.get_popup().visible)
        await RenderingServer.frame_post_draw
        ui.hud.viewport.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/uniform-option-popup.png")
        choice.get_popup().hide()
    reader.bridge = bridge
    ui.settings.select_tab(1)
    ui.settings.open_sync()
    assert(bridge.requests[-1].action == "questium_sync", "Sync page requests the backend state")
    ui.consume({"kind": "questium_sync", "enabled": true, "status": "Ready", "devices": [
        {"id": "phone", "name": "Phone", "main": true, "selected": true},
        {"id": "quest", "name": "Other Quest", "main": false, "selected": false}
    ]})
    assert(ui.heading.text == "Questium Sync")
    ui.settings.send_value({"id": "questium_sync:selected"}, ["phone", "quest"], false)
    assert(bridge.requests[-1].action == "questium_sync" and bridge.requests[-1].operation == "selected")
    assert(bridge.requests[-1].value == ["phone", "quest"], "Sync supports selecting multiple devices")
    ui.consume({"kind": "app_update", "version": "v1.0.1", "message": "New version on GitHub. Update now?"})
    assert(ui.app_updater.popup.node.visible, "A new release opens the startup update offer")
    if DisplayServer.get_name() != "headless":
        for frame in 4: await process_frame
        await RenderingServer.frame_post_draw
        ui.app_updater.popup.viewport.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/questium-update-offer.png")
    ui.app_updater.accept.pressed.emit()
    assert(bridge.requests[-1].action == "app_update_install", "Yes requests the download and installation")
    ui.consume({"kind": "app_update_status", "busy": true, "message": "Downloading 50%"})
    assert(ui.app_updater.accept.disabled, "Only one update download can start")
    var no: Button = ui.app_updater.accept.get_parent().get_child(1)
    no.pressed.emit()
    assert(not ui.app_updater.popup.node.visible and ui.hud.node.visible, "No returns to the app")
    reader.bridge = null
    assert(not ui.nav_buttons["All Books"].visible, "Settings categories replace library navigation")
    ui.place_settings()
    var popup: Vector3 = reader.ui.options.global_position
    var distance: float = popup.distance_to(reader.camera.global_position)
    assert(distance >= 0.379 and distance <= 0.561, "Book settings are at reachable distance")
    assert((ui.facing_basis().inverse() * (popup - reader.camera.global_position)).x > 0.20, "Book settings open to the right")
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
