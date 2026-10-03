extends Node3D

const BookScript = preload("res://book.gd")
var book: SpatialBook
var origin: XROrigin3D
var camera: Camera3D
var xr: XRInterface
var environment: WorldEnvironment
var bridge: Object
var labels: Dictionary = {}
var panels: Array[Dictionary] = []
var library_panel: Node3D
var library_list: VBoxContainer
var library_entries: Array = []
var library_categories: Array = []
var library_page := 0
var category := ""
var query := ""
var library_mode := "library"
var selected_manga := ""
var ui_owner := ""
var ui_capture: Dictionary = {}
var covers: Dictionary = {}
var category_menu: OptionButton
var toolbar_view: SubViewport
var title: Label
var seeker: HSlider
var status: Label
var tracked: Dictionary = {}
var holder := ""
var moving := false
var hold_offset := Vector3.ZERO
var hold_basis := Basis.IDENTITY
var pending_seek := -1
var chapter_token := ""
var local_pages: Array[String] = []

func _ready() -> void:
    environment = WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color.BLACK
    add_child(environment)
    origin = XROrigin3D.new()
    add_child(origin)
    xr = XRServer.find_interface("OpenXR")
    if xr and xr.is_initialized():
        get_viewport().use_xr = true
        var xr_camera := XRCamera3D.new()
        origin.add_child(xr_camera)
        camera = xr_camera
        for hand in ["left", "right"]:
            var controller := XRController3D.new()
            controller.tracker = "/user/hand/" + hand
            origin.add_child(controller)
            var hand_root := XRNode3D.new()
            hand_root.tracker = "/user/hand_tracker/" + hand
            origin.add_child(hand_root)
            if ClassDB.class_exists("OpenXRFbHandTrackingMesh"):
                var hand_mesh = ClassDB.instantiate("OpenXRFbHandTrackingMesh")
                hand_mesh.set("hand", 0 if hand == "left" else 1)
                var material := ShaderMaterial.new()
                material.shader = preload("res://hand.gdshader")
                hand_mesh.set("material", material)
                hand_root.add_child(hand_mesh)
                var modifier := XRHandModifier3D.new()
                modifier.hand_tracker = "/user/hand_tracker/" + hand
                hand_mesh.add_child(modifier)
            var ray := MeshInstance3D.new()
            var cylinder := CylinderMesh.new()
            cylinder.top_radius = 0.0008
            cylinder.bottom_radius = 0.0008
            cylinder.height = 1.5
            ray.mesh = cylinder
            ray.rotation.x = PI / 2.0
            ray.position.z = -0.75
            var ray_material := StandardMaterial3D.new()
            ray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            ray_material.albedo_color = Color(0.72, 0.45, 0.95)
            ray.material_override = ray_material
            controller.add_child(ray)
            tracked[hand] = {"controller": controller, "pressed": false, "hand_root": hand_root, "ray": ray}
    else:
        camera = Camera3D.new()
        camera.position.y = 1.35
        origin.add_child(camera)
    camera.current = true
    book = BookScript.new()
    add_child(book)
    recenter()
    book.spread_changed.connect(_spread_changed)
    if Engine.has_singleton("HouriVR"):
        bridge = Engine.get_singleton("HouriVR")
        bridge.connect("response", _response)
        var translated = JSON.parse_string(bridge.call("labels"))
        if translated is Dictionary:
            labels = translated
    _build_toolbar()
    _build_library()
    if bridge:
        _request("library")
    else:
        _load_desktop_pages()
    _set_passthrough(false)

func _label(text: String) -> String:
    return str(labels.get(text, text))

func recenter() -> void:
    book.position = camera.global_position - camera.global_basis.z * 0.75
    book.rotation = Vector3(deg_to_rad(-12.0), camera.global_rotation.y, 0.0)

