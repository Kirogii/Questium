extends SceneTree

var reader: Node3D
var hand: XRHandTracker

func _initialize() -> void:
    check.call_deferred()

func sample(point: Vector3, valid: bool = true, pinch: bool = false) -> void:
    hand.has_tracking_data = valid
    var world: Vector3 = reader.book.to_global(point)
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    for joint in [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_THUMB_TIP, XRHandTracker.HAND_JOINT_PALM]:
        hand.set_hand_joint_flags(joint, flags)
        var position := world + (Vector3.UP * (0.01 if pinch else 0.08) if joint == XRHandTracker.HAND_JOINT_THUMB_TIP else Vector3.ZERO)
        hand.set_hand_joint_transform(joint, Transform3D(Basis.IDENTITY, reader.origin.to_local(position)))
    reader._process(0.02)

func stroke(side: int, distance: float = 0.24) -> void:
    sample(Vector3(side * distance, 0, 0.08))
    sample(Vector3(side * (distance - 0.03), 0, 0.09))
    sample(Vector3(side * (distance - 0.07), 0, 0.10))

func reset() -> void:
    reader._cancel_interactions()
    reader.book.set_mode("book")
    reader.book.set_open(1)
    reader.book.rtl = false
    reader.book.seek(0)

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
    var texture := ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGB8))
    for i in range(8): reader.book.supply_page(i, texture)
    reader.book.global_transform = Transform3D(Basis.from_euler(Vector3(0.3, 0.6, 0.1)), Vector3(0, 1.2, -0.8)).scaled_local(Vector3.ONE * 1.5)
    hand = XRHandTracker.new()
    hand.name = "/user/hand_tracker/right"
    hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
    XRServer.add_tracker(hand)
    sample(Vector3(0.1, 0, 0.08))
    sample(Vector3(-0.1, 0, 0.08))
    assert(reader.book.turn_direction == 0, "A central hand movement cannot acquire a page")
    stroke(1)
    assert(reader.hand_page_turn.owner == "right" and reader.book.turning_leaf.visible, "Open-hand motion acquires the right page")
    assert(reader.holder.is_empty() and not reader.moving, "Sweeping never grabs or moves the book body")
    var other_tip: Vector3 = reader.book.to_global(Vector3(0, 0, 0.03))
    reader.hand_page_turn.update("left", other_tip, true, true, 0.02)
    reader._pointer("left", other_tip, Vector3.FORWARD, true, true)
    assert(reader.hand_page_turn.owner == "right" and reader.book.turn_direction == 1, "Other hand pinch cannot cancel a captured page")
    assert(reader.holder.is_empty(), "Other hand cannot steal the book during a page sweep")
    sample(Vector3(0.06, 0, 0.12))
    var curl: float = reader.book.turn_progress
    sample(Vector3(-0.06, 0, 0.12))
    assert(reader.book.turn_progress > curl and reader.book.turn_progress > 0.5, "The curl follows hand travel across the spine")
    sample(Vector3(-0.17, 0, 0.09))
    sample(Vector3(-0.23, 0, 0.08))
    await create_timer(0.35).timeout
    assert(reader.book.first_page == 2, "A completed sweep advances one spread")
    sample(Vector3(-0.17, 0, 0.08))
    sample(Vector3(-0.06, 0, 0.08))
    sample(Vector3(0.06, 0, 0.08))
    assert(reader.book.turn_direction == 0, "Return stroke cannot turn back until the hand leaves")
    sample(Vector3(0.24, 0, 0.08))
    sample(Vector3(0.21, 0, 0.09))
    sample(Vector3(0.17, 0, 0.10))
    assert(reader.book.turn_direction == 1, "Returning to the original edge re-arms the next forward sweep without a large lift")
    reset()
    stroke(1)
    sample(Vector3(0.1, 0, 0.08), false)
    assert(reader.book.turn_direction == 0 and reader.book.first_page == 0, "Tracking loss cancels without saving a new spread")
    reset()
    stroke(1)
    sample(Vector3(0.1, 0, 0.25))
    await create_timer(0.35).timeout
    assert(reader.book.first_page == 0, "Lifting before the midpoint settles back")
    reset()
    XRServer.remove_tracker(hand)
    hand.name = "/user/hand_tracker/left"
    XRServer.add_tracker(hand)
    stroke(1)
    assert(reader.hand_page_turn.owner == "left", "Either tracked hand can sweep a page")
    reader._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    assert(reader.hand_page_turn.owner.is_empty() and reader.book.turn_direction == 0, "Focus loss cancels the swept leaf")
    reset()
    stroke(1)
    reader.book.rtl = true
    reader._cancel_interactions()
    stroke(-1)
    assert(reader.book.turn_direction == 1, "RTL next page is acquired from the left")
    sample(Vector3(-0.06, 0, 0.10))
    sample(Vector3(0.06, 0, 0.10))
    sample(Vector3(0.17, 0, 0.08))
    sample(Vector3(0.23, 0, 0.08))
    await create_timer(0.35).timeout
    assert(reader.book.first_page == 2)
    reset()
    reader.book.set_preview(true)
    stroke(1)
    assert(reader.book.turn_direction == 0, "Cover preview does not accept page sweeps")
    reader.book.set_preview(false)
    reader.book.set_mode("scroll")
    stroke(1)
    assert(reader.hand_page_turn.owner.is_empty(), "Long strips retain their vertical scroll interaction")
    reset()
    sample(Vector3(0.24, 0, 0.08))
    sample(Vector3(-0.24, 0, 0.08))
    assert(reader.book.turn_direction == 0, "A tracking position jump cannot flip a page")
    XRServer.remove_tracker(hand)
    reader.queue_free()
    await process_frame
    print("PASS: real XR hand samples, tilted/resized book, continuous curl, midpoint settling, return-stroke guard, tracking loss, RTL, preview and long-strip exclusions")
    quit()
