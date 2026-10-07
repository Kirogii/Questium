extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.camera.queue_free()
    reader.camera = XRCamera3D.new()
    reader.origin.add_child(reader.camera)
    reader._build_tracking()
    var head := XRPositionalTracker.new()
    head.name = "head"
    XRServer.add_tracker(head)
    reader.awaiting_head_pose = true
    reader._process(0.01)
    assert(reader.awaiting_head_pose, "Wait for a valid headset pose")
    var pose := Transform3D(Basis(Vector3.UP, 0.6), Vector3(1, 1.8, 2))
    head.set_pose("default", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
    var right := XRControllerTracker.new()
    right.name = "right_hand"
    XRServer.add_tracker(right)
    right.set_pose("aim", Transform3D(Basis.IDENTITY, Vector3(0.2, 1.5, 1.5)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
    right.set_pose("grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
    reader._process(0.01)
    assert(not reader.awaiting_head_pose)
    assert(reader.library_panel.global_position.is_equal_approx(pose.origin - pose.basis.z * reader.workspace.gui_distance), "HUD uses the latest tracked headset pose at the closer distance")
    assert(not reader.book.visible, "Startup waits for a selected book")
    assert(reader.tracked.right.controller.get_has_tracking_data(), "Use Godot's right_hand tracker and aim pose")
    assert(reader.tracked.right.ray.visible, "Tracked controller must show its pointer")
    reader.library_panel.visible = true
    right.set_input("trigger_click", true)
    assert(reader.ui.controller_input("right", reader.tracked.right.controller), "Trigger selects library entries")
    var left := XRControllerTracker.new()
    left.name = "left_hand"
    XRServer.add_tracker(left)
    left.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
    left.set_input("trigger_click", true)
    assert(reader.ui.controller_input("left", reader.tracked.left.controller), "Left trigger also selects library entries")
    assert(reader.tracked.left.can_ui, "Library interaction must not be blocked by reader hand preference")
    reader._response(JSON.stringify({"kind": "chapter", "token": "test", "count": 0, "start": 0, "title": "test"}))
    assert(reader.book.visible and not reader.library_panel.visible, "Chapter entry shows the physical reader")
    reader.toggle_library()
    assert(reader.library_panel.visible, "Library can reopen from reader mode")
    XRServer.remove_tracker(right)
    XRServer.remove_tracker(left)
    XRServer.remove_tracker(head)
    reader.queue_free()
    await process_frame
    print("PASS: tracked head placement, controller pointer, library trigger and reader transition")
    quit()
