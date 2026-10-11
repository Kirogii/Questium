extends SceneTree

func _initialize() -> void:
    call_deferred("render")

func render() -> void:
    var room := Node3D.new()
    room.set_script(load("res://room.gd"))
    root.add_child(room)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("08090b")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("9eabc1")
    environment.environment.ambient_light_energy = 0.045
    environment.environment.glow_enabled = true
    environment.environment.glow_intensity = 0.35
    environment.environment.glow_hdr_threshold = 1.15
    root.add_child(environment)
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.position = Vector3(-2.0, 1.65, 7.0)
    camera.look_at(Vector3(-2.0, 1.65, -4.0))
    for i in 12:
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    assert(image.save_png("D:/VR Kommiku/artifacts/noir_bar.png") == OK)
    print("PASS noir render ", image.get_size(), " saved D:/VR Kommiku/artifacts/noir_bar.png")
    quit()
