extends SceneTree

func _initialize() -> void: check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    ui.show_section("Source Search")
    ui.minimize_popups()
    for index in 20:
        var id := str(index)
        var image := Image.create(32, 48, false, Image.FORMAT_RGB8)
        image.fill(Color.RED if index % 2 == 0 else Color.BLUE)
        ui.cover_cache[id] = ImageTexture.create_from_image(image)
        ui.source_items.append({"id": id, "title": "Manga %d" % index})
    ui.render_grid()
    reader._build_hud_composition_view()
    ui.hud.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    reader.hud_composition_view.size = ui.hud.viewport.size
    reader.hud_composition_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    ui.library_items = ui.source_items.duplicate()
    for scenario in [{"section": "Source Search", "scroll": 0}, {"section": "Source Search", "scroll": 420}, {"section": "Source Search", "scroll": 900}, {"section": "Home", "scroll": 0}, {"section": "Home", "scroll": 420}, {"section": "Home", "scroll": 900}]:
        ui.show_section(scenario.section)
        ui.minimize_popups()
        var scroll: int = scenario.scroll
        ui.gallery_scroll.scroll_vertical = scroll
        for frame in 12: await process_frame
        ui.refresh_visible_covers()
        for frame in 8: await process_frame
        var bounds: Rect2 = ui.gallery_scroll.get_global_rect()
        if ui.search_row.visible:
            assert(bounds.position.y >= ui.search_row.get_global_rect().end.y)
        assert(bounds.end.y <= ui.hud.pixels.y)
        if DisplayServer.get_name() != "headless":
            await RenderingServer.frame_post_draw
            var source: Image = ui.hud.viewport.get_texture().get_image()
            var presented: Image = reader.hud_composition_view.get_texture().get_image()
            assert(source.get_size() == presented.get_size())
            presented.save_png("E:/Questium-Build/logs/hud-clip-%s-%d.png" % [scenario.section.replace(" ", "-"), scroll])
            for y in range(50, source.get_height(), 100):
                for x in range(50, source.get_width(), 100):
                    var expected := source.get_pixel(x, y)
                    var actual := presented.get_pixel(x, y)
                    assert(absf(expected.a - actual.a) < 0.02, "Presentation preserves scroll clipping")
                    if expected.a > 0.99:
                        assert(Vector3(expected.r, expected.g, expected.b).distance_to(Vector3(actual.r, actual.g, actual.b)) < 0.03, "Opaque content retains position and color")
    reader.queue_free()
    await process_frame
    print("PASS: Library and Browse scroll bounds and full-resolution HUD presentation")
    quit()
