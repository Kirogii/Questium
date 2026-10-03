extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var book := SpatialBook.new()
    root.add_child(book)
    await process_frame
    var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    var texture := ImageTexture.create_from_image(image)
    book.set_chapter(5)
    assert(not book.begin_turn(-1), "First spread cannot turn backward")
    assert(not book.begin_turn(1), "Unloaded target spread cannot turn")
    for index in range(5):
        book.supply_page(index, texture)
    assert(book.begin_turn(1))
    book.set_turn_progress(0.25)
    book.release_turn()
    await create_timer(0.35).timeout
    assert(book.first_page == 0, "Cancelled grab must not change reading position")
    assert(book.step(1))
    await create_timer(0.35).timeout
    assert(book.first_page == 2)
    assert(book.step(1))
    await create_timer(0.35).timeout
    assert(book.first_page == 4, "Odd final page is a valid spread")
    assert(not book.step(1))
    assert(book.seek(1))
    assert(book.first_page == 0)
    book.rtl = true
    assert(book.begin_turn(-1), "RTL next turn starts on the left")
    book.set_turn_progress(0.75)
    book.release_turn()
    await create_timer(0.35).timeout
    assert(book.first_page == 2)
    assert(book.begin_turn(1))
    book.cancel_turn()
    assert(book.first_page == 2, "Tracking loss must cancel without changing position")
    assert(book.turn_direction == 0)
    assert(not book.turning_leaf.visible)
    book.set_chapter(100)
    book.prepare_seek(80)
    book.supply_page(80, texture)
    assert(not book.seek(80), "Seek waits for both pages")
    book.supply_page(81, texture)
    assert(book.seek(80), "Far seek pages must survive cache trimming")
    assert(book.first_page == 80)
    book.queue_free()
    print("PASS: book loading, boundaries, seek, RTL, grab cancellation and settlement")
    quit()
