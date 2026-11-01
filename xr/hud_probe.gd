extends Node

# Explicit ADB opt-in for the locally signed preview; never runs in normal use.
const DIRECTORY := "/storage/emulated/0/Android/data/app.houri.beta/files"

func run(reader: Node3D) -> void:
    DirAccess.remove_absolute(DIRECTORY + "/hud-probe.flag")
    await get_tree().create_timer(2.0).timeout
    var ui = reader.workspace
    var bridge = reader.bridge
    if bridge:
        bridge.disconnect("response", reader._response)
    reader.bridge = null
    reader.set_process(false)
    var saved_library: Array = ui.library_items.duplicate()
    var saved_sources: Array = ui.source_items.duplicate()
    var entries: Array = []
    for index in 20:
        var id := "hud-probe-%d" % index
        var image := Image.create(64, 96, false, Image.FORMAT_RGB8)
        image.fill(Color.RED if index % 2 == 0 else Color.BLUE)
        ui.cover_cache[id] = ImageTexture.create_from_image(image)
        entries.append({"id": id, "title": "Manga %d — clipping check" % index})
    ui.library_items = entries.duplicate()
    ui.source_items = entries.duplicate()
    var passed := true
    for section in ["Home", "Source Search"]:
        ui.show_section(section)
        ui.minimize_popups()
        for offset in [0, 420, 900]:
            ui.gallery_scroll.scroll_vertical = offset
            for frame in 12: await get_tree().process_frame
            ui.refresh_visible_covers()
            for frame in 12: await get_tree().process_frame
            await RenderingServer.frame_post_draw
            var bounds: Rect2 = ui.gallery_scroll.get_global_rect()
            var image: Image = ui.hud.viewport.get_texture().get_image()
            var valid: bool = not image.is_empty() and bounds.size.y > 200 and bounds.end.y <= ui.hud.pixels.y
            if ui.search_row.visible:
                valid = valid and bounds.position.y >= ui.search_row.get_global_rect().end.y
            var colors := 0
            var outside := 0
            var scale: Vector2 = Vector2(image.get_size()) / Vector2(ui.hud.pixels)
            for y in range(0, image.get_height(), 8):
                for x in range(0, image.get_width(), 8):
                    var color := image.get_pixel(x, y)
                    if (color.r > 0.8 and color.g < 0.1 and color.b < 0.1) or (color.b > 0.8 and color.g < 0.1 and color.r < 0.1):
                        colors += 1
                        if not bounds.has_point(Vector2(x, y) / scale): outside += 1
            valid = valid and colors > 200 and outside == 0
            passed = passed and valid
            image.save_png(DIRECTORY + "/hud-probe-%s-%d.png" % [section.replace(" ", "-"), offset])
            print("HUD_PROBE ", section, " scroll=", offset, " valid=", valid, " cover_samples=", colors, " outside=", outside, " bounds=", bounds, " layer=", reader.hud_composition != null)
    ui.library_items = saved_library
    ui.source_items = saved_sources
    reader.bridge = bridge
    if bridge: bridge.connect("response", reader._response)
    reader.set_process(true)
    ui.show_section("Home")
    print("HUD_PROBE RESULT ", "PASS" if passed else "FAIL")
    queue_free()
