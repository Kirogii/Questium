extends Node

# ADB opt-in; fixture pages remain in memory and never update reader progress.
const DIRECTORY := "/storage/emulated/0/Android/data/app.houri.beta/files"

func run(reader: Node3D) -> void:
    DirAccess.remove_absolute(DIRECTORY + "/book-probe.flag")
    await get_tree().create_timer(2.0).timeout
    var bridge = reader.bridge
    if bridge: bridge.disconnect("response", reader._response)
    reader.bridge = null
    reader.set_process(false)
    var compositor
    for child in reader.get_children():
        if child.get_script() == preload("res://book_composition.gd"): compositor = child
    if compositor == null or compositor.entries.size() != 3:
        print("BOOK_PROBE RESULT FAIL: native page layers unavailable")
        return
    var book: SpatialBook = reader.book
    book.set_process(false)
    book.token = "book-probe"
    book.set_chapter(4)
    book.visible = true
    var image := Image.create(700, 1000, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    image.fill_rect(Rect2i(0, 0, 350, 500), Color.RED)
    image.fill_rect(Rect2i(350, 500, 350, 500), Color.BLUE)
    image.generate_mipmaps()
    var texture := ImageTexture.create_from_image(image)
    for index in 4: book.supply_page(index, texture)
    book.set_mode("book")
    book.set_open(1.0)
    var passed := true
    for mode in ["book", "scroll"]:
        book.set_mode(mode)
        compositor.sync()
        for frame in 24: await get_tree().process_frame
        await RenderingServer.frame_post_draw
        for index in ([0, 1] if mode == "book" else [2]):
            var entry: Dictionary = compositor.entries[index]
            var page: Image = entry.viewport.get_texture().get_image()
            var valid: bool = page != null and not page.is_empty() and entry.layer.visible and entry.layer.sort_order > 0 and not entry.layer.enable_hole_punch
            var colored := 0
            if page != null and not page.is_empty():
                for y in range(100, 1900, 40):
                    for x in range(100, 1300, 40):
                        var color := page.get_pixel(x, y)
                        if maxf(color.r, maxf(color.g, color.b)) > 0.6: colored += 1
                valid = valid and colored > 1100
                page.save_png(DIRECTORY + "/book-probe-%d.png" % index)
            passed = passed and valid
            print("BOOK_PROBE ", mode, " page=", index, " valid=", valid, " filled_samples=", colored)
    book.set_mode("book")
    var turning := book.begin_turn(1)
    compositor.sync()
    passed = passed and turning and not compositor.entries[0].layer.visible and book.left_leaf.layers != 0
    print("BOOK_PROBE RESULT ", "PASS" if passed else "FAIL", " animated_fallback=", turning)
    book.cancel_turn()
    book.token = ""
    book.hide()
    book.set_process(true)
    reader.bridge = bridge
    if bridge: bridge.connect("response", reader._response)
    reader.set_process(true)
    reader.workspace.show_section("Home")
    queue_free()
