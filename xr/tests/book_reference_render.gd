extends SceneTree

func _initialize() -> void:
    render.call_deferred()

func render() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.workspace.show_settings()
    reader.workspace.settings.select_tab(1)
    for frame in 12: await process_frame
    await RenderingServer.frame_post_draw
    reader.workspace.hud.viewport.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/questium-settings.png")
    reader.ui.show_controllers()
    for frame in 8: await process_frame
    await RenderingServer.frame_post_draw
    for panel in reader.panels:
        if panel.node == reader.ui.options:
            panel.viewport.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/controller-guide.png")
    reader.ui.close_options()
    reader.workspace.hud.node.visible = false
    reader.workspace.badge.node.visible = false
    var book: SpatialBook = reader.book
    book.visible = true
    book.set_preview(false)
    book.set_mode("book")
    book.set_chapter(4)
    book.set_hard_cover(true)
    book.global_transform = Transform3D(reader.camera.global_basis * Basis(Vector3.RIGHT, -0.12), reader.camera.global_position + reader.camera.global_basis * Vector3(0, -0.04, -0.65)).scaled_local(Vector3.ONE * 1.1)
    for page in 4:
        var image := Image.load_from_file("D:/VR Kommiku/artifacts/real-page-check/%s.png" % (12 + page))
        image.generate_mipmaps()
        book.supply_page(page, ImageTexture.create_from_image(image))
    book.begin_turn(1)
    book.set_turn_progress(0.35)
    for frame in 12: await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/reference-book.png")
    print("PASS: book and Questium settings renders saved")
    reader.queue_free()
    await process_frame
    quit()
