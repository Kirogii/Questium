extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader._build_tracking()
    var tracker := XRControllerTracker.new()
    tracker.name = "left_hand"
    XRServer.add_tracker(tracker)
    tracker.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
    var original: Transform3D = reader.origin.global_transform
    for stick in [Vector2(0, 1), Vector2(0, -1)]:
        tracker.set_input("primary", stick)
        reader._locomotion(1.0)
        assert(reader.origin.global_transform.is_equal_approx(original), "Vertical stick targeting does not move the viewpoint without a trigger")
    reader.camera.position.x = 0.3
    var head_position: Vector3 = reader.camera.global_position
    tracker.set_input("primary", Vector2(1, 0))
    reader._locomotion(0.5)
    assert(is_equal_approx(reader.origin.rotation.y, -PI / 6.0), "Right stick deflection turns the view right")
    assert(reader.camera.global_position.is_equal_approx(head_position), "Turning pivots around the headset without moving it")
    assert(reader.locomotion_hand == "left", "Turning consumes the left stick instead of page controls")
    tracker.set_input("primary", Vector2(-1, 0))
    reader._locomotion(0.5)
    assert(reader.origin.global_transform.is_equal_approx(original), "Left deflection turns back")
    tracker.set_input("primary", Vector2(0.2, 0))
    reader._locomotion(0.5)
    assert(reader.origin.global_transform.is_equal_approx(original), "Deadzone prevents stick drift")
    reader.camera.rotation.y = 1.0
    reader.recenter()
    assert(reader.workspace.hud.node.global_basis.orthonormalized().is_equal_approx(reader.workspace.facing_basis()), "Recenter follows the user's heading at any HUD scale")
    assert(reader.origin.global_transform.is_equal_approx(original), "Recenter moves the GUI, not the world")
    XRServer.remove_tracker(tracker)
    reader.queue_free()
    await process_frame
    print("PASS: left stick turning, headset pivot, deadzone and GUI recenter")
    quit()
