extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func toggle_for(parent: Node, caption: String) -> CheckButton:
    for child in parent.get_children():
        if child is HBoxContainer and child.get_child_count() == 2 and child.get_child(0) is Label and child.get_child(0).text == caption:
            return child.get_child(1) as CheckButton
    return null

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.ui.config_path = "D:/VR Kommiku/artifacts/book-test-controls.cfg"
    reader.ui.config.clear()
    reader.ui.load_config()
    assert(reader.ui.hard_cover and reader.ui.book_sfx, "Hardcover and book sounds default on")
    reader.book.token = "test"
    reader.book.set_hard_cover(true)
    reader.book.set_open(0.0)
    reader.book.global_position = reader.camera.global_position + Vector3(2, 0, -2)
    var start: Vector3 = reader.book.global_position
    reader.summon_book()
    assert(reader.book_flight.is_running())
    assert(reader.book.global_position.is_equal_approx(start), "Recall starts from the placed book")
    await create_timer(0.8).timeout
    var local: Vector3 = reader.camera.global_basis.inverse() * (reader.book.global_position - reader.camera.global_position)
    assert(absf(local.x) < 0.01 and is_equal_approx(local.z, -0.65), "Book flies to a reachable reading pose")
    assert(reader.book.openness > 0.99, "Summoned book opens for reading")
    var workspace = reader.workspace
    workspace.show_settings()
    workspace.settings.select_tab(1)
    assert(workspace.settings.tabs.visible and workspace.settings.tabs.get_child_count() == 2)
    for caption in ["Hard Cover", "Book SFX", "Stretch pages to fit", "Upscale Manga", "Force two pages", "Force long scroll", "Haptic feedback", "See through"]:
        assert(toggle_for(workspace.gallery, caption) != null, "Questium contains " + caption)
    var sfx := toggle_for(workspace.gallery, "Book SFX")
    sfx.button_pressed = false
    assert(not reader.ui.book_sfx and not reader.book.sfx_enabled)
    reader.book.play_sfx("page")
    for player in reader.book.sfx_players: assert(not player.playing, "Mute stops and suppresses sound")
    var saved := ConfigFile.new()
    assert(saved.load(reader.ui.config_path) == OK and saved.get_value("reader", "book_sfx") == false)
    toggle_for(workspace.gallery, "Hard Cover").button_pressed = false
    assert(not reader.book.hard_cover)
    sfx.button_pressed = true
    reader.book.last_sfx_at = -1000
    reader.book.play_sfx("page")
    assert(reader.book.sfx_players[0].playing, "Enabled book actions play imported audio")
    reader.book.stop_sfx()
    workspace.settings.select_tab(0)
    assert(workspace.heading.text == "Tachiyomi Settings")
    workspace.hud_back.pressed.emit()
    assert(workspace.section == "Home" and workspace.hud.node.visible, "Settings arrow returns to main UI without closing it")
    DirAccess.remove_absolute(reader.ui.config_path)
    reader.queue_free()
    await process_frame
    print("PASS: book recall, default hardcover, shared settings tabs, persisted SFX mute and back navigation")
    quit()
