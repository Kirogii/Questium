extends Node3D

var fallback: Node3D

func _init(hand: String = "right") -> void:
    fallback = Node3D.new()
    add_child(fallback)
    var shell := StandardMaterial3D.new()
    shell.albedo_color = Color(0.82, 0.84, 0.86)
    var dark := StandardMaterial3D.new()
    dark.albedo_color = Color(0.025, 0.025, 0.03)
    var handle := CapsuleMesh.new()
    handle.radius = 0.025
    handle.height = 0.115
    part(handle, Vector3(0, -0.035, 0.018), Vector3(0.25, 0, 0), shell)
    var face := CylinderMesh.new()
    face.top_radius = 0.036
    face.bottom_radius = 0.032
    face.height = 0.015
    part(face, Vector3(0, 0.032, 0), Vector3(0.2, 0, 0), dark)
    for at in [Vector3(-0.015, 0.045, 0.006), Vector3(0.012, 0.042, -0.01), Vector3(0.019, 0.045, 0.009)]:
        var button := CylinderMesh.new()
        button.top_radius = 0.006
        button.bottom_radius = 0.006
        button.height = 0.009
        part(button, at * Vector3(-1 if hand == "left" else 1, 1, 1), Vector3.ZERO, shell)
    var trigger := BoxMesh.new()
    trigger.size = Vector3(0.028, 0.021, 0.017)
    part(trigger, Vector3(0, 0.006, -0.027), Vector3(0.25, 0, 0), dark)

func part(mesh: Mesh, at: Vector3, angles: Vector3, material: Material) -> void:
    var piece := MeshInstance3D.new()
    piece.mesh = mesh
    piece.position = at
    piece.rotation = angles
    piece.material_override = material
    fallback.add_child(piece)

func native_loaded() -> void:
    fallback.visible = false
