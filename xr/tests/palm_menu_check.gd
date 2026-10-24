extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    for entry in reader.panels: entry.node.visible = false
    reader.book.visible = false
    reader.palm_hand = "left"
    reader.ui_hand = "right"
    var toolbar: Dictionary = {}
    for entry in reader.panels:
        if entry.node == reader.toolbar: toolbar = entry
    assert(not toolbar.is_empty() and toolbar.get("hand_attached", false))
    assert(not toolbar.has("drag_bar"), "Palm toolbar has no world drag rail")
    toolbar.node.visible = true
    toolbar.node.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -0.6))
    toolbar.content.visible = false
    var button := Button.new()
    button.size = Vector2(toolbar.pixels)
    toolbar.viewport.add_child(button)
    var clicks := [0]
    button.pressed.connect(func(): clicks[0] += 1)
    await process_frame
    await process_frame
    var front: Vector3 = toolbar.node.to_global(Vector3(0, 0, 0.035))
    var contact: Vector3 = toolbar.node.to_global(Vector3(0, 0, 0.002))
    assert(reader.hand_touch.near_popup(front), "Palm controls reserve near-field gestures")
    reader.hand_touch.update("left", front, true, false)
    assert(not reader.hand_touch.update("left", contact, true, false), "Carrying hand cannot steal menu capture")
    assert(reader.ui_owner.is_empty())
    reader.hand_touch.update("right", front, true, false)
    assert(reader.hand_touch.update("right", contact, true, false))
    reader.hand_touch.update("right", front, true, false)
    await process_frame
    assert(clicks[0] == 1 and reader.ui_owner.is_empty(), "Other hand can tap palm controls")
    reader.hand_touch.update("right", front, true, false)
    reader.hand_touch.update("right", contact, true, false)
    reader.hand_touch.update("right", contact, false, false)
    await process_frame
    assert(clicks[0] == 1 and reader.ui_owner.is_empty() and reader.ui_capture.is_empty(), "Tracking loss releases without activation")
    var world: Dictionary = reader._panel(reader, Vector2(0.4, 0.3), Vector2i(400, 300), Vector3(0, 1.3, -1))
    assert(world.has("drag_bar"), "World windows retain drag rails")
    var options: Dictionary = {}
    for entry in reader.panels:
        if entry.node == reader.ui.options: options = entry
    reader.chapter_token = "palm-test"
    reader.ui.palm_options_requested = true
    reader.ui.update_palm_options(true, Vector3(0, 1.2, -0.6))
    assert(options.hand_attached and not options.drag_bar.visible, "Palm options hide their rail")
    reader.ui.close_options()
    reader.tracked.clear()
    reader.ui.toggle(false)
    assert(not options.hand_attached and options.drag_bar.visible, "Detached options retain their rail")
    reader.queue_free()
    await process_frame
    print("PASS: palm tap ownership, tracking-loss release and attached rail exclusion")
    quit()
