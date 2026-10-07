class_name SpatialBook
extends Node3D

signal spread_changed(first_page: int)
signal turn_started
signal turn_finished(committed: bool)

const PAGE_WIDTH := 0.28
const PAGE_HEIGHT := 0.40
const REST_ANGLE := 0.035
const COVER_THICKNESS := 0.0007
const COVER_OFFSET := 0.003
const PAPER_SHADER = preload("res://paper.gdshader")
const GEOMETRY = preload("res://book_geometry.gd")

var page_count := 0
var first_page := 0
var requested_spread := -1
var rtl := false
var textures: Dictionary = {}
var blank: ImageTexture
var left_leaf: MeshInstance3D
var right_leaf: MeshInstance3D
var turning_leaf: MeshInstance3D
var turning_material: ShaderMaterial
var turn_direction := 0
var turn_side := 1
var turn_progress := 0.0
var grabbed := false
var settling: Tween
var mode := "auto"
var scroll_mode := false
var vertical_chapter := false
var scroll_offset := 0.0
var scroll_overshoot := 0.0
var edge_bars: Array[MeshInstance3D] = []
var close_marker: Label3D
var openness := 1.0
var cover_dragged := false
var cover_start := 1.0
var cover_grab_angle := 0.0
var cover_settling: Tween
var grab_angle := 0.0
var grab_progress := 0.0
var cover_texture: Texture2D
var artwork: Texture2D
var preview_only := false
var body_parts: Array[Node3D] = []
var cover_pivot: Node3D
var cover_face: MeshInstance3D
var scroll_window: Node3D
var scroll_screen: MeshInstance3D
var scroll_slots: Array[MeshInstance3D] = []
var source_sizes: Dictionary = {}
var strips: Dictionary = {}
var strip_textures: Dictionary = {}
var token := ""
var chapter_title := ""
var pending_page := -1

func _ready() -> void:
    var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
    image.fill(Color(0.96, 0.95, 0.92))
    blank = ImageTexture.create_from_image(image)
    left_leaf = _leaf(-1)
    right_leaf = _leaf(1)
    turning_leaf = _leaf(1)
    turning_leaf.position.z = 0.001
    turning_leaf.visible = false
    turning_material = turning_leaf.material_override
    for side in [-1, 1]:
        var cover := MeshInstance3D.new()
        cover.mesh = GEOMETRY.cover(Vector3(PAGE_WIDTH + 0.002, PAGE_HEIGHT + 0.003, COVER_THICKNESS))
        cover.rotation.y = -side * REST_ANGLE
        cover.position = Vector3(side * PAGE_WIDTH / 2.0 * cos(REST_ANGLE), 0.0, PAGE_WIDTH / 2.0 * sin(REST_ANGLE) - COVER_OFFSET)
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = Color(0.08, 0.07, 0.10)
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        cover.material_override = material
        add_child(cover)
        body_parts.append(cover)
        var paper_stack := MeshInstance3D.new()
        paper_stack.mesh = GEOMETRY.stack(side, PAGE_WIDTH, PAGE_HEIGHT, REST_ANGLE)
        var paper_material := ShaderMaterial.new()
        paper_material.shader = preload("res://paper_stack.gdshader")
        paper_stack.material_override = paper_material
        add_child(paper_stack)
        body_parts.append(paper_stack)
    var spine := MeshInstance3D.new()
    spine.mesh = GEOMETRY.cover(Vector3(0.003, PAGE_HEIGHT + 0.002, 0.005))
    spine.position.z = -0.001
    var spine_material := StandardMaterial3D.new()
    spine_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    spine_material.albedo_color = Color(0.08, 0.07, 0.10)
    spine_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    spine.material_override = spine_material
    add_child(spine)
    body_parts.append(spine)
    cover_pivot = Node3D.new()
    add_child(cover_pivot)
    # The hard cover itself follows the hinge, not only the cover image.
    var front_cover := body_parts[0]
    front_cover.reparent(cover_pivot)
    front_cover.position = Vector3(-PAGE_WIDTH / 2, 0, -COVER_OFFSET)
    front_cover.rotation = Vector3.ZERO
    cover_face = MeshInstance3D.new()
    var face := QuadMesh.new()
    face.size = Vector2(PAGE_WIDTH, PAGE_HEIGHT)
    cover_face.mesh = face
    cover_face.position = Vector3(-PAGE_WIDTH / 2, 0, -COVER_OFFSET - COVER_THICKNESS)
    cover_face.rotation.y = PI
    var face_material := ShaderMaterial.new()
    face_material.shader = preload("res://book_cover.gdshader")
    cover_face.material_override = face_material
    cover_pivot.add_child(cover_face)
    scroll_window = Node3D.new()
    add_child(scroll_window)
    var case_mesh := MeshInstance3D.new()
    var case_shape := BoxMesh.new()
    case_shape.size = Vector3(0.74, 1.04, 0.014)
    case_mesh.mesh = case_shape
    var case_material := StandardMaterial3D.new()
    case_material.albedo_color = Color(0.035, 0.035, 0.045)
    case_material.roughness = 0.3
    case_mesh.material_override = case_material
    scroll_window.add_child(case_mesh)
    scroll_screen = MeshInstance3D.new()
    var screen_mesh := QuadMesh.new()
    screen_mesh.size = Vector2(0.70, 1.0)
    scroll_screen.mesh = screen_mesh
    scroll_screen.position.z = 0.009
    var screen_material := ShaderMaterial.new()
    screen_material.shader = preload("res://scroll.gdshader")
    scroll_screen.material_override = screen_material
    scroll_window.add_child(scroll_screen)
    scroll_slots.append(scroll_screen)
    # Multiple clipped leaves can share the viewport at an image boundary.
    for index in range(5):
        var slot := MeshInstance3D.new()
        slot.mesh = screen_mesh
        slot.position = scroll_screen.position
        slot.material_override = screen_material.duplicate()
        slot.visible = false
        scroll_window.add_child(slot)
        scroll_slots.append(slot)
    for side in [-1, 1]:
        var bar := MeshInstance3D.new()
        var shape := CapsuleMesh.new()
        shape.radius = 0.002
        shape.height = 0.28
        bar.mesh = shape
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = Color.WHITE
        bar.material_override = material
        add_child(bar)
        edge_bars.append(bar)
    close_marker = Label3D.new()
    close_marker.text = "×"
    close_marker.font_size = 64
    close_marker.pixel_size = 0.0006
    close_marker.outline_size = 12
    close_marker.no_depth_test = false
    add_child(close_marker)
    _refresh()

