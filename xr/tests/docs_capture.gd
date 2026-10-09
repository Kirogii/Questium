extends SceneTree

# Documentation fixtures: actual app controls, reader meshes and hand skin.
# These scenes deliberately use generated sample content, never user libraries.
var reader
var destination := "D:/VR Kommiku/artifacts/docs-media"

func _initialize() -> void:
    capture.call_deferred()

static func sample(index: int) -> ImageTexture:
    var image := Image.create(360, 510, false, Image.FORMAT_RGB8)
    image.fill(Color(0.94, 0.93, 0.88))
    for row in range(3):
        var tint := Color.from_hsv(fmod(index * 0.16 + row * 0.05, 1.0), 0.48, 0.52)
        image.fill_rect(Rect2i(18, 18 + row * 164, 324, 145), tint)
        image.fill_rect(Rect2i(30, 30 + row * 164, 78, 119), tint.lightened(0.38))
        image.fill_rect(Rect2i(126, 30 + row * 164, 202, 38), Color(0.94, 0.93, 0.88))
    return ImageTexture.create_from_image(image)

func snapshot(name: String) -> void:
    for frame in range(6):
        await process_frame
        await RenderingServer.frame_post_draw
    assert(root.get_texture().get_image().save_png(destination + "/" + name + ".png") == OK)

func skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D: return node
    for child in node.get_children():
        var found := skeleton(child)
        if found: return found
    return null

func skin(node: Node, material: Material) -> void:
    if node is MeshInstance3D: node.material_override = material
    for child in node.get_children(): skin(child, material)

func capture() -> void:
    DirAccess.make_dir_recursive_absolute(destination)
    RenderingServer.set_default_clear_color(Color(0.20, 0.22, 0.26))
    reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    # Photographic fixture behind the real HUD makes its screen-space blur visible.
    var backdrop := MeshInstance3D.new()
    var plane := QuadMesh.new()
    plane.size = Vector2(7, 4.6)
    backdrop.mesh = plane
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://../.github/readme-images/tutorial-landscape.jpg")))
    backdrop.material_override = material
    reader.add_child(backdrop)
    backdrop.global_position = reader.camera.global_position + Vector3(0, 0, -3)

    var ui = reader.workspace
    var entries: Array = []
    for i in range(8):
        var id := str(i + 1)
        ui.cover_cache[id] = sample(i)
        entries.append({"id": id, "title": ["Moonlight Atlas", "The Paper Garden", "Across the Horizon", "After the Rain", "Quiet Stars", "Winter Notes", "Blue Hour", "A Small Journey"][i], "chapters": 12 + i, "last_read": (int(Time.get_unix_time_from_system()) - (0 if i < 2 else 86400)) * 1000})
    ui.consume({"kind": "library", "items": entries})
    await snapshot("library")
    ui.filter = "History"
    ui.show_section("Home")
    entries[0]["history_chapter"] = "Chapter 3"
    entries[0]["last_page"] = 8
    ui.consume({"kind": "history", "items": [entries[0]]})
    await snapshot("history")
    ui.select_book(entries[0])
    await create_timer(0.7).timeout
    ui.consume({"kind": "details", "manga": "1", "title": "Moonlight Atlas", "description": "A sample comic for the Questium documentation. Explore chapters from this glass panel, then resume your place in the spatial reader.", "favorite": true})
    ui.consume({"kind": "chapters", "manga": "1", "resume": "3", "items": [{"id": "1", "title": "Chapter 1"}, {"id": "2", "title": "Chapter 2"}, {"id": "3", "title": "Chapter 3"}]})
    await snapshot("preview")
    ui.preview.node.visible = false
    ui.badge.node.visible = false
    reader.book.set_preview(false)
    reader.book.set_mode("book")
    reader.book.set_chapter(6)
    reader.book.set_open(1.0)
    reader.book.global_transform = Transform3D(Basis.IDENTITY, reader.camera.global_position + Vector3(0, 0, -0.7))
    for i in range(6): reader.book.supply_page(i, sample(i))
    await snapshot("reader")
    reader.ui.hard_cover = true
    reader.title.text = "Moonlight Atlas"
    reader.book.set_hard_cover(true)
    reader.ui.toggle()
    await snapshot("settings")
    ui.hud.node.visible = false
    ui.minimize_popups()
    ui.preview.node.visible = false
    reader.book.visible = false
    print("PASS: application screenshots with generated sample content")
    quit()
