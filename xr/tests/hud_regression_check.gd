extends SceneTree
class Bridge extends RefCounted:
    var requests: Array = []
    func request(value: String) -> void: requests.append(JSON.parse_string(value))
    func hideKeyboard(_field: String) -> void: pass
func _initialize() -> void: check.call_deferred()
func find_button(node: Node, text: String) -> Button:
    if node is Button and node.text == text: return node
    for child in node.get_children():
        var result := find_button(child, text)
        if result: return result
    return null
func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    var bridge := Bridge.new()
    reader.bridge = bridge
    ui.show_section("Home")
    for frame in 12: await process_frame
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        ui.hud.viewport.get_texture().get_image().save_png("E:/Questium-Build/logs/vr-fixed-hud.png")
    assert(ui.nav_buttons.size() == 9 and not ui.nav_buttons.has("Updates") and not ui.nav_buttons.has("More"))
    for nav in ui.nav_buttons.values():
        assert(nav.is_visible_in_tree() and nav.get_global_rect().end.y <= 900, "All original buttons fit without scrolling")
        assert(not nav.get_parent() is ScrollContainer)
    assert(ui.source_category_row.get_child_count() == 3)
    assert(not find_button(ui.source_category_row, "Search by tags"))
    ui.selected_source = "123"
    ui.native_source_filters = true
    ui.show_source_filters()
    assert(bridge.requests[-1].action == "source_filters", "Filters never opens manga browsing")
    ui.consume({"kind": "source_filters", "source": "123", "request_id": ui.filter_revision, "items": [{"key": "0", "type": "checkbox", "name": "Completed", "state": false}]})
    if DisplayServer.get_name() != "headless":
        for frame in 8: await process_frame
        await RenderingServer.frame_post_draw
        ui.source_filter_panel.viewport.get_texture().get_image().save_png("E:/Questium-Build/logs/vr-fixed-filters.png")
    ui.source_filter_body.get_child(0).button_pressed = true
    assert(ui.source_filters["0"])
    find_button(ui.source_filter_panel.content, "Reset").pressed.emit()
    assert(ui.source_filters.is_empty() and not ui.source_filter_body.get_child(0).button_pressed)
    ui.filter = "Updates"
    ui.show_section("Home")
    assert(bridge.requests[-1].action == "updates")
    ui.consume({"kind": "updates", "items": [
        {"id": "1", "title": "Older", "day": "2026-10-23", "update_chapter": "Chapter 1"},
        {"id": "2", "title": "Newer", "day": "2026-10-24", "update_chapter": "Chapter 8"},
        {"id": "1", "title": "Older", "day": "2026-10-24", "update_chapter": "Chapter 2"}
    ]})
    if DisplayServer.get_name() != "headless":
        for frame in 8: await process_frame
        await RenderingServer.frame_post_draw
        ui.hud.viewport.get_texture().get_image().save_png("E:/Questium-Build/logs/vr-fixed-updates.png")
    for frame in 8: await process_frame
    ui.refresh_visible_covers()
    for frame in 4: await process_frame
    assert(ui.gallery.get_child_count() == 5)
    assert(ui.gallery.get_child(0).text == "2026-10-24" and ui.gallery.get_child(3).text == "2026-10-23")
    assert(ui.cover_targets["1"].size() == 2)
    ui.hud.node.position = Vector3(2, 2, 2)
    var before: Vector3 = ui.hud.node.global_position
    ui.request_recenter()
    assert(ui.recenter_label.text == "3")
    ui.tick_recenter(1.0)
    assert(ui.recenter_label.text == "2" and ui.hud.node.global_position == before)
    ui.tick_recenter(1.0)
    assert(ui.recenter_label.text == "1" and ui.hud.node.global_position == before)
    ui.tick_recenter(1.0)
    assert(not ui.recenter_label.visible and ui.hud.node.global_position != before)
    ui.show_settings()
    ui.settings.select_tab(1)
    find_button(ui.gallery, "Recenter").pressed.emit()
    assert(ui.recenter_remaining == 3.0, "Settings recenter uses the same delayed action")
    reader.bridge = null
    reader.queue_free()
    await process_frame
    print("PASS fixed sidebar, options-only filters/reset, daily updates/covers, delayed 3-2-1 recenter")
    quit()
