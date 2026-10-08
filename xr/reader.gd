extends Node3D

const BookScript = preload("res://book.gd")
const HandVisual = preload("res://hand_visual.gd")
const PINCH_START_DISTANCE := 0.022
const PINCH_RELEASE_DISTANCE := 0.032
const CONTACT_HYSTERESIS := 0.035
var book: SpatialBook
var origin: XROrigin3D
var camera: Camera3D
var xr: XRInterface
var environment: WorldEnvironment
var bridge: Object
var labels: Dictionary = {}
var panels: Array[Dictionary] = []
var library_panel: Node3D
var android_app: Object
var android_layer: OpenXRCompositionLayerQuad
var android_started := false
var android_status: Label
var workspace: RefCounted
var hand_page_turn: RefCounted
var hand_touch: RefCounted
var hand_controls: RefCounted
var room: Node3D
var books: Array[SpatialBook] = []
var reader_filters: Dictionary = {}
var toolbar: Node3D
var toolbar_forced := false
var palm_dwell := 0.0
var palm_hidden := 0.0
var window_holder := ""
var held_window: Node3D
var held_window_offset := Vector3.ZERO
var held_window_basis := Basis.IDENTITY
var scale_hands: Dictionary = {}
var scale_start_distance := 0.0
var scale_start := Vector3.ONE
var scale_anchor := Vector3.ZERO
var scale_start_vector := Vector3.RIGHT
var scale_start_basis := Basis.IDENTITY
var scroll_drag_y := 0.0
var snap_turn_ready := true
var chapter_requests: Dictionary = {}
var native_controls: Node3D
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
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color(0.85, 0.88, 0.92)
    environment.environment.ambient_light_energy = 0.65
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
        _build_tracking()
    else:
        camera = Camera3D.new()
        camera.position.y = 1.35
        origin.add_child(camera)
    camera.current = true
    book = BookScript.new()
    add_child(book)
    books.append(book)
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
    toolbar = toolbar_view.get_parent()
    toolbar.reparent(self)
    ui.options.reparent(self)
    toolbar.visible = false
    # A translucent sphere dims passthrough without hiding the real room.
    var dimmer := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 8.0
    sphere.height = 16.0
    dimmer.mesh = sphere
    var dim_material := StandardMaterial3D.new()
    dim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    dim_material.cull_mode = BaseMaterial3D.CULL_FRONT
    dim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    dim_material.albedo_color = Color(0, 0, 0, 0.42)
    dimmer.material_override = dim_material
    camera.add_child(dimmer)
    workspace = preload("res://frosted_workspace.gd").new(self)
    workspace.build()
    hand_page_turn = preload("res://hand_page_turn.gd").new(self)
    hand_touch = preload("res://hand_touch.gd").new(self)
    hand_controls = preload("res://hand_controls.gd").new(self)
    if bridge:
        book.visible = false
        if not android_app:
            _request("library")
            _request("reader_filters")
    else:
        _load_desktop_pages()
        book.visible = not local_pages.is_empty()
    _set_passthrough(true)
    if bridge and bridge.has_method("keyboardProbeEnabled") and bridge.call("keyboardProbeEnabled"):
        _probe_keyboard.call_deferred()
    if xr and xr.has_signal("pose_recentered"):
        xr.connect("pose_recentered", func(): _cancel_interactions(); recenter.call_deferred())

func _probe_keyboard() -> void:
    await get_tree().create_timer(2.0).timeout
    workspace.show_sources(false)
    workspace.picker_search.grab_focus()

func _build_tracking() -> void:
    for hand in ["left", "right"]:
        var controller := XRController3D.new()
        controller.tracker = hand + "_hand"
        controller.pose = "aim"
        origin.add_child(controller)
        var grip := XRNode3D.new()
        grip.tracker = controller.tracker
        grip.pose = "grip"
        grip.show_when_tracked = true
        origin.add_child(grip)
        if ClassDB.class_exists("OpenXRFbRenderModel"):
            var controller_model = ClassDB.instantiate("OpenXRFbRenderModel")
            controller_model.set("render_model_type", 0 if hand == "left" else 1)
            grip.add_child(controller_model)
            controller_model.connect("openxr_fb_render_model_loaded", func(): print("VR controller model loaded: ", hand))
        var hand_root := XRNode3D.new()
        hand_root.tracker = "/user/hand_tracker/" + hand
        hand_root.pose = "default"
        hand_root.show_when_tracked = false
        origin.add_child(hand_root)
        var hand_material := ShaderMaterial.new()
        hand_material.shader = preload("res://hand.gdshader")
        var hand_visual := HandVisual.new(hand, hand_material)
        hand_root.add_child(hand_visual)
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
        var pointer := Node3D.new()
        add_child(pointer)
        pointer.add_child(ray)
        var aim := XRController3D.new()
        aim.tracker = "/user/fbhandaim/" + hand
        origin.add_child(aim)
        tracked[hand] = {"controller": controller, "pressed": false, "hand_root": hand_root, "ray": pointer, "grip": grip, "native_mesh": hand_visual.native != null, "native_skeleton": hand_visual.native, "hand_visual": hand_visual, "aim": aim, "material": hand_material}
        print("VR hand visual registered: ", hand, " native=", hand_visual.native != null, " fallback bones=", hand_visual.fallback_skeleton.get_bone_count())

