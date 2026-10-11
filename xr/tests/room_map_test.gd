extends SceneTree

func _initialize() -> void:
    var room := Node3D.new()
    room.set_script(load("res://room.gd"))
    get_root().add_child(room)
    call_deferred("_check", room)

func _check(room: Node3D) -> void:
    if FileAccess.get_sha256("res://scenes/bar_end.fbx") != FileAccess.get_sha256("D:/VR Kommiku/scenes/bar_end.fbx"):
        printerr("Shipped FBX differs from authoritative source")
        quit(1)
        return
    if room.map_source != "res://scenes/bar_end.fbx":
        printerr("Expected the shipped FBX, got: ", room.map_source)
        quit(1)
        return
    if room.imported_map == null or room.collision_bodies.size() < 28 or room.seat_points.size() != 21:
        printerr("Imported geometry, collision, or seat points missing")
        quit(1)
        return
    if room.bounds.size.y < 20.0 or room.bounds.size.x < 12.0:
        printerr("Bounds did not come from the FBX floor: ", room.bounds)
        quit(1)
        return
    if room.fixture_points.size() != 10 or room.textured_surfaces < 200:
        printerr("Actual pendant emit surfaces/textures missing: ", room.fixture_points.size(), " / ", room.textured_surfaces)
        quit(1)
        return
    var dust_count := 0
    var flame_count := 0
    var shaft_count := 0
    for child in room.get_children():
        if child is CPUParticles3D and String(child.name).begins_with("SparseDust_"):
            dust_count += 1
            if child.amount != 8 or child.mesh.material.albedo_color.a > 0.05:
                printerr("Dust is not sparse/faint")
                quit(1)
                return
        if String(child.name).begins_with("WhiteBulbFlame_"):
            flame_count += 1
        if child.has_meta("volumetric_light_shaft"):
            shaft_count += 1
        if child is SpotLight3D and String(child.name).begins_with("Bulb_") and not room.fixture_points.has(child.position):
            printerr("Fixture light not anchored to imported bulb")
            quit(1)
            return
    if dust_count != 10 or flame_count != 10 or shaft_count != 10:
        printerr("Bulb effects missing")
        quit(1)
        return
    print("PASS FBX map_source=", room.map_source, " bounds=", room.bounds, " seats=", room.seat_points.size(), " bulbs=", room.fixture_points.size(), " textures=", room.textured_surfaces, " dust/flames/shafts=", dust_count)
    quit()
