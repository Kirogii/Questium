extends RefCounted

var reader: Node3D
var windows: Array[Dictionary] = []
var sources: OptionButton
var search: LineEdit
var results: VBoxContainer
var details: VBoxContainer
var detail_cover: TextureRect
var detail_title: Label
var description: Label
var chapter_list: VBoxContainer
var selected_source := ""
var selected_manga := ""
var page := 1
var favorite := false
var cover_targets: Dictionary = {}
var dock_preview: MeshInstance3D
var dock_poses: Array[Transform3D] = []

func _init(host: Node3D) -> void:
    reader = host

func build() -> void:
    var left: Dictionary = reader._panel(reader, Vector2(0.88, 0.80), Vector2i(1056, 960), Vector3.ZERO)
    var right: Dictionary = reader._panel(reader, Vector2(0.88, 0.80), Vector2i(1056, 960), Vector3.ZERO)
    windows = [{"node": reader.library_panel, "size": Vector2(1.2, 1.0), "dock": 0}, {"node": left.node, "size": left.size, "dock": 1}, {"node": right.node, "size": right.size, "dock": 2}]
    for window in windows:
        var handle := MeshInstance3D.new()
        var bar := BoxMesh.new()
        bar.size = Vector3(0.18, 0.012, 0.012)
        handle.mesh = bar
        handle.position.y = -window.size.y / 2 - 0.03
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = Color(0.83, 0.84, 0.81)
        handle.material_override = material
        window.node.add_child(handle)
        glass(window.node, window.size)
    reader.ui.label(left.content, "Sources", 30)
    sources = OptionButton.new()
    sources.custom_minimum_size.y = 64
    left.content.add_child(sources)
    sources.item_selected.connect(func(index: int):
        selected_source = str(sources.get_item_metadata(index))
        run_search(1)
    )
    search = LineEdit.new()
    search.placeholder_text = "Search manga in this source"
    search.custom_minimum_size.y = 64
    left.content.add_child(search)
    search.text_submitted.connect(func(_text: String): run_search(1))
    var actions := HBoxContainer.new()
    left.content.add_child(actions)
    reader._button(actions, "Search", func(): run_search(1))
    reader._button(actions, "<", func(): run_search(maxi(1, page - 1)))
    reader._button(actions, ">", func(): run_search(page + 1))
    var scrolling := ScrollContainer.new()
    scrolling.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.content.add_child(scrolling)
    results = VBoxContainer.new()
    results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scrolling.add_child(results)
    details = right.content
    detail_title = reader.ui.label(details, "Manga details", 30)
    detail_cover = TextureRect.new()
    detail_cover.custom_minimum_size = Vector2(150, 190)
    detail_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    detail_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    details.add_child(detail_cover)
    description = reader.ui.label(details, "Select a manga from the source results. Your library stays open while you read.", 20)
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var favorites := HBoxContainer.new()
    details.add_child(favorites)
    reader._button(favorites, "Library + / âˆ’", func():
        if not selected_manga.is_empty():
            reader._request("favorite", {"manga": selected_manga, "enabled": not favorite})
    )
    reader._button(favorites, "Close Book", reader.close_book)
    var chapter_scroll := ScrollContainer.new()
    chapter_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    details.add_child(chapter_scroll)
    chapter_list = VBoxContainer.new()
    chapter_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    chapter_scroll.add_child(chapter_list)
    dock_preview = MeshInstance3D.new()
    var preview := QuadMesh.new()
    preview.size = Vector2(0.88, 0.80)
    dock_preview.mesh = preview
    var preview_material := StandardMaterial3D.new()
    preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    preview_material.albedo_color = Color(0.72, 0.94, 0.26, 0.18)
    dock_preview.material_override = preview_material
    reader.add_child(dock_preview)
    dock_preview.visible = false
    recenter()
    reader._request("sources")

func glass(node: Node3D, size: Vector2) -> void:
    var mesh := MeshInstance3D.new()
    var quad := QuadMesh.new()
    quad.size = size
    mesh.mesh = quad
    mesh.position.z = -0.008
    var material := ShaderMaterial.new()
    material.shader = preload("res://glass.gdshader")
    material.set_shader_parameter("panel_size", size)
    mesh.material_override = material
    node.add_child(mesh)
    for panel in reader.panels:
        if panel.node == node and panel.has("background"):
            panel.background.add_theme_stylebox_override("panel", reader.ui.style(Color(0.10, 0.11, 0.12, 0.18), 40))

func run_search(new_page: int) -> void:
    if selected_source.is_empty():
        return
    page = new_page
    reader._request("source_search", {"source": selected_source, "query": search.text, "page": page})