func _label(text: String) -> String:
    return str(labels.get(text, text))

func recenter() -> void:
    if workspace:
        _cancel_interactions()
    var head := camera.global_transform
    var tracker := XRServer.get_tracker("head") as XRPositionalTracker
    if camera is XRCamera3D and tracker and tracker.has_pose("default"):
        var pose := tracker.get_pose("default")
        if pose.has_tracking_data:
            head = origin.global_transform * pose.get_adjusted_transform()
    var facing := Basis(Vector3.UP, head.basis.get_euler().y)
    if book.token.is_empty() and not workspace:
        book.global_position = head.origin - facing.z * 0.75 - Vector3.UP * 0.12
        book.global_rotation = Vector3(deg_to_rad(-12.0), facing.get_euler().y, 0.0)
    if is_instance_valid(library_panel):
        library_panel.global_position = head.origin - facing.z * 1.1
        library_panel.global_basis = facing
    if workspace:
        workspace.recenter(head)

func _head_is_tracked() -> bool:
    var tracker := XRServer.get_tracker("head") as XRPositionalTracker
    return tracker != null and tracker.has_pose("default") and tracker.get_pose("default").has_tracking_data

func toggle_library() -> void:
    ui.options.visible = false
    if workspace:
        workspace.show_section("Home")

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
    var frost := MeshInstance3D.new()
    var frost_quad := QuadMesh.new()
    frost_quad.size = size
    frost.mesh = frost_quad
    frost.position.z = -0.008
    var frost_material := ShaderMaterial.new()
    frost_material.shader = preload("res://glass.gdshader")
    frost_material.set_shader_parameter("panel_size", size)
    frost.material_override = frost_material
    node.add_child(frost)
    var background := Panel.new()
    background.add_theme_stylebox_override("panel", ui.style(Color(0.40, 0.39, 0.37, 0.08), 32))
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
    button.add_theme_stylebox_override("normal", ui.style(Color(0.72, 0.71, 0.68, 0.13), 20))
    button.add_theme_stylebox_override("hover", ui.style(Color(0.85, 0.84, 0.80, 0.30), 20))
    button.add_theme_stylebox_override("pressed", ui.style(Color(0.76, 0.94, 0.23, 0.24), 20))
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

func _create_android_layer() -> void:
    android_layer = OpenXRCompositionLayerQuad.new()
    library_panel = android_layer
    android_layer.quad_size = Vector2(1.2, 1.0)
    android_layer.android_surface_size = Vector2i(1440, 1200)
    android_layer.use_android_surface = true
    # Depth-aware hole punching lets hands and books pass in front of the
    # native Android window instead of being covered by a compositor overlay.
    android_layer.sort_order = -1
    android_layer.enable_hole_punch = true
    # Meta's OpenGL Android swapchain has inverted image rows.
    android_layer.set("XR_FB_composition_layer_image_layout/vertical_flip", true)
    # OpenXR uses this node's local transform, not its parent's transform.
    android_layer.position = Vector3(0, 1.35, -1.1)
    origin.add_child(android_layer)
    recenter()

func _build_library() -> void:
    if OS.get_name() == "Android" and xr and xr.is_initialized():
        android_app = JavaClassWrapper.wrap("eu.kanade.tachiyomi.ui.vr.VrAndroidPanel")
        if android_app:
            _create_android_layer()
            panels.append({"node": library_panel, "size": Vector2(1.2, 1.0), "pixels": Vector2i(1440, 1200), "android": true})
            _build_android_controls()
            return
    var panel := _panel(self, Vector2(1.0, 0.70), Vector2i(1200, 840), Vector3(0.0, 1.45, -1.4))
    library_panel = panel.node
    var content: VBoxContainer = panel.content
    var heading := HBoxContainer.new()
    content.add_child(heading)
    _button(heading, "Library", func(): _request("library"))
    _button(heading, "Close", func():
        if not chapter_token.is_empty():
            library_panel.visible = false
            book.visible = true
    )
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

func _build_android_controls() -> void:
    var panel := _panel(library_panel, Vector2(1.2, 0.10), Vector2i(1440, 120), Vector3(0, -0.57, 0.02))
    var row := HBoxContainer.new()
    native_controls = panel.node
    native_controls.reparent(self)
    native_controls.visible = false
    panel.content.add_child(row)
    _button(row, "Back", func(): android_app.call("back"))
    _button(row, "Center", recenter)
    _button(row, "Exit VR", func(): _request("exit"))
    android_status = Label.new()
    android_status.add_theme_font_size_override("font_size", 20)
    row.add_child(android_status)
    var keyboard := _panel(library_panel, Vector2(1.2, 0.35), Vector2i(1440, 420), Vector3(0, -0.83, 0.02))
    keyboard.node.visible = false
    _button(row, "ABC", func(): keyboard.node.visible = not keyboard.node.visible)
    var letter_buttons: Array[Button] = []
    for letters in ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm.,", "@:/_-+!?=\\"]:
        var keys := HBoxContainer.new()
        keyboard.content.add_child(keys)
        for letter in letters:
            var button := _button(keys, letter, func(): pass)
            button.pressed.connect(func(): _key(button.text))
            letter_buttons.append(button)
            button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var keys := HBoxContainer.new()
    keyboard.content.add_child(keys)
    _button(keys, "⇧", func():
        for button in letter_buttons:
            button.text = button.text.to_upper() if button.text == button.text.to_lower() else button.text.to_lower()
    )
    _button(keys, "⌫", func(): _key("BACKSPACE"))
    _button(keys, "________", func(): _key(" "))
    _button(keys, "↵", func(): _key("ENTER"))

