extends SceneTree

func _initialize() -> void:
    render.call_deferred()

func render() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.workspace.hud.node.visible = false
    reader.workspace.badge.node.visible = false
    reader.book.visible = true
    reader.book.set_preview(false)
    reader.book.set_mode("book")
    reader.book.set_chapter(6)
    reader.book.global_transform = Transform3D(Basis.IDENTITY, reader.camera.global_position + Vector3(0, -0.02, -0.9)).scaled_local(Vector3.ONE * 1.65)
    for i in range(6):
        var page := Image.create(400, 560, false, Image.FORMAT_RGB8)
        page.fill(Color(0.96, 0.95, 0.91))
        for row in range(3):
            page.fill_rect(Rect2i(26, 28 + row * 176, 348, 150), Color(0.18 + i * 0.08, 0.23 + row * 0.10, 0.30 + i * 0.04))
            page.fill_rect(Rect2i(40, 44 + row * 176, 80, 118), Color(0.78, 0.76, 0.68))
            page.fill_rect(Rect2i(142, 44 + row * 176, 214, 48), Color(0.85, 0.84, 0.78))
        reader.book.supply_page(i, ImageTexture.create_from_image(page))
    if "--cover" in OS.get_cmdline_user_args():
        reader.book.set_cover(reader.book.textures[0])
        reader.camera.position.x += 0.35
        reader.camera.look_at(reader.book.global_position + Vector3(0.12, 0, 0))
        for openness in [0.0, 0.45, 1.0]:
            reader.book.set_open(openness)
            await create_timer(0.1).timeout
            await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/book-motion-study/hinge-%s.png" % openness)
        quit()
        return
    for point in [Vector3(0.25, 0, 0.08), Vector3(0.22, 0, 0.10), Vector3(0.17, 0, 0.12), Vector3(0.06, 0, 0.15), Vector3(-0.04, 0, 0.15)]:
        reader.hand_page_turn.update("right", reader.book.to_global(point), true, false, 0.02)
    await create_timer(0.5).timeout
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/hand-sweep-curl.png")
    quit()
