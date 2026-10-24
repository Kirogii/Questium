extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    for panel in reader.panels: panel.node.visible = false
    reader._build_tracking()
    var book: SpatialBook = reader.book
    book.visible = true
    book.set_preview(false)
    book.set_chapter(2)
    book.set_mode("scroll")
    var texture := ImageTexture.create_from_image(Image.create(100, 500, false, Image.FORMAT_RGB8))
    book.supply_page(0, texture)
    book.supply_page(1, texture)
    var hand := XRHandTracker.new()
    hand.name = "/user/hand_tracker/right"
    hand.has_tracking_data = true
    hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
    XRServer.add_tracker(hand)
    # A flat hand also satisfies edge/chopping detection. Vertical contact must
    # still scroll, including Quest's VALID inferred positions without TRACKED.
    pose(reader, hand, Vector3(0.10, -0.10, 0.025))
    reader._process(0.016)
    assert(reader.tracked.right.chopping, "Fixture must reproduce the overlapping chopping pose")
    pose(reader, hand, Vector3(0.10, 0.05, 0.025))
    reader._process(0.016)
    assert(reader.hand_controls.scroll_owner == "right")
    assert(book.scroll_offset > 0.14, "Fast inferred fingertip swipe must scroll through real gesture routing")
    var before: float = book.scroll_offset
    # Once captured, brief index extension classification jitter cannot drop it.
    reader.tracked.right.finger_extended = false
    assert(reader.hand_controls.swipe("right", book.to_global(Vector3(0.10, 0.10, 0.025)), true, false, 0.016))
    assert(book.scroll_offset > before)
    assert(not reader.hand_controls.swipe("left", book.to_global(Vector3(0.1, 0.1, 0.025)), true, false, 0.016), "Other hand cannot steal capture")
    before = book.scroll_offset
    reader.hand_controls.swipe("right", book.to_global(Vector3(0.1, 0.3, 0.025)), true, false, 0.3)
    assert(is_equal_approx(book.scroll_offset, before), "Frame stalls must not scroll stale travel")
    assert(not reader.hand_controls.swipe("right", book.to_global(Vector3(0.1, 0.3, 0.025)), false, false, 0.016))
    assert(reader.hand_controls.scroll_owner.is_empty(), "Invalid tracking releases capture")
    reader.tracked.right.finger_extended = true
    reader.ui_owner = "left"
    assert(not reader.hand_controls.swipe("right", book.to_global(Vector3(0.1, 0.3, 0.025)), true, false, 0.016), "UI capture keeps priority")
    reader.ui_owner = ""
    reader.hand_controls.swipe("right", book.to_global(Vector3(0.1, 0.2, 0.025)), true, false, 0.016)
    before = book.scroll_offset
    assert(reader.hand_controls.swipe("right", book.to_global(Vector3(0.16, 0.1, 0.025)), true, false, 0.016))
    assert(book.scroll_offset < before, "A downward diagonal phone swipe follows the finger")
    reader.hand_controls.cancel()
    reader.hand_controls.swipe("right", book.to_global(Vector3(0, 0.2, 0.025)), true, false, 0.016)
    before = book.scroll_offset
    assert(not reader.hand_controls.swipe("right", book.to_global(Vector3(0.15, 0.21, 0.025)), true, false, 0.016))
    assert(is_equal_approx(book.scroll_offset, before), "Mostly horizontal motion must not scroll")
    XRServer.remove_tracker(hand)
    reader.queue_free()
    await process_frame
    print("PASS: longpage fast fingertip swipes, chopping overlap, inferred positions, capture stability and cancellation")
    quit()

func pose(reader: Node3D, hand: XRHandTracker, point: Vector3) -> void:
    var tip: Vector3 = reader.origin.to_local(reader.book.to_global(point))
    var basis: Basis = reader.origin.global_basis.inverse() * reader.book.global_basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5)
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID
    var palm := tip - Vector3.UP * 0.10
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, flags)
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(basis, palm))
    for pair in [[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP], [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP], [XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP], [XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]]:
        hand.set_hand_joint_flags(pair[0], flags)
        hand.set_hand_joint_transform(pair[0], Transform3D(basis, palm))
        hand.set_hand_joint_flags(pair[1], flags)
        hand.set_hand_joint_transform(pair[1], Transform3D(basis, tip))
