extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.tracked = {"left": {"pressed": false, "natural_hand": true}, "right": {"pressed": false, "natural_hand": true}}
    reader.workspace.hud.node.visible = false
    var book: SpatialBook = reader.book
    book.visible = true
    book.set_preview(false)
    book.set_mode("book")
    book.set_open(1)
    var pose := book.global_transform
    var left := book.to_global(Vector3(-0.28, 0.2, 0.02))
    var right := book.to_global(Vector3(0.28, 0.2, 0.02))
    assert(reader.hand_controls.resize("left", left, true, true))
    assert(book.global_transform.is_equal_approx(pose), "One corner alone cannot resize or move the book")
    assert(reader.hand_controls.resize("right", right, true, true))
    right += book.global_basis.x.normalized() * 0.15
    reader.hand_controls.resize("right", right, true, true)
    assert(book.scale.x > 1.1, "Opposite top corners resize the physical book")
    var resized := book.global_transform
    reader.hand_controls.resize("left", left, true, false)
    assert(book.global_transform.is_equal_approx(resized), "Releasing a resize preserves placement")
    reader.hand_controls.cancel()
    book.set_mode("scroll")
    assert(not reader.hand_controls.resize("right", right, true, true), "Long scroll windows cannot corner-resize")
    book.set_chapter(2)
    book.set_mode("scroll")
    var image := Image.create(100, 500, false, Image.FORMAT_RGB8)
    var texture := ImageTexture.create_from_image(image)
    book.supply_page(0, texture)
    book.supply_page(1, texture)
    var start := book.to_global(Vector3(0.1, -0.1, 0.025))
    reader.hand_controls.swipe("right", start, true, false, 0.016)
    var finish := book.to_global(Vector3(0.1, 0, 0.025))
    assert(reader.hand_controls.swipe("right", finish, true, false, 0.016))
    assert(book.scroll_offset > 0, "Light upward fingertip swipe scrolls content")
    reader.tracked.right.fist = true
    assert(not reader.hand_controls.swipe("right", finish, true, false, 0.016), "Fist grabs cannot scroll")
    book.set_mode("book")
    reader.tracked.right.pressed = false
    var contact := book.to_global(Vector3(0.1, 0, 0.02))
    reader._pointer("right", contact, Vector3.FORWARD, true, true)
    assert(reader.moving, "Fist carries book body")
    reader._cancel_interactions()
    reader.tracked.right.fist = false
    reader._pointer("right", contact, Vector3.FORWARD, true, true)
    assert(not reader.moving, "A small interior pinch does not grab the body")
    reader._cancel_interactions()
    reader.title.text = "Very long manga title ".repeat(50)
    reader.ui.show_book()
    await process_frame
    assert(reader.ui.options_title.size.y < 100, "Long title remains bounded")
    assert(reader.ui.footer.get_child_count() == 2, "Book actions remain outside the scrolling settings")
    reader.workspace.reading = true
    reader.recenter()
    assert(reader.workspace.hud.node.to_local(book.global_position).x > 1, "Recenter puts book beside HUD")
    reader.queue_free()
    await process_frame
    print("PASS: dual-corner resize, fingertip scrolling, fist grab isolation, long-title bounds and beside-HUD recenter")
    quit()
