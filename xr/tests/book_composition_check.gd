extends SceneTree

func _initialize() -> void: check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    assert(not reader.workspace.hud.surface.material_override.no_depth_test, "Scene-backed HUD also respects hands and pointer depth")
    reader.title.text = "An extremely long manga title with many words ".repeat(30)
    for frame in 4: await process_frame
    var column: Control = reader.title.get_parent()
    assert(column.size.x <= 1000, "Long title must not expand the palm menu")
    for control in column.get_child(2).get_children():
        assert(control.get_global_rect().end.x <= 1000, "All palm buttons remain inside the viewport")
    var compositor = load("res://book_composition.gd").new()
    reader.add_child(compositor)
    compositor.setup(reader)
    assert(not compositor.NATIVE_PAGE_LAYERS_ENABLED and compositor.entries.is_empty(), "Use the scene-rendered pages until Quest composition layers present their content reliably")
    var book: SpatialBook = reader.book
    book.token = "test"
    book.visible = true
    book.set_chapter(4)
    var image := Image.create(700, 1000, false, Image.FORMAT_RGB8)
    image.fill(Color.WHITE)
    image.fill_rect(Rect2i(0, 0, 350, 500), Color.RED)
    image.fill_rect(Rect2i(350, 500, 350, 500), Color.BLUE)
    var texture := ImageTexture.create_from_image(image)
    for index in 4: book.supply_page(index, texture)
    book.set_mode("book")
    book.set_open(1.0)
    compositor.sync()
    assert(book.left_leaf.layers != 0 and book.right_leaf.layers != 0, "Stationary manga pages stay visible in the scene renderer")
    assert(book.left_leaf.material_override.get_shader_parameter("front_image") == texture)
    assert(book.right_leaf.material_override.get_shader_parameter("front_image") == texture)
    var geometry = load("res://book_geometry.gd")
    for side in [-1, 1]:
        var stack: ArrayMesh = geometry.stack(side, book.PAGE_WIDTH, book.PAGE_HEIGHT, 0.008)
        var vertices: PackedVector3Array = stack.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        for vertex in vertices:
            assert(vertex.z < 0.0, "Paper stack stays behind the printed page surface")
    assert(book.begin_turn(1))
    compositor.sync()
    assert(book.left_leaf.layers != 0 and book.right_leaf.layers != 0, "Animated pages keep using the scene renderer")
    book.turn_direction = 0
    book.set_mode("scroll")
    compositor.sync()
    assert(book.scroll_screen.layers != 0, "Long pages stay visible in the scene renderer")
    book.hide()
    compositor.sync()
    reader.queue_free()
    await process_frame
    print("PASS: long palm titles and visible scene-rendered manga pages in book and scroll modes")
    quit()
