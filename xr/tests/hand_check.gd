extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader._build_tracking()
    var hand := XRHandTracker.new()
    hand.name = "/user/hand_tracker/left"
    hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
    hand.has_tracking_data = true
    XRServer.add_tracker(hand)
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    for joint in [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_THUMB_TIP]:
        hand.set_hand_joint_flags(joint, flags)
        hand.set_hand_joint_transform(joint, Transform3D(Basis.IDENTITY, Vector3(float(joint) * 0.01, 1, -1)))
    reader._process(0.02)
    assert(not reader.tracked.left.has("fingers") and not reader.tracked.left.has("joints"), "Hand tracking never creates capsule placeholders")
    assert(reader.tracked.left.native_mesh, "The bundled vendor extension registers real hand meshes")
    assert(reader.tracked.left.hand_visual.fallback_skeleton.get_bone_count() == 26, "A complete skinned fallback exists before native mesh delivery")
    assert(reader.tracked.left.hand_root.visible, "Valid hand tracking reveals the skinned model")
    assert(not reader.tracked.left.grip.visible, "Controllers are hidden while real hands are tracked")
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, 0)
    reader._process(0.02)
    assert(reader.tracked.left.hand_root.visible, "A briefly occluded fingertip does not erase the tracked palm and hand")
    assert(not reader.tracked.left.valid, "Occluded fingertip cannot acquire interactions")
    hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN
    hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, flags)
    reader._process(0.02)
    assert(reader.tracked.left.hand_root.visible and reader.tracked.left.valid, "Unspecified runtime source still renders a valid tracked hand")
    hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
    reader._process(0.02)
    assert(not reader.tracked.left.hand_root.visible, "Controller-inferred hands cannot trigger natural hand gestures")
    hand.has_tracking_data = false
    reader._process(0.02)
    assert(not reader.tracked.left.hand_root.visible, "Tracking loss hides the skinned hand")
    XRServer.remove_tracker(hand)
    reader.queue_free()
    await process_frame
    print("PASS: native and skinned fallback models, unknown source, partial occlusion, controller exclusion and tracking loss")
    quit()
