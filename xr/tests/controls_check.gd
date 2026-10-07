extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    var texture := ImageTexture.create_from_image(image)
    reader.library_panel.visible = false
    reader.book.visible = true
    reader.book.set_chapter(8)
    for index in range(8):
        reader.book.supply_page(index, texture)
    assert(reader.bindings["right:trigger_click"] == "Next page")
    assert(reader.bindings["left:trigger_click"] == "Previous page")
    var tracker := XRControllerTracker.new()
    tracker.name = "/user/hand/right"
    XRServer.add_tracker(tracker)
    var controller := XRController3D.new()
    controller.tracker = tracker.name
    reader.origin.add_child(controller)
    reader.tracked["right"] = {"controller": controller, "pressed": false}
    tracker.set_input("trigger_click", true)
    assert(not reader.ui.controller_input("right", controller), "Page trigger must not also press the UI")
    assert(reader.book.turn_direction == 1, "Right trigger turns forward")
    reader.book.cancel_turn()
    reader.ui.controller_input("right", controller)
    assert(reader.book.turn_direction == 0, "Held trigger must not repeat")
    tracker.set_input("trigger_click", false)
    tracker.set_input("ax_button", true)
    assert(reader.ui.controller_input("right", controller), "A activates pointer interaction")
    assert(reader.tracked.right.can_ui and not reader.tracked.right.can_grab)
    tracker.set_input("ax_button", false)
    tracker.set_input("grip_click", true)
    assert(reader.ui.controller_input("right", controller))
    assert(reader.tracked.right.can_grab and not reader.tracked.right.can_ui)
    var point: Vector3 = reader.book.to_global(Vector3(SpatialBook.PAGE_WIDTH + 0.025, 0, 0))
    reader.tracked.right.pressed = false
    reader._pointer("right", point, Vector3.FORWARD, true, true)
    assert(reader.holder == "right", "White bar must be grabbable")
    reader._cancel_interactions()
    tracker.set_input("grip_click", false)
    reader.ui.controller_input("right", controller)
    reader._page_region(reader.camera.global_position, (point - reader.camera.global_position).normalized(), "right")
    assert(reader.book.turn_direction == 1, "Point-and-A page region turns forward")
    reader.book.cancel_turn()
    reader.ui.config_path = ProjectSettings.globalize_path("res://tests/controls-test.cfg")
    reader.ui.perform("Switch hands")
    assert(reader.preferred_hand == "left")
    tracker.set_input("ax_button", true)
    assert(not reader.ui.controller_input("right", controller), "Switching pointer hands disables right A")
    var saved := ConfigFile.new()
    assert(saved.load(reader.ui.config_path) == OK)
    assert(saved.get_value("reader", "hand") == "left")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(reader.ui.config_path))
    reader.ui.toggle()
    assert(reader.ui.options.visible)
    reader.ui.show_settings()
    reader.ui.show_controllers()
    await process_frame
    assert(reader.ui.content.get_child_count() >= 4)
    XRServer.remove_tracker(tracker)
    reader.queue_free()
    await process_frame
    print("PASS: trigger edges, A interaction, grip grabs, white bars, page regions and settings")
    quit()
