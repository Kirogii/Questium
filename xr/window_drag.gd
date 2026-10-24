extends RefCounted

const HEIGHT := 0.045
const GAP := 0.012
var reader: Node3D

func _init(owner: Node3D) -> void:
    reader = owner

func register(panel: Dictionary) -> void:
    var rail := MeshInstance3D.new()
    rail.name = "WindowDragBar"
    var quad := QuadMesh.new()
    quad.size = Vector2(minf(panel.size.x * 0.65, 0.48), HEIGHT)
    rail.mesh = quad
    rail.position = Vector3(0, -panel.size.y * 0.5 - GAP - HEIGHT * 0.5, 0)
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(0.73, 0.78, 0.86, 0.85)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    rail.material_override = material
    panel.node.add_child(rail)
    panel.drag_bar = rail

func handle_ray(start: Vector3, direction: Vector3) -> Dictionary:
    var hits: Array[Dictionary] = []
    var book_hit: Dictionary = reader._book_ray_hit(start, direction)
    for panel in reader.panels:
        var node: Node3D = panel.node
        if not node.is_visible_in_tree(): continue
        var local := node.to_local(start)
        var ray := node.global_basis.inverse() * direction
        if absf(ray.z) < 0.0001: continue
        var distance := -local.z / ray.z
        if distance < 0 or distance > 5: continue
        var point := local + ray * distance
        var content: bool = absf(point.x) <= panel.size.x * 0.5 and absf(point.y) <= panel.size.y * 0.5
        var bar: MeshInstance3D = panel.get("drag_bar")
        var on_bar := false
        if is_instance_valid(bar):
            var size: Vector2 = bar.mesh.size
            on_bar = bar.visible and not panel.get("hand_attached", false) and absf(point.x) <= size.x * 0.5 and absf(point.y - bar.position.y) <= HEIGHT * 0.5
        if not content and not on_bar: continue
        var priority := maxi(int(node.get_meta("popup_priority", 0)), int(node.get_meta("raycast_priority", 0)))
        hits.append({"node": node, "distance": distance, "point": start + direction * distance, "bar": on_bar, "priority": priority})
    hits.sort_custom(func(a: Dictionary, b: Dictionary): return a.priority > b.priority if a.priority != b.priority else a.distance < b.distance)
    if hits.is_empty() or not hits[0].bar: return {}
    if not book_hit.is_empty() and float(book_hit.distance) <= float(hits[0].distance): return {}
    return hits[0]
