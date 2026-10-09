extends Node3D

## Scene/map host for the spatial reader.
##
## A map scene is optional.  The importer can load a packed scene placed in
## res://scenes, but the fallback below is deliberately complete so a fresh
## checkout still has a usable bar, floor, walls, seats, and fire.

const MAP_DIRECTORY := "res://scenes"
const MAP_NAMES := ["bar_end.tscn", "bar_end.glb", "bar_end.gltf"]
const TOON_SHADER = preload("res://toon_environment.gdshader")
const FIRE_SHADER = preload("res://fire_animated.gdshader")
const POST_SHADER = preload("res://scene_post_process.gdshader")
const SHAFT_SHADER = preload("res://light_shaft.gdshader")

var map_source := "procedural-bar-fallback"
var imported_map: Node3D
var collision_bodies: Array[StaticBody3D] = []
var seat_points: Array[Node3D] = []
var floor_y := 0.0
var bounds := Rect2(-6.0, -5.0, 12.0, 10.0)

func _ready() -> void:
    name = "BarScene"
    if not _load_project_scene():
        _build_bar_fallback()
    else:
        _build_imported_seat_points()
    # Imported art is not trusted to contain usable physics. Keep the reader
    # collision contract stable for both imported and procedural maps.
    _build_collision_surfaces()

func _load_project_scene() -> bool:
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(MAP_DIRECTORY)):
        return false
    for filename in MAP_NAMES:
        var path := MAP_DIRECTORY.path_join(filename)
        if not ResourceLoader.exists(path):
            continue
        var resource := load(path)
        if resource is PackedScene:
            var instance := (resource as PackedScene).instantiate()
            if not instance is Node3D:
                instance.queue_free()
                continue
            imported_map = instance as Node3D
            add_child(imported_map)
            map_source = path
            _apply_scene_materials(imported_map)
            return true
    return false

func _apply_scene_materials(node: Node) -> void:
    for child in node.get_children():
        if child is MeshInstance3D:
            var mesh_node := child as MeshInstance3D
            # Preserve imported textures/materials. The toon shader is used
            # by the procedural fallback; imported art remains artist-owned.
            mesh_node.set_meta("scene_map_mesh", true)
        _apply_scene_materials(child)

func _toon(color: Color, emission: Color = Color.BLACK) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = TOON_SHADER
    material.set_shader_parameter("base_color", color)
    material.set_shader_parameter("emission_color", emission)
    material.set_shader_parameter("emission_strength", 0.0 if emission == Color.BLACK else 0.35)
    return material

func _box(size: Vector3, at: Vector3, color: Color, collision := false) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.position = at
    node.material_override = _toon(color)
    add_child(node)
    if collision:
        _surface_collision(size, at, node.name + "Surface")
    return node

func _surface_collision(size: Vector3, at: Vector3, surface_name: String) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = surface_name
    body.collision_layer = 1
    body.collision_mask = 1
    body.position = at
    body.set_meta("room_surface", true)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    add_child(body)
    collision_bodies.append(body)
    return body

func _build_collision_surfaces() -> void:
    # A low, explicit collision shell works with imported scenes and prevents
    # a book from falling through maps whose FBX importer has no colliders.
    _surface_collision(Vector3(12.0, 0.12, 10.0), Vector3(0, -0.06, 0), "FloorSurface")
    _surface_collision(Vector3(12.0, 3.6, 0.12), Vector3(0, 1.8, 5.0), "BackWallSurface")
    _surface_collision(Vector3(0.12, 3.6, 10.0), Vector3(-6.0, 1.8, 0), "LeftWallSurface")
    _surface_collision(Vector3(0.12, 3.6, 10.0), Vector3(6.0, 1.8, 0), "RightWallSurface")
    _surface_collision(Vector3(12.0, 0.12, 10.0), Vector3(0, 3.7, 0), "CeilingSurface")

