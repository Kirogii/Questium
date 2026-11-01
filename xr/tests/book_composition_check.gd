extends SceneTree

func _initialize() -> void: check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    assert(not reader.workspace.hud.surface.material_override.no_depth_test, "Scene-backed HUD also respects hands and pointer depth")
    reader.title.text = "An extremely long manga title with many words ".repeat(30)
    for frame in 4: await process_frame
    var column: Control = reader.title.get_parent()
    assert(column.size.x <= 1000, "Long title must not expand the palm menu")
    for control in column.get_child(2).get_children():
        assert(control.get_global_rect().end.x <= 1000, "All palm buttons remain inside the viewport")
    var compositor = load("res://book_composition.gd").new()
    reader.add_child(compositor)
    compositor.setup(reader)
    for index in 3: compositor.create_entry(index)
    var book: SpatialBook = reader.book
    book.token = "test"
    book.visible = true
    book.set_chapter(4)
    var image := Image.create(700, 1000, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    image.fill_rect(Rect2i(0, 0, 350, 500), Color.RED)
    image.fill_rect(Rect2i(350, 500, 350, 500), Color.BLUE)
    var texture := ImageTexture.create_from_image(image)
    for index in 4: book.supply_page(index, texture)
    book.set_mode("book")
    book.set_open(1.0)
    compositor.sync()
    assert(compositor.entries[0].layer.visible and compositor.entries[1].layer.visible)
    assert(not compositor.entries[2].layer.visible)
    assert(book.left_leaf.layers == 0 and book.right_leaf.layers == 0)
    assert(compositor.entries[0].meshes[0].material_override == book.left_leaf.material_override)
    for entry in compositor.entries:
        assert(entry.layer.sort_order < 0 and entry.layer.enable_hole_punch, "Sharp pages allow closer hands and rays to occlude them")
        assert(entry.layer.layer_viewport == entry.presentation)
        assert(entry.presentation.get_child(0).texture == entry.viewport.get_texture())
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        compositor.entries[0].viewport.get_texture().get_image().save_png("E:/Questium-Build/logs/composition-left-page.png")
        compositor.entries[1].viewport.get_texture().get_image().save_png("E:/Questium-Build/logs/composition-right-page.png")
    book.scale = Vector3.ONE * 1.3
    compositor.sync()
    assert(compositor.entries[0].layer.quad_size.is_equal_approx(Vector2(0.28, 0.40) * 1.3))
    var page_normal: Vector3 = book.global_basis * Basis(Vector3.UP, book.REST_ANGLE).z
    var page_center: Vector3 = book.global_transform * Vector3(-book.PAGE_WIDTH * cos(book.REST_ANGLE) / 2, 0, book.PAGE_WIDTH * sin(book.REST_ANGLE) / 2)
    assert(is_equal_approx((compositor.entries[0].layer.global_position - page_center).dot(page_normal.normalized()), compositor.PAGE_CLEARANCE * 1.3), "Depth mask clears the paper stack at the book's scale")
    assert(book.begin_turn(1))
    compositor.sync()
    assert(not compositor.entries[0].layer.visible and book.left_leaf.layers != 0, "Animated pages use the original 3D geometry")
    assert(compositor.entries[0].presentation.render_target_update_mode == SubViewport.UPDATE_DISABLED)
    book.turn_direction = 0
    book.set_mode("scroll")
    compositor.sync()
    assert(compositor.entries[2].layer.visible and not compositor.entries[0].layer.visible)
    assert(book.scroll_screen.layers == 0)
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        compositor.entries[2].viewport.get_texture().get_image().save_png("E:/Questium-Build/logs/composition-scroll-page.png")
    book.hide()
    compositor.sync()
    assert(not compositor.entries[2].layer.visible and book.scroll_screen.layers != 0)
    assert(compositor.entries[2].viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
    reader.queue_free()
    await process_frame
    print("PASS: long palm titles, stationary page layers, animated fallback, scrolling, scale and hide/restore")
    quit()
