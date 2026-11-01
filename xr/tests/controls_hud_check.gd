extends SceneTree

func _initialize() -> void: check.call_deferred()

func find_text(node: Node, text: String) -> BaseButton:
    if node is BaseButton and node.text == text: return node
    if node is Label and node.text == text:
        var parent := node.get_parent()
        while parent != null:
            if parent is BaseButton: return parent
            parent = parent.get_parent()
    for child in node.get_children():
        var found := find_text(child, text)
        if found: return found
    return null

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.ui
    var workspace = reader.workspace
    workspace.nav_buttons["Browse"].pressed.emit()
    assert(workspace.section == "Source Search" and not workspace.picker.node.visible)
    find_text(workspace.source_row, "Choose Source").pressed.emit()
    assert(workspace.picker.node.visible)
    workspace.show_settings()
    workspace.settings.select_tab(1)
    find_text(workspace.settings.sidebar, "Controls").pressed.emit()
    for frame in 4: await process_frame
    assert(workspace.heading.text == "Controls")
    ui.config_path = "user://controls-hud-check.cfg"
    var toggle: CheckButton = find_text(workspace.gallery, "Hand sweep / chop page turns")
    toggle.button_pressed = false
    assert(not ui.gestures.page_turn)
    var choice: OptionButton = workspace.gallery.get_child(1).get_child(1)
    choice.item_selected.emit(ui.ACTIONS.find("None"))
    assert(reader.bindings[reader.bindings.keys()[0]] == "None")
    ui.gestures.page_turn = true
    ui.load_config()
    assert(not ui.gestures.page_turn, "Gesture switches persist after reload")
    assert(reader.bindings[reader.bindings.keys()[0]] == "None", "Bindings persist after reload")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(ui.config_path))
    reader._build_hud_composition_view()
    var white := ColorRect.new()
    white.color = Color.WHITE
    white.size = Vector2(workspace.hud.pixels)
    workspace.hud.viewport.add_child(white)
    workspace.hud.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    reader.hud_composition_view.size = workspace.hud.viewport.size
    reader.hud_composition_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    for frame in 8: await process_frame
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        var image: Image = reader.hud_composition_view.get_texture().get_image()
        assert(image.get_pixel(1, 1).a < 0.01)
        assert(image.get_pixel(image.get_width() - 2, image.get_height() - 2).a < 0.01)
        assert(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a > 0.99)
    reader.queue_free()
    await process_frame
    print("PASS: Browse picker is explicit, Controls bindings/gesture persistence, rounded HUD output")
    quit()