func _key(text: String) -> void:
    for panel in panels:
        if not panel.has("viewport"):
            continue
        var focused = panel.viewport.gui_get_focus_owner()
        if focused is LineEdit:
            if text == "BACKSPACE":
                focused.delete_char_at_caret()
            elif text == "ENTER":
                focused.text_submitted.emit(focused.text)
            else:
                focused.insert_text_at_caret(text)
            return
    if android_app:
        android_app.call("key", text)

func _activate_book(target: SpatialBook) -> void:
    if target != book:
        _cancel_interactions()
    book = target
    chapter_token = target.token
    pending_seek = target.pending_page
    title.text = target.chapter_title
    seeker.max_value = maxi(0, target.page_count - 1)
    ui.update_pages(target.first_page)
    ui.update_title()

func close_book(return_home: bool = true) -> void:
    if book.token.is_empty():
        return
    _cancel_interactions()
    _request("progress", {"token": book.token, "index": mini(book.first_page + (0 if book.scroll_mode else 1), maxi(0, book.page_count - 1))})
    _request("close_book", {"token": book.token})
    if books.size() == 1:
        book.visible = false
        book.token = ""
        book.textures.clear()
        book.strips.clear()
        book.strip_textures.clear()
        chapter_token = ""
    else:
        var closed := book
        books.erase(closed)
        _activate_book(books.back())
        closed.queue_free()
    toolbar_forced = false
    toolbar.visible = false
    if workspace and return_home:
        workspace.show_section("Home")

func _palm_toolbar(facing: bool, at: Vector3, delta: float) -> void:
    palm_dwell = palm_dwell + delta if facing else 0.0
    palm_hidden = 0.0 if facing else palm_hidden + delta
    var was_visible := toolbar.visible
    var natural_hands := tracked.values().any(func(value): return value.get("natural_hand", false))
    var active := (toolbar_forced and not natural_hands) or (facing and palm_dwell > 0.10)
    toolbar.visible = active and not chapter_token.is_empty()
    if is_instance_valid(native_controls):
        native_controls.visible = active and (not chapter_token.is_empty() or library_panel.visible)
    if active:
        # Palm attachment is the requested behavior; the reference alone
        # cannot establish its original attachment strategy.
        var position := at + Vector3.UP * 0.06
        if not natural_hands and not facing:
            position = camera.global_position - camera.global_basis.z * 0.55 - Vector3.UP * 0.28
        toolbar.global_position = position
        toolbar.look_at(camera.global_position, Vector3.UP, true)
        if is_instance_valid(native_controls):
            native_controls.global_transform = toolbar.global_transform
            native_controls.global_position -= Vector3.UP * 0.16
    if ui.options.visible and not workspace:
        ui.options.global_position = book.global_position + Vector3.UP * 0.50
        ui.options.look_at(camera.global_position, Vector3.UP, true)

func _locomotion(_delta: float) -> void:
    pass

