extends Node3D

var hand := "left"
var material: ShaderMaterial
var native: Skeleton3D
var native_modifier: XRHandModifier3D
var fallback: Node3D
var fallback_skeleton: Skeleton3D
var native_ready := false
var native_unavailable := false

func _init(which: String = "left", appearance: ShaderMaterial = null) -> void:
    hand = which
    material = appearance

func _ready() -> void:
    fallback = load("res://hands/" + hand + ".gltf").instantiate()
    add_child(fallback)
    fallback_skeleton = _prepare_model(fallback)
    # The demo rig has no weighted palm bone; add an unweighted joint so the
    # modifier can map all 26 OpenXR joints without a missing-bone warning.
    var palm_name := ("Left" if hand == "left" else "Right") + "Palm"
    if fallback_skeleton.find_bone(palm_name) < 0:
        fallback_skeleton.add_bone(palm_name)
    var modifier := XRHandModifier3D.new()
    modifier.hand_tracker = "/user/hand_tracker/" + hand
    fallback_skeleton.add_child(modifier)
    if ClassDB.class_exists("OpenXRFbHandTrackingMesh"):
        native = ClassDB.instantiate("OpenXRFbHandTrackingMesh") as Skeleton3D
        native.set("hand", 0 if hand == "left" else 1)
        native.set("material", material)
        native.connect("openxr_fb_hand_tracking_mesh_ready", _native_ready)
        native.connect("openxr_fb_hand_tracking_mesh_unavailable", _native_unavailable)
        native_modifier = XRHandModifier3D.new()
        native_modifier.hand_tracker = "/user/hand_tracker/" + hand
        native.add_child(native_modifier)
        add_child(native)
        native.visible = native_ready

func _prepare_model(node: Node) -> Skeleton3D:
    var skeleton := node as Skeleton3D
    if node is MeshInstance3D:
        node.material_override = material
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        node.custom_aabb = AABB(Vector3(-0.3, -0.3, -0.3), Vector3(0.6, 0.6, 0.6))
    for child in node.get_children():
        var found := _prepare_model(child)
        if found: skeleton = found
    return skeleton

func _native_ready() -> void:
    var mesh: MeshInstance3D = native.call("get_mesh_instance")
    native_ready = is_instance_valid(mesh) and mesh.mesh != null and native.get_bone_count() > 0
    if not native_ready:
        _native_unavailable()
        return
    native_unavailable = false
    mesh.material_override = material
    mesh.custom_aabb = AABB(Vector3(-0.3, -0.3, -0.3), Vector3(0.6, 0.6, 0.6))
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # Refresh mappings after the asynchronously supplied skeleton is ready.
    native_modifier.hand_tracker = "/user/hand_tracker/" + hand
    native.visible = true
    fallback.visible = false
    print("VR hand mesh ready: ", hand, " bones=", native.get_bone_count())

func _native_unavailable() -> void:
    native_ready = false
    native_unavailable = true
    if native: native.visible = false
    fallback.visible = true
    print("VR hand mesh fallback: ", hand)

static func natural_tracking(tracker: XRHandTracker) -> bool:
    # UNKNOWN is valid on runtimes without the optional data-source extension.
    return tracker != null and tracker.has_tracking_data and tracker.hand_tracking_source != XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER

static func can_render(tracker: XRHandTracker) -> bool:
    if not natural_tracking(tracker): return false
    var position := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    return (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM) & position) != 0
