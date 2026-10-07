extends SceneTree

func _initialize() -> void:
    check.call_deferred()

func check() -> void:
    var reader = load("res://reader.tscn").instantiate()
    root.add_child(reader)
    await process_frame
    reader.set_process(false)
    reader.library_panel.visible = false
    reader.tracked = {"left": {"pressed": false}, "right": {"pressed": false}}
    var book: SpatialBook = reader.book
    book.visible = true
    book.set_preview(false)
    book.global_transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(0, 1, -1))
    book.set_open(0)
    var contact := Vector3(0.13, 0.02, 0.03)
    var tip := book.to_global(contact)
    reader._pointer("right", tip, Vector3.FORWARD, true, true)
    assert(reader.moving and not book.cover_dragged, "Middle of closed cover carries the book, as at 26.6 s")
    var wrist := Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, 0.4)
    tip += Vector3(0.1, 0.15, 0)
    reader._pointer("right", tip, Vector3.FORWARD, true, true, wrist)
    assert(book.to_global(contact).distance_to(tip) < 0.0001, "Grabbed point stays attached during wrist rotation")
    var held := book.global_transform
    reader._pointer("left", tip + Vector3(1, 0, 0), Vector3.FORWARD, true, true)
    assert(reader.scale_hands.size() == 1 and book.global_transform.is_equal_approx(held), "Unrelated distant pinch must not resize the book")
    reader._pointer("left", tip, Vector3.FORWARD, false, true)
    reader._pointer("right", tip, Vector3.FORWARD, false, true, wrist)
    assert(book.global_transform.is_equal_approx(held), "Released book stays where placed")

    # The same hinged bar moves from the closed right edge to the open left edge.
    var bar := book.edge_bars[0]
    tip = book.to_global(bar.position)
    reader._pointer("right", tip, Vector3.FORWARD, true, true)
    assert(book.cover_dragged and not reader.moving)
    reader._pointer("right", book.to_global(Vector3(-0.30, 0, 0.065)), Vector3.FORWARD, true, true)
    reader._pointer("right", book.to_global(bar.position), Vector3.FORWARD, false, true)
    await create_timer(0.35).timeout
    assert(is_equal_approx(book.openness, 1.0), "Right bar opens the front cover")
    assert(book.global_transform.is_equal_approx(held), "Cover opening must not move the body")
    assert(bar.position.x < 0 and bar.position.z > 0)
    reader._pointer("left", book.to_global(bar.position), Vector3.FORWARD, true, true)
    assert(book.cover_dragged and not reader.moving, "Left bar closes the open cover, as at 37.3 s")
    reader._pointer("left", book.to_global(Vector3(0.305, 0, 0)), Vector3.FORWARD, true, true)
    reader._pointer("left", book.to_global(bar.position), Vector3.FORWARD, false, true)
    await create_timer(0.35).timeout
    assert(is_zero_approx(book.openness))
    book.set_open(0.5)
    assert(reader._reader_at(book.to_global(bar.position)) == book, "Half-open moving handle remains reachable above the spine")
    book.hover_edges([bar.position, Vector3(3, 3, 3)])
    assert(bar.material_override.albedo_color != Color.WHITE, "Other hand cannot erase edge hover")
    book.set_open(0)

    # Two hands must both contact the same book. Releasing either preserves pose.
    tip = book.to_global(contact)
    reader._pointer("right", tip, Vector3.FORWARD, true, true, wrist)
    var second := book.to_global(Vector3(0.22, -0.06, 0.03))
    reader._pointer("left", second, Vector3.FORWARD, true, true)
    assert(reader.scale_hands.size() == 2)
    second = tip + Basis(Vector3.FORWARD, 0.3) * ((second - tip) * 1.4)
    reader._pointer("left", second, Vector3.FORWARD, true, true)
    held = book.global_transform
    reader._pointer("right", tip, Vector3.FORWARD, false, true, wrist)
    assert(reader.holder == "left", "Remaining hand keeps carrying after original hand releases")
    reader._pointer("left", second, Vector3.FORWARD, true, true)
    assert(book.global_transform.is_equal_approx(held), "Ownership transfer must preserve orientation and position")
    reader._pointer("left", second, Vector3.FORWARD, true, false)
    assert(reader.holder.is_empty(), "Tracking loss releases the remaining hand safely")
    assert(book.global_transform.is_equal_approx(held))
    reader.queue_free()
    print("PASS: reference cover hinges, rigid contact grab, distant pinch isolation, hand transfer and hover")
    quit()
