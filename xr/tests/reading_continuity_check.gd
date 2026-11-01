extends SceneTree

func _initialize() -> void: check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var book: SpatialBook = reader.book
    book.token = "old-chapter"
    book.set_chapter(8)
    book.set_open(1.0)
    book.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, 0.5, -0.1)).scaled(Vector3.ONE * 1.2), Vector3(1.0, 1.3, -1.8))
    var placement := book.global_transform
    var count: int = reader.books.size()
    reader._response(JSON.stringify({"kind": "chapter", "replaces": "old-chapter", "token": "new-chapter", "title": "Chapter 2", "count": 10, "start": 0}))
    assert(reader.book == book and reader.books.size() == count)
    assert(book.global_transform.is_equal_approx(placement), "Chapter changes retain position, rotation and scale")
    assert(not reader.book_flight or not reader.book_flight.is_running(), "Chapter changes must not start a reposition tween")
    assert(book.token == "new-chapter" and book.page_count == 10)
    reader._set_scenes_enabled(true)
    reader._set_passthrough(true)
    assert(not reader.scenes_enabled and not reader.room.visible, "See through removes the virtual scene even when passthrough is unavailable")
    reader.apply_graphics_settings()
    assert(not reader.room.visible, "Graphics changes must not restore the scene")
    assert(reader.workspace.hud.background.get_theme_stylebox("panel").bg_color.a == 1.0, "Main HUD has a fully opaque backing")
    for primary in [0xffff8800, 0xff4488ff]:
        reader.ui.apply_palette("test-theme", {"primary": primary, "surface": 0xff202020})
        var icons_checked := 0
        for icon in reader.workspace.hud.viewport.find_children("*", "TextureRect", true, false):
            if not icon.has_meta("theme_primary_icon"): continue
            icons_checked += 1
            assert(icon.modulate.is_equal_approx(reader.ui.theme_color("primary", Color.WHITE)), "Navigation icons update with the selected main theme color")
        assert(icons_checked > 0)
        assert(reader.workspace.hud.background.get_theme_stylebox("panel").bg_color.a == 1.0, "Theme changes keep the HUD opaque")
    reader.ui.apply_palette("questium_frost", {})
    for icon in reader.workspace.hud.viewport.find_children("*", "TextureRect", true, false):
        if icon.has_meta("theme_primary_icon"):
            assert(icon.modulate.is_equal_approx(Color(0.77, 0.97, 0.15)), "Default theme restores its accent")
    reader._set_scenes_enabled(true)
    assert(reader.room.visible, "Scenes can still be restored explicitly")
    reader.queue_free()
    await process_frame
    print("PASS: chapter placement, see-through scene removal, HUD backing")
    quit()
