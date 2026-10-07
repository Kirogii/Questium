extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    ui.consume({"kind": "sources", "items": [{"id": "1", "title": "Alpha source"}, {"id": "2", "title": "Beta source"}]})
    ui.show_sources(false)
    assert(ui.picker_list.get_child_count() == 2, "Installed sources use image and title rows")
    ui.picker_search.text = "Beta"
    ui.render_sources()
    assert(ui.picker_list.get_child_count() == 1, "Source search filters the picker")
    ui.consume({"kind": "extensions", "items": [{"id": "pkg.example", "title": "Example extension"}]})
    ui.show_sources(true)
    assert(ui.picker_list.get_child_count() == 1, "Extension browser is separate from installed sources")
    ui.keyboard_target = ui.search
    ui.consume({"kind": "keyboard_text", "field": "stale", "text": "wrong"})
    assert(ui.search.text.is_empty(), "Stale keyboard sessions cannot overwrite another textbox")
    ui.consume({"kind": "keyboard_text", "field": str(ui.search.get_instance_id()), "text": "native text"})
    assert(ui.search.text == "native text", "Quest keyboard text reaches the focused field")
    ui.select_book({"id": "first", "title": "First book"})
    await create_timer(0.55).timeout
    reader._response(JSON.stringify({"kind": "chapter", "token": "first-token", "count": 4, "start": 0, "title": "First book"}))
    var original: SpatialBook = reader.book
    ui.show_section("Home")
    ui.select_book({"id": "second", "title": "Second book"})
    await create_timer(0.55).timeout
    assert(reader.book != original and not original.visible, "New preview cannot overlap a previous reader book")
    assert(is_equal_approx(reader.book.scale.x, 1.05), "Preview uses the smaller cover scale")
    var front: Vector3 = reader.camera.global_position
    var direction: Vector3 = (ui.preview.node.global_position - front).normalized()
    assert(reader._panel_input(front, direction, false, false), "Preview actions remain reachable past the cover")
    ui.show_section("Reader")
    assert(reader.book == original and original.visible, "Reader restores the active chapter after abandoning a preview")
    reader.ui.layout_mode = "book"
    reader._response(JSON.stringify({"kind": "chapter", "token": "forced", "replaces": "first-token", "count": 4, "start": 0, "title": "Tall chapter", "vertical": true}))
    assert(not reader.book.scroll_mode, "Forced two-page mode overrides long-page detection")
    reader.ui.layout_mode = "scroll"
    reader._response(JSON.stringify({"kind": "chapter", "token": "scroll", "replaces": "forced", "count": 4, "start": 0, "title": "Normal chapter", "vertical": false}))
    assert(reader.book.scroll_mode, "Forced long-scroll mode overrides a normal chapter")
    reader.queue_free()
    await process_frame
    print("PASS: source/extension picker, keyboard session delivery, preview depth, reader restoration and forced layouts")
    quit()
