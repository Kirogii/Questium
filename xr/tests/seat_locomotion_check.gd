extends SceneTree

func _initialize() -> void:
    call_deferred("check")

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    assert(reader.room.get_seat_points().size() > 0, "bar exposes seat targets")
    for seat in reader.room.get_seat_points():
        assert(seat.get_meta("target_kind") == "seat")
        assert(float(seat.get_meta("seat_height")) > reader.room.floor_y)
        assert(float(seat.get_meta("reach_radius")) > 0.0)
    var original_camera: Camera3D = reader.camera
    var original_origin: XROrigin3D = reader.origin
    reader._set_locomotion_target(reader.room.get_seat_points()[0])
    assert(reader.locomotion_circle.visible, "seat hover renders a target circle")
    assert(is_instance_valid(original_camera) and is_instance_valid(original_origin), "XR camera and origin remain intact")
    reader.tracked.clear()
    var seat_y: float = reader.locomotion_circle.global_position.y - 0.012
    reader._commit_locomotion_target()
    assert(is_equal_approx(reader.camera.global_position.y, seat_y + 0.80), "Seated eye height is above the cushion")
    var floor_target := Vector3(-2.0, reader.room.floor_y, 1.0)
    reader._set_locomotion_target_position(floor_target, "floor", reader.room.floor_y)
    reader._commit_locomotion_target()
    assert(reader.camera.global_position.is_equal_approx(floor_target + Vector3.UP * reader.standing_eye_height), "Floor marker commits and restores standing height")
    reader._calibrate_player_height(1.5)
    assert(is_equal_approx(reader.standing_eye_height, 1.725), "Standing camera is fifteen percent above tracked height")
    assert(is_equal_approx(reader.origin.position.y, reader.room.floor_y + 0.225), "Height adjustment offsets the origin above the floor")
    assert(reader.origin.scale == Vector3.ONE)
    assert(not reader.seated, "Standing startup keeps the existing height mode")
    reader._calibrate_player_height(1.1)
    assert(reader.seated, "Low tracked eye height selects seated startup")
    assert(is_equal_approx(reader.standing_eye_height, 1.725), "Seated startup raises the view to comfortable reading height")
    assert(is_equal_approx(reader.origin.position.y, reader.room.floor_y + 0.625), "Seated lift translates the origin and tracked hands together")
    assert(reader.origin.scale == Vector3.ONE)
    reader._calibrate_player_height(1.5)
    reader.workspace.hud.node.visible = true
    reader.ui.options.visible = false
    var controller := XRControllerTracker.new()
    controller.name = "left_hand"
    XRServer.add_tracker(controller)
    controller.set_pose("aim", Transform3D(Basis.looking_at(Vector3(0, -1, -1).normalized()), Vector3(-2, 1, 1)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
    controller.set_input("primary", Vector2(0, 1))
    controller.set_input("trigger_click", false)
    await physics_frame
    reader._locomotion(0.016)
    assert(reader.locomotion_circle.visible and reader.locomotion_target_kind == "floor", "Joystick ray finds the floor while the HUD remains visible")
    var before: Vector3 = reader.origin.global_position
    controller.set_input("trigger_click", true)
    reader._locomotion(0.016)
    assert(reader.origin.global_position.distance_to(before) > 0.1, "Trigger commits a floor target through controller input")
    var aim_start: Vector3 = reader.workspace.hud.node.global_position + reader.workspace.hud.node.global_basis.z * 0.4
    var aim_direction: Vector3 = -reader.workspace.hud.node.global_basis.z
    var ui_aim := Transform3D(Basis.looking_at(aim_direction), aim_start)
    controller.set_pose("aim", reader.origin.global_transform.affine_inverse() * ui_aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
    reader._locomotion(0.016)
    assert(not reader.locomotion_circle.visible and reader.locomotion_hand.is_empty(), "Aiming at the HUD keeps its joystick/trigger controls instead of teleporting")
    XRServer.remove_tracker(controller)
    reader.queue_free()
    await process_frame
    print("PASS: seat metadata and hover circle")
    quit()
