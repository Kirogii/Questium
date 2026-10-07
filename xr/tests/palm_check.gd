extends SceneTree

func _initialize() -> void:
    _check.call_deferred()

func _check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.chapter_token = "palm-test"
    var palm := Vector3(0.2, 1.0, -0.45)
    assert(not reader.toolbar.visible, "Toolbar starts hidden")
    reader._palm_toolbar(true, palm, 0.1)
    assert(not reader.toolbar.visible, "Short palm glance does not flicker the menu")
    reader._palm_toolbar(true, palm, 0.1)
    assert(reader.toolbar.visible and reader.toolbar.global_position.is_equal_approx(palm + Vector3.UP * 0.06), "Dwell reveals menu above palm without flying in")
    reader._palm_toolbar(false, palm, 0.2)
    assert(not reader.toolbar.visible, "Turning the palm away hides the menu immediately")
    reader.ui_capture = {"panel": reader.panels[0], "pixel": Vector2.ZERO}
    var captured_pose: Transform3D = reader.toolbar.global_transform
    reader.ui_owner = "right"
    reader._palm_toolbar(false, palm + Vector3.RIGHT, 0.5)
    assert(not reader.toolbar.visible, "Captured selection must not keep an averted palm menu visible")
    reader.ui_capture.clear()
    reader.ui_owner = ""
    reader._palm_toolbar(false, palm, 0.5)
    assert(not reader.toolbar.visible, "Menu hides after capture and grace end")
    reader.ui.perform("Book Options")
    reader._palm_toolbar(false, Vector3.ZERO, 0.1)
    assert(reader.toolbar.visible, "Controller menu reveals the toolbar without hands")
    reader.queue_free()
    await process_frame
    print("PASS: palm dwell, attachment, grace, captured stability and controller reveal")
    quit()
