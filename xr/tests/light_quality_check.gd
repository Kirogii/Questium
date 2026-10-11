extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.position = Vector3(0, 0, 3)
    camera.look_at(Vector3.ZERO)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color.BLACK
    root.add_child(environment)
    var shaft := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.height = 2.0
    cylinder.top_radius = 0.12
    cylinder.bottom_radius = 0.65
    shaft.mesh = cylinder
    var material := ShaderMaterial.new()
    material.shader = load("res://light_shaft.gdshader")
    material.set_shader_parameter("height", 2.0)
    material.set_shader_parameter("opacity", 0.8)
    shaft.material_override = material
    root.add_child(shaft)
    var cabinet := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.2, 0.6, 0.1)
    cabinet.mesh = box
    cabinet.position.z = 1.0
    var opaque := StandardMaterial3D.new()
    opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    opaque.albedo_color = Color(0.15, 0.15, 0.15)
    cabinet.material_override = opaque
    root.add_child(cabinet)
    for frame in 8: await process_frame
    await RenderingServer.frame_post_draw
    var lit := root.get_texture().get_image()
    shaft.visible = false
    for frame in 3: await process_frame
    await RenderingServer.frame_post_draw
    var unlit := root.get_texture().get_image()
    var top_left := camera.unproject_position(Vector3(-0.08, 0.25, 1.05))
    var bottom_right := camera.unproject_position(Vector3(0.08, -0.25, 1.05))
    for y in range(int(top_left.y), int(bottom_right.y)):
        for x in range(int(top_left.x), int(bottom_right.x)):
            assert(lit.get_pixel(x, y).is_equal_approx(unlit.get_pixel(x, y)), "Opaque cabinet must completely hide rays behind it")
    var changed := 0
    for y in range(0, lit.get_height(), 4):
        for x in range(0, lit.get_width(), 4):
            if lit.get_pixel(x, y).r - unlit.get_pixel(x, y).r > 0.01: changed += 1
    assert(changed > 100, "The unobstructed ray remains visibly lit, so the occlusion test cannot pass by hiding all rays")
    lit.save_png("D:/VR Kommiku/artifacts/light-occlusion.png")
    var room := Node3D.new()
    room.set_script(load("res://room.gd"))
    root.add_child(room)
    for frame in 3: await physics_frame
    for node in room.get_children():
        if not node.has_meta("volumetric_light_shaft"): continue
        var at: Vector3 = node.get_meta("bulb_position")
        var query := PhysicsRayQueryParameters3D.create(at + Vector3.DOWN * 0.02, Vector3(at.x, room.floor_y - 0.1, at.z))
        var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
        var bottom: float = node.position.y - node.mesh.height * 0.5
        assert(bottom >= room.floor_y, "Beam cannot extend below the room floor")
        if not hit.is_empty(): assert(is_equal_approx(bottom, hit.position.y + 0.015), "Beam ends above its first furniture surface")
        assert(is_equal_approx(node.material_override.get_shader_parameter("height"), node.mesh.height))
    print("PASS: opaque cabinet occlusion, visible smooth beam and table/counter/floor shaft endpoints")
    quit()
