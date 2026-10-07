extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var gui = reader.workspace
    gui.set_hud_scale(0.5)
    reader.recenter()
    assert(is_equal_approx(gui.hud.node.scale.x, 0.5))
    assert(is_equal_approx(gui.hud.node.global_position.distance_to(reader.camera.global_position), 0.62))
    assert(gui.enabled_languages == ["en"], "VR defaults to English only")
    gui.consume({"kind": "sources", "items": [{"id": "1", "title": "English", "lang": "en"}, {"id": "2", "title": "French", "lang": "fr"}]})
    assert(gui.picker_list.get_child_count() == 1 and gui.selected_source == "1")
    gui.enabled_languages.append("fr")
    gui.render_sources()
    assert(gui.picker_list.get_child_count() == 2)
    gui.enabled_languages = ["fr"]
    gui.ensure_source_language()
    assert(gui.selected_source == "2", "Disabled-language source cannot remain selected")
    gui.enabled_languages = ["en"]
    var top_left: Vector3 = gui.hud.node.to_global(Vector3(-gui.hud.size.x * 0.5, gui.hud.size.y * 0.5, 0))
    var top_right: Vector3 = gui.hud.node.to_global(Vector3(gui.hud.size.x * 0.5, gui.hud.size.y * 0.5, 0))
    var at: Vector3 = gui.hud.node.global_position
    assert(reader.hand_controls.resize_hud("left", top_left, true, true))
    assert(reader.hand_controls.resize_hud("right", top_right, true, true))
    reader.hand_controls.resize_hud("right", top_right + Vector3.RIGHT * 0.2, true, true)
    assert(gui.hud_scale > 0.5 and gui.hud.node.global_position.is_equal_approx(at), "HUD corners resize without moving the panel")
    reader.hand_controls.cancel()
    gui.set_hud_scale(0.5)
    reader.camera.rotation.y = 0.9
    var fixed_hud: Transform3D = gui.hud.node.global_transform
    var fixed_book: Transform3D = reader.book.global_transform
    for i in range(100): reader._process(0.02)
    assert(gui.hud.node.global_transform.is_equal_approx(fixed_hud), "Turning away never automatically recenters the HUD")
    assert(reader.book.global_transform.is_equal_approx(fixed_book), "Turning away never automatically recenters the book")
    reader.camera.rotation = Vector3.ZERO
    reader.recenter()
    var tracker := XRHandTracker.new()
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    var palm := Vector3(-0.25, 1.2, -0.3)
    tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis.IDENTITY, palm))
    for joint in [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
        tracker.set_hand_joint_flags(joint, flags)
        tracker.set_hand_joint_transform(joint, Transform3D(Basis.IDENTITY, palm + Vector3(0.02, 0.025, 0)))
    for joint in [XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_TIP]: tracker.set_hand_joint_flags(joint, flags)
    tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, Transform3D(Basis.IDENTITY, palm + Vector3(0.02, 0, 0)))
    tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP, Transform3D(Basis.IDENTITY, palm + Vector3(0.02, 0.05, 0)))
    assert(reader.hand_controls.thumb_up(tracker))
    reader.hand_controls.joystick("right", tracker, true, 0.1)
    reader.hand_controls.joystick("right", tracker, true, 0.1)
    var before := float(gui.gui_distance)
    palm.z += 0.08
    tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis.IDENTITY, palm))
    # Move all joints as one fist, preserving its shape.
    for joint in [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP, XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_TIP]:
        var pose := tracker.get_hand_joint_transform(joint)
        pose.origin.z += 0.08
        tracker.set_hand_joint_transform(joint, pose)
    reader.hand_controls.joystick("right", tracker, true, 0.02)
    assert(gui.gui_distance < before, "Thumb-up fist pulled toward the head brings GUI closer")
    reader.hand_controls.cancel()
    reader._build_tracking()
    assert(reader.tracked.right.grip != null, "Native controllers have a tracked grip root")
    if ClassDB.class_exists("OpenXRFbRenderModel"):
        assert(reader.tracked.right.grip.get_child_count() > 0, "Native controller render model is registered")
    tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, flags)
    tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, flags)
    tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST, Transform3D(Basis.IDENTITY, Vector3.ZERO))
    tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.04)))
    var direction: Vector3 = reader.hand_controls.forward(tracker)
    tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
    assert(direction.is_equal_approx(reader.hand_controls.forward(tracker)), "Curling index finger cannot lift the hand-forward ray")
    reader.queue_free()
    await process_frame
    print("PASS: closer half-size HUD, language filters, panel resizing, manual-only recentering, thumb-up distance gesture, controller visuals and stable hand-forward aim")
    quit()
