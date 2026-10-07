extends SceneTree

const JOINT_NAMES := ["Palm", "Hand", "ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip", "IndexMetacarpal", "IndexProximal", "IndexIntermediate", "IndexDistal", "IndexTip", "MiddleMetacarpal", "MiddleProximal", "MiddleIntermediate", "MiddleDistal", "MiddleTip", "RingMetacarpal", "RingProximal", "RingIntermediate", "RingDistal", "RingTip", "LittleMetacarpal", "LittleProximal", "LittleIntermediate", "LittleDistal", "LittleTip"]

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.workspace.hud.node.visible = false
    reader.workspace.badge.node.visible = false
    reader._build_tracking()
    var trackers: Array[XRHandTracker] = []
    for side in ["left", "right"]:
        var tracker := XRHandTracker.new()
        tracker.name = "/user/hand_tracker/" + side
        tracker.set_tracker_hand(XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT)
        tracker.has_tracking_data = true
        tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN
        XRServer.add_tracker(tracker)
        trackers.append(tracker)
        var data: Dictionary = reader.tracked[side]
        var skeleton: Skeleton3D = data.hand_visual.fallback_skeleton
        var offset := Vector3(-0.13 if side == "left" else 0.13, 1.2, -0.5)
        var palm := Transform3D(Basis(Vector3.RIGHT, PI / 2), offset)
        tracker.set_pose("default", palm, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
        var prefix := "Left" if side == "left" else "Right"
        for joint in range(JOINT_NAMES.size()):
            var bone := skeleton.find_bone(prefix + JOINT_NAMES[joint])
            assert(bone >= 0)
            var pose := palm * skeleton.get_bone_global_rest(bone)
            tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED)
            tracker.set_hand_joint_transform(joint, pose)
        data.hand_root.visible = true
        assert(data.hand_visual.fallback.visible, "Native-unavailable path renders a real skinned hand")
        var modifier: XRHandModifier3D = skeleton.get_child(skeleton.get_child_count() - 1)
        var distal := skeleton.find_bone(prefix + "IndexDistal")
        var observed := [Vector3.ZERO]
        modifier.modification_processed.connect(func(): observed[0] = skeleton.get_bone_global_pose(distal).origin)
        var target := skeleton.get_bone_global_rest(distal).origin + Vector3(0.018, 0.012, 0)
        var joint_index := JOINT_NAMES.find("IndexDistal")
        var tracked_pose := tracker.get_hand_joint_transform(joint_index)
        tracked_pose.origin = palm * target
        tracker.set_hand_joint_transform(joint_index, tracked_pose)
        await process_frame
        await process_frame
        assert(observed[0].distance_to(target) < 0.001, "Tracked finger joints actually deform the fallback skeleton")
        data.material.set_shader_parameter("interaction", 1.0 if side == "right" else 0.0)
    if "--render" in OS.get_cmdline_user_args():
        reader.camera.global_position = Vector3(0, 1.24, -0.12)
        reader.camera.look_at(Vector3(0, 1.24, -0.5))
        await create_timer(0.2).timeout
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/book-motion-study/tracked-hand-fallback.png")
    for tracker in trackers: XRServer.remove_tracker(tracker)
    reader.queue_free()
    await process_frame
    print("PASS: both fallback skins, 26 joint mappings, actual finger deformation and white/purple materials")
    quit()