func set_preview(enabled: bool) -> void:
    preview_only = enabled
    _refresh()

func set_cover(texture: Texture2D) -> void:
    artwork = texture
    cover_texture = texture
    _refresh()

func _leaf(side: int) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for row in range(24):
        for column in range(64):
            for offset in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
                var uv := Vector2(float(column + offset.x) / 64.0, float(row + offset.y) / 24.0)
                surface.set_uv(uv)
                surface.set_normal(Vector3(0.0, 0.0, 1.0))
                surface.add_vertex(Vector3(side * uv.x * PAGE_WIDTH, (0.5 - uv.y) * PAGE_HEIGHT, 0.0))
    var leaf := MeshInstance3D.new()
    leaf.mesh = surface.commit()
    # Shader-deformed pages travel outside their undeformed CPU bounding box.
    leaf.custom_aabb = AABB(Vector3(-PAGE_WIDTH, -PAGE_HEIGHT / 2.0, -0.02), Vector3(2.0 * PAGE_WIDTH, PAGE_HEIGHT, PAGE_WIDTH + 0.10))
    var material := ShaderMaterial.new()
    material.shader = PAPER_SHADER
    material.set_shader_parameter("side", float(side))
    material.set_shader_parameter("width", PAGE_WIDTH)
    material.set_shader_parameter("rest_angle", REST_ANGLE)
    material.set_shader_parameter("front_image", blank)
    material.set_shader_parameter("back_image", blank)
    leaf.material_override = material
    add_child(leaf)
    return leaf

func set_chapter(count: int, start: int = 0, right_to_left: bool = false) -> void:
    cancel_turn()
    page_count = maxi(0, count)
    first_page = clampi(start - posmod(start, 2), 0, maxi(0, count - 1))
    rtl = right_to_left
    requested_spread = -1
    textures.clear()
    cover_texture = artwork
    source_sizes.clear()
    strips.clear()
    strip_textures.clear()
    scroll_offset = 0.0
    scroll_overshoot = 0.0
    scroll_mode = mode == "scroll" or (vertical_chapter and mode != "book")
    if scroll_mode:
        first_page = clampi(start, 0, maxi(0, count - 1))
    _refresh()

func supply_page(index: int, texture: Texture2D, source_size: Vector2i = Vector2i.ZERO) -> void:
    if index < 0 or index >= page_count:
        return
    textures[index] = texture
    if index == 0 and artwork == null:
        cover_texture = texture
    source_sizes[index] = source_size if source_size.x > 0 else Vector2i(texture.get_width(), texture.get_height())
    if mode == "auto" and float(source_sizes[index].y) / maxf(1, source_sizes[index].x) > 2.2:
        scroll_mode = true
    _trim_textures()
    _refresh()