func _reader_at(point: Vector3) -> SpatialBook:
    for candidate in books:
        if not candidate.visible:
            continue
        var local := candidate.to_local(point)
        if candidate.cover_handle_at(local):
            return candidate
        if not candidate.scroll_mode and candidate.openness < 0.05 and local.x < -0.04:
            continue
        var half_width := 0.38 if candidate.scroll_mode else SpatialBook.PAGE_WIDTH + CONTACT_HYSTERESIS
        var half_height := 0.54 if candidate.scroll_mode else SpatialBook.PAGE_HEIGHT / 2 + 0.03
        if absf(local.z) < 0.10 and absf(local.x) < half_width and absf(local.y) < half_height:
            return candidate
    return null

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
    if filtered.is_empty():
        var empty := Label.new()
        empty.text = _label("Library") + ": 0 " + _label("entries")
        empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        empty.custom_minimum_size = Vector2(1000, 100)
        empty.add_theme_font_size_override("font_size", 30)
        library_list.add_child(empty)
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
    if action in ["next_chapter", "previous_chapter"]:
        data["token"] = chapter_token
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
    if workspace and workspace.consume(data):
        return
    match data.get("kind", ""):
        "reader_filters":
            reader_filters = data
            for model in books: model.apply_reader_filters(data)
        "error":
            status.visible = true
            status.text = str(data.get("message", _label("Unable to load content")))
        "library", "chapters":
            library_mode = str(data.kind)
            library_entries = data.get("items", [])
            library_page = 0
            selected_manga = str(data.get("manga", ""))
            if android_app:
                return
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
            var replaced := str(data.get("replaces", ""))
            var target: SpatialBook
            for existing in books:
                if existing.token == replaced and not replaced.is_empty():
                    target = existing
            if target == null:
                if book.token.is_empty():
                    target = book
                else:
                    target = BookScript.new()
                    add_child(target)
                    target.apply_reader_filters(reader_filters)
                    books.append(target)
                    target.spread_changed.connect(func(index: int):
                        if target == book:
                            _spread_changed(index)
                        else:
                            _request("progress", {"token": target.token, "index": index})
                    )
                var facing := Basis(Vector3.UP, camera.global_basis.get_euler().y)
                target.global_transform = Transform3D(facing * Basis(Vector3.RIGHT, deg_to_rad(-8)), camera.global_position + facing * Vector3(0.22 * (books.size() - 1), -0.35, -0.85))
            _activate_book(target)
            var previous_open := target.openness if not replaced.is_empty() else (1.0 if int(data.start) > 0 else 0.0)
            book.visible = true
            chapter_token = str(data.token)
            book.token = chapter_token
            book.chapter_title = str(data.title)
            book.vertical_chapter = bool(data.get("vertical", false))
            book.set_chapter(int(data.count), int(data.start), bool(data.get("rtl", false)))
            book.set_open(previous_open)
            seeker.max_value = maxi(0, book.page_count - 1)
            ui.update_pages(book.first_page)
            title.text = str(data.title)
            ui.update_title()
            pending_seek = int(data.start)
            book.pending_page = pending_seek
            _preload(book.first_page)
            if workspace:
                workspace.chapter_opened()
            # Resumed chapters still need the first image for their cover.
            _request("page", {"token": chapter_token, "index": 0})
        "page":
            var target: SpatialBook
            for existing in books:
                if existing.token == str(data.token):
                    target = existing
            if target == null:
                return
            var image := Image.new()
            if image.load(str(data.path)) != OK:
                status.text = _label("Unable to decode page")
                push_error("VR page decode failed: " + str(data.path))
                return
            image.generate_mipmaps()
            target.supply_page(int(data.index), ImageTexture.create_from_image(image), Vector2i(int(data.get("width", image.get_width())), int(data.get("height", image.get_height()))))
            print("VR page supplied: ", data.token, " index=", data.index, " size=", image.get_size())
            if not data.get("strips", []).is_empty():
                target.supply_strips(int(data.index), data.strips)
            if target.pending_page >= 0 and target.seek(target.pending_page):
                target.pending_page = -1
                if target == book:
                    pending_seek = -1

func _preload(index: int) -> void:
    for page in range(maxi(0, index - 2), mini(book.page_count, index + 4)):
        if not book.textures.has(page):
            _request("page", {"token": chapter_token, "index": page})

func _seek(index: int) -> void:
    pending_seek = index if book.scroll_mode else index - posmod(index, 2)
    book.pending_page = pending_seek
    book.prepare_seek(pending_seek)
    _preload(pending_seek)
    if book.seek(pending_seek):
        pending_seek = -1

func _spread_changed(index: int) -> void:
    seeker.value = index
    ui.update_pages(index)
    status.text = "%s %s–%s / %s" % [_label("Pages"), index + 1, mini(index + 2, book.page_count), book.page_count]
    _request("progress", {"token": chapter_token, "index": mini(index + (0 if book.scroll_mode else 1), book.page_count - 1)})
    _preload(index)

func _turn(direction: int) -> void:
    if book.turn_direction != 0:
        return
    var stride := 1 if book.scroll_mode else 2
    if book.first_page + direction * stride < 0 or book.first_page + direction * stride >= book.page_count:
        var key := chapter_token + ("next" if direction > 0 else "previous")
        var now := Time.get_ticks_msec()
        if now - int(chapter_requests.get(key, -1000)) >= 1000:
            chapter_requests[key] = now
            _request("next_chapter" if direction > 0 else "previous_chapter")
        return
    if not book.step(direction):
        _preload(book.first_page + direction * stride)
        status.text = _label("Waiting for pages, or chapter boundary")

func _scroll_reader(distance: float) -> void:
    if not book.visible or not book.scroll_mode or book.page_count == 0:
        return
    var need := book.scroll_by(distance)
    if absi(need) == 2:
        _turn(signi(need))
    elif need != 0:
        _preload(book.first_page + need)

func _set_passthrough(enabled: bool) -> void:
    var supported := xr and xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
    var active: bool = enabled and supported
    passthrough_enabled = active
    if is_instance_valid(room):
        room.visible = not active
    get_viewport().transparent_bg = active
    environment.environment.background_color = Color(0.0, 0.0, 0.0, 0.0 if active else 1.0)
    if xr:
        xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if active else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
    if enabled and not supported:
        status.text = _label("Passthrough unavailable; using black")

