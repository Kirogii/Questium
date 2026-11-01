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
    var bridge := Bridge.new()
    reader.bridge = bridge
    reader._set_scenes_enabled(true)
    reader._set_passthrough(true)
    assert(not reader.scenes_enabled and not reader.room.visible, "First See through activation hides the scene")
    assert(bridge.requests[-1].action == "scene_mode" and not bridge.requests[-1].enabled, "See through persists the shared Android scene preference")
    reader._response(JSON.stringify({"kind": "reader_filters", "scenes": true}))
    assert(not reader.room.visible, "An older settings snapshot cannot undo the pending toggle")
    reader._response(JSON.stringify({"kind": "reader_filters", "scenes": false}))
    assert(reader.pending_scene_mode == null)
    for cycle in 2:
        reader.workspace.show_settings()
        reader.workspace.settings.select_tab(1)
        assert(reader.workspace.hud.background.get_theme_stylebox("panel").bg_color.a == 1.0, "Settings keeps the HUD opaque")
        reader._response(JSON.stringify({"kind": "reader_filters", "scenes": false}))
        assert(not reader.room.visible and not reader.scenes_enabled)
        reader.workspace.show_section("Home")
        reader._response(JSON.stringify({"kind": "reader_filters", "scenes": false}))
        assert(not reader.room.visible and not reader.scenes_enabled, "Leaving Settings retains See through")
        assert(reader.workspace.hud.background.get_theme_stylebox("panel").bg_color.a == 1.0, "Leaving Settings keeps the HUD opaque")
    reader._set_passthrough(false)
    assert(reader.scenes_enabled and reader.room.visible, "Disabling See through restores the scene")
    reader._response(JSON.stringify({"kind": "reader_filters", "scenes": true}))
    var requests_before: int = bridge.requests.size()
    reader._response(JSON.stringify({"kind": "reader_filters", "scenes": false}))
    assert(not reader.scenes_enabled and not reader.room.visible, "Android scene setting remains authoritative after synchronization")
    assert(bridge.requests.size() == requests_before, "Incoming preferences do not echo back to Android")
    reader._set_scenes_enabled(true)
    reader.bridge = null
    reader.queue_free()
    await process_frame
    print("PASS: first See through toggle, shared scene preference, stale snapshots, settings entry/exit, opaque HUD")
    quit()
