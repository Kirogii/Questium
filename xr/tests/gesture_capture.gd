extends SceneTree

# Render tutorial demonstrations with the shipped skin and real book geometry.
# Python adds typography and motion cues; these are not headset recordings.
const FRAMES := 84
const SIZE := Vector2i(900, 540)
var output := "D:/VR Kommiku/artifacts/docs-media"
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var hand: Node3D
var rig: Skeleton3D
var upright: Basis
var book: SpatialBook
var panel: MeshInstance3D
var panel_view: SubViewport
var action: Button
var contact: MeshInstance3D
var motion_data: Array = []

func _initialize() -> void:
    capture.call_deferred()

func ramp(t: float, start: float, end: float) -> float:
    return smoothstep(0.0, 1.0, clampf((t - start) / (end - start), 0, 1))

func find_rig(node: Node) -> Skeleton3D:
    if node is Skeleton3D: return node
    for child in node.get_children():
        var found := find_rig(child)
        if found: return found
    return null

func set_skin(node: Node, material: Material) -> void:
    if node is MeshInstance3D:
        node.material_override = material
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for child in node.get_children(): set_skin(child, material)

func bend(name: String, amount: float, axis: Vector3 = Vector3.RIGHT) -> void:
    var bone := rig.find_bone("Right" + name)
    var rest := rig.get_bone_rest(bone).basis.get_rotation_quaternion()
    rig.set_bone_pose_rotation(bone, rest * Quaternion(axis, amount))

func finger(name: String, amount: float) -> void:
    bend(name + "Proximal", -amount * 1.25)
    bend(name + "Intermediate", -amount * 1.50)
    bend(name + "Distal", -amount * 0.85)

func tip(name: String) -> Vector3:
    return rig.global_transform * rig.get_bone_global_pose(rig.find_bone("Right" + name + "Tip")).origin

# CCD keeps the thumb and index tips in contact instead of merely curling them.
func reach(name: String, target: Vector3) -> void:
    var end := rig.find_bone("Right" + name + "Tip")
    var target_local := rig.global_transform.affine_inverse() * target
    for iteration in range(32):
        for suffix in ["Distal", "Intermediate", "Proximal", "Metacarpal"]:
            var bone := rig.find_bone("Right" + name + suffix)
            if bone < 0: continue
            var pose := rig.get_bone_global_pose(bone)
            var current := rig.get_bone_global_pose(end).origin - pose.origin
            var desired := target_local - pose.origin
            if current.length() < 0.0001 or desired.length() < 0.0001: continue
            var rotation := Quaternion(current.normalized(), desired.normalized())
            var parent := rig.get_bone_parent(bone)
            var parent_basis := rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
            rig.set_bone_pose_rotation(bone, (parent_basis.inverse() * Basis(rotation) * pose.basis).get_rotation_quaternion())
        if rig.get_bone_global_pose(end).origin.distance_to(target_local) < 0.001: break

func pinch(amount: float) -> void:
    finger("Index", amount * 0.5)
    bend("ThumbProximal", -amount * 0.35)
    var index_start := tip("Index")
    var thumb_start := tip("Thumb")
    var meeting := hand.global_position + Vector3(0.020, 0.115, 0.030)
    reach("Index", index_start.lerp(meeting, amount))
    reach("Thumb", thumb_start.lerp(meeting, amount))

func make_panel() -> void:
    # Capture the actual book-options viewport, not a separately designed mockup.
    var host = load("res://reader.tscn").instantiate()
    root.add_child(host)
    host.set_process(false)
    host.title.text = "Sample book"
    host.ui.show_book()
    host.ui.options.visible = true
    for entry in host.panels:
        if entry.node == host.ui.options: panel_view = entry.viewport
    action = host.ui.footer.get_child(1)
    panel = MeshInstance3D.new()
    var quad := QuadMesh.new()
    quad.size = Vector2(0.25, 0.375)
    panel.mesh = quad
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_texture = panel_view.get_texture()
    panel.material_override = material
    stage.add_child(panel)
    var backing := MeshInstance3D.new()
    backing.mesh = quad
    backing.position.z = -0.001
    var glass := StandardMaterial3D.new()
    glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.albedo_color = Color(0.24, 0.30, 0.32, 0.90)
    backing.material_override = glass
    panel.add_child(backing)