func _process(_delta: float) -> void:
    if android_app and not android_started:
        var surface = android_layer.get_android_surface()
        if surface:
            android_started = true
            android_app.call("start", surface, 1440, 1200)
    if android_app and android_started:
        android_status.text = str(android_app.call("error"))
    if awaiting_head_pose and _head_is_tracked():
        awaiting_head_pose = false
        recenter()
        print("VR head pose ready; library centered")
    _locomotion(_delta)
    if workspace: workspace.sync_badge()
    var palm_visible := false
    var palm_position := Vector3.ZERO
    for hand in ["left", "right"]:
        if not tracked.has(hand):
            continue
        var controller: XRController3D = tracked[hand].controller
        var tracker := XRServer.get_tracker("/user/hand_tracker/" + hand) as XRHandTracker
        var pressed := false
        var valid := false
        var natural_hand := false
        var finger_tracked := false
        var chopping := false
        var tip := controller.global_position
        var pointer_basis := controller.global_basis
        var direction := -controller.global_basis.z
        var pointer_origin := tip
        tracked[hand].hand_root.visible = false
        tracked[hand].ray.visible = false
        tracked[hand].grip.visible = false
        if HandVisual.natural_tracking(tracker):
            tracked[hand].hand_root.visible = HandVisual.can_render(tracker)
            natural_hand = true
            var required := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
            var palm := origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
            if hand != preferred_hand and hand_controls.seeker_facing(tracker):
                palm_visible = true
                palm_position = palm.origin
            chopping = hand_controls.edge_hand(tracker, tracked[hand].get("chopping", false))
            var palm_tracked := (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM) & required) != 0
            var pinch_tracked := (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) & required) != 0 and (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_TIP) & required) != 0
            finger_tracked = (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) & required) != 0
            valid = finger_tracked or (chopping and palm_tracked)
            chopping = chopping and palm_tracked
            if valid:
                natural_hand = true
                tracked[hand].can_grab = true
                tracked[hand].can_ui = true
                tip = origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
                pointer_basis = origin.global_basis * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).basis
                var thumb := origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
                pressed = pinch_tracked and tip.distance_to(thumb) < (PINCH_RELEASE_DISTANCE if tracked[hand].pressed else PINCH_START_DISTANCE)
                tracked[hand].was_fist = tracked[hand].get("fist", false)
                tracked[hand].fist = hand_controls.is_fist(tracker, tracked[hand].was_fist)
                tracked[hand].finger_extended = hand_controls.finger_extended(tracker)
                var aim: XRController3D = tracked[hand].aim
                direction = -aim.global_basis.z.normalized() if aim.get_has_tracking_data() else hand_controls.forward(tracker)
                pointer_origin = aim.global_position if aim.get_has_tracking_data() else palm.origin
                # Filter small aim jitter, but follow deliberate movement immediately.
                # A pinch must not freeze an old ray while its origin keeps moving.
                var old_direction: Vector3 = tracked[hand].get("aim_direction", direction)
                var weight := clampf(_delta * (18.0 if old_direction.angle_to(direction) < 0.08 else 65.0), 0, 1)
                direction = old_direction.slerp(direction, weight).normalized()
                tracked[hand].aim_direction = direction
                var old_origin: Vector3 = tracked[hand].get("aim_origin", pointer_origin)
                pointer_origin = old_origin.lerp(pointer_origin, clampf(_delta * (24.0 if old_origin.distance_to(pointer_origin) < 0.018 else 70.0), 0, 1))
                tracked[hand].aim_origin = pointer_origin
        else:
            tracked[hand].fist = false
            valid = controller.get_has_tracking_data()
            tracked[hand].grip.visible = valid
            pressed = ui.controller_input(hand, controller) if valid else false
        tracked[hand].natural_hand = natural_hand
        tracked[hand].chopping = chopping
        if valid:
            tracked[hand].ray.visible = library_panel.visible or hand == preferred_hand
            if not natural_hand: pointer_origin = tip
            tracked[hand].ray.global_position = pointer_origin
            tracked[hand].ray.look_at(pointer_origin + direction, Vector3.UP)
        ui_hand = hand
        var closing: bool = hand_touch.update_close(hand, tip, valid and finger_tracked and natural_hand, pressed)
        var touching_popup: bool = natural_hand and finger_tracked and hand_touch.near_popup(tip)
        var joystick: bool = hand_controls.joystick(hand, tracker, valid and natural_hand and not closing, _delta)
        var hud_resizing: bool = hand_controls.resize_hud(hand, tip, valid and natural_hand and not joystick and not chopping, pressed and not tracked[hand].get("fist", false))
        var resizing: bool = hud_resizing or hand_controls.resize(hand, tip, valid and natural_hand and not joystick and not chopping, pressed and not tracked[hand].get("fist", false))
        var scrolling: bool = hand_controls.swipe(hand, tip, valid and natural_hand and not touching_popup and not resizing and not joystick and not chopping, pressed, _delta)
        var fist: bool = natural_hand and tracked[hand].get("fist", false)
        var sweep_tip := tip
        if valid and natural_hand and not fist and chopping:
            sweep_tip = origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
        if fist and not resizing:
            tip = origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
        var sweeping: bool = hand_page_turn.update(hand, sweep_tip, valid and natural_hand and not closing and not touching_popup and not resizing and not scrolling and not fist and not joystick, pressed and not chopping, _delta)
        var chopping_book: bool = not touching_popup and chopping and book.visible and not book.preview_only and (book.scroll_mode or book.openness >= 0.8) and hand_page_turn.in_volume(book.to_local(sweep_tip))
        var touching: bool = hand_touch.update(hand, tip, valid and finger_tracked and natural_hand and not closing and not chopping_book and not sweeping and not resizing and not scrolling and not fist, pressed)
        if not closing and not chopping_book and not sweeping and not touching and not resizing and not scrolling and not joystick:
            _pointer(hand, tip if not natural_hand or fist or _reader_at(tip) != null else pointer_origin, direction, pressed or fist, valid, pointer_basis)
        tracked[hand].tip = tip
        tracked[hand].valid = valid
        var interacting: bool = holder == hand or scale_hands.has(hand) or ui_owner == hand or window_holder == hand or sweeping
        if tracked[hand].get("material") != null:
            tracked[hand].material.set_shader_parameter("interaction", 1.0 if interacting else 0.0)
        if natural_hand and (interacting or _reader_at(tip) != null):
            tracked[hand].ray.visible = false
    for candidate in books:
        var contacts: Array = []
        for hand in tracked:
            if tracked[hand].get("valid", false):
                contacts.append(candidate.to_local(tracked[hand].tip))
        candidate.hover_edges(contacts)
    _palm_toolbar(palm_visible, palm_position, _delta)

