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
    assert(reader.room.map_source == "res://scenes/bar_end.fbx", "Default scene is the supplied bar")
    assert(reader.room.get_seat_points().size() == 21, "Map exposes actual stools and booth seats")
    for point in reader.room.get_seat_points():
        assert(point.get_meta("interactable", false), "Seat points are interactable")
        assert(not str(point.get_meta("seat_group")) in reader.room.TABLE_MESHES, "Tables cannot be mistaken for seats")
    assert(reader.room.collision_bodies.size() >= 5, "Floor, walls, and seat/table surfaces have collision")
    assert(load("res://toon_environment.gdshader") != null)
    assert(load("res://fire_animated.gdshader") != null)
    reader._set_scenes_enabled(false)
    assert(not reader.room.visible, "Scenes setting hides the map")
    reader._set_scenes_enabled(true)
    assert(reader.room.visible, "Scenes setting restores the map")
    reader.queue_free()
    await process_frame
    print("PASS: scene setting, supplied bar, actual stools/booths, collision and focused shaders")
    quit()