func _panel(parent: Node3D, size: Vector2, pixels: Vector2i, position: Vector3) -> Dictionary:
    var node := Node3D.new()
    parent.add_child(node)
    node.position = position
    var viewport := SubViewport.new()
    viewport.size = pixels
    viewport.transparent_bg = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    node.add_child(viewport)
    var surface := MeshInstance3D.new()
    var quad := QuadMesh.new()
    quad.size = size
    surface.mesh = quad
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_texture = viewport.get_texture()
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
    surface.material_override = material
    node.add_child(surface)
    var background := ColorRect.new()
    background.color = Color(0.055, 0.06, 0.08)
    background.size = Vector2(pixels)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    viewport.add_child(background)
    var content := VBoxContainer.new()
    content.position = Vector2(16.0, 12.0)
    content.size = Vector2(pixels) - Vector2(32.0, 24.0)
    viewport.add_child(content)
    var data := {"node": node, "viewport": viewport, "size": size, "pixels": pixels, "content": content}
    panels.append(data)
    return data

func _button(row: Container, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = _label(text)
    button.custom_minimum_size = Vector2(72.0, 48.0)
    button.add_theme_font_size_override("font_size", 22)
    row.add_child(button)
    button.pressed.connect(callback)
    return button

func _build_toolbar() -> void:
    var panel := _panel(book, Vector2(0.60, 0.19), Vector2i(1000, 316), Vector3(0.0, -0.32, 0.025))
    toolbar_view = panel.viewport
    var content: VBoxContainer = panel.content
    title = Label.new()
    title.text = "VR Komikku"
    title.add_theme_font_size_override("font_size", 24)
    content.add_child(title)
    var row := HBoxContainer.new()
    content.add_child(row)
    _button(row, "Library", func(): library_panel.visible = not library_panel.visible)
    _button(row, "<", func(): _turn(-1))
    seeker = HSlider.new()
    seeker.custom_minimum_size = Vector2(450.0, 48.0)
    seeker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    seeker.step = 1.0
    row.add_child(seeker)
    seeker.drag_ended.connect(func(changed: bool):
        if changed:
            _seek(int(seeker.value))
    )
    _button(row, ">", func(): _turn(1))
    _button(row, "Center", recenter)
    var options := HBoxContainer.new()
    content.add_child(options)
    _button(options, "Black", func(): _set_passthrough(false))
    _button(options, "See through", func(): _set_passthrough(true))
    _button(options, "LTR / RTL", func():
        book.cancel_turn()
        book.rtl = not book.rtl
        book._refresh()
    )
    _button(options, "Exit VR", func(): _request("exit"))
    var adjustments := HBoxContainer.new()
    content.add_child(adjustments)
    _slider(adjustments, "Size", 0.5, 2.5, 1.0, func(value: float): book.scale = Vector3.ONE * value)
    _slider(adjustments, "Distance", 0.35, 2.0, 0.75, func(value: float): book.position = camera.global_position - camera.global_basis.z * value)
    _slider(adjustments, "Tilt", -60.0, 45.0, -12.0, func(value: float): book.rotation.x = deg_to_rad(value))
    status = Label.new()
    status.text = _label("Loading library…")
    status.add_theme_font_size_override("font_size", 20)
    content.add_child(status)

func _slider(row: Container, caption: String, minimum: float, maximum: float, value: float, callback: Callable) -> void:
    var label := Label.new()
    label.text = _label(caption)
    row.add_child(label)
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = 0.01
    slider.value = value
    slider.custom_minimum_size = Vector2(185.0, 45.0)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    slider.value_changed.connect(callback)

func _build_library() -> void:
    var panel := _panel(self, Vector2(1.0, 0.70), Vector2i(1200, 840), Vector3(0.0, 1.45, -1.4))
    library_panel = panel.node
    var content: VBoxContainer = panel.content
    var heading := HBoxContainer.new()
    content.add_child(heading)
    _button(heading, "Library", func(): _request("library"))
    _button(heading, "Close", func(): library_panel.visible = false)
    _button(heading, "<", func():
        library_page = maxi(0, library_page - 1)
        _render_library()
    )
    _button(heading, ">", func():
        library_page += 1
        _render_library()
    )
    category_menu = OptionButton.new()
    category_menu.custom_minimum_size = Vector2(160.0, 48.0)
    heading.add_child(category_menu)
    category_menu.item_selected.connect(func(index: int):
        category = "" if index == 0 else str(library_categories[index - 1].id)
        library_page = 0
        _render_library()
    )
    var search := LineEdit.new()
    search.placeholder_text = _label("Search library / chapters")
    search.custom_minimum_size.y = 44.0
    content.add_child(search)
    search.text_changed.connect(func(text: String):
        query = text
        library_page = 0
        _render_library()
    )
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content.add_child(scroll)
    library_list = VBoxContainer.new()
    library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(library_list)

func _render_library() -> void:
    for child in library_list.get_children():
        library_list.remove_child(child)
        child.queue_free()
    covers.clear()
    var filtered: Array = library_entries.filter(func(item: Dictionary):
        return str(item.title).to_lower().contains(query.to_lower()) and (library_mode != "library" or category.is_empty() or category in item.get("categories", []))
    )
    library_page = clampi(library_page, 0, maxi(0, (filtered.size() - 1) / 12))
    var grid := GridContainer.new()
    grid.columns = 4 if library_mode == "library" else 1
    library_list.add_child(grid)
    for item in filtered.slice(library_page * 12, library_page * 12 + 12):
        var entry: Dictionary = item
        if library_mode == "library":
            var card := VBoxContainer.new()
            card.custom_minimum_size.x = 270.0
            grid.add_child(card)
            var cover := TextureButton.new()
            cover.custom_minimum_size = Vector2(250.0, 235.0)
            cover.ignore_texture_size = true
            cover.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
            card.add_child(cover)
            cover.pressed.connect(func(): _request("chapters", {"manga": str(entry.id)}))
            covers[str(entry.id)] = cover
            _request("cover", {"manga": str(entry.id)})
            var button := _button(card, str(entry.title), func(): _request("chapters", {"manga": str(entry.id)}))
            button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            button.custom_minimum_size.x = 250.0
        else:
            _button(grid, ("✓ " if entry.get("read", false) else "") + str(entry.title), func(): _request("open", {"manga": selected_manga, "chapter": str(entry.id)}))
    status.text = "%s %s · %s %s" % [filtered.size(), _label("entries"), _label("screen"), library_page + 1]

func _request(action: String, data: Dictionary = {}) -> void:
    data["action"] = action
    if bridge:
        bridge.call("request", JSON.stringify(data))
    elif action == "page" and not local_pages.is_empty():
        var index := int(data.get("index", -1))
        if index >= 0 and index < local_pages.size():
            _response.call_deferred(JSON.stringify({"kind": "page", "token": chapter_token, "index": index, "path": local_pages[index]}))

func _response(json: String) -> void:
    var data = JSON.parse_string(json)
    if not data is Dictionary:
        return
    match data.get("kind", ""):
        "error":
            status.text = str(data.get("message", _label("Unable to load content")))
        "library", "chapters":
            library_mode = str(data.kind)
            library_entries = data.get("items", [])
            library_page = 0
            selected_manga = str(data.get("manga", ""))
            category_menu.visible = library_mode == "library"
            if library_mode == "library":
                library_categories = data.get("categories", [])
                category_menu.clear()
                category_menu.add_item(_label("All categories"))
                for entry in library_categories:
                    category_menu.add_item(str(entry.title))
                category = ""
            _render_library()
            library_panel.visible = true
        "cover":
            var cover = covers.get(str(data.manga))
            if is_instance_valid(cover):
                var image := Image.new()
                if image.load(str(data.path)) == OK:
                    image.generate_mipmaps()
                    cover.texture_normal = ImageTexture.create_from_image(image)
        "chapter":
            chapter_token = str(data.token)
            book.set_chapter(int(data.count), int(data.start), bool(data.get("rtl", false)))
            seeker.max_value = maxi(0, book.page_count - 1)
            title.text = str(data.title)
            library_panel.visible = false
            pending_seek = book.first_page
            _preload(book.first_page)
        "page":
            if str(data.token) != chapter_token:
                return
            var image := Image.new()
            if image.load(str(data.path)) != OK:
                status.text = _label("Unable to decode page")
                return
            image.generate_mipmaps()
            book.supply_page(int(data.index), ImageTexture.create_from_image(image))
            if pending_seek >= 0 and book.seek(pending_seek):
                pending_seek = -1

func _preload(index: int) -> void:
    for page in range(maxi(0, index - 2), mini(book.page_count, index + 4)):
        if not book.textures.has(page):
            _request("page", {"token": chapter_token, "index": page})

func _seek(index: int) -> void:
    pending_seek = index - posmod(index, 2)
    book.prepare_seek(pending_seek)
    _preload(pending_seek)
    if book.seek(pending_seek):
        pending_seek = -1

func _spread_changed(index: int) -> void:
    seeker.value = index
    status.text = "%s %s–%s / %s" % [_label("Pages"), index + 1, mini(index + 2, book.page_count), book.page_count]
    _request("progress", {"token": chapter_token, "index": mini(index + 1, book.page_count - 1)})
    _preload(index)

func _turn(direction: int) -> void:
    if book.turn_direction != 0:
        return
    if book.first_page + direction * 2 < 0 or book.first_page + direction * 2 >= book.page_count:
        _request("next_chapter" if direction > 0 else "previous_chapter")
        return
    if not book.step(direction):
        _preload(book.first_page + direction * 2)
        status.text = _label("Waiting for pages, or chapter boundary")

func _set_passthrough(enabled: bool) -> void:
    var supported := xr and xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
    var active: bool = enabled and supported
    get_viewport().transparent_bg = active
    environment.environment.background_color = Color(0.0, 0.0, 0.0, 0.0 if active else 1.0)
    if xr:
        xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if active else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
    if enabled and not supported:
        status.text = _label("Passthrough unavailable; using black")

func _process(_delta: float) -> void:
    for hand in ["left", "right"]:
        if not tracked.has(hand):
            continue
        var controller: XRController3D = tracked[hand].controller
        var tracker := XRServer.get_tracker("/user/hand_tracker/" + hand) as XRHandTracker
        var pressed := false
        var valid := false
        var tip := controller.global_position
        var pointer_basis := controller.global_basis
        var direction := -controller.global_basis.z
        tracked[hand].hand_root.visible = false
        tracked[hand].ray.visible = false
        if tracker and tracker.has_tracking_data and tracker.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED:
            var required := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
            valid = (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) & required) != 0 and (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_TIP) & required) != 0
            if valid:
                tracked[hand].hand_root.visible = true
                tip = origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
                pointer_basis = origin.global_basis * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).basis
                var thumb := origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
                pressed = tip.distance_to(thumb) < (0.032 if tracked[hand].pressed else 0.022)
                direction = (tip - camera.global_position).normalized()
        else:
            valid = controller.get_is_active()
            tracked[hand].ray.visible = valid
            pressed = controller.is_button_pressed("trigger_click") or controller.is_button_pressed("grip_click")
        _pointer(hand, tip, direction, pressed, valid, pointer_basis)

