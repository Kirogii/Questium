extends SceneTree

var reader: Node3D
var hand: XRHandTracker

func _initialize() -> void:
    check.call_deferred()

func sample(point: Vector3, delta: float = 0.016, thumb_visible: bool = true) -> void:
    var world: Vector3 = reader.book.to_global(point)
    var palm_basis: Basis = reader.origin.global_basis.inverse() * reader.book.global_basis * Basis(Vector3.FORWARD, PI / 2)
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, flags)
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(palm_basis, reader.origin.to_local(world)))
    # Two reliably tracked fingers are enough; the others can be occluded
    # edge-on. Thumb is deliberately close enough to look like a pinch.
    for pair in [[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP], [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP]]:
        hand.set_hand_joint_flags(pair[0], flags)
        hand.set_hand_joint_flags(pair[1], flags)
        hand.set_hand_joint_transform(pair[0], Transform3D(Basis.IDENTITY, reader.origin.to_local(world)))
        hand.set_hand_joint_transform(pair[1], Transform3D(Basis.IDENTITY, reader.origin.to_local(world + reader.book.global_basis.y * 0.08)))
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_TIP, flags if thumb_visible else 0)
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP, hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP))
    reader._process(delta)

func reset() -> void:
    reader._cancel_interactions()
    reader.book.seek(0)
    reader.tracked.right.pressed = false

func check() -> void:
    reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader._build_tracking()
    reader.workspace.hud.node.visible = false
    reader.book.visible = true
    reader.book.set_preview(false)
    reader.book.set_chapter(8)
    reader.book.set_mode("book")
    reader.book.set_open(1)
    var texture := ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGB8))
    for i in range(8): reader.book.supply_page(i, texture)
    hand = XRHandTracker.new()
    hand.name = "/user/hand_tracker/right"
    hand.has_tracking_data = true
    hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
    XRServer.add_tracker(hand)
    var pose: Transform3D = reader.book.global_transform
    # Start inside the white bar, and use tiny per-frame travel. Previously
    # this started a curl but could not commit at the middle.
    sample(Vector3(0.25, 0, 0.12))
    for i in range(1, 21): sample(Vector3(0.25 - i * 0.004, 0, 0.12), 0.016, false)
    assert(reader.hand_page_turn.owner == "right" and reader.book.turn_progress > 0.10, "Occluded thumb and two fingers still curl the sheet continuously")
    reader.hand_page_turn.update("right", Vector3.ZERO, false, false, 0.02)
    assert(reader.hand_page_turn.owner == "right", "One missing tracking frame must not drop the curl")
    for i in range(21, 58): sample(Vector3(0.25 - i * 0.004, 0, 0.12), 0.016, false)
    await create_timer(0.35).timeout
    assert(reader.book.first_page == 2, "Slow chopping swipe commits at the center from a broad edge")
    reset()
    sample(Vector3(0.26, 0, 0.10))
    sample(Vector3(0.17, 0, 0.10), 0.02)
    await create_timer(0.35).timeout
    assert(reader.book.first_page == 2, "Fast short flick commits before the center even when thumb appears pinched")
    assert(reader.book.global_transform.is_equal_approx(pose), "Chopping never carries the book")
    reset()
    sample(Vector3(0.20, 0.23, 0.22), 0.08, false)
    sample(Vector3(0.16, 0.23, 0.22), 0.12, false)
    assert(reader.hand_page_turn.owner == "right", "Palm inside the bar and above the page edge still catches the sheet")
    sample(Vector3(0.02, 0.23, 0.22), 0.18, false)
    await create_timer(0.35).timeout
    assert(reader.book.first_page == 2, "Near-edge elevated chopping completes without exact bar alignment")
    reset()
    reader.book.set_mode("scroll")
    sample(Vector3(0.36, 0, 0.10))
    sample(Vector3(0.26, 0.01, 0.10), 0.02)
    assert(reader.book.first_page == 1, "Chopping takes precedence over the finger scroller in long mode")
    XRServer.remove_tracker(hand)
    reader.queue_free()
    await process_frame
    print("PASS: real chopping routing, broad edge, continuous slow curl, occluded thumb, tracking grace, fast partial flick, stationary book and long-mode priority")
    quit()
