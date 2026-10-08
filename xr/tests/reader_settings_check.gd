extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var book: SpatialBook = reader.book
    book.set_chapter(8, 2)
    book.token = "settings-test"
    book.scroll_offset = 0.25
    reader._response(JSON.stringify({"kind": "reader_render", "revision": "new", "books": {"settings-test": true}}))
    assert(book.upscale_enabled and book.first_page == 2 and is_equal_approx(book.scroll_offset, 0.25))
    reader._response(JSON.stringify({"kind": "page", "revision": "old", "token": "settings-test", "index": 2, "path": "missing.png"}))
    assert(book.textures.is_empty(), "Obsolete processing results must be ignored before decoding")
    reader._response(JSON.stringify({"kind": "reader_filters", "contrast": 125, "preload": 8, "side_padding": 10, "crop_pager": true, "crop_scroll": true, "page_transitions": false, "scale_type": 3, "page_numbers": true}))
    assert(book.preload_pages == 8 and not book.page_transitions and book.crop_pager and book.crop_scroll)
    assert(is_equal_approx(book.scroll_content_width, 0.56))
    assert(reader.ui.number.visible and reader.ui.total.visible)
    for surface in [book.left_leaf, book.right_leaf, book.turning_leaf] + book.scroll_slots:
        assert(is_equal_approx(float(surface.material_override.get_shader_parameter("reader_contrast")), 1.25))
    var image := Image.create(20, 40, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    book.crop_bounds[2] = Vector4(0.1, 0.2, 0.8, 0.6)
    book.supply_page(2, ImageTexture.create_from_image(image))
    assert(book.left_leaf.material_override.get_shader_parameter("front_crop") == Vector4(0.1, 0.2, 0.8, 0.6))
    assert(is_equal_approx(book._page_height(2), 0.84))
    book.set_chapter(2)
    assert(book.crop_bounds.is_empty(), "Crop bounds cannot leak into the next chapter")
    reader.queue_free()
    await process_frame
    print("PASS: live renderer revision, stale response rejection, crop, preload, page transitions and shared paper/strip filters")
    quit()
