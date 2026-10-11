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
    reader.tracked.right.was_fist = false
    var scroll_contact := book.to_global(Vector3(0.20, -0.35, 0.08))
    assert(reader._reader_at(scroll_contact) == book, "Scroll screen's visible lower interior is grabbable")
    assert(reader._reader_at(book.to_global(Vector3(0.5, 0, 0))) == null, "Outside scroll screen cannot acquire")
    var offset := book.scroll_offset
    reader._pointer("right", scroll_contact, Vector3.FORWARD, true, true)
    assert(reader.holder == "right" and reader.moving, "Clenching inside long-page screen carries its body")
    reader.tracked.right.was_fist = true
    var moved_contact := scroll_contact + Vector3(0.08, 0.12, 0)
    reader._pointer("right", moved_contact, Vector3.FORWARD, true, true)
    assert(book.to_global(Vector3(0.20, -0.35, 0.08)).distance_to(moved_contact) < 0.0001, "Scroll body follows captured palm contact")
    assert(is_equal_approx(book.scroll_offset, offset), "Carrying screen cannot scroll its content")
    var held := book.global_transform
    reader.tracked.right.fist = false
    reader._pointer("right", moved_contact, Vector3.FORWARD, true, true)
    assert(reader.holder.is_empty() and not reader.moving, "Opening a fist releases even if thumb and index still pinch")
    assert(book.global_transform.is_equal_approx(held), "Release preserves scroll screen pose")
    reader.tracked.right.pressed = false
    reader.tracked.right.was_fist = false
    reader.tracked.right.fist = true
    reader._pointer("right", moved_contact, Vector3.FORWARD, true, true)
    reader._pointer("right", moved_contact, Vector3.FORWARD, true, false)
    assert(reader.holder.is_empty(), "Tracking loss releases a carried scroll screen")
    reader.tracked.right.pressed = false
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
    assert(reader.ui.footer.get_child_count() == 2, "Close and recenter remain outside the scrolling content")
    reader.workspace.reading = true
    reader.recenter()
    assert(reader.workspace.hud.node.to_local(book.global_position).x > 1, "Recenter puts book beside HUD")
    reader._build_tracking()
    book.set_mode("scroll")
    book.visible = true
    reader.workspace.hud.node.visible = false
    var hand := XRHandTracker.new()
    hand.name = "/user/hand_tracker/right"
    hand.has_tracking_data = true
    hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
    var palm: Vector3 = reader.origin.to_local(book.to_global(Vector3(0.12, 0.12, 0.04)))
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis.IDENTITY, palm))
    for joint in [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
        # A clench can occlude the tips: valid inferred positions remain usable.
        hand.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
        hand.set_hand_joint_transform(joint, Transform3D(Basis.IDENTITY, palm + Vector3.UP * 0.03))
    XRServer.add_tracker(hand)
    reader._process(0.016)
    assert(reader.holder == "right" and reader.moving, "Real hand routing acquires scroll screen with valid occluded fingertip positions")
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, Transform3D(Basis.IDENTITY, palm + Vector3.UP * 0.10))
    reader._process(0.016)
    assert(reader.holder.is_empty(), "Real routing releases when fist opens even without tracked index tip")
    XRServer.remove_tracker(hand)
    reader.queue_free()
    await process_frame
    print("PASS: dual-corner resize, fingertip scrolling, fist grab isolation, long-title bounds and beside-HUD recenter")
    quit()