func prepare_seek(index: int) -> void:
    requested_spread = clampi(index if scroll_mode else index - posmod(index, 2), 0, maxi(0, page_count - 1))
    _trim_textures()

func _trim_textures() -> void:
    # Keep the current window and a pending seek until both destination pages load.
    for key in textures.keys():
        if absi(int(key) - first_page) > 5 and (requested_spread < 0 or absi(int(key) - requested_spread) > 5):
            textures.erase(key)

func _texture(index: int) -> Texture2D:
    return textures.get(index, blank)

func _paint(leaf: MeshInstance3D, index: int) -> void:
    leaf.material_override.set_shader_parameter("front_image", _texture(index))
    leaf.material_override.set_shader_parameter("back_image", _texture(index))

func _refresh() -> void:
    close_marker.visible = not preview_only
    if not is_instance_valid(scroll_window):
        return
    cover_pivot.rotation.y = lerpf(PI, REST_ANGLE, openness)
    for index in range(edge_bars.size()):
        edge_bars[index].visible = not preview_only and (index == 0 or scroll_mode or openness > 0.05)
        edge_bars[index].position = Vector3((-1 if index == 0 else 1) * (0.395 if scroll_mode else PAGE_WIDTH + 0.025), 0, 0.005)
    if not scroll_mode:
        edge_bars[0].position = cover_pivot.basis * Vector3(-PAGE_WIDTH - 0.025, 0, 0)
    close_marker.position = Vector3(0.405 if scroll_mode else PAGE_WIDTH + 0.035, 0.55 if scroll_mode else PAGE_HEIGHT / 2 + 0.035, 0.015)
    scroll_window.visible = scroll_mode
    for part in body_parts:
        part.visible = not scroll_mode
    cover_pivot.visible = not scroll_mode
    # Flatten the closed page block so it cannot sit in front of the cover art.
    body_parts[3].rotation.y = (1.0 - openness) * REST_ANGLE
    body_parts[2].rotation.y = -openness * REST_ANGLE
    body_parts[2].position = Vector3(PAGE_WIDTH / 2 * cos(openness * REST_ANGLE), 0, PAGE_WIDTH / 2 * sin(openness * REST_ANGLE) - COVER_OFFSET)
    cover_face.material_override.set_shader_parameter("cover_image", cover_texture if cover_texture != null else blank)
    # Collapse the left paper stack into the closed book until the cover opens.
    body_parts[1].visible = not scroll_mode and openness > 0.04
    body_parts[1].rotation.y = (1.0 - openness) * (PI - REST_ANGLE)
    left_leaf.visible = not scroll_mode and openness > 0.04
    right_leaf.visible = not scroll_mode and openness > 0.04
    left_leaf.rotation.y = (1.0 - openness) * (PI - REST_ANGLE)
    right_leaf.rotation.y = (1.0 - openness) * REST_ANGLE
    turning_leaf.visible = not scroll_mode and turn_direction != 0
    if scroll_mode:
        scroll_offset = clampf(scroll_offset, 0, _scroll_limit(first_page))
        _refresh_scroll_pages()
        return
    _paint(left_leaf, first_page + (1 if rtl else 0))
    _paint(right_leaf, first_page + (0 if rtl else 1))
    if turn_direction != 0:
        var front := first_page + (1 if turn_direction > 0 else 0)
        var back := first_page + (2 if turn_direction > 0 else -1)
        turning_material.set_shader_parameter("front_image", _texture(front))
        turning_material.set_shader_parameter("back_image", _texture(back))
        _paint(left_leaf if turn_side < 0 else right_leaf, first_page + (3 if turn_direction > 0 else -2))

func can_turn(direction: int) -> bool:
    if scroll_mode:
        return first_page + direction >= 0 and first_page + direction < page_count and textures.has(first_page + direction)
    var target := first_page + direction * 2
    return turn_direction == 0 and target >= 0 and target < page_count and textures.has(target) and (target + 1 >= page_count or textures.has(target + 1))

func begin_turn(side: int, contact: Vector3 = Vector3.INF) -> bool:
    if scroll_mode or openness < 0.8:
        return false
    var direction := side * (-1 if rtl else 1)
    if not can_turn(direction):
        return false
    turn_direction = direction
    turn_side = side
    turn_progress = 0.0
    grabbed = true
    grab_angle = 0.0 if contact == Vector3.INF else atan2(maxf(0.0, contact.z), side * contact.x)
    grab_progress = 0.0
    turning_material.set_shader_parameter("side", float(side))
    turning_material.set_shader_parameter("progress", 0.0)
    turning_leaf.visible = true
    _refresh()
    turn_started.emit()
    return true

