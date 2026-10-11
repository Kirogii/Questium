extends SceneTree

class SearchBridge extends RefCounted:
    var requests: Array = []
    func request(value: String) -> void:
        requests.append(JSON.parse_string(value))
    func hideKeyboard(_field: String) -> void:
        pass

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    for panel in reader.panels: panel.node.visible = false
    var book: SpatialBook = reader.book
    book.visible = true
    book.set_mode("book")
    book.set_open(1)
    book.set_chapter(8)
    book.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -1))
    var texture := ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGB8))
    for index in 8: book.supply_page(index, texture)
    var tracker := XRControllerTracker.new()
    tracker.name = "/user/hand/right"
    XRServer.add_tracker(tracker)
    var controller := XRController3D.new()
    controller.tracker = tracker.name
    reader.origin.add_child(controller)
    reader.tracked.right = {"controller": controller, "pressed": false, "natural_hand": false}
    var pose := book.global_transform
    var rail := Vector3(SpatialBook.PAGE_WIDTH + 0.025, 0, 0)
    var start: Vector3 = book.to_global(rail + Vector3.BACK * 0.6)
    tracker.set_input("trigger_click", true)
    assert(reader.ui.controller_input("right", controller))
    reader._pointer("right", start, Vector3.FORWARD, true, true)
    assert(reader.holder == "right" and book.grabbed and not reader.moving, "Distant trigger captures the page, not the book body")
    reader._pointer("right", start + Vector3(-0.1, 0, 0.1), Vector3.FORWARD, true, true)
    assert(book.turn_progress > 0 and book.turn_progress < 0.5, "Held ray follows the controller without losing its acquisition distance")
    reader._pointer("right", start, Vector3.FORWARD, false, true)
    await create_timer(0.35).timeout
    assert(book.first_page == 0, "Early release returns the leaf without advancing")
    reader._pointer("right", start, Vector3.FORWARD, true, true)
    reader._pointer("right", start + Vector3(-0.6, 0, 0.1), Vector3.FORWARD, true, true)
    assert(book.turn_progress > 0.5)
    reader._pointer("right", start, Vector3.FORWARD, false, true)
    await create_timer(0.35).timeout
    assert(book.first_page == 2, "Release after crossing the spine commits one spread")
    var forward_progress: Array[float] = []
    reader._pointer("right", book.to_global(rail + Vector3.BACK * 0.6), Vector3.FORWARD, true, true)
    for distance in [0.1, 0.2, 0.3, 0.4]:
        reader._pointer("right", book.to_global(rail + Vector3(-distance, 0, 0.6)), Vector3.FORWARD, true, true)
        forward_progress.append(book.turn_progress)
    assert(forward_progress[0] > 0 and forward_progress[1] > forward_progress[0] and forward_progress[3] > 0.5 and forward_progress[3] < 1, "A flat lateral drag curls continuously through the spine")
    book.cancel_turn()
    reader._release_body("right")
    reader.tracked.right.pressed = false
    start = book.to_global(Vector3(-rail.x, 0, 0.6))
    reader._pointer("right", start, Vector3.FORWARD, true, true)
    assert(book.grabbed and not book.cover_dragged, "Open left rail grabs the previous page instead of closing the cover")
    for index in 4:
        reader._pointer("right", start + Vector3(0.1 * (index + 1), 0, 0), Vector3.FORWARD, true, true)
        assert(absf(book.turn_progress - forward_progress[index]) < 0.015, "Both directions need the same sideways travel and show the same curl")
    reader._pointer("right", start + Vector3(0.6, 0, 0.1), Vector3.FORWARD, true, true)
    reader._pointer("right", start, Vector3.FORWARD, false, true)
    await create_timer(0.35).timeout
    assert(book.first_page == 0)
    reader.ui.config_path = "user://livro-direction-test.cfg"
    reader.ui.set_reading_direction("rtl")
    assert(book.rtl and book.begin_turn(-1, -rail), "RTL advances from the left rail")
    book.cancel_turn()
    book.set_chapter(8, 0, false)
    assert(book.rtl, "An explicit direction survives opening another chapter")
    reader.ui.load_config()
    assert(reader.ui.reading_direction == "rtl" and book.rtl, "Direction persists across config reloads")
    reader.ui.set_reading_direction("ltr")
    book.set_chapter(8, 0, true)
    assert(not book.rtl)
    reader.ui.set_reading_direction("auto")
    assert(book.rtl, "Follow source restores the chapter's original direction")
    book.set_chapter(8)
    for index in 8: book.supply_page(index, texture)
    DirAccess.remove_absolute(reader.ui.config_path)
    assert(book.global_transform.is_equal_approx(pose), "Page gestures leave the book stationary")
    start = book.to_global(rail + Vector3.BACK * 0.6)
    reader._pointer("right", start, Vector3.FORWARD, true, true)
    reader._pointer("right", start, Vector3.FORWARD, true, false)
    assert(reader.holder.is_empty() and not book.grabbed, "Tracking loss cancels the captured page")
    book.visible = false
    var ui = reader.workspace
    var bridge := SearchBridge.new()
    ui.show_section("Source Search")
    ui.selected_source = "1"
    ui.source_category = "latest"
    ui.search.text = " isekai "
    reader.bridge = bridge
    for frame in 5: await process_frame
    var button: Button = ui.search_row.get_child(1)
    var pixel := button.get_global_rect().get_center()
    var point := Vector3((pixel.x / ui.hud.pixels.x - 0.5) * ui.hud.size.x, (0.5 - pixel.y / ui.hud.pixels.y) * ui.hud.size.y, 0)
    start = ui.hud.node.to_global(point + Vector3.BACK * 0.2)
    var ray: Vector3 = -ui.hud.node.global_basis.z.normalized()
    reader.tracked.right.pressed = false
    reader._pointer("right", start, ray, true, true)
    reader._pointer("right", start, ray, false, true)
    assert(bridge.requests.size() == 1, "Ray trigger clicks the actual Search button at supersampled UI coordinates")
    assert(bridge.requests[0].query == "isekai" and bridge.requests[0].category == "browse")
    var count := bridge.requests.size()
    for z in [0.08, 0.003, 0.08]:
        reader.hand_touch.update("left", ui.hud.node.to_global(point + Vector3.BACK * z), true, false)
    assert(bridge.requests.size() == count + 1, "Fingertip press and withdrawal click the actual Search button")
    ui.search.text_submitted.emit(ui.search.text)
    assert(bridge.requests.size() == count + 2, "Quest keyboard Enter follows the same search path")
    count = bridge.requests.size()
    reader._pointer("right", start, ray, true, true)
    reader._pointer("right", start, ray, true, false)
    assert(bridge.requests.size() == count and reader.ui_capture.is_empty(), "Tracking loss cancels a controller UI press without clicking")
    reader._pointer("right", start, ray, true, true)
    reader._cancel_interactions()
    assert(bridge.requests.size() == count and reader.ui_capture.is_empty(), "Focus loss cancels a controller UI press without clicking")
    ui.consume({"kind": "source_results", "source": "1", "page": 1, "request_id": ui.search_revision - 1, "items": [{"id": "stale", "title": "Old results"}]})
    assert(ui.source_items.is_empty(), "Older search results cannot replace the latest query")
    ui.consume({"kind": "source_results", "source": "1", "page": 1, "request_id": ui.search_revision, "items": [{"id": "fresh", "title": "Isekai"}]})
    assert(ui.source_items.size() == 1 and ui.source_items[0].id == "fresh")
    reader.bridge = null
    reader.origin.rotation = Vector3.ZERO
    reader.camera.position = Vector3(0.3, 1.5, 0.2)
    for yaw in [0.0, PI, -1.2]:
        reader.camera.rotation.y = yaw
        var head: Vector3 = reader.camera.global_position
        reader._align_startup_heading(reader.camera.global_transform)
        assert((-reader.camera.global_basis.z).dot(Vector3.BACK) > 0.99, "Startup always faces the counter")
        assert(reader.camera.global_position.is_equal_approx(head), "Heading alignment preserves the headset pivot and height")
    XRServer.remove_tracker(tracker)
    reader.queue_free()
    await process_frame
    print("PASS: held trigger rail commit/cancel, left rail, tracking loss, ray/tap/Enter search, stale results, supersampled coordinates and startup heading")
    quit()