func _build_bar_fallback() -> void:
    # The fallback is intentionally low-poly and instancing-friendly for Quest.
    _box(Vector3(12, 0.08, 10), Vector3(0, -0.045, 0), Color("21171a"))
    _box(Vector3(12, 3.6, 0.12), Vector3(0, 1.8, 5), Color("151116"))
    _box(Vector3(0.12, 3.6, 10), Vector3(-6, 1.8, 0), Color("1b161b"))
    _box(Vector3(0.12, 3.6, 10), Vector3(6, 1.8, 0), Color("1b161b"))
    var backer := _box(Vector3(8.8, 2.5, 0.08), Vector3(0, 1.55, 4.91), Color("24161b"))
    backer.material_override = _post_material(Color("24161b"))

    # Back bar and shelves.
    _box(Vector3(5.8, 1.0, 0.72), Vector3(0, 0.55, 3.65), Color("39211b"), true)
    _box(Vector3(5.8, 0.10, 0.88), Vector3(0, 1.10, 3.65), Color("6c3f29"), true)
    for shelf_y in [1.65, 2.25, 2.85]:
        _box(Vector3(5.4, 0.07, 0.42), Vector3(0, shelf_y, 4.20), Color("47261e"), true)
    for x in [-2.1, -1.4, -0.7, 0.0, 0.7, 1.4, 2.1]:
        _bottle(Vector3(x, 1.38 + fmod(absf(x), 0.3), 4.02))

    # A single soft bar pool keeps the shelves readable without flooding the room.
    _pool_light(Vector3(0, 3.15, 3.15), "BarPoolLight", 1.75, 4.1, 76.0)
    _light_shaft(Vector3(0, 3.52, 3.15), 2.25, 0.58, Color("e39a5f"), 0.055)
    _fixture(Vector3(0, 3.46, 3.15), Vector3(0.34, 0.07, 0.34))

    # Reader-friendly tables and two-person seating groups.
    _table(Vector3(-3.4, 0, -1.15), 2)
    _table(Vector3(0.0, 0, -1.15), 2)
    _table(Vector3(3.4, 0, -1.15), 2)
    _table(Vector3(-2.0, 0, -3.65), 2)
    _table(Vector3(2.0, 0, -3.65), 2)

    # A small fireplace gives the fallback the supplied bar-map focal point.
    _box(Vector3(1.65, 1.2, 0.30), Vector3(-4.6, 0.62, 3.92), Color("241217"), true)
    _box(Vector3(1.15, 0.72, 0.08), Vector3(-4.6, 1.34, 3.74), Color("65351f"))
    var flame := MeshInstance3D.new()
    var flame_mesh := SphereMesh.new()
    flame_mesh.radius = 0.35
    flame_mesh.height = 0.86
    flame.mesh = flame_mesh
    flame.position = Vector3(-4.6, 0.92, 3.70)
    var fire_material := ShaderMaterial.new()
    fire_material.shader = FIRE_SHADER
    fire_material.set_shader_parameter("fire_color", Color("ff7a24"))
    fire_material.set_shader_parameter("glow_color", Color("ffd36a"))
    flame.material_override = fire_material
    add_child(flame)

    var ceiling := _box(Vector3(12, 0.08, 10), Vector3(0, 3.65, 0), Color("0b090c"))
    ceiling.material_override = _toon(Color("0b090c"), Color("030204"))
    var light := OmniLight3D.new()
    light.position = Vector3(-4.6, 1.3, 3.0)
    light.light_color = Color("ff9b55")
    light.light_energy = 1.35
    light.omni_range = 4.2
    light.shadow_enabled = false
    add_child(light)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52, -25, 0)
    sun.light_energy = 0.14
    sun.light_color = Color("817781")
    sun.shadow_enabled = false
    add_child(sun)

func _build_imported_seat_points() -> void:
    # The asset is allowed to provide its own art, but interaction points stay
    # deterministic so the reader can offer seating even when FBX metadata is
    # incomplete. These points match the fallback bar's table layout.
    for at in [Vector3(-3.4, 0, -1.15), Vector3(0.0, 0, -1.15), Vector3(3.4, 0, -1.15), Vector3(-2.0, 0, -3.65), Vector3(2.0, 0, -3.65)]:
        var group := "ImportedSeatGroup_%s" % str(seat_points.size())
        _seat_point(group, at + Vector3(-0.58, 0.46, -0.95), Vector3(0, 0, 1))
        _seat_point(group, at + Vector3(0.58, 0.46, -0.95), Vector3(0, 0, 1))

func _post_material(color: Color) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = POST_SHADER
    material.set_shader_parameter("tint", color)
    material.set_shader_parameter("grain_strength", 0.035)
    return material

func _bottle(at: Vector3) -> void:
    var bottle := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.055
    mesh.bottom_radius = 0.09
    mesh.height = 0.36
    bottle.mesh = mesh
    bottle.position = at
    bottle.material_override = _toon(Color(0.10 + fmod(absf(at.x), 0.16), 0.18, 0.14))
    add_child(bottle)

