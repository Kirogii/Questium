extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.tracked["right"] = {"pressed": false, "can_grab": true, "can_ui": false, "buttons": {"grip_click": true}}
    var start: Vector3 = reader.camera.global_position
    assert(reader.workspace.windows.size() == 1, "Remote controls use the single frosted HUD")
    var direction := Vector3.FORWARD
    reader._response(JSON.stringify({"kind": "chapter", "token": "remote", "count": 4, "start": 0, "title": "Remote"}))
    direction = (reader.book.global_position - start).normalized()
    reader._pointer("right", start, direction, true, true)
    assert(reader.holder == "right" and reader.moving, "Controller grip acquires the distant book body")
    var book_at_start: Vector3 = reader.book.global_position
    reader._pointer("right", start + Vector3.RIGHT * 0.1, direction, true, true)
    assert(reader.book.global_position.is_equal_approx(book_at_start + Vector3.RIGHT * 0.1), "Remote book movement preserves its offset")
    reader._pointer("right", start, direction, false, true)
    reader.book.hover_edge(reader.book.edge_bars[0].position)
    assert(reader.book.edge_bars[0].material_override.albedo_color != Color.WHITE, "Closed cover contact guide highlights on hover")
    var close: Vector3 = reader.book.to_global(reader.book.close_marker.position)
    reader._page_region(start, (close - start).normalized(), "right")
    assert(reader.chapter_token.is_empty() and not reader.book.visible, "Ray activates the per-book close control")
    reader.queue_free()
    await process_frame
    print("PASS: single HUD, remote body grabs, retained offsets, edge feedback and per-book ray close")
    quit()
