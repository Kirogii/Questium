extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var book := SpatialBook.new()
    root.add_child(book)
    book.set_mode("scroll")
    book.set_chapter(3)
    var colors := [Color.RED, Color.BLUE, Color.GREEN]
    for index in range(3):
        var image := Image.create(100, 500, false, Image.FORMAT_RGB8)
        image.fill(colors[index])
        book.supply_page(index, ImageTexture.create_from_image(image))
    book.scroll_offset = 3.0
    book._refresh()
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 1.2
    camera.position = Vector3(0, 0, 2)
    camera.current = true
    await create_timer(0.1).timeout
    await RenderingServer.frame_post_draw
    var rendered := root.get_texture().get_image()
    var upper := rendered.get_pixel(640, 275)
    var lower := rendered.get_pixel(640, 525)
    assert(upper.r > 0.8 and upper.b < 0.1, "Upper viewport shows the current page's tail")
    assert(lower.b > 0.8 and lower.r < 0.1, "Lower viewport shows the following page's beginning simultaneously")
    rendered.save_png("D:/VR Kommiku/artifacts/book-motion-study/continuous-scroll-boundary.png")
    book.scroll_by(0.6)
    assert(book.first_page == 1 and is_equal_approx(book.scroll_offset, 0.1))
    book.scroll_by(-0.2)
    assert(book.first_page == 0 and is_equal_approx(book.scroll_offset, 3.4), "Reverse movement preserves the exact boundary position")
    book.queue_free()
    camera.queue_free()
    await process_frame
    print("PASS: rendered two-page boundary pixels and exact forward/backward scroll continuity")
    quit()