func drag(local_finger: Vector3) -> void:
    if not grabbed:
        return
    var angle := atan2(maxf(0.0, local_finger.z), turn_side * local_finger.x)
    # Offset by the acquired contact angle so pinching above a curved leaf
    # never jumps the page forward on the first frame.
    set_turn_progress(clampf(grab_progress + (angle - grab_angle) / (PI - 2.0 * REST_ANGLE), 0.0, 1.0))
    turning_material.set_shader_parameter("grab_y", clampf(local_finger.y / PAGE_HEIGHT + 0.5, 0, 1))

func set_turn_progress(value: float) -> void:
    turn_progress = value
    turning_material.set_shader_parameter("progress", value)

func release_turn() -> void:
    if not grabbed:
        return
    grabbed = false
    _settle(turn_progress >= 0.5)

func step(direction: int) -> bool:
    if scroll_mode:
        if not can_turn(direction):
            return false
        scroll_offset = 0.0
        return seek(first_page + direction)
    if not begin_turn(direction * (-1 if rtl else 1)):
        return false
    grabbed = false
    _settle(true)
    return true

func _settle(commit: bool) -> void:
    settling = create_tween()
    settling.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var target := 1.0 if commit else 0.0
    settling.tween_method(set_turn_progress, turn_progress, target, 0.08 + 0.20 * absf(target - turn_progress))
    settling.tween_callback(func():
        if commit:
            first_page += 2 * turn_direction
            _trim_textures()
        turn_direction = 0
        turning_leaf.visible = false
        _refresh()
        if commit:
            spread_changed.emit(first_page)
        turn_finished.emit(commit)
    )

func cancel_turn() -> void:
    if settling and settling.is_valid():
        settling.kill()
    grabbed = false
    turn_direction = 0
    cancel_cover()
    if turning_leaf:
        turning_leaf.visible = false
        _refresh()

func seek(index: int) -> bool:
    var target := clampi(index if scroll_mode else index - posmod(index, 2), 0, maxi(0, page_count - 1))
    if page_count == 0 or not textures.has(target) or (not scroll_mode and target + 1 < page_count and not textures.has(target + 1)):
        return false
    cancel_turn()
    scroll_offset = 0.0
    first_page = target
    scroll_overshoot = 0.0
    requested_spread = -1
    _trim_textures()
    _refresh()
    spread_changed.emit(first_page)
    return true

func set_mode(value: String) -> void:
    mode = value
    cancel_turn()
    scroll_mode = value == "scroll" or (value == "auto" and (vertical_chapter or _has_tall_pages()))
    if not scroll_mode:
        first_page -= posmod(first_page, 2)
    scroll_offset = 0
    scroll_overshoot = 0.0
    _refresh()

func _has_tall_pages() -> bool:
    for size in source_sizes.values():
        if float(size.y) / maxf(size.x, 1) > 2.2:
            return true
    return false

func scroll_by(distance: float) -> int:
    if not scroll_mode:
        return 0
    var next := scroll_offset + distance + scroll_overshoot
    scroll_overshoot = 0.0
    if next < 0:
        if first_page == 0:
            scroll_offset = 0.0
            scroll_overshoot = maxf(-0.04, next)
            return -2 if next < -0.035 else 0
        if not textures.has(first_page - 1):
            scroll_offset = 0.0
            scroll_overshoot = -0.035
            return -1
        var previous_height := _page_height(first_page - 1)
        seek(first_page - 1)
        next = maxf(0, previous_height + next)
    var height := _page_height(first_page)
    if next >= height and textures.has(first_page + 1):
        seek(first_page + 1)
        next -= height
    var limit := _scroll_limit(first_page)
    scroll_offset = clampf(next, 0, limit)
    if next > limit:
        scroll_overshoot = minf(0.04, next - limit)
        _refresh()
        if next > limit + 0.035:
            return 2 if first_page + 1 >= page_count else 1
        return 0
    _refresh()
    return 0

func _page_height(index: int) -> float:
    var size: Vector2i = source_sizes.get(index, Vector2i(7, 10))
    return maxf(0.01, 0.70 * float(size.y) / maxf(size.x, 1))

func _scroll_limit(index: int) -> float:
    return _page_height(index) if index + 1 < page_count and textures.has(index + 1) else maxf(0, _page_height(index) - 1.0)