func _notification(what: int) -> void:
    if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT] and is_instance_valid(book):
        _cancel_interactions()

func _cancel_interactions() -> void:
    if hand_page_turn: hand_page_turn.cancel()
    if hand_touch: hand_touch.cancel()
    if hand_controls: hand_controls.cancel()
    book.cancel_turn()
    holder = ""
    moving = false
    scale_hands.clear()
    scale_start_distance = 0.0
    if is_instance_valid(held_window) and workspace:
        workspace.finish_drag(held_window)
    held_window = null
    window_holder = ""
    _panel_input(camera.global_position, Vector3.UP, false, true)
    ui_owner = ""
    for hand in tracked:
        tracked[hand].pressed = false
        tracked[hand].buttons = {}
        tracked[hand].stick_down = false

func _pointer(hand: String, tip: Vector3, direction: Vector3, pressed: bool, valid: bool, pointer_basis: Basis = Basis.IDENTITY) -> void:
    if window_holder == hand and tracked[hand].get("natural_hand", false):
        pressed = tracked[hand].get("fist", false)
    if holder == hand and moving and tracked[hand].get("natural_hand", false):
        pressed = tracked[hand].get("fist", false)
    if hand_page_turn and not hand_page_turn.owner.is_empty() and hand_page_turn.owner != hand:
        tracked[hand].pressed = pressed if valid else false
        return
    var previous: bool = tracked[hand].pressed
    var remote_distance := float(tracked[hand].get("remote_distance", 0.0))
    if (holder == hand and moving) or window_holder == hand:
        tip += direction * remote_distance
    else:
        tracked[hand].remote_distance = 0.0
    tracked[hand].pointer_basis = pointer_basis
    tracked[hand].tip = tip
    tracked[hand].valid = valid
    if not valid:
        if holder == hand:
            book.cancel_turn()
            _release_body(hand)
        pressed = false
    if window_holder == hand:
        if pressed:
            held_window.global_position = tip + held_window_offset
            held_window.global_basis = pointer_basis * held_window_basis
            workspace.preview_snap(held_window)
        else:
            workspace.finish_drag(held_window)
            held_window = null
            window_holder = ""
        tracked[hand].pressed = pressed
        return
    if workspace and not tracked[hand].get("fist", false) and holder.is_empty() and (ui_owner.is_empty() or ui_owner == hand) and workspace.popup_ray(tip, direction):
        ui_hand = hand
        if _panel_input(tip, direction, pressed, previous):
            if pressed and not previous: ui_owner = hand
            elif not pressed and ui_owner == hand: ui_owner = ""
            tracked[hand].pressed = pressed
            return
    if pressed and (not previous or (tracked[hand].get("fist", false) and not tracked[hand].get("was_fist", false))) and valid and ui_owner.is_empty():
        for candidate in books:
            if candidate.is_visible_in_tree() and candidate.close_at(candidate.to_local(tip)):
                _activate_book(candidate)
                close_book()
                tracked[hand].pressed = true
                return
        var window: Node3D = workspace.handle_at(tip) if workspace and tracked[hand].get("fist", false) else null
        var controller_grip := bool(tracked[hand].get("buttons", {}).get("grip_click", false))
        if window == null and workspace and controller_grip:
            var window_hit: Dictionary = workspace.handle_ray(tip, direction)
            var book_hit := _book_ray_hit(tip, direction)
            if not window_hit.is_empty() and (book_hit.is_empty() or float(window_hit.distance) < float(book_hit.distance)):
                window = window_hit.node
                tracked[hand].remote_distance = window_hit.distance
                tip = window_hit.point
        if window != null and holder.is_empty() and window_holder.is_empty():
            window_holder = hand
            held_window = window
            held_window_offset = window.global_position - tip
            held_window_basis = pointer_basis.inverse() * window.global_basis
            workspace.begin_drag(window)
            tracked[hand].pressed = pressed
            return
        var nearby := _reader_at(tip)
        if nearby == null and controller_grip:
            var hit := _book_ray_hit(tip, direction)
            if not hit.is_empty():
                nearby = hit.book
                tracked[hand].remote_distance = hit.distance
                tip += direction * float(hit.distance)
        if nearby != null and holder.is_empty():
            _activate_book(nearby)
    if holder != "" and holder != hand and moving:
        if pressed and valid and not tracked[hand].get("natural_hand", false) and (scale_hands.has(hand) or (not previous and _reader_at(tip) == book)):
            scale_hands[hand] = tip
            if scale_start_distance == 0:
                scale_start_distance = tip.distance_to(scale_hands.get(holder, tip))
                scale_start = book.scale
                scale_start_basis = book.global_basis
                scale_start_vector = tip - Vector3(scale_hands.get(holder, tip))
                scale_anchor = book.global_position - (tip + Vector3(scale_hands.get(holder, tip))) * 0.5
            if scale_start_distance > 0.03:
                var distance := tip.distance_to(scale_hands.get(holder, tip))
                var ratio := clampf(distance / scale_start_distance, 0.5 / maxf(scale_start.x, 0.001), 2.5 / maxf(scale_start.x, 0.001))
                var current := tip - Vector3(scale_hands.get(holder, tip))
                var rotation := Basis(Quaternion(scale_start_vector.normalized(), current.normalized())) if current.length() > 0.01 else Basis.IDENTITY
                book.global_basis = rotation * scale_start_basis.scaled(Vector3.ONE * ratio)
                book.global_position = (tip + Vector3(scale_hands.get(holder, tip))) * 0.5 + rotation * (scale_anchor * ratio)
        elif scale_hands.has(hand):
            scale_hands.erase(hand)
            scale_start_distance = 0
            _rebase_hold(holder)
        tracked[hand].pressed = pressed
        return
    if holder == hand:
        scale_hands[hand] = tip
        if pressed:
            if moving and scale_start_distance == 0:
                book.global_position = tip + pointer_basis * hold_offset
                book.global_basis = pointer_basis * hold_basis
            elif moving:
                pass
            elif book.cover_dragged:
                book.drag_cover(book.to_local(tip))
            elif book.scroll_mode:
                var local_y := book.to_local(tip).y
                _scroll_reader(local_y - scroll_drag_y)
                scroll_drag_y = local_y
            else:
                book.drag(book.to_local(tip))
        else:
            if book.cover_dragged:
                book.release_cover()
            elif not moving and valid:
                book.release_turn()
            _release_body(hand)
        # A captured gesture owns its release; it cannot become a UI event.
        tracked[hand].pressed = pressed
        return
    elif book.visible and pressed and (not previous or (tracked[hand].get("fist", false) and not tracked[hand].get("was_fist", false))) and holder.is_empty() and ui_owner.is_empty() and valid and tracked[hand].get("can_grab", true):
        var point := book.to_local(tip)
        if _reader_at(tip) == book:
            var controller_grip := bool(tracked[hand].get("buttons", {}).get("grip_click", false))
            var fist_grip := bool(tracked[hand].get("fist", false))
            # Outer page corners acquire the leaf before the body. Otherwise
            # a lower-edge pinch incorrectly moves the entire book.
            var page_edge := not book.scroll_mode and absf(point.x) > SpatialBook.PAGE_WIDTH * 0.72 and absf(point.x) < SpatialBook.PAGE_WIDTH + CONTACT_HYSTERESIS
            if not controller_grip and not fist_grip and (book.cover_handle_at(point) or (page_edge and book.openness < 0.8 and point.x > 0)):
                holder = hand
                book.begin_cover(point)
            elif not controller_grip and not fist_grip and page_edge and book.openness >= 0.8:
                if book.begin_turn(1 if point.x > 0.0 else -1, point):
                    holder = hand
                    book.drag(point)
                    ui.haptic(hand)
                else:
                    var direction_to_load := (1 if point.x > 0 else -1) * (-1 if book.rtl else 1)
                    _preload(book.first_page + direction_to_load * 2)
            elif controller_grip or (fist_grip and not book.scroll_mode) or not tracked[hand].get("natural_hand", false):
                holder = hand
                moving = true
                hold_offset = pointer_basis.inverse() * (book.global_position - tip)
                hold_basis = pointer_basis.inverse() * book.global_basis
                scale_hands[hand] = tip
            elif book.scroll_mode and not tracked[hand].get("natural_hand", false):
                holder = hand
                scroll_drag_y = point.y
    if holder.is_empty() and not tracked[hand].get("fist", false) and (ui_owner.is_empty() or ui_owner == hand) and (tracked[hand].get("can_ui", true) or ui_owner == hand):
        if valid or (previous and not pressed):
            var hit := _panel_input(tip, direction, pressed, previous)
            if hit and pressed and not previous:
                ui_owner = hand
            elif not hit and pressed and not previous:
                _page_region(tip, direction, hand)
        if not pressed and ui_owner == hand:
            ui_owner = ""
    tracked[hand].pressed = pressed

