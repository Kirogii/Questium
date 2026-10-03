extends SceneTree

func _initialize() -> void:
    _render.call_deferred()

func _render() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    for frame in range(6):
        await process_frame
        await RenderingServer.frame_post_draw
    var destination := ""
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--preview="):
            destination = argument.trim_prefix("--preview=")
    assert(not destination.is_empty())
    var image := root.get_texture().get_image()
    assert(image.save_png(destination) == OK)
    print("PASS: rendered reader preview")
    quit()
