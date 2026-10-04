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
var ui: RefCounted
var preferred_hand := "right"
var haptics := true
var ui_hand := ""
var passthrough_enabled := false
var awaiting_head_pose := false
var bindings := {"left:trigger_click": "Previous page", "right:trigger_click": "Next page", "left:ax_button": "Interact", "right:ax_button": "Interact", "left:by_button": "Library", "right:by_button": "Book Options", "left:primary_click": "Switch hands", "right:primary_click": "Center", "left:menu_button": "Book Options", "left:grip_click": "Grab", "right:grip_click": "Grab"}


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
        awaiting_head_pose = true
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
    ui = preload("res://reader_ui.gd").new(self)
    ui.load_config()
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
    viewport.transparent_bg = true
    viewport.gui_embed_subwindows = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    node.add_child(viewport)
    var surface := MeshInstance3D.new()
    var quad := QuadMesh.new()
    quad.size = size
    surface.mesh = quad
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_texture = viewport.get_texture()
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
    surface.material_override = material
    node.add_child(surface)
    var background := Panel.new()
    background.add_theme_stylebox_override("panel", ui.style(Color(0.14, 0.15, 0.17), 32))
    background.size = Vector2(pixels)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    viewport.add_child(background)
    var content := VBoxContainer.new()
    content.position = Vector2(16.0, 12.0)
    content.size = Vector2(pixels) - Vector2(32.0, 24.0)
    viewport.add_child(content)
    var data := {"node": node, "viewport": viewport, "size": size, "pixels": pixels, "content": content, "background": background}
    panels.append(data)
    return data

func _button(row: Container, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = _label(text)
    button.custom_minimum_size = Vector2(72.0, 48.0)
    button.add_theme_font_size_override("font_size", 22)
    row.add_child(button)
    button.add_theme_stylebox_override("normal", ui.style(Color(0.25, 0.27, 0.30), 20))
    button.add_theme_stylebox_override("hover", ui.style(Color(0.36, 0.39, 0.44), 20))
    button.add_theme_stylebox_override("pressed", ui.style(Color(0.46, 0.41, 0.56), 20))
    button.pressed.connect(func():
        ui.haptic(ui_hand)
        callback.call()
    )
    return button

func _build_toolbar() -> void:
    ui.build()

func _slider(row: Container, caption: String, minimum: float, maximum: float, value: float, callback: Callable) -> void:
    var icon := TextureRect.new()
    icon.texture = load("res://icons/" + {"Size": "size", "Tilt": "tilt", "Distance": "eye"}[caption] + ".svg")
    icon.custom_minimum_size = Vector2(48, 48)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.tooltip_text = _label(caption)
    row.add_child(icon)
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = 0.01
    slider.value = value
    slider.custom_minimum_size = Vector2(185.0, 70.0)
    slider.add_theme_icon_override("grabber", preload("res://icons/knob.svg"))
    slider.add_theme_icon_override("grabber_highlight", preload("res://icons/knob.svg"))
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
            status.visible = true
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
            ui.update_pages(book.first_page)
            title.text = str(data.title)
            ui.update_title()
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
    ui.update_pages(index)
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
    passthrough_enabled = active
    get_viewport().transparent_bg = active
    environment.environment.background_color = Color(0.0, 0.0, 0.0, 0.0 if active else 1.0)
    if xr:
        xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if active else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
    if enabled and not supported:
        status.text = _label("Passthrough unavailable; using black")

func _process(_delta: float) -> void:
    if awaiting_head_pose and camera is XRCamera3D and camera.get_is_active():
        awaiting_head_pose = false
        recenter()
        library_panel.global_position = camera.global_position - camera.global_basis.z * 1.1 + Vector3.UP * 0.08
        library_panel.global_rotation.y = camera.global_rotation.y
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
                tracked[hand].can_grab = true
                tracked[hand].can_ui = true
                tracked[hand].hand_root.visible = true
                tip = origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
                pointer_basis = origin.global_basis * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).basis
                var thumb := origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
                pressed = tip.distance_to(thumb) < (0.032 if tracked[hand].pressed else 0.022)
                direction = (tip - camera.global_position).normalized()
        else:
            valid = controller.get_is_active()
            tracked[hand].ray.visible = valid
            pressed = ui.controller_input(hand, controller)
        ui_hand = hand
        _pointer(hand, tip, direction, pressed, valid, pointer_basis)

func _notification(what: int) -> void:
    if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT] and is_instance_valid(book):
        _cancel_interactions()

func _cancel_interactions() -> void:
    book.cancel_turn()
    holder = ""
    moving = false
    _panel_input(camera.global_position, Vector3.UP, false, true)
    ui_owner = ""
    for hand in tracked:
        tracked[hand].pressed = false
        tracked[hand].buttons = {}
        tracked[hand].stick_down = false

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
    elif pressed and not previous and holder.is_empty() and ui_owner.is_empty() and valid and tracked[hand].get("can_grab", true):
        var point := book.to_local(tip)
        if absf(point.z) < 0.075 and absf(point.y) < SpatialBook.PAGE_HEIGHT / 2.0:
            if absf(point.x) < 0.04:
                holder = hand
                moving = true
                hold_offset = book.global_position - tip
                hold_basis = pointer_basis.inverse() * book.global_basis
            elif absf(point.x) > SpatialBook.PAGE_WIDTH * 0.72 and absf(point.x) < SpatialBook.PAGE_WIDTH + 0.05:
                if book.begin_turn(1 if point.x > 0.0 else -1):
                    holder = hand
                    ui.haptic(hand)
    if holder.is_empty() and (ui_owner.is_empty() or ui_owner == hand) and (tracked[hand].get("can_ui", true) or ui_owner == hand):
        if valid or (previous and not pressed):
            var hit := _panel_input(tip, direction, pressed, previous)
            if hit and pressed and not previous:
                ui_owner = hand
            elif not hit and pressed and not previous:
                _page_region(tip, direction, hand)
        if not pressed and ui_owner == hand:
            ui_owner = ""
    tracked[hand].pressed = pressed

func _page_region(start: Vector3, direction: Vector3, hand: String) -> void:
    var local_start := book.to_local(start)
    var local_direction := book.global_basis.inverse() * direction
    if absf(local_direction.z) < 0.0001:
        return
    var distance := -local_start.z / local_direction.z
    if distance < 0 or distance > 5:
        return
    var point := local_start + local_direction * distance
    if absf(point.y) < SpatialBook.PAGE_HEIGHT / 2 and absf(point.x) > SpatialBook.PAGE_WIDTH * 0.72 and absf(point.x) < SpatialBook.PAGE_WIDTH + 0.05:
        _turn((1 if point.x > 0 else -1) * (-1 if book.rtl else 1))
        ui.haptic(hand)

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
    ui.update_pages(book.first_page)
    status.text = "Desktop validation: pass -- --pages=<directory> to load images"