func setup() -> void:
    viewport = SubViewport.new()
    viewport.size = SIZE
    viewport.own_world_3d = true
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.msaa_3d = Viewport.MSAA_4X
    root.add_child(viewport)
    stage = Node3D.new()
    viewport.add_child(stage)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 0.66
    camera.near = 0.01
    camera.far = 5.0
    camera.position = Vector3(0, 0.13, 1.3)
    stage.add_child(camera)
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0, 0, 0, 0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("a7b2c8")
    environment.ambient_light_energy = 0.45
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world.environment = environment
    stage.add_child(world)
    for settings in [[Vector3(-25, -30, 0), Color("e6ecff"), 0.8], [Vector3(25, 140, 0), Color("b29aff"), 0.55]]:
        var light := DirectionalLight3D.new()
        light.rotation_degrees = settings[0]
        light.light_color = settings[1]
        light.light_energy = settings[2]
        stage.add_child(light)
    hand = load("res://hands/right.gltf").instantiate()
    stage.add_child(hand)
    rig = find_rig(hand)
    var wrist := rig.find_bone("RightHand")
    var axis := (rig.get_bone_global_rest(rig.find_bone("RightMiddleTip")).origin - rig.get_bone_global_rest(wrist).origin).normalized()
    var across := (rig.get_bone_global_rest(rig.find_bone("RightIndexProximal")).origin - rig.get_bone_global_rest(rig.find_bone("RightLittleProximal")).origin).normalized()
    var normal := across.cross(axis).normalized()
    upright = Basis(axis.cross(normal).normalized(), axis, normal).inverse()
    var skin := ShaderMaterial.new()
    var ink := Shader.new()
    ink.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
    float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
    float edge = smoothstep(0.10, 0.30, facing);
    float shade = clamp(dot(normalize(NORMAL), normalize(vec3(-0.4,0.7,0.6))), 0.0, 1.0);
    float hatch = step(0.85, fract((FRAGCOORD.x + FRAGCOORD.y * 0.7) / 6.0));
    vec3 paper = vec3(0.94, 0.96, 0.95) - (1.0-shade) * 0.12 - hatch * (1.0-shade) * 0.16;
    ALBEDO = mix(vec3(0.10,0.15,0.17), paper, edge);
}"""
    skin.shader = ink
    set_skin(hand, skin)
    book = load("res://book.gd").new()
    stage.add_child(book)
    book.set_chapter(8)
    for i in range(8): book.supply_page(i, preload("res://tests/docs_capture.gd").sample(i))
    make_panel()
    contact = MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.008
    sphere.height = 0.016
    contact.mesh = sphere
    var glow := StandardMaterial3D.new()
    glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow.albedo_color = Color("c4ef74")
    contact.material_override = glow
    stage.add_child(contact)

func capture() -> void:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
    setup()
    for gesture in ["page-turn", "finger-scroll", "grab-drag", "pinch-select"]:
        DirAccess.make_dir_recursive_absolute(output + "/" + gesture)
        book.cancel_turn()
        book.first_page = 0
        book.set_mode("scroll" if gesture == "finger-scroll" else "book")
        book.position = Vector3(-0.07, 0.16, -0.13)
        book.scale = Vector3.ONE * (0.62 if gesture == "finger-scroll" else 0.91)
        book.visible = true
        panel.visible = gesture == "grab-drag" or gesture == "pinch-select"
        if panel.visible:
            book.position = Vector3(-0.20, 0.18, -0.15)
            book.scale = Vector3.ONE * 0.62
        if gesture == "page-turn": book.begin_turn(1)
        var metadata: Array = []
        for frame in range(FRAMES):
            var t := float(frame) / (FRAMES - 1)
            var move := ramp(t, 0.28, 0.70)
            var release := ramp(t, 0.76, 0.93)
            rig.reset_bone_poses()
            hand.basis = Basis(Vector3.UP, 0.42) * upright
            hand.position = Vector3(0.11, -0.10, 0.05)
            panel.position = Vector3(0.20, 0.18, -0.13)
            contact.visible = false
            action.text = "Recenter"
            var phase := 0 if t < 0.28 else (1 if t < 0.76 else 2)
            var pointer := Vector3.ZERO
            if gesture == "page-turn":
                hand.basis = Basis(Vector3.UP, 1.28) * upright
                hand.position = Vector3(lerpf(0.25, -0.10, move), -0.075 - release * 0.075, 0.03 + release * 0.10)
                # Extended, gathered fingers form a relaxed chopping hand.
                for digit in ["Index", "Middle", "Ring", "Little"]: finger(digit, 0.035)
                book.set_turn_progress(move)
                if frame >= 59:
                    book.cancel_turn()
                    book.first_page = 2
                    book._refresh()
                book.edge_bars[1].material_override.albedo_color = Color("b9a1ff") if phase == 1 else Color.WHITE
                pointer = book.to_global(Vector3(SpatialBook.PAGE_WIDTH + 0.022, 0, 0))
            elif gesture == "finger-scroll":
                for digit in ["Middle", "Ring", "Little"]: finger(digit, 0.82)
                bend("ThumbProximal", -0.4)
                hand.position = Vector3(0.09, -0.18 + move * 0.19 - release * 0.06, 0.04 + release * 0.08)
                book.scroll_offset = move * 0.38
                book._refresh()
                pointer = tip("Index")
                contact.visible = phase == 1
                contact.position = pointer
            elif gesture == "grab-drag":
                var grip := ramp(t, 0.10, 0.24) * (1 - ramp(t, 0.76, 0.90))
                for digit in ["Index", "Middle", "Ring", "Little"]: finger(digit, grip * 0.85)
                bend("ThumbProximal", -grip * 0.8)
                bend("ThumbMetacarpal", grip * 0.5, Vector3.UP)
                var travel := Vector3(move * 0.13, move * 0.09, 0)
                hand.position = Vector3(0.12, -0.01, 0.045) + travel
                panel.position += travel
                action.text = "Recenter"
                pointer = hand.position + Vector3(0, 0.08, 0)
            else:
                var amount := ramp(t, 0.28, 0.52) * (1 - ramp(t, 0.78, 0.93))
                hand.position = Vector3(0.23, -0.12, 0.08)
                pinch(amount)
                if amount > 0.95:
                    assert(tip("Index").distance_to(tip("Thumb")) < 0.015, "Pinch tips must visibly meet")
                    contact.visible = true
                    contact.position = (tip("Index") + tip("Thumb")) / 2
                action.text = "Recenter"
                pointer = panel.position + Vector3(0.025, -0.169, 0.012)
            await process_frame
            await RenderingServer.frame_post_draw
            var projected := camera.unproject_position(pointer)
            var wrist_screen := camera.unproject_position(hand.position + Vector3(0, 0.06, 0))
            metadata.append({"phase": phase, "point": [projected.x, projected.y], "hand": [wrist_screen.x, wrist_screen.y]})
            assert(viewport.get_texture().get_image().save_png(output + "/" + gesture + "/%03d.png" % frame) == OK)
        var file := FileAccess.open(output + "/" + gesture + "/motion.json", FileAccess.WRITE)
        file.store_string(JSON.stringify(metadata))
    print("PASS: 4 gesture tutorials, 84 frames each, real hand skin and verified pinch contact")
    quit()