func _rebase_hold(hand: String) -> void:
    var basis: Basis = tracked[hand].get("pointer_basis", Basis.IDENTITY)
    hold_offset = basis.inverse() * (book.global_position - Vector3(scale_hands.get(hand, book.global_position)))
    hold_basis = basis.inverse() * book.global_basis

func _release_body(hand: String) -> void:
    scale_hands.erase(hand)
    scale_start_distance = 0.0
    if moving:
        for remaining in scale_hands.keys():
            if tracked[remaining].get("pressed", false) and tracked[remaining].get("valid", false):
                holder = remaining
                _rebase_hold(holder)
                return
    holder = ""
    moving = false
    scale_hands.clear()

func _page_region(start: Vector3, direction: Vector3, hand: String) -> void:
    var hit := _book_ray_hit(start, direction)
    if hit.is_empty():
        return
    _activate_book(hit.book)
    var local_start := book.to_local(start)
    var local_direction := book.global_basis.inverse() * direction
    if absf(local_direction.z) < 0.0001:
        return
    var distance := -local_start.z / local_direction.z
    if distance < 0 or distance > 5:
        return
    var point := local_start + local_direction * distance
    if book.close_at(point):
        close_book()
        return
    if book.scroll_mode and absf(point.x) < 0.35 and absf(point.y) < 0.5:
        _scroll_reader(0.3 if point.y < 0 else -0.3)
        return
    if book.openness < 0.8 and point.x > 0 and point.x < SpatialBook.PAGE_WIDTH and absf(point.y) < SpatialBook.PAGE_HEIGHT / 2:
        book.set_open(1.0)
        return
    if absf(point.y) < SpatialBook.PAGE_HEIGHT / 2 and absf(point.x) > SpatialBook.PAGE_WIDTH * 0.72 and absf(point.x) < SpatialBook.PAGE_WIDTH + 0.05:
        _turn((1 if point.x > 0 else -1) * (-1 if book.rtl else 1))
        ui.haptic(hand)

