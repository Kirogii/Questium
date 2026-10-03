class_name SpatialBook
extends Node3D

signal spread_changed(first_page: int)
signal turn_started
signal turn_finished(committed: bool)

const PAGE_WIDTH := 0.28
const PAGE_HEIGHT := 0.40
const PAPER_SHADER = preload("res://paper.gdshader")

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
        var box := BoxMesh.new()
        box.size = Vector3(PAGE_WIDTH + 0.012, PAGE_HEIGHT + 0.016, 0.015)
        cover.mesh = box
        cover.rotation.y = -side * 0.20
        cover.position = Vector3(side * PAGE_WIDTH / 2.0 * cos(0.20), 0.0, PAGE_WIDTH / 2.0 * sin(0.20) - 0.014)
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = Color(0.08, 0.07, 0.10)
        cover.material_override = material
        add_child(cover)
        var paper_stack := MeshInstance3D.new()
        var stack_mesh := BoxMesh.new()
        stack_mesh.size = Vector3(PAGE_WIDTH - 0.006, PAGE_HEIGHT - 0.006, 0.008)
        paper_stack.mesh = stack_mesh
        paper_stack.rotation = cover.rotation
        paper_stack.position = cover.position + Vector3(0.0, 0.0, 0.010)
        var paper_material := StandardMaterial3D.new()
        paper_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        paper_material.albedo_color = Color(0.86, 0.84, 0.79)
        paper_stack.material_override = paper_material
        add_child(paper_stack)
    var spine := MeshInstance3D.new()
    var spine_mesh := BoxMesh.new()
    spine_mesh.size = Vector3(0.012, PAGE_HEIGHT + 0.016, 0.022)
    spine.mesh = spine_mesh
    spine.position.z = -0.012
    var spine_material := StandardMaterial3D.new()
    spine_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    spine_material.albedo_color = Color(0.08, 0.07, 0.10)
    spine.material_override = spine_material
    add_child(spine)
    _refresh()

func _leaf(side: int) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for row in range(8):
        for column in range(32):
            for offset in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
                var uv := Vector2(float(column + offset.x) / 32.0, float(row + offset.y) / 8.0)
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
    _refresh()

func supply_page(index: int, texture: Texture2D) -> void:
    if index < 0 or index >= page_count:
        return
    textures[index] = texture
    _trim_textures()
    _refresh()

func prepare_seek(index: int) -> void:
    requested_spread = clampi(index - posmod(index, 2), 0, maxi(0, page_count - 1))
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
    _paint(left_leaf, first_page + (1 if rtl else 0))
    _paint(right_leaf, first_page + (0 if rtl else 1))
    if turn_direction != 0:
        var front := first_page + (1 if turn_direction > 0 else 0)
        var back := first_page + (2 if turn_direction > 0 else -1)
        turning_material.set_shader_parameter("front_image", _texture(front))
        turning_material.set_shader_parameter("back_image", _texture(back))
        _paint(left_leaf if turn_side < 0 else right_leaf, first_page + (3 if turn_direction > 0 else -2))

func can_turn(direction: int) -> bool:
    var target := first_page + direction * 2
    return turn_direction == 0 and target >= 0 and target < page_count and textures.has(target) and (target + 1 >= page_count or textures.has(target + 1))

func begin_turn(side: int) -> bool:
    var direction := side * (-1 if rtl else 1)
    if not can_turn(direction):
        return false
    turn_direction = direction
    turn_side = side
    turn_progress = 0.0
    grabbed = true
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
    set_turn_progress(clampf(angle / PI, 0.0, 1.0))

func set_turn_progress(value: float) -> void:
    turn_progress = value
    turning_material.set_shader_parameter("progress", value)

func release_turn() -> void:
    if not grabbed:
        return
    grabbed = false
    _settle(turn_progress >= 0.5)

func step(direction: int) -> bool:
    if not begin_turn(direction * (-1 if rtl else 1)):
        return false
    grabbed = false
    _settle(true)
    return true

func _settle(commit: bool) -> void:
    settling = create_tween()
    settling.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    settling.tween_method(set_turn_progress, turn_progress, 1.0 if commit else 0.0, 0.28)
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
    if turning_leaf:
        turning_leaf.visible = false
        _refresh()

func seek(index: int) -> bool:
    var target := clampi(index - posmod(index, 2), 0, maxi(0, page_count - 1))
    if page_count == 0 or not textures.has(target) or (target + 1 < page_count and not textures.has(target + 1)):
        return false
    cancel_turn()
    first_page = target
    requested_spread = -1
    _trim_textures()
    _refresh()
    spread_changed.emit(first_page)
    return true
