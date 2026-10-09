extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.chapter_token = "palm-test"
    var palm := Vector3(0.2, 1.0, -0.45)
    assert(not reader.toolbar.visible, "Toolbar starts hidden")
    reader._palm_toolbar(true, palm, 0.1)
    assert(not reader.toolbar.visible, "Short palm glance does not flicker the menu")
    reader._palm_toolbar(true, palm, 0.1)
    assert(reader.toolbar.visible and reader.toolbar.global_position.is_equal_approx(palm + Vector3.UP * 0.06), "Dwell reveals menu above palm without flying in")
    reader._palm_toolbar(false, palm, 0.2)
    assert(not reader.toolbar.visible, "Turning the palm away hides the menu immediately")
    reader.ui_capture = {"panel": reader.panels[0], "pixel": Vector2.ZERO}
    var captured_pose: Transform3D = reader.toolbar.global_transform
    reader.ui_owner = "right"
    reader._palm_toolbar(false, palm + Vector3.RIGHT, 0.5)
    assert(not reader.toolbar.visible, "Captured selection must not keep an averted palm menu visible")
    reader.ui_capture.clear()
    reader.ui_owner = ""
    reader._palm_toolbar(false, palm, 0.5)
    assert(not reader.toolbar.visible, "Menu hides after capture and grace end")
    reader.ui.perform("Book Options")
    reader._palm_toolbar(false, Vector3.ZERO, 0.1)
    assert(reader.toolbar.visible, "Controller menu reveals the toolbar without hands")
    reader.tracked["left"] = {"natural_hand": true}
    reader._palm_toolbar(true, palm, 0.2)
    assert(reader.toolbar.global_position.is_equal_approx(palm + Vector3.UP * 0.06), "Forced controller menu cannot detach seeker from a tracked hand")
    reader._palm_toolbar(false, palm, 0.2)
    assert(not reader.toolbar.visible, "Forced menu cannot leave seeker at the bottom of vision during hand tracking")
    var hand := XRHandTracker.new()
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    var hand_position: Vector3 = reader.camera.global_position - reader.camera.global_basis.z * 0.4
    var normal: Vector3 = reader.camera.global_position - hand_position
    var hand_basis := Basis.looking_at(normal).rotated(Vector3.RIGHT, -PI / 2)
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, flags)
    var face_pose := Transform3D(reader.origin.global_basis.inverse() * hand_basis, reader.origin.to_local(hand_position))
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, face_pose)
    for pair in [[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP], [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP]]:
        hand.set_hand_joint_flags(pair[0], flags)
        hand.set_hand_joint_flags(pair[1], flags)
        hand.set_hand_joint_transform(pair[0], Transform3D(Basis.IDENTITY, Vector3.ZERO))
        hand.set_hand_joint_transform(pair[1], Transform3D(Basis.IDENTITY, Vector3.UP * 0.08))
    assert(reader.hand_controls.seeker_facing(hand), "Open chopping hand facing the user reveals seeker even with missing thumb")
    var rotated := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
    var palm_basis := rotated.basis
    rotated.basis = palm_basis.rotated(Vector3.UP, PI)
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, rotated)
    assert(not reader.hand_controls.seeker_facing(hand), "Back of hand toward the face must never reveal the seeker")
    rotated.basis = rotated.basis.rotated(Vector3.UP, PI / 2)
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, rotated)
    assert(not reader.hand_controls.seeker_facing(hand), "Edge-on hand turned away does not reveal seeker")
    hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, face_pose)
    # A valid-but-not-currently-tracked pose is common for one Quest frame;
    # the seeker gate accepts it without weakening the signed palm check.
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
    for pair in [[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP], [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP]]:
        hand.set_hand_joint_flags(pair[0], XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
        hand.set_hand_joint_flags(pair[1], XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
    assert(reader.hand_controls.seeker_facing(hand), "Valid palm pose survives a transient tracking-bit change")
    reader._palm_toolbar(true, palm, 0.06)
    reader._palm_toolbar(false, palm, 0.02)
    reader._palm_toolbar(true, palm, 0.06)
    assert(reader.toolbar.visible, "A one-frame pose dropout does not lose reveal dwell")
    reader._palm_toolbar(false, palm, 0.2)
    assert(not reader.toolbar.visible, "A sustained averted palm hides the seeker")
    reader.queue_free()
    await process_frame
    print("PASS: palm dwell, attachment, grace, captured stability and controller reveal")
    quit()
