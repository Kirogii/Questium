extends SceneTree

func _initialize() -> void:
    render.call_deferred()

func render() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var image := Image.new()
    image.load("D:/VR Kommiku/Reference/Reference4.png")
    var cover := image.get_region(Rect2i(int(image.get_width() * 0.363), int(image.get_height() * 0.255), int(image.get_width() * 0.273), int(image.get_height() * 0.465)))
    var texture := ImageTexture.create_from_image(cover)
    var ui = reader.workspace
    ui.library_items = []
    for i in range(8):
        var id := str(i)
        ui.library_items.append({"id": id, "title": "A Dimension Next Door", "unread": 12, "chapters": 194, "added": int(Time.get_unix_time_from_system()) - (0 if i < 2 else 86400)})
        ui.cover_cache[id] = texture
    ui.render_grid()
    await create_timer(0.7).timeout
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/frosted-library.png")
    ui.select_book(ui.library_items[0], ui.cover_targets["0"])
    await create_timer(0.7).timeout
    ui.consume({"kind": "details", "manga": "0", "title": "A Dimension Next Door", "favorite": false, "description": "A manga preview with its real cover artwork. The side window holds a scrollable description and chapters."})
    ui.consume({"kind": "chapters", "manga": "0", "items": [{"id": "1", "title": "Chapter 1"}, {"id": "2", "title": "Chapter 2"}, {"id": "3", "title": "Chapter 3"}]})
    ui.info.node.visible = true
    await create_timer(0.5).timeout
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/frosted-preview.png")
    quit()