func consume(data: Dictionary) -> bool:
    match str(data.get("kind", "")):
        "sources":
            sources.clear()
            for item in data.get("items", []):
                sources.add_item(str(item.title))
                sources.set_item_metadata(sources.item_count - 1, str(item.id))
            if sources.item_count > 0:
                selected_source = str(sources.get_item_metadata(0))
                run_search(1)
            else:
                reader.ui.label(results, "Install a source extension from Browse in the center window.")
        "source_results":
            if str(data.source) != selected_source or int(data.page) != page:
                return true
            clear(results)
            cover_targets.clear()
            for item in data.get("items", []):
                var row := HBoxContainer.new()
                results.add_child(row)
                var cover := TextureRect.new()
                cover.custom_minimum_size = Vector2(90, 120)
                cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                row.add_child(cover)
                cover_targets[str(item.id)] = cover
                var button: Button = reader._button(row, str(item.title), func():
                    selected_manga = str(item.id)
                    detail_title.text = str(item.title)
                    reader._request("details", {"manga": selected_manga})
                )
                button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
                reader._request("cover", {"manga": str(item.id)})
        "details":
            if str(data.manga) != selected_manga:
                return true
            detail_title.text = str(data.title)
            description.text = str(data.description).left(650)
            favorite = bool(data.favorite)
        "chapters":
            if str(data.manga) != selected_manga:
                return false
            clear(chapter_list)
            for chapter in data.get("items", []):
                reader._button(chapter_list, ("âœ“ " if chapter.get("read", false) else "") + str(chapter.title), func(): reader._request("open", {"manga": selected_manga, "chapter": str(chapter.id)}))
        "cover":
            var image := Image.new()
            if image.load(str(data.path)) == OK:
                var texture := ImageTexture.create_from_image(image)
                var target = cover_targets.get(str(data.manga))
                if is_instance_valid(target):
                    target.texture = texture
                if str(data.manga) == selected_manga:
                    detail_cover.texture = texture
            return false
        _:
            return false
    return true

func clear(container: Container) -> void:
    for child in container.get_children():
        container.remove_child(child)
        child.queue_free()

func _new_dock_pose(index: int) -> Transform3D:
    var head: Transform3D = reader.camera.global_transform
    var facing := Basis(Vector3.UP, head.basis.get_euler().y)
    var offset := Vector3(0, 0.22, -1.65)
    var angle := 0.0
    if index != 0:
        offset.x = -1.08 if index == 1 else 1.08
        offset.z = -1.42
        angle = 0.40 if index == 1 else -0.40
    return Transform3D(facing * Basis(Vector3.UP, angle), head.origin + facing * offset)

func dock_pose(index: int) -> Transform3D:
    return dock_poses[index]

func recenter() -> void:
    dock_poses.clear()
    for index in range(3):
        dock_poses.append(_new_dock_pose(index))
    for window in windows:
        var dock := int(window.dock)
        if dock >= 0 and dock < dock_poses.size():
            window.node.global_transform = dock_pose(dock)

func handle_at(point: Vector3) -> Node3D:
    for window in windows:
        if not window.node.is_visible_in_tree():
            continue
        var local: Vector3 = window.node.to_local(point)
        if absf(local.z) < 0.10 and absf(local.x) < window.size.x / 2 and absf(local.y + window.size.y / 2 + 0.03) < 0.065:
            return window.node
    return null

func handle_ray(start: Vector3, direction: Vector3) -> Dictionary:
    var hit: Dictionary = {}
    var nearest := 5.0
    for window in windows:
        if not window.node.is_visible_in_tree():
            continue
        var local: Vector3 = window.node.to_local(start)
        var ray: Vector3 = window.node.global_transform.basis.inverse() * direction
        if absf(ray.z) < 0.0001:
            continue
        var distance := -local.z / ray.z
        var point := local + ray * distance
        if distance > 0 and distance < nearest and absf(point.x) < 0.16 and absf(point.y + window.size.y / 2 + 0.03) < 0.055:
            nearest = distance
            hit = {"node": window.node, "distance": distance, "point": start + direction * distance}
    return hit

func preview_snap(node: Node3D) -> int:
    var nearest := -1
    var distance := 0.28
    for i in range(3):
        var occupied := false
        for window in windows:
            if window.node != node and window.dock == i:
                occupied = true
        if occupied:
            continue
        var pose := dock_pose(i)
        var delta := node.global_position.distance_to(pose.origin)
        if delta < distance:
            distance = delta
            nearest = i
            dock_preview.global_transform = pose
    dock_preview.visible = nearest >= 0
    return nearest

func begin_drag(node: Node3D) -> void:
    for window in windows:
        if window.node == node:
            window.dock = -1

func finish_drag(node: Node3D) -> void:
    var target := preview_snap(node)
    if target >= 0:
        node.global_transform = dock_pose(target)
        for window in windows:
            if window.node == node:
                window.dock = target
    dock_preview.visible = false
