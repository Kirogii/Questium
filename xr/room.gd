extends Node3D

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.position = at
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.95
    node.material_override = material
    add_child(node)
    return node

func _ready() -> void:
    name = "UnfurnishedReferenceRoom"
    _box(Vector3(12, 0.08, 10), Vector3(0, -0.045, 0), Color(0.47, 0.48, 0.49))
    # One instanced draw for all planks keeps the room affordable on Quest.
    var planks := MultiMeshInstance3D.new()
    var instances := MultiMesh.new()
    instances.transform_format = MultiMesh.TRANSFORM_3D
    instances.use_colors = true
    var plank := BoxMesh.new()
    plank.size = Vector3(0.295, 0.012, 1.66)
    instances.mesh = plank
    instances.instance_count = 240
    for row in range(40):
        for board in range(6):
            var index := row * 6 + board
            var tone := 0.39 + float(posmod(row * 17 + board * 11, 9)) * 0.018
            instances.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(-5.85 + row * 0.3, 0, -4.16 + board * 1.665)))
            instances.set_instance_color(index, Color(tone, tone + 0.01, tone + 0.018))
    planks.multimesh = instances
    var wood := StandardMaterial3D.new()
    wood.vertex_color_use_as_albedo = true
    wood.roughness = 0.95
    planks.material_override = wood
    add_child(planks)
    _box(Vector3(12, 0.08, 10), Vector3(0, 3.65, 0), Color(0.76, 0.77, 0.78))
    _box(Vector3(0.12, 3.6, 10), Vector3(-6, 1.8, 0), Color(0.68, 0.69, 0.70))
    _box(Vector3(0.12, 3.6, 10), Vector3(6, 1.8, 0), Color(0.68, 0.69, 0.70))
    _box(Vector3(12, 3.6, 0.12), Vector3(0, 1.8, 5), Color(0.68, 0.69, 0.70))
    _box(Vector3(12, 0.45, 0.12), Vector3(0, 0.225, -5), Color(0.68, 0.69, 0.70))
    _box(Vector3(12, 0.65, 0.12), Vector3(0, 3.275, -5), Color(0.68, 0.69, 0.70))
    for x in [-5.5, -2.0, 2.0, 5.5]:
        _box(Vector3(1.0, 2.5, 0.12), Vector3(x, 1.7, -5), Color(0.68, 0.69, 0.70))
    for x in [-3.75, 0.0, 3.75]:
        var pane := _box(Vector3(2.55, 2.5, 0.04), Vector3(x, 1.7, -5.04), Color(0.89, 0.94, 0.94))
        pane.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        for dx in [-1.27, 0, 1.27]:
            _box(Vector3(0.055, 2.5, 0.08), Vector3(x + dx, 1.7, -4.94), Color(0.37, 0.39, 0.39))
        _box(Vector3(2.55, 0.055, 0.08), Vector3(x, 1.7, -4.94), Color(0.37, 0.39, 0.39))
        # Folded blinds at each side, with a narrow header above the frame.
        _box(Vector3(2.9, 0.1, 0.14), Vector3(x, 3.0, -4.86), Color(0.83, 0.83, 0.80))
        for side in [-1, 1]:
            for fold in range(7):
                var curtain := _box(Vector3(0.065, 2.65, 0.10), Vector3(x + side * (1.12 + fold * 0.035), 1.60, -4.83 + sin(fold * 1.7) * 0.05), Color(0.77 + fold % 2 * 0.04, 0.78 + fold % 2 * 0.04, 0.78 + fold % 2 * 0.04))
                curtain.rotation.z = side * 0.035
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -25, 0)
    sun.light_energy = 0.75
    add_child(sun)
