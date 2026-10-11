extends Node3D

## The shipped bar is authoritative: its imported geometry determines the room.
const MAP_PATH := "res://scenes/bar_end.fbx"
const SHAFT_SHADER = preload("res://light_shaft.gdshader")
const MAP_SHADER = preload("res://map_noir.gdshader")
const FLAME_SHADER = preload("res://fire_animated.gdshader")
const MAP_OFFSET := Vector3(1.5, 0.0, 24.0)
const TABLE_MESHES := ["Cube_018", "Cube_028", "Cube_048", "Cube_049", "Cube_039", "Cube_044"]
const STOOL_MESHES := ["Cube_014", "Cube_015", "Cube_016", "Cube_017", "Cube_019", "Cube_020", "Cube_021", "Cube_022", "Cube_038"]
const BOOTH_MESHES := ["Cube_023", "Cube_024", "Cube_029", "Cube_030", "Cube_040", "Cube_041", "Cube_045", "Cube_046", "Cube_050", "Cube_051", "Cube_053", "Cube_054"]

var map_source := ""
var imported_map: Node3D
var collision_bodies: Array[StaticBody3D] = []
var seat_points: Array[Node3D] = []
var floor_y := 0.0
var bounds := Rect2()
var fixture_points: Array[Vector3] = []
var textured_surfaces := 0

func _ready() -> void:
    name = "BarScene"
    var resource := load(MAP_PATH) as PackedScene
    if resource == null:
        push_error("Required bar map could not be imported: " + MAP_PATH)
        return
    imported_map = resource.instantiate() as Node3D
    if imported_map == null:
        push_error("Required bar map has no 3D root: " + MAP_PATH)
        return
    imported_map.position = MAP_OFFSET
    add_child(imported_map)
    map_source = MAP_PATH
    var floor_mesh := _find_mesh(imported_map, "Plane_009")
    if floor_mesh == null:
        push_error("Bar map floor Plane_009 is missing")
        return
    var floor_box := _world_box(floor_mesh)
    floor_y = floor_box.position.y
    bounds = Rect2(floor_box.position.x, floor_box.position.z, floor_box.size.x, floor_box.size.z)
    _surface_collision(Vector3(floor_box.size.x, 0.12, floor_box.size.z), Vector3(floor_box.get_center().x, floor_y - 0.06, floor_box.get_center().z), "FloorSurface")
    _build_furniture(imported_map)
    _dress_map(imported_map)
    _build_counter_lighting()
    var reflections := ReflectionProbe.new()
    reflections.name = "BarSurfaceReflections"
    reflections.position = Vector3(bounds.get_center().x, 1.5, bounds.get_center().y)
    reflections.size = Vector3(bounds.size.x, 6.0, bounds.size.y)
    reflections.box_projection = true
    reflections.interior = true
    reflections.ambient_mode = ReflectionProbe.AMBIENT_COLOR
    reflections.ambient_color = Color("9eabc1")
    reflections.ambient_color_energy = 0.045
    reflections.cull_mask = 2
    reflections.intensity = 0.55
    add_child(reflections)
    # Furniture accents are bounded fills, separate from the real fixture shafts.
    for seat in seat_points:
        var fill := OmniLight3D.new()
        fill.name = "ChairFill_" + String(seat.get_meta("seat_group"))
        fill.position = seat.position + Vector3(0.0, 0.70, 0.0)
        fill.light_color = Color("c9b7a4")
        fill.light_energy = 1.1
        fill.light_cull_mask = 2
        fill.omni_range = 1.45
        add_child(fill)

