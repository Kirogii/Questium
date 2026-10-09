extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    assert(reader.scenes_enabled, "Scenes default to enabled")
    assert(is_instance_valid(reader.room), "Reader owns the scene/map host")
    assert(reader.room.map_source == "procedural-bar-fallback" or reader.room.map_source.begins_with("res://scenes/"), "Map source is project-local or explicit fallback")
    assert(reader.room.get_seat_points().size() >= 10, "Fallback bar exposes movable seat points")
    var groups := {}
    for point in reader.room.get_seat_points():
        groups[str(point.get_meta("seat_group"))] = groups.get(str(point.get_meta("seat_group")), 0) + 1
        assert(point.get_meta("interactable", false), "Seat points are interactable")
    for count in groups.values():
        assert(count == 2, "Fallback tables are two-person seats")
    assert(reader.room.collision_bodies.size() >= 5, "Floor, walls, and seat/table surfaces have collision")
    assert(load("res://toon_environment.gdshader") != null)
    assert(load("res://fire_animated.gdshader") != null)
    reader._set_scenes_enabled(false)
    assert(not reader.room.visible, "Scenes setting hides the map")
    reader._set_scenes_enabled(true)
    assert(reader.room.visible, "Scenes setting restores the map")
    reader.queue_free()
    await process_frame
    print("PASS: scene setting, procedural bar fallback, seats, collision shell and focused shaders")
    quit()
