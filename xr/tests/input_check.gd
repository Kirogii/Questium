extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.book.visible = true
    var panel: Dictionary = reader.panels[0]
    panel.node.visible = true
    var aim: Vector3 = panel.node.global_position
    var start: Vector3 = reader.camera.global_position
    assert(reader._panel_input(start, (aim - start).normalized(), true, false))
    assert(not reader.ui_capture.is_empty(), "A press must capture the panel")
    reader._panel_input(start, Vector3.UP, false, true)
    assert(reader.ui_capture.is_empty(), "Release outside the panel must clear its captured press")
    reader.tracked["right"] = {"pressed": true}
    var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    var texture := ImageTexture.create_from_image(image)
    reader.book.set_chapter(4)
    for page in range(4):
        reader.book.supply_page(page, texture)
    assert(reader.book.begin_turn(1))
    reader.holder = "right"
    reader._pointer("right", Vector3.ZERO, Vector3.FORWARD, true, false)
    assert(reader.holder.is_empty())
    assert(reader.book.begin_turn(1))
    reader._cancel_interactions()
    assert(reader.book.turn_direction == 0, "Losing application focus cancels a turn")
    assert(reader.book.turn_direction == 0, "Tracking loss must cancel a physical page grab")
    reader.tracked["right"].pressed = false
    var spine: Vector3 = reader.book.global_position
    var original_basis: Basis = reader.book.global_basis
    reader._pointer("right", spine, Vector3.FORWARD, true, true)
    assert(reader.moving, "Pinching the spine grabs the book")
    var rotation := Basis(Vector3.UP, 0.3)
    reader._pointer("right", spine + Vector3(0.1, 0.0, 0.0), Vector3.FORWARD, true, true, rotation)
    assert(reader.book.global_position.is_equal_approx(spine + Vector3(0.1, 0.0, 0.0)))
    assert(reader.book.global_basis.is_equal_approx(rotation * original_basis), "Held book follows wrist rotation")
    reader._pointer("right", spine, Vector3.FORWARD, false, true)
    assert(reader.holder.is_empty())
    reader.tracked["left"] = {"pressed": false}
    var scale_pose: Vector3 = reader.book.global_position
    reader._pointer("right", scale_pose, Vector3.FORWARD, true, true)
    reader._pointer("left", scale_pose + Vector3(0.2, 0, 0), Vector3.FORWARD, true, true)
    reader._pointer("left", scale_pose + Vector3(0.4, 0, 0), Vector3.FORWARD, true, true)
    assert(is_equal_approx(reader.book.scale.x, 2.0), "Two hands resize using their separation")
    var scaled_pose: Vector3 = reader.book.global_position
    reader._pointer("right", scale_pose, Vector3.FORWARD, true, true)
    assert(reader.book.global_position.is_equal_approx(scaled_pose), "First hand cannot overwrite the two-hand midpoint")
    reader._pointer("left", scale_pose + Vector3(0.4, 0, 0), Vector3.FORWARD, false, true)
    reader._pointer("right", scale_pose, Vector3.FORWARD, true, true)
    assert(reader.book.global_position.is_equal_approx(scaled_pose), "Releasing the second hand does not jump the book")
    reader._cancel_interactions()
    reader.book.scale = Vector3.ONE
    var corner: Vector3 = reader.book.to_global(Vector3(SpatialBook.PAGE_WIDTH * 0.9, -0.18, 0.02))
    reader._pointer("right", corner, Vector3.FORWARD, true, true)
    assert(reader.holder == "right" and reader.book.grabbed, "Lower outer corner captures a page")
    assert(not reader.moving, "Page corner must not acquire the book body")
    reader._cancel_interactions()
    reader.book.set_open(0.0)
    reader.tracked.right.pressed = false
    corner = reader.book.to_global(Vector3(SpatialBook.PAGE_WIDTH * 0.9, -0.18, 0.02))
    reader._pointer("right", corner, Vector3.FORWARD, true, true)
    assert(reader.book.cover_dragged and not reader.moving, "Closed lower corner captures the cover")
    reader.queue_free()
    print("PASS: UI pointer capture, out-of-panel release, tracking-loss cancellation")
    quit()
