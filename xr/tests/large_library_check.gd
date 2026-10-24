extends SceneTree
class Bridge extends RefCounted:
    var requests: Array = []
    func request(value: String) -> void: requests.append(JSON.parse_string(value))
    func hideKeyboard(_field: String) -> void: pass
func _initialize() -> void: check.call_deferred()
func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    var bridge := Bridge.new()
    reader.bridge = bridge
    ui.show_section("Home")
    ui.library_items.clear()
    for index in 1419:
        ui.library_items.append({"id": str(index), "title": "Book %d" % index})
    ui.render_grid()
    for frame in 8: await process_frame
    ui.refresh_visible_covers()
    for frame in 4: await process_frame
    ui.refresh_visible_covers()
    assert(ui.virtual_cards.size() == 1419)
    var loaded := 0
    for entry in ui.virtual_cards:
        if entry.loaded: loaded += 1
    assert(loaded > 0 and loaded < 40, "Only viewport-near cards have controls")
    assert(ui.cover_pending.size() == 4, "At most four covers in flight")
    var old_ids: Array = ui.cover_pending.keys()
    ui.gallery_scroll.scroll_vertical = 90000
    for frame in 8: await process_frame
    ui.refresh_visible_covers()
    assert(not ui.virtual_cards[0].loaded and ui.virtual_cards[0].node.get_child_count() == 0)
    var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
    image.fill(Color.RED)
    var image_path := "E:/Questium-Build/logs/lazy-cover-fixture.png"
    image.save_png(image_path)
    for id in old_ids: ui.consume({"kind": "cover", "manga": id, "path": image_path})
    assert(ui.cover_cache.is_empty(), "Stale responses are rejected before decoding")
    ui.refresh_visible_covers()
    assert(ui.cover_pending.size() <= 4 and ui.cover_pending.size() > 0)
    for id in ui.cover_pending.keys(): ui.consume({"kind": "cover", "manga": id, "path": ""})
    for index in 100: ui.cover_cache["cached-%d" % index] = ImageTexture.new()
    ui.trim_cover_cache()
    assert(ui.cover_cache.size() <= 40)
    for menu in ["History", "Updates"]:
        ui.filter = menu
        var entries: Array = []
        for index in 1419:
            entries.append({"id": str(index), "title": "Book %d" % index, "day": "2026-10-24", "history_chapter": "Chapter 10", "update_chapter": "Long chapter name ".repeat(100), "update_count": 3})
        if menu == "History": ui.history_items = entries
        else: ui.update_items = entries
        ui.gallery_scroll.scroll_vertical = 0
        ui.render_grid()
        for frame in 8: await process_frame
        ui.refresh_visible_covers()
        loaded = 0
        for entry in ui.virtual_cards:
            if entry.loaded: loaded += 1
        assert(loaded > 0 and loaded < 40, menu + " also hydrates only nearby entries")
        if menu == "Updates":
            for frame in 8: await process_frame
            var first: PanelContainer = ui.virtual_cards[0].node
            var hydrated_size := first.size
            assert(is_equal_approx(hydrated_size.y, 174.0), "Long update chapter keeps fixed row height")
            var chapter: Label = first.get_child(0).get_child(1).get_child(1)
            assert(chapter.clip_text and chapter.tooltip_text.length() > 1000)
            ui.gallery_scroll.scroll_vertical = 90000
            for frame in 8: await process_frame
            ui.refresh_visible_covers()
            for frame in 8: await process_frame
            assert(first.get_child_count() == 0)
            assert(first.size.is_equal_approx(hydrated_size), "Culled update row keeps identical geometry")
    ui.hud.node.visible = false
    ui.refresh_visible_covers()
    assert(ui.cover_targets.is_empty(), "Hidden HUD releases all cover controls")
    for entry in ui.virtual_cards: assert(not entry.loaded)
    reader.bridge = null
    reader.queue_free()
    await process_frame
    print("PASS 1419 library/history/updates books: nearviewport controls, four requests, stale rejection, bounded cache and hidden HUD release")
    quit()
