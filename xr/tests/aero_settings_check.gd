extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.chapter_token = "settings-test"
    var book: SpatialBook = reader.book
    book.set_chapter(8)
    var thin: AABB = book.body_parts[0].mesh.get_aabb()
    book.set_hard_cover(true)
    var thick: AABB = book.body_parts[0].mesh.get_aabb()
    assert(thick.size.z > thin.size.z * 5 and thick.size.x > thin.size.x, "Hardcover uses thick overhanging boards")
    assert(book.body_parts[4].mesh is CylinderMesh, "Hardcover has a rounded bound spine")
    book.set_hard_cover(false)
    assert(book.body_parts[0].mesh.get_aabb().size.z < thick.size.z / 5, "Soft-cover geometry restores")
    reader.tracked["left"] = {"natural_hand": true}
    reader.ui.toggle(true)
    assert(reader.ui.palm_options_requested)
    var palm: Vector3 = reader.camera.global_position + Vector3(-0.15, -0.25, -0.5)
    reader.ui.update_palm_options(true, palm)
    assert(reader.ui.options.visible and reader.ui.options.global_position.y > palm.y + 0.2)
    reader.ui.update_palm_options(false, palm)
    assert(not reader.ui.options.visible and reader.ui.palm_options_requested, "Turning away hides without forgetting the open panel")
    reader.ui.update_palm_options(true, palm)
    assert(reader.ui.options.visible, "Returning the palm restores settings")
    reader.ui.close_options()
    reader.ui.update_palm_options(true, palm)
    assert(not reader.ui.options.visible, "Close remains closed")
    reader.ui.toggle(false)
    assert(not reader.ui.palm_options_requested, "Controller settings do not require a visible palm")
    var panel: Dictionary
    for candidate in reader.panels:
        if candidate.node == reader.ui.options: panel = candidate
    reader.ui.options_page = 0
    reader.ui.swipe_tabs(panel, Vector2(600, 50), true, false)
    assert(reader.ui.swipe_tabs(panel, Vector2(300, 55), true, true))
    reader.ui.swipe_tabs(panel, Vector2(300, 55), false, true)
    assert(reader.ui.options_page == 1, "Horizontal gesture selects next section")
    await process_frame
    reader.ui.swipe_tabs(panel, Vector2(300, 50), true, false)
    assert(not reader.ui.swipe_tabs(panel, Vector2(310, 230), true, true), "Vertical scroll must not switch sections")
    reader.ui.swipe_tabs(panel, Vector2(310, 230), false, true)
    assert(reader.ui.options_page == 1)
    reader.queue_free()
    await process_frame
    print("PASS: hardcover geometry, palm settings hide/restore/close, controller placement and swipe sections")
    quit()