func _pointer(hand: String, tip: Vector3, direction: Vector3, pressed: bool, valid: bool, pointer_basis: Basis = Basis.IDENTITY) -> void:
    var previous: bool = tracked[hand].pressed
    if not valid:
        if holder == hand:
            book.cancel_turn()
            holder = ""
            moving = false
        pressed = false
    if holder == hand:
        if pressed:
            if moving:
                book.global_position = tip + hold_offset
                book.global_basis = pointer_basis * hold_basis
            else:
                book.drag(book.to_local(tip))
        else:
            if not moving and valid:
                book.release_turn()
            holder = ""
            moving = false
    elif pressed and not previous and holder.is_empty() and ui_owner.is_empty() and valid:
        var point := book.to_local(tip)
        if absf(point.z) < 0.045 and absf(point.y) < SpatialBook.PAGE_HEIGHT / 2.0:
            if absf(point.x) < 0.04:
                holder = hand
                moving = true
                hold_offset = book.global_position - tip
                hold_basis = pointer_basis.inverse() * book.global_basis
            elif absf(point.x) > SpatialBook.PAGE_WIDTH * 0.72 and absf(point.x) < SpatialBook.PAGE_WIDTH + 0.03:
                if book.begin_turn(1 if point.x > 0.0 else -1):
                    holder = hand
    if holder.is_empty() and (ui_owner.is_empty() or ui_owner == hand):
        if valid or (previous and not pressed):
            var hit := _panel_input(tip, direction, pressed, previous)
            if hit and pressed and not previous:
                ui_owner = hand
        if not pressed and ui_owner == hand:
            ui_owner = ""
    tracked[hand].pressed = pressed

