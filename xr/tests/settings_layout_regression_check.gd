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

func capture(viewport: SubViewport, name: String) -> void:
    if "--capture" not in OS.get_cmdline_user_args(): return
    for frame in 8: await process_frame
    await RenderingServer.frame_post_draw
    viewport.get_texture().get_image().save_png("E:/Questium-Build/logs/" + name + ".png")

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    var bridge := Bridge.new()
    reader.bridge = bridge
    ui.source_category_row.visible = true
    ui.show_settings()
    assert(not ui.source_category_row.visible, "Source filter controls cannot leak into Settings")
    var categories: Array = []
    for index in 18: categories.append({"id": index, "title": "Category " + str(index)})
    ui.consume({"kind": "settings", "title": "Appearance", "categories": categories, "category": 0, "items": []})
    await process_frame
    assert(ui.settings.sidebar_scroll.is_visible_in_tree(), "Settings category list must be visible")
    assert(ui.settings.sidebar.get_child_count() == 19, "All backend settings categories remain reachable")
    assert(ui.settings.sidebar_scroll.size.y > 200, "Category scrolling area gets real height")
    await capture(ui.hud.viewport, "settings-category-layout")
    ui.settings.select_tab(1)
    assert(ui.settings.sidebar_scroll.is_visible_in_tree())
    ui.settings.select_tab(0)
    assert(ui.settings.sidebar.get_child_count() == 19)
    ui.settings.open_backend("more")
    ui.consume({"kind": "settings_detail", "scope": "backend", "title": "More", "items": [
        {"id": "download", "type": "action", "title": "Downloads", "x": 850, "y": 1400, "width": 2, "height": 2},
        {"id": "checked", "type": "switch", "title": "Example switch", "value": true, "x": 0, "y": 0, "width": 1, "height": 1},
        {"id": "scroll", "type": "scroll"}
    ]})
    await process_frame
    var action: Button
    var toggle: CheckButton
    for control in descendants(ui.settings.details_list):
        if control is Button and control.text == "Downloads": action = control
        if control is CheckButton: toggle = control
    assert(action != null and action.custom_minimum_size.y >= 64, "Phone pixel bounds cannot shrink VR controls")
    assert(action.scale == Vector2.ONE and action.size.x > 200, "Semantic controls use responsive full width layout")
    assert(toggle != null and toggle.button_pressed)
    await capture(ui.settings.details.viewport, "more-popup-controls")
    action.pressed.emit()
    assert(bridge.requests[-1].action == "settings_semantic" and bridge.requests[-1].id == "download")
    toggle.button_pressed = false
    assert(bridge.requests[-1].id == "checked" and bridge.requests[-1].value == false)
    ui.show_section("Home")
    assert(not ui.settings.sidebar_scroll.visible and not ui.settings.tabs.visible)
    ui.show_settings()
    assert(ui.settings.sidebar_scroll.is_visible_in_tree() and ui.settings.tabs.is_visible_in_tree())
    reader.bridge = null
    print("PASS settings categories, responsive native popup cards and semantic actions")
    reader.queue_free()
    await process_frame
    quit()