func _book_ray_hit(start: Vector3, direction: Vector3) -> Dictionary:
    var nearest := 5.0
    var hit: Dictionary = {}
    for candidate in books:
        if not candidate.is_visible_in_tree():
            continue
        var local := candidate.to_local(start)
        var ray := candidate.global_transform.basis.inverse() * direction
        if absf(ray.z) < 0.0001:
            continue
        var distance := -local.z / ray.z
        var point := local + ray * distance
        var width := 0.38 if candidate.scroll_mode else SpatialBook.PAGE_WIDTH + CONTACT_HYSTERESIS
        var height := 0.54 if candidate.scroll_mode else SpatialBook.PAGE_HEIGHT / 2 + 0.03
        if distance >= 0 and distance < nearest and ((absf(point.x) < width and absf(point.y) < height) or candidate.close_at(point)):
            nearest = distance
            hit = {"book": candidate, "distance": distance}
    return hit

func _panel_input(start: Vector3, direction: Vector3, pressed: bool, previous: bool, touched: Dictionary = {}) -> bool:
    # Route to the nearest visible panel, preserving capture when a drag
    # leaves its bounds. A book in front blocks clicks on windows behind it.
    var candidates: Array[Dictionary] = []
    var book_hit := _book_ray_hit(start, direction)
    for candidate in panels:
        if not touched.is_empty() and candidate != touched:
            continue
        var node: Node3D = candidate.node
        if not node.is_visible_in_tree():
            continue
        var local := node.to_local(start)
        var ray := node.global_transform.basis.inverse() * direction
        if absf(ray.z) < 0.0001:
            continue
        var distance := -local.z / ray.z
        var point := local + ray * distance
        var captured: bool = not ui_capture.is_empty() and ui_capture.panel == candidate
        if captured or (distance >= 0 and distance <= 5 and absf(point.x) <= candidate.size.x / 2 and absf(point.y) <= candidate.size.y / 2):
            if captured or candidate.get("popup", false) or book_hit.is_empty() or distance < float(book_hit.distance):
                candidates.append({"panel": candidate, "distance": distance, "priority": int(node.get_meta("popup_priority", 0))})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.priority > b.priority if a.priority != b.priority else a.distance < b.distance)
    for entry in candidates:
        var panel: Dictionary = entry.panel
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
            if workspace and node == workspace.hud.node:
                workspace.minimize_popups()
            ui_capture = {"panel": panel, "pixel": pixel}
        if not ui_capture.is_empty():
            ui_capture.pixel = pixel
        if panel.get("android", false):
            android_app.call("hover", pixel.x, pixel.y)
            if pressed or previous:
                android_app.call("touch", pixel.x, pixel.y, 0 if pressed and not previous else (2 if pressed else 1))
            if not pressed:
                ui_capture.clear()
            return true
        var motion := InputEventMouseMotion.new()
        motion.position = pixel
        motion.global_position = pixel
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        panel.viewport.push_input(motion, true)
        if workspace and workspace.drag_scroll(panel, pixel, pressed, previous):
            if not pressed:
                ui_capture.clear()
            return true
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
        if ui_capture.panel.get("android", false):
            android_app.call("touch", ui_capture.pixel.x, ui_capture.pixel.y, 1)
            ui_capture.clear()
            return false
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
    library_panel.visible = true
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--pages="):
            var directory := argument.trim_prefix("--pages=")
            for filename in DirAccess.get_files_at(directory):
                if filename.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
                    local_pages.append(directory.path_join(filename))
    local_pages.sort()
    chapter_token = "desktop" if not local_pages.is_empty() else ""
    book.token = chapter_token
    book.set_chapter(local_pages.size())
    seeker.max_value = maxi(0, book.page_count - 1)
    for index in range(mini(6, local_pages.size())):
        var image := Image.new()
        if image.load(local_pages[index]) == OK:
            image.generate_mipmaps()
            book.supply_page(index, ImageTexture.create_from_image(image))
    ui.update_pages(book.first_page)
    status.text = "Desktop validation: pass -- --pages=<directory> to load images"