func _panel_input(start: Vector3, direction: Vector3, pressed: bool, previous: bool) -> bool:
    for panel in panels:
        if not ui_capture.is_empty() and ui_capture.panel != panel:
            continue
        var node: Node3D = panel.node
        if not node.is_visible_in_tree():
            continue
        var local_start := node.to_local(start)
        var local_direction := node.global_transform.basis.inverse() * direction
        if absf(local_direction.z) < 0.0001:
            continue
        var distance := -local_start.z / local_direction.z
        if distance < 0.0 or distance > 5.0:
            continue
        var point := local_start + local_direction * distance
        var size: Vector2 = panel.size
        if ui_capture.is_empty() and (absf(point.x) > size.x / 2.0 or absf(point.y) > size.y / 2.0):
            continue
        var pixel := Vector2(point.x / size.x + 0.5, 0.5 - point.y / size.y) * Vector2(panel.pixels)
        pixel = pixel.clamp(Vector2.ZERO, Vector2(panel.pixels) - Vector2.ONE)
        if pressed and not previous:
            ui_capture = {"panel": panel, "pixel": pixel}
        if not ui_capture.is_empty():
            ui_capture.pixel = pixel
        var motion := InputEventMouseMotion.new()
        motion.position = pixel
        motion.global_position = pixel
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        panel.viewport.push_input(motion, true)
        if pressed != previous:
            var click := InputEventMouseButton.new()
            click.position = pixel
            click.global_position = pixel
            click.button_index = MOUSE_BUTTON_LEFT
            click.pressed = pressed
            panel.viewport.push_input(click, true)
        if not pressed:
            ui_capture.clear()
        return true
    if not ui_capture.is_empty() and not pressed:
        var release := InputEventMouseButton.new()
        release.position = ui_capture.pixel
        release.global_position = ui_capture.pixel
        release.button_index = MOUSE_BUTTON_LEFT
        release.pressed = false
        ui_capture.panel.viewport.push_input(release, true)
        ui_capture.clear()
    return false

func _unhandled_input(event: InputEvent) -> void:
    if xr and xr.is_initialized():
        return
    if event is InputEventMouseMotion or event is InputEventMouseButton:
        var pixel: Vector2 = event.position
        var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
        _panel_input(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel), pressed, bool(tracked.get("desktop", {}).get("pressed", false)))
        tracked["desktop"] = {"pressed": pressed}
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_RIGHT:
            _turn(1)
        elif event.keycode == KEY_LEFT:
            _turn(-1)

func _load_desktop_pages() -> void:
    library_panel.visible = false
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--pages="):
            var directory := argument.trim_prefix("--pages=")
            for filename in DirAccess.get_files_at(directory):
                if filename.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
                    local_pages.append(directory.path_join(filename))
    local_pages.sort()
    chapter_token = "desktop"
    book.set_chapter(local_pages.size())
    seeker.max_value = maxi(0, book.page_count - 1)
    for index in range(mini(6, local_pages.size())):
        var image := Image.new()
        if image.load(local_pages[index]) == OK:
            image.generate_mipmaps()
            book.supply_page(index, ImageTexture.create_from_image(image))
    status.text = "Desktop validation: pass -- --pages=<directory> to load images"
