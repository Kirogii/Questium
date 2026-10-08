extends RefCounted

# Near-field fingertip presses use the same native controls as pointer selection.
# Approach from in front, press through the surface, withdraw to release.
var reader: Node3D
var samples: Dictionary = {}
var owner := ""
var panel: Dictionary = {}

func _init(host: Node3D) -> void:
    reader = host

func update(hand: String, tip: Vector3, valid: bool, pinched: bool) -> bool:
    if owner == hand:
        if not valid or pinched or not panel.node.is_visible_in_tree():
            cancel()
            return true
        var local: Vector3 = panel.node.to_local(tip)
        var scale_z: float = panel.node.global_basis.z.length()
        if absf(local.x) > panel.size.x / 2 or absf(local.y) > panel.size.y / 2 or local.z * scale_z < -0.08:
            cancel()
            return true
        var held := local.z * scale_z < 0.025
        send(local, held, true)
        if not held:
            owner = ""
            reader.ui_owner = ""
            panel = {}
            samples.erase(hand)
        return true
    if not valid or pinched or not owner.is_empty() or not reader.holder.is_empty() or not reader.ui_owner.is_empty():
        samples.erase(hand)
        return false
    var nearest: Dictionary = {}
    var depth := 0.14
    for candidate in reader.panels:
        if candidate.get("android", false) or not candidate.node.is_visible_in_tree():
            continue
        var local: Vector3 = candidate.node.to_local(tip)
        var world_depth: float = local.z * candidate.node.global_basis.z.length()
        if absf(local.x) > candidate.size.x / 2 or absf(local.y) > candidate.size.y / 2 or world_depth < -0.065 or absf(world_depth) >= depth:
            continue
        var normal: Vector3 = candidate.node.global_basis.z.normalized()
        var front: Vector3 = candidate.node.to_global(Vector3(local.x, local.y, 0.06))
        var obstruction: Dictionary = reader._book_ray_hit(front, -normal)
        if not candidate.get("popup", false) and not obstruction.is_empty() and float(obstruction.distance) < front.distance_to(candidate.node.to_global(Vector3(local.x, local.y, 0))):
            continue
        nearest = {"panel": candidate, "local": local, "depth": world_depth}
        depth = absf(world_depth)
    if nearest.is_empty():
        samples.erase(hand)
        return false
    var previous: Dictionary = samples.get(hand, {})
    var same: bool = not previous.is_empty() and previous.panel == nearest.panel
    var armed: bool = (same and previous.get("armed", false)) or nearest.depth > 0.018
    samples[hand] = {"panel": nearest.panel, "armed": armed, "local": nearest.local}
    if not same or not armed or nearest.depth > 0.008 or panel_motion(nearest, previous) > 0.20:
        return false
    panel = nearest.panel
    owner = hand
    reader.ui_owner = hand
    send(nearest.local, true, false)
    return true

func send(local: Vector3, pressed: bool, previous: bool) -> void:
    var front: Vector3 = panel.node.to_global(Vector3(local.x, local.y, 0.06))
    reader._panel_input(front, -panel.node.global_basis.z.normalized(), pressed, previous, panel)

func panel_motion(current: Dictionary, previous: Dictionary) -> float:
    return current.panel.node.to_global(current.local).distance_to(current.panel.node.to_global(previous.local))

func near_popup(tip: Vector3) -> bool:
    for candidate in reader.panels:
        if not candidate.get("popup", false) or not candidate.node.is_visible_in_tree(): continue
        var local: Vector3 = candidate.node.to_local(tip)
        if absf(local.x) <= candidate.size.x / 2 and absf(local.y) <= candidate.size.y / 2 and absf(local.z) * candidate.node.global_basis.z.length() < 0.14:
            return true
    return false

func cancel() -> void:
    if not owner.is_empty():
        # Release outside controls so tracking loss cannot activate a button.
        if not reader.ui_capture.is_empty():
            var motion := InputEventMouseMotion.new()
            motion.position = Vector2(-1000, -1000)
            motion.global_position = motion.position
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            reader.ui_capture.panel.viewport.push_input(motion, true)
            var release := InputEventMouseButton.new()
            release.position = Vector2(-1000, -1000)
            release.global_position = release.position
            release.button_index = MOUSE_BUTTON_LEFT
            release.pressed = false
            reader.ui_capture.panel.viewport.push_input(release, true)
            reader.ui_capture.clear()
        reader.ui_owner = ""
    owner = ""
    panel = {}
    samples.clear()
