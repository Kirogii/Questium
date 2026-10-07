extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    for entry in reader.panels:
        entry.node.visible = false
    reader.book.visible = false
    var panel: Dictionary = reader._panel(reader, Vector2(0.4, 0.3), Vector2i(400, 300), Vector3(0, 1.3, -0.6))
    var button := Button.new()
    button.position = Vector2(100, 75)
    button.size = Vector2(200, 150)
    panel.viewport.add_child(button)
    var clicks := [0]
    button.pressed.connect(func(): clicks[0] += 1)
    await process_frame
    await process_frame
    var touch = reader.hand_touch
    var front: Vector3 = panel.node.to_global(Vector3(0, 0, 0.035))
    var contact: Vector3 = panel.node.to_global(Vector3(0, 0, 0.002))
    assert(not touch.update("right", contact, true, false), "Appearing on the panel cannot press it")
    touch.update("right", front, true, false)
    assert(touch.update("right", contact, true, false))
    assert(reader.ui_owner == "right" and not reader.ui_capture.is_empty())
    assert(not touch.update("left", contact, true, false), "Other hand cannot steal a touch")
    touch.update("right", front, true, false)
    await process_frame
    assert(clicks[0] == 1 and reader.ui_owner.is_empty(), "Approach, touch, withdraw activates exactly once")
    touch.update("right", front, true, false)
    touch.update("right", contact, true, false)
    touch.update("right", contact, false, false)
    await process_frame
    assert(clicks[0] == 1 and reader.ui_capture.is_empty(), "Tracking loss cancels without clicking")
    touch.update("right", front, true, false)
    assert(not touch.update("right", contact, true, true), "Pinch and poke cannot double-activate")
    reader.book.visible = true
    reader.book.set_open(1)
    reader.book.global_transform = panel.node.global_transform
    reader.book.global_position += Vector3(0, 0, 0.025)
    touch.update("right", front, true, false)
    assert(not touch.update("right", contact, true, false), "Book blocks touches on a window behind it")
    reader.queue_free()
    await process_frame
    print("PASS: direct fingertip tap, ownership, tracking-loss cancellation, pinch exclusion and book occlusion")
    quit()
