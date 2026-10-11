extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    ui.filter = "History"
    ui.show_section("Home")
    var entries: Array = []
    var titles := ["Short title", "A Very Long Manga Title That Must Stop At The Second Line Instead Of Expanding The Whole Card", "UnbrokenTitle".repeat(20), "First line\nSecond line\nThird line\nFourth line", "異世界で始まる新しい物語".repeat(12), "Another short title"]
    for index in titles.size():
        var id := str(900 + index)
        var image := Image.create(32 if index % 2 == 0 else 128, 96 if index % 2 == 0 else 32, false, Image.FORMAT_RGB8)
        image.fill(Color.from_hsv(index / 6.0, 0.45, 0.65))
        ui.cover_cache[id] = ImageTexture.create_from_image(image)
        entries.append({"id": id, "title": titles[index], "history_chapter": "Chapter " + str(index + 1) + (" - an extremely long chapter name".repeat(12) if index % 2 else ""), "last_page": index, "last_read": 1000})
    ui.consume({"kind": "history", "items": entries})
    for frame in 12: await process_frame
    var expected: Vector2 = ui.grid.get_child(0).size
    assert(expected.x == ui.COVER_BOX.x + 32 and expected.y <= 417, "History stays at the intended compact card size")
    for card in ui.grid.get_children():
        assert(card.size.is_equal_approx(expected), "All history cards have equal dimensions across rows")
        var column: VBoxContainer = card.get_child(0)
        var image_box: Control = column.get_child(0)
        assert(image_box.size.is_equal_approx(ui.COVER_BOX))
        assert(image_box.get_child(0).size.is_equal_approx(ui.COVER_BOX), "Portrait and landscape covers use the same cropped box")
        var caption: Button = column.get_child(1)
        var title: Label = caption.get_child(0)
        assert(caption.size.is_equal_approx(ui.TITLE_BOX) and title.max_lines_visible == 2)
        assert(title.get_visible_line_count() <= 2 and title.clip_text)
        if title.get_line_count() > 1: assert(title.get_visible_line_count() == 2, "Long titles must show both reserved lines")
        assert(title.mouse_filter == Control.MOUSE_FILTER_IGNORE and caption.tooltip_text == title.text, "Full titles remain accessible and do not block clicks")
        var chapter: Label = column.get_child(2)
        assert(chapter.size.x <= ui.COVER_BOX.x and chapter.clip_text and chapter.tooltip_text == chapter.text)
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        ui.hud.viewport.get_texture().get_image().save_png("D:/VR Kommiku/artifacts/history-uniform-cards.png")
    var caption: Button = ui.grid.get_child(1).get_child(0).get_child(1)
    caption.pressed.emit()
    assert(ui.selected_manga == "901", "The two-line title retains book selection")
    reader.queue_free()
    await process_frame
    print("PASS: compact uniform History cards, two-line multilingual titles, one-line chapter clipping, varied cover crops and title selection")
    quit()
