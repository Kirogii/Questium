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
    for stick in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
        tracker.set_input("primary", stick)
        reader._locomotion(1.0)
        assert(reader.origin.global_transform.is_equal_approx(original), "Sticks cannot move or turn the viewpoint")
    reader.camera.rotation.y = 1.0
    reader.recenter()
    assert(reader.workspace.hud.node.global_basis.is_equal_approx(reader.workspace.facing_basis()), "Recenter follows the user's heading")
    assert(reader.origin.global_transform.is_equal_approx(original), "Recenter moves the GUI, not the world")
    XRServer.remove_tracker(tracker)
    reader.queue_free()
    await process_frame
    print("PASS: seated viewpoint, disabled walking and snap turning, facing-based GUI recenter")
    quit()
