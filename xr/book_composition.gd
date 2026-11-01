extends Node

const PAGE_CLEARANCE := 0.003

# Reuse the actual page meshes/materials in isolated orthographic viewports.
# Only the active book gets layers; animated/closed pages stay in the 3D scene.
var reader: Node3D
var entries: Array[Dictionary] = []
var suppressed: Dictionary = {}

func setup(host: Node3D) -> void:
    reader = host
    if not reader.xr or not reader.xr.is_initialized(): return
    var probe := OpenXRCompositionLayerQuad.new()
    var supported := probe.is_natively_supported()
    probe.free()
    if not supported: return
    for index in 3:
        create_entry(index)
    RenderingServer.frame_pre_draw.connect(sync)

func create_entry(index: int) -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1400, 2000)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    add_child(viewport)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0.035, 0.035, 0.045)
    environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    viewport.add_child(environment)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = 0.01
    camera.far = 2.0
    viewport.add_child(camera)
    var meshes: Array[MeshInstance3D] = []
    for slot in (6 if index == 2 else 1):
        var mesh := MeshInstance3D.new()
        viewport.add_child(mesh)
        meshes.append(mesh)
    var layer := OpenXRCompositionLayerQuad.new()
    layer.name = "ReaderPageComposition%d" % index
    layer.visible = false
    # Keep hands/rays in the scene in front of the sharp page presentation.
    layer.sort_order = -2
    layer.enable_hole_punch = true
    # Keep 3D depth rendering out of the GLES OpenXR external framebuffer.
    var presentation := SubViewport.new()
    presentation.size = viewport.size
    presentation.disable_3d = true
    presentation.render_target_update_mode = SubViewport.UPDATE_DISABLED
    add_child(presentation)
    var image := TextureRect.new()
    image.texture = viewport.get_texture()
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    presentation.add_child(image)
    image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    reader.origin.add_child(layer)
    layer.layer_viewport = presentation
    entries.append({"layer": layer, "viewport": viewport, "presentation": presentation, "camera": camera, "meshes": meshes})

func restore_meshes() -> void:
    for mesh in suppressed:
        if is_instance_valid(mesh): mesh.layers = suppressed[mesh]
    suppressed.clear()

func sync() -> void:
    restore_meshes()
    var book: SpatialBook = reader.book
    var active := is_instance_valid(book) and book.is_visible_in_tree() and not book.preview_only and not book.token.is_empty()
    for index in entries.size():
        var entry: Dictionary = entries[index]
        var enabled := active and (book.scroll_mode if index == 2 else (not book.scroll_mode and book.openness >= 0.999 and book.turn_direction == 0 and not book.cover_dragged))
        entry.layer.visible = enabled
        entry.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
        entry.presentation.render_target_update_mode = entry.viewport.render_target_update_mode
        if not enabled: continue
        var sources: Array = book.scroll_slots if index == 2 else [book.left_leaf if index == 0 else book.right_leaf]
        var size := Vector2(0.70, 1.0) if index == 2 else Vector2(book.PAGE_WIDTH, book.PAGE_HEIGHT)
        var pose := Transform3D.IDENTITY
        if index == 2:
            pose.origin.z = book.scroll_screen.position.z
        else:
            var side := -1.0 if index == 0 else 1.0
            pose.origin.x = side * book.PAGE_WIDTH / 2
        entry.camera.size = size.y
        entry.camera.transform = Transform3D(pose.basis, pose.origin + pose.basis.z)
        for slot in sources.size():
            var source: MeshInstance3D = sources[slot]
            var copy: MeshInstance3D = entry.meshes[slot]
            copy.mesh = source.mesh
            copy.material_override = source.material_override
            copy.transform = source.transform
            copy.custom_aabb = source.custom_aabb
            copy.visible = source.visible
            suppressed[source] = source.layers
            source.layers = 0
        var world_pose: Transform3D = book.global_transform * pose
        # Keep the depth mask ahead of the paper stack without tilting it off the page.
        world_pose.origin += world_pose.basis.z * PAGE_CLEARANCE
        entry.layer.global_transform = Transform3D(world_pose.basis.orthonormalized(), world_pose.origin)
        entry.layer.quad_size = size * Vector2(world_pose.basis.x.length(), world_pose.basis.y.length())

func _exit_tree() -> void:
    restore_meshes()
    for entry in entries:
        if is_instance_valid(entry.layer):
            entry.layer.layer_viewport = null
            entry.layer.queue_free()
