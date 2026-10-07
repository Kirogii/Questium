extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.workspace.hud.node.visible = false
    reader.book.visible = true
    reader.book.set_preview(false)
    reader.book.set_chapter(8)
    reader.book.set_mode("book")
    reader.book.set_open(1)
    var hand := XRHandTracker.new()
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    # Palm normal points across the book; the fingers form the upright flat
    # hand shown in the user's front and side reference photos.
    var palm_basis: Basis = reader.origin.global_basis.inverse() * reader.book.global_basis * Basis(Vector3.FORWARD, PI / 2)
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(palm_basis, Vector3.ZERO))
    for pair in [[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP], [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP], [XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP]]:
        hand.set_hand_joint_flags(pair[0], flags)
        hand.set_hand_joint_flags(pair[1], flags)
        hand.set_hand_joint_transform(pair[0], Transform3D(Basis.IDENTITY, Vector3.ZERO))
        hand.set_hand_joint_transform(pair[1], Transform3D(Basis.IDENTITY, Vector3.UP * 0.08))
    assert(reader.hand_controls.edge_hand(hand), "The flat, upright reference pose uses palm-based swipes")
    var texture := ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGB8))
    for i in range(8): reader.book.supply_page(i, texture)
    var pose: Transform3D = reader.book.global_transform
    for fast in [false, true]:
        reader.hand_page_turn.cancel()
        reader.book.seek(0)
        var duration: float = 0.02 if fast else 0.12
        for x in ([0.305, 0.25, 0.15] if fast else [0.305, 0.25, 0.15, 0.03]):
            reader.hand_page_turn.update("right", reader.book.to_global(Vector3(x, 0, 0.06)), true, false, duration)
        await create_timer(0.35).timeout
        assert(reader.book.first_page == 2, "Slow bar-to-center and quick partial inward swipes each turn one spread")
        assert(reader.book.global_transform.is_equal_approx(pose), "Open-hand turning never moves the book")
    reader.hand_page_turn.cancel()
    reader.book.set_mode("scroll")
    reader.book.seek(0)
    reader.hand_page_turn.update("right", reader.book.to_global(Vector3(0.39, 0, 0.06)), true, false, 0.02)
    reader.hand_page_turn.update("right", reader.book.to_global(Vector3(0.26, 0, 0.06)), true, false, 0.02)
    assert(reader.book.first_page > 0, "A fast inward white-bar gesture also advances long mode")
    reader.queue_free()
    await process_frame
    print("PASS: reference flat-hand pose, slow bar-to-center and fast inward page turns, stationary book, long-mode bar swipe")
    quit()
