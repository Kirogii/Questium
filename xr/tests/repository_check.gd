extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    var ui = reader.workspace
    ui.show_section("Source Search")
    ui.show_repositories()
    assert(ui.repository_panel.node.visible, "Repository section opens from Sources")
    assert(ui.repository_panel.node in ui.roots(), "Repository panel follows distance and recenter controls")
    assert(ui.handle_at(ui.repository_panel.node.global_position) == ui.repository_panel.node, "Repository popup can be fist-dragged and stays on top")
    ui.add_repository()
    assert(not ui.repository_pending and not ui.repository_add.disabled, "Empty URL is rejected before requesting network validation")
    ui.repository_url.text = "https://example.com/index.min.json"
    ui.add_repository()
    ui.add_repository()
    assert(ui.repository_pending and ui.repository_add.disabled, "Network addition cannot be submitted twice")
    reader._response(JSON.stringify({"kind": "repository_status", "success": false, "message": "Invalid repository"}))
    assert(not ui.repository_pending and not ui.repository_add.disabled and not ui.repository_url.text.is_empty(), "Failure permits retry and keeps the URL")
    ui.add_repository()
    reader._response(JSON.stringify({"kind": "repository_status", "success": true, "message": "Repository added."}))
    reader._response(JSON.stringify({"kind": "repositories", "items": [{"title": "Test repo", "url": "https://example.com/index.min.json"}]}))
    assert(ui.repository_url.text.is_empty() and ui.repository_list.get_child_count() == 3, "Validated repository displays its saved title and URL")
    ui.repository_panel.node.visible = false
    assert(ui.repository_panel.node.get_meta("popup_priority", 0) > 0, "Repository panel uses popup depth priority")
    reader.queue_free()
    await process_frame
    print("PASS: repository form, empty input, pending guard, retry, saved list, topmost popup and fist dragging")
    quit()
