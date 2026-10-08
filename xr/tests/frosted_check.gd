extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    assert(ui.windows.size() == 1 and reader.android_app == null, "Single native VR HUD")
    assert(ui.hud.node.visible and not reader.book.visible, "Start in VR library")
    assert(not ui.search_row.visible and ui.nav_buttons.has("Recently Deleted"), "Reference 1 Home has cover groups and counted sidebar")
    reader._response(JSON.stringify({"kind": "library", "items": [{"id": "42", "title": "Book A", "unread": 2}, {"id": "43", "title": "Book B", "unread": 1}]}))
    assert(ui.grid.get_child_count() == 2, "Cover grid populated")
    ui.search.text = "Book A"
    ui.search.text_changed.emit(ui.search.text)
    assert(ui.grid.get_child_count() == 1, "Library search filters grid")
    var artwork := ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGB8))
    ui.cover_cache["42"] = artwork
    ui.select_book({"id": "42", "title": "Book A"}, ui.cover_targets["42"])
    assert(reader.book.visible and ui.hud.node.visible, "Book emerges before HUD disappears")
    assert(reader.book.cover_texture == artwork and is_zero_approx(reader.book.openness))
    await create_timer(0.65).timeout
    assert(not ui.hud.node.visible and ui.preview.node.visible, "Cover preview replaces HUD after emergence")
    reader._response(JSON.stringify({"kind": "chapters", "manga": "42", "resume": "12", "items": [{"id": "11", "title": "Chapter 1"}, {"id": "12", "title": "Chapter 2"}]}))
    assert(ui.read_button.tooltip_text == "Resume" and ui.read_button.text.is_empty(), "Resume uses an image action with its label on hover")
    ui.chapter_search.text = "2"
    ui.chapter_search.text_changed.emit(ui.chapter_search.text)
    assert(ui.chapter_list.get_child_count() == 1, "Chapter search filters independently")
    reader.camera.rotation = Vector3(0.2, 1.2, 0.1)
    var origin_before: Transform3D = reader.origin.global_transform
    reader.recenter()
    var facing: Basis = ui.facing_basis()
    assert((-facing.z).is_equal_approx(-reader.camera.global_basis.z.normalized()), "Recenter preserves gaze elevation")
    assert(ui.hud.node.global_position.is_equal_approx(reader.camera.global_position - facing.z * ui.gui_distance))
    assert(ui.preview.node.global_basis.is_equal_approx(facing), "Preview faces recentered heading")
    reader._locomotion(1.0)
    assert(reader.origin.global_transform.is_equal_approx(origin_before), "No stick locomotion")
    for pitch in [PI / 2, -PI / 2]:
        reader.camera.rotation = Vector3(pitch, 0.7, 0)
        reader.recenter()
        assert(ui.hud.node.global_basis.is_finite(), "Looking straight up or down produces a valid GUI pose")
        assert((-ui.hud.node.global_basis.z.normalized()).is_equal_approx(-reader.camera.global_basis.z.normalized()))
    reader.camera.rotation = Vector3.ZERO
    reader.recenter()
    ui.read_selected()
    reader._response(JSON.stringify({"kind": "chapter", "token": "test", "count": 4, "start": 0, "title": "Book A", "vertical": false}))
    assert(ui.reading and not ui.preview.node.visible, "Chapter enters reader")
    reader.book.supply_page(0, ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGB8)))
    assert(reader.book.cover_texture == artwork, "Chapter page does not replace cover art")
    reader.toggle_library()
    assert(ui.hud.node.visible and not reader.book.visible)
    ui.show_section("Reader")
    assert(reader.book.visible and not ui.hud.node.visible, "Reader section restores current chapter")
    reader._response(JSON.stringify({"kind": "chapter", "token": "long", "replaces": "test", "count": 4, "start": 0, "title": "Webtoon", "vertical": true}))
    assert(reader.book.scroll_mode, "Long-page chapters use vertical reader")
    reader.queue_free()
    await process_frame
    print("PASS: native HUD, cover emergence, preview, chapter search, resume, cover retention, recenter, seated VR and long-page reader")
    quit()