func _table(at: Vector3, people: int) -> void:
    _box(Vector3(1.55, 0.10, 0.90), at + Vector3.UP * 0.86, Color("3b211b"), true)
    for offset in [Vector3(-0.58, 0.42, -0.28), Vector3(0.58, 0.42, -0.28), Vector3(0, 0.42, 0.28)]:
        _box(Vector3(0.10, 0.82, 0.10), at + offset, Color("1a1114"), true)
    var group := "SeatGroup_%s" % str(seat_points.size())
    _seat_point(group, at + Vector3(-0.58, 0.46, -0.95), Vector3(0, 0, 1))
    _seat_point(group, at + Vector3(0.58, 0.46, -0.95), Vector3(0, 0, 1))
    if people > 2:
        _seat_point(group, at + Vector3(0, 0.46, 0.78), Vector3(0, 0, -1))
    _pool_light(at + Vector3(0, 2.82, 0), "TablePoolLight_%02d" % seat_points.size(), 1.15, 3.25, 58.0)
    _light_shaft(at + Vector3(0, 3.50, 0), 2.30, 0.52, Color("d68d58"), 0.040)
    _fixture(at + Vector3(0, 3.45, 0), Vector3(0.26, 0.06, 0.26))

func _pool_light(at: Vector3, light_name: String, energy: float, light_range: float, angle: float) -> void:
    var light := SpotLight3D.new()
    light.name = light_name
    light.position = at
    light.rotation_degrees = Vector3(-90, 0, 0)
    light.light_color = Color("f0a66a")
    light.light_energy = energy
    light.spot_range = light_range
    light.spot_angle = angle
    light.spot_angle_attenuation = 1.4
    light.shadow_enabled = false
    add_child(light)

func _light_shaft(at: Vector3, height: float, radius: float, color: Color, opacity: float) -> void:
    var shaft := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius * 0.22
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 8
    shaft.mesh = mesh
    shaft.position = at + Vector3.DOWN * height * 0.5
    var material := ShaderMaterial.new()
    material.shader = SHAFT_SHADER
    material.set_shader_parameter("tint", color)
    material.set_shader_parameter("opacity", opacity)
    material.set_shader_parameter("emission_strength", 0.7)
    shaft.material_override = material
    shaft.set_meta("volumetric_light_shaft", true)
    add_child(shaft)

func _fixture(at: Vector3, size: Vector3) -> void:
    var fixture := _box(size, at, Color("241713"))
    fixture.material_override = _toon(Color("241713"), Color("d77b3f"))

func _seat_point(group: String, at: Vector3, facing: Vector3) -> void:
    _box(Vector3(0.68, 0.12, 0.60), at + Vector3.DOWN * 0.16, Color("2b181b"), true)
    var point := Marker3D.new()
    point.name = "SeatPoint_%02d" % seat_points.size()
    point.position = at
    point.rotation.y = atan2(facing.x, facing.z)
    point.set_meta("seat_group", group)
    point.set_meta("seat_index", seat_points.size())
    point.set_meta("interactable", true)
    point.set_meta("movable", true)
    add_child(point)
    seat_points.append(point)
    # A small interaction volume makes seat points discoverable by future
    # locomotion/comfort flows without making them physical obstacles.
    var area := Area3D.new()
    area.name = point.name + "Interaction"
    area.collision_layer = 2
    area.collision_mask = 2
    area.position = at
    area.set_meta("seat_point", point)
    var shape := CollisionShape3D.new()
    var sphere := SphereShape3D.new()
    sphere.radius = 0.28
    shape.shape = sphere
    area.add_child(shape)
    add_child(area)

func resolve_book_transform(book: Node3D) -> void:
    if not is_instance_valid(book) or not book.visible:
        return
    var position := book.global_position
    # Prefer the real room physics shell so a released book can rest on the
    # floor, a table, or a seat. The bounds fallback also works in headless
    # tests and before the physics world has completed its first frame.
    var world := get_world_3d()
    if world:
        var space := world.direct_space_state
        var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.25, position - Vector3.UP * 2.0)
        query.collision_mask = 1
        var hit := space.intersect_ray(query)
        if not hit.is_empty():
            position.y = maxf(position.y, float(hit.position.y) + 0.075)
    # SpatialBook is a thin object; keep its center just above the floor.
    position.y = maxf(position.y, floor_y + 0.075)
    position.x = clampf(position.x, bounds.position.x + 0.18, bounds.end.x - 0.18)
    position.z = clampf(position.z, bounds.position.y + 0.18, bounds.end.y - 0.18)
    book.global_position = position

func get_seat_points() -> Array[Node3D]:
    return seat_points
