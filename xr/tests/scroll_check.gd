extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var book := SpatialBook.new()
    root.add_child(book)
    await process_frame
    book.set_mode("scroll")
    book.set_chapter(3, 1)
    assert(book.first_page == 1 and book.scroll_mode, "Forced scroll mode preserves odd page resume")
    var image := Image.create(100, 500, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    var texture := ImageTexture.create_from_image(image)
    book.supply_page(1, texture, Vector2i(100, 500))
    book.scroll_offset = 2.5
    for frame in range(5):
        book.scroll_by(0.01)
    assert(book.first_page == 1 and is_equal_approx(book.scroll_offset, 2.5), "Unloaded next page blocks and clamps scroll")
    book.supply_page(2, texture, Vector2i(100, 500))
    book.scroll_by(0.01)
    assert(book.first_page == 1 and book.scroll_offset > 2.5, "Loaded neighbor enters the same viewport without replacing the current page")
    assert(book.scroll_slots[1].visible, "Both images are visible across the boundary")
    book.scroll_by(0.96)
    assert(book.first_page == 2 and book.scroll_offset > 0 and book.scroll_offset < 0.05, "Crossing the full page height preserves continuous distance")
    book.scroll_offset = 2.5
    assert(book.scroll_by(0.05) == 2, "Last page requests next chapter explicitly")
    book.supply_page(0, texture, Vector2i(100, 500))
    assert(book.seek(0))
    assert(book.scroll_by(-0.05) == -2, "First page requests previous chapter explicitly")
    book.seek(1)
    for frame in range(5):
        book.scroll_by(-0.01)
    assert(book.first_page == 0 and book.scroll_offset > 2.4, "Slow backward drag resumes the previous page near its bottom")
    book.set_mode("book")
    assert(book.first_page == 0 and not book.scroll_mode)
    book.queue_free()
    await process_frame
    print("PASS: odd resume, slow drag, loading boundaries, backward continuity and chapter boundaries")
    quit()