func close_at(point: Vector3) -> bool:
    return not preview_only and point.distance_to(close_marker.position) < 0.04

func hover_edge(point: Vector3) -> void:
    hover_edges([point])

func _near_bar(point: Vector3, bar: MeshInstance3D) -> bool:
    return bar.visible and Vector2(point.x - bar.position.x, point.z - bar.position.z).length() < 0.04 and absf(point.y) < 0.17

func cover_handle_at(point: Vector3) -> bool:
    return not scroll_mode and not preview_only and _near_bar(point, edge_bars[0])

func hover_edges(points: Array) -> void:
    for index in range(edge_bars.size()):
        var bar := edge_bars[index]
        var near := cover_dragged and index == 0
        for point in points:
            near = near or _near_bar(point, bar)
        bar.material_override.albedo_color = Color(0.70, 0.35, 1.0) if near else Color.WHITE

func set_open(value: float) -> void:
    openness = clampf(value, 0, 1)
    _refresh()

func supply_strips(index: int, entries: Array) -> void:
    strips[index] = entries
    _refresh()

func _strip_texture(path: String) -> Texture2D:
    if not strip_textures.has(path):
        var image := Image.new()
        if image.load(path) != OK:
            return blank
        image.generate_mipmaps()
        strip_textures[path] = ImageTexture.create_from_image(image)
    return strip_textures[path]

func _refresh_scroll_pages() -> void:
    var page_top := -scroll_offset
    var index := first_page
    var active_paths: Array[String] = []
    for slot in scroll_slots:
        slot.visible = index < page_count and page_top < 1.0 and textures.has(index)
        if not slot.visible:
            slot.material_override.set_shader_parameter("page_image", blank)
            slot.material_override.set_shader_parameter("next_image", blank)
            continue
        var height := _page_height(index)
        var material: ShaderMaterial = slot.material_override
        material.set_shader_parameter("page_top", page_top)
        material.set_shader_parameter("page_height", height)
        material.set_shader_parameter("page_image", _texture(index))
        _refresh_strips(material, index, maxf(0, -page_top), active_paths)
        page_top += height
        index += 1
    for path in strip_textures.keys():
        if path not in active_paths:
            strip_textures.erase(path)

func _refresh_strips(material: ShaderMaterial, index: int, visible_offset: float, active_paths: Array[String]) -> void:
    var entries: Array = strips.get(index, [])
    if entries.is_empty():
        material.set_shader_parameter("next_image", blank)
        material.set_shader_parameter("strip_start", 0.0)
        material.set_shader_parameter("strip_fraction", 1.0)
        material.set_shader_parameter("next_fraction", 1.0)
        return
    var size: Vector2i = source_sizes.get(index, Vector2i(1, 1))
    var top_pixel := visible_offset / 0.70 * size.x
    var segment := 0
    for i in range(entries.size()):
        if top_pixel >= float(entries[i].top):
            segment = i
    var current: Dictionary = entries[segment]
    var next: Dictionary = entries[mini(segment + 1, entries.size() - 1)]
    material.set_shader_parameter("page_image", _strip_texture(str(current.path)))
    material.set_shader_parameter("next_image", _strip_texture(str(next.path)))
    active_paths.append(str(current.path))
    active_paths.append(str(next.path))
    material.set_shader_parameter("strip_start", float(current.top) / size.y)
    material.set_shader_parameter("strip_fraction", float(current.height) / size.y)
    material.set_shader_parameter("next_fraction", float(next.height) / size.y)

func release_cover() -> void:
    cover_dragged = false
    settle_cover(openness >= 0.5)

func settle_cover(open: bool) -> void:
    cover_dragged = false
    if cover_settling and cover_settling.is_valid():
        cover_settling.kill()
    cover_settling = create_tween()
    cover_settling.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var target := 1.0 if open else 0.0
    cover_settling.tween_method(set_open, openness, target, 0.08 + 0.20 * absf(target - openness))

func begin_cover(contact: Vector3 = Vector3.ZERO) -> void:
    if cover_settling and cover_settling.is_valid():
        cover_settling.kill()
    cover_start = openness
    cover_grab_angle = atan2(maxf(0, contact.z), contact.x)
    cover_dragged = true

func drag_cover(contact: Vector3) -> void:
    if cover_dragged:
        var angle := atan2(maxf(0, contact.z), contact.x)
        set_open(cover_start + (angle - cover_grab_angle) / (PI - REST_ANGLE))

func cancel_cover() -> void:
    if cover_settling and cover_settling.is_valid():
        cover_settling.kill()
    if cover_dragged:
        cover_dragged = false
        set_open(cover_start)
