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
    var book: SpatialBook = reader.book
    book.visible = true
    book.set_preview(false)
    book.set_mode("book")
    book.set_chapter(4)
    book.global_transform = Transform3D(Basis(Vector3.RIGHT, -0.08), reader.camera.global_position + Vector3(0, -0.03, -0.95)).scaled_local(Vector3.ONE * 1.5)
    for page in range(4):
        var image := Image.load_from_file("D:/VR Kommiku/artifacts/real-page-check/%s.png" % (12 + page))
        assert(image != null)
        image.generate_mipmaps()
        book.supply_page(page, ImageTexture.create_from_image(image))
    for progress in [-1.0, 0.30, 0.58]:
        if progress >= 0:
            book.cancel_turn()
            book.begin_turn(1)
            book.set_turn_progress(progress)
        await create_timer(0.15).timeout
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/book-motion-study/real-pages-%s.png" % progress)
    quit()
