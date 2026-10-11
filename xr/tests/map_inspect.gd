extends SceneTree

func _initialize() -> void:
    var map = load("res://scenes/bar_end.fbx").instantiate()
    root.add_child(map)
    call_deferred("finish", map)

func finish(map: Node) -> void:
    inspect(map)
    quit()

func inspect(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh: MeshInstance3D = node
        print(mesh.name, " world_box=", mesh.global_transform * mesh.mesh.get_aabb())
        for i in mesh.mesh.get_surface_count():
            var mat = mesh.get_active_material(i)
            print("  material ", mat.resource_name, " ", mat.albedo_color if mat is StandardMaterial3D else "", " texture=", mat.albedo_texture.resource_path if mat is StandardMaterial3D and mat.albedo_texture else "none", " emission=", mat.emission if mat is StandardMaterial3D else "")
    for child in node.get_children():
        inspect(child)