func _dress_map(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        mesh_node.layers = 2
        for surface in mesh_node.mesh.get_surface_count():
            var original := mesh_node.get_active_material(surface) as StandardMaterial3D
            if original == null:
                continue
            # Keep imported glass/foliage transparency and all atlas UVs intact.
            if original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
                continue
            var material := ShaderMaterial.new()
            material.shader = MAP_SHADER
            material.set_shader_parameter("base_color", original.albedo_color)
            if node.name == "Plane_009":
                material.set_shader_parameter("surface_roughness", 0.24)
                material.set_shader_parameter("surface_specular", 0.75)
            elif node.name in TABLE_MESHES or node.name in ["Plane_023", "Cube_003"]:
                material.set_shader_parameter("surface_roughness", 0.16)
                material.set_shader_parameter("surface_specular", 0.9)
            material.set_shader_parameter("has_texture", original.albedo_texture != null)
            if original.albedo_texture:
                material.set_shader_parameter("albedo_texture", original.albedo_texture)
                textured_surfaces += 1
            mesh_node.set_surface_override_material(surface, material)
            # Circle_001..010 are the imported pendant bulbs. The EMIT surface
            # vertices, rather than the cord/shade AABB, locate the actual bulb.
            if String(node.name).begins_with("Circle_") and int(String(node.name).get_slice("_", 1)) <= 10 and original.resource_name.ends_with(".EMIT"):
                material.set_shader_parameter("bulb_emission", 1.8)
                var arrays := mesh_node.mesh.surface_get_arrays(surface)
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                var center := Vector3.ZERO
                for vertex in vertices:
                    center += vertex
                center = mesh_node.global_transform * (center / maxf(vertices.size(), 1))
                fixture_points.append(center)
                _pool_light(center, "Bulb_" + String(node.name), 0.85, 3.5)
                _fixture_flame(center)
    for child in node.get_children():
        _dress_map(child)

func _fixture_flame(at: Vector3) -> void:
    var flame := MeshInstance3D.new()
    flame.name = "WhiteBulbFlame_%02d" % fixture_points.size()
    var quad := QuadMesh.new()
    quad.size = Vector2(0.075, 0.12)
    flame.mesh = quad
    # A slight downward lift clears the opaque bulb surface for the tiny lick.
    flame.position = at + Vector3.DOWN * 0.09
    var material := ShaderMaterial.new()
    material.shader = FLAME_SHADER
    flame.material_override = material
    flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(flame)
    var sparks := CPUParticles3D.new()
    sparks.name = "WhiteFireParticles_%02d" % fixture_points.size()
    sparks.position = flame.position
    sparks.amount = 5
    sparks.lifetime = 0.55
    sparks.preprocess = 0.55
    sparks.gravity = Vector3(0.0, 0.045, 0.0)
    sparks.direction = Vector3.UP
    sparks.spread = 12.0
    sparks.initial_velocity_min = 0.015
    sparks.initial_velocity_max = 0.04
    sparks.scale_amount_min = 0.18
    sparks.scale_amount_max = 0.35
    sparks.mesh = quad.duplicate()
    sparks.mesh.material = material
    add_child(sparks)
    var dust := CPUParticles3D.new()
    dust.name = "SparseDust_%02d" % fixture_points.size()
    dust.position = at + Vector3.DOWN * 1.0
    dust.amount = 8
    dust.lifetime = 12.0
    dust.preprocess = 12.0
    dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    dust.emission_box_extents = Vector3(0.5, 0.85, 0.5)
    dust.gravity = Vector3(0.0, 0.006, 0.0)
    dust.initial_velocity_min = 0.008
    dust.initial_velocity_max = 0.018
    dust.scale_amount_min = 0.003
    dust.scale_amount_max = 0.007
    var mote := SphereMesh.new()
    mote.radius = 0.5
    mote.height = 1.0
    mote.radial_segments = 4
    mote.rings = 2
    var dust_material := StandardMaterial3D.new()
    dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    dust_material.albedo_color = Color(0.65, 0.65, 0.65, 0.045)
    mote.material = dust_material
    dust.mesh = mote
    add_child(dust)

func _find_mesh(node: Node, mesh_name: String) -> MeshInstance3D:
    if node is MeshInstance3D and node.name == mesh_name:
        return node as MeshInstance3D
    for child in node.get_children():
        var found := _find_mesh(child, mesh_name)
        if found:
            return found
    return null

func _world_box(mesh_node: MeshInstance3D) -> AABB:
    var local := mesh_node.mesh.get_aabb()
    var box := AABB(mesh_node.global_transform * local.position, Vector3.ZERO)
    for x in [local.position.x, local.end.x]:
        for y in [local.position.y, local.end.y]:
            for z in [local.position.z, local.end.z]:
                box = box.expand(mesh_node.global_transform * Vector3(x, y, z))
    return box

func _build_furniture(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        var box := _world_box(mesh_node)
        # Imported booths, counter and tables: collide with the actual occupied footprint.
        if node.name in TABLE_MESHES or node.name == "Cube_003":
            _surface_collision(Vector3(box.size.x, maxf(box.size.y, 0.08), box.size.z), box.get_center(), node.name + "Surface")
        if node.name in STOOL_MESHES or node.name in BOOTH_MESHES:
            var seat_height := box.end.y if node.name in STOOL_MESHES else box.position.y + 0.47
            _surface_collision(Vector3(box.size.x, seat_height - floor_y, box.size.z), Vector3(box.get_center().x, (floor_y + seat_height) * 0.5, box.get_center().z), node.name + "SeatSurface")
            var point := Marker3D.new()
            point.name = "SeatPoint_%02d" % seat_points.size()
            point.position = Vector3(box.get_center().x, seat_height, box.get_center().z)
            point.set_meta("seat_group", String(node.name))
            point.set_meta("seat_index", seat_points.size())
            point.set_meta("interactable", true)
            point.set_meta("movable", true)
            point.set_meta("target_kind", "seat")
            point.set_meta("seat_height", point.position.y)
            point.set_meta("reach_radius", 0.72)
            add_child(point)
            seat_points.append(point)
    for child in node.get_children():
        _build_furniture(child)

func _surface_collision(size: Vector3, at: Vector3, surface_name: String) -> void:
    var body := StaticBody3D.new()
    body.name = surface_name
    body.collision_layer = 1
    body.position = at
    body.set_meta("room_surface", true)
    body.set_meta("walkable", surface_name == "FloorSurface")
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    add_child(body)
    collision_bodies.append(body)

func _pool_light(at: Vector3, light_name: String, energy: float, light_range: float) -> void:
    var light := SpotLight3D.new()
    light.name = light_name
    light.position = at
    light.rotation_degrees.x = -90
    light.light_color = Color("d7c7b5")
    light.light_energy = energy
    light.light_cull_mask = 2
    light.spot_range = light_range
    light.spot_angle = 62.0
    light.shadow_enabled = false
    add_child(light)
    var shaft := MeshInstance3D.new()
    shaft.name = light_name + "Godrays"
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.12
    mesh.bottom_radius = 0.65
    mesh.height = 2.7
    shaft.mesh = mesh
    shaft.position = at + Vector3.DOWN * 1.35
    var material := ShaderMaterial.new()
    material.shader = SHAFT_SHADER
    material.set_shader_parameter("tint", Color("d7c7b5"))
    material.set_shader_parameter("opacity", 0.48)
    shaft.material_override = material
    shaft.set_meta("volumetric_light_shaft", true)
    shaft.set_meta("bulb_position", at)
    shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(shaft)
    _fit_light_shaft.call_deferred(shaft)

func _fit_light_shaft(shaft: MeshInstance3D) -> void:
    await get_tree().physics_frame
    if not is_instance_valid(shaft): return
    var at: Vector3 = shaft.get_meta("bulb_position")
    var query := PhysicsRayQueryParameters3D.create(at + Vector3.DOWN * 0.02, Vector3(at.x, floor_y - 0.1, at.z))
    query.collision_mask = 1
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    var end_y := float(hit.position.y) if not hit.is_empty() else floor_y
    var beam_height := maxf(0.05, at.y - end_y - 0.015)
    (shaft.mesh as CylinderMesh).height = beam_height
    shaft.position = at + Vector3.DOWN * beam_height * 0.5
    shaft.material_override.set_shader_parameter("height", beam_height)

func _build_counter_lighting() -> void:
    # The supplied model's long glass/counter run is around x=2.7, z=4 after
    # the model offset. Give it a broad, shadow-casting wash so the worktop and
    # bottles read as the visual focal point instead of disappearing into the
    # global noir exposure.
    for index in range(3):
        var light := SpotLight3D.new()
        light.name = "CounterWash_%02d" % index
        light.position = Vector3(2.55 + float(index) * 0.42, 3.15, 3.8)
        light.rotation_degrees = Vector3(-90, 0, 0)
        light.light_color = Color("ffd7ae")
        light.light_energy = 2.15
        light.light_cull_mask = 2
        light.spot_range = 5.5
        light.spot_angle = 54.0
        light.spot_angle_attenuation = 1.0
        light.shadow_enabled = index == 1
        add_child(light)
    var counter_glow := OmniLight3D.new()
    counter_glow.name = "CounterBounce"
    counter_glow.position = Vector3(2.8, 1.55, 3.15)
    counter_glow.light_color = Color("d9986d")
    counter_glow.light_energy = 0.78
    counter_glow.light_cull_mask = 2
    counter_glow.omni_range = 3.8
    add_child(counter_glow)

func resolve_book_transform(book: Node3D) -> void:
    if not is_instance_valid(book) or not book.visible or map_source.is_empty():
        return
    var position := book.global_position
    var world := get_world_3d()
    if world:
        var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.25, position - Vector3.UP * 2.0)
        query.collision_mask = 1
        var hit := world.direct_space_state.intersect_ray(query)
        if not hit.is_empty():
            position.y = maxf(position.y, float(hit.position.y) + 0.075)
    position.y = maxf(position.y, floor_y + 0.075)
    position.x = clampf(position.x, bounds.position.x + 0.18, bounds.end.x - 0.18)
    position.z = clampf(position.z, bounds.position.y + 0.18, bounds.end.y - 0.18)
    book.global_position = position

func get_seat_points() -> Array[Node3D]:
    return seat_points

func get_locomotion_targets() -> Array[Node3D]:
    # Keep target discovery owned by the imported room. This avoids guessing
    # furniture positions in the reader and makes the circles follow the real map.
    return seat_points
