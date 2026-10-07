extends RefCounted

# Work in book coordinates so a tilted or resized book has the same gesture.
const EDGE := SpatialBook.PAGE_WIDTH * 0.75
const INTENT_TRAVEL := 0.045
const MAX_SAMPLE_JUMP := 0.15
var reader: Node3D
var samples: Dictionary = {}
var owner := ""
var owned_book: SpatialBook

func _init(host: Node3D) -> void:
    reader = host

func cancel() -> void:
    if not owner.is_empty() and is_instance_valid(owned_book):
        owned_book.cancel_turn()
    owner = ""
    owned_book = null
    samples.clear()

func in_volume(point: Vector3) -> bool:
    return absf(point.x) <= SpatialBook.PAGE_WIDTH + 0.13 and absf(point.y) <= SpatialBook.PAGE_HEIGHT * 0.5 + 0.025 and point.z >= -0.015 and point.z <= 0.22

func finish(hand: String) -> void:
    owned_book.release_turn()
    samples[hand] = {"blocked": true, "book": owned_book, "side": int(samples[hand].side)}
    owner = ""
    owned_book = null

func update(hand: String, world_tip: Vector3, valid_hand: bool, pinched: bool, delta: float) -> bool:
    var target: SpatialBook = reader.book
    if not valid_hand or delta > 0.12:
        if owner == hand: cancel()
        samples.erase(hand)
        return false
    # A resting or pinching second hand must not cancel the captured leaf.
    if not owner.is_empty() and owner != hand:
        samples.erase(hand)
        return false
    if target.scroll_mode:
        if not owner.is_empty(): cancel()
        return scroll_bar(hand, world_tip, pinched, delta)
    if not target.is_visible_in_tree() or target.preview_only or target.openness < 0.8 or pinched or not reader.holder.is_empty() or not reader.ui_owner.is_empty():
        cancel()
        return false
    if not owner.is_empty() and owned_book != target:
        cancel()
    var point := target.to_local(world_tip)
    var state: Dictionary = samples.get(hand, {})
    if state.get("book") != target:
        state = {}
        samples.erase(hand)
    # Ignore the return stroke, then re-arm at the original outer edge. This
    # permits successive turns without requiring an exaggerated hand lift.
    if state.get("blocked", false):
        if not in_volume(point):
            samples.erase(hand)
        elif state.has("side") and point.x * state.side >= EDGE and target.turn_direction == 0:
            samples[hand] = {"book": target, "start": point, "last": point, "side": int(state.side), "age": 0.0, "peak": 0.0, "bar_start": absf(point.x) >= SpatialBook.PAGE_WIDTH - 0.01}
        return false
    if owner == hand:
        if point.distance_to(state.last) > MAX_SAMPLE_JUMP:
            cancel()
            return false
        state.age += maxf(delta, 0)
        state.last = point
        var progress := clampf((state.start.x - point.x) * state.side / (2.0 * absf(state.start.x)), 0, 1)
        target.set_turn_progress(progress)
        target.turning_material.set_shader_parameter("grab_y", clampf(point.y / SpatialBook.PAGE_HEIGHT + 0.5, 0, 1))
        state.peak = maxf(state.peak, progress)
        var inward_travel: float = (state.start.x - point.x) * state.side
        var fast_inward: bool = state.age <= 0.30 and inward_travel >= 0.10 and inward_travel / maxf(state.age, 0.02) >= 0.65 and absf(point.y - state.start.y) < inward_travel * 0.75
        if state.get("bar_start", false) and (point.x * state.side <= 0.035 or fast_inward):
            target.set_turn_progress(maxf(0.51, progress))
            finish(hand)
            return true
        if not in_volume(point) or progress >= 0.90 or state.age > 1.5 or (progress < 0.02 and state.peak > 0.16):
            finish(hand)
        return true
    if target.turn_direction != 0 or not in_volume(point):
        samples.erase(hand)
        return false
    if state.is_empty():
        if absf(point.x) < EDGE: return false
        samples[hand] = {"book": target, "start": point, "last": point, "side": 1 if point.x > 0 else -1, "age": 0.0, "peak": 0.0, "bar_start": absf(point.x) >= SpatialBook.PAGE_WIDTH - 0.01}
        return false
    if point.distance_to(state.last) > MAX_SAMPLE_JUMP:
        samples.erase(hand)
        return false
    state.last = point
    state.age += maxf(delta, 0)
    if state.age > 1.2:
        samples.erase(hand)
        return false
    var inward: float = (state.start.x - point.x) * state.side
    if inward < INTENT_TRAVEL or state.age < 0.025:
        return false
    var direction: int = int(state.side) * (-1 if target.rtl else 1)
    if not target.begin_turn(int(state.side), state.start):
        samples[hand] = {"blocked": true, "book": target}
        reader._turn(direction)
        return false
    owner = hand
    owned_book = target
    reader.ui.haptic(hand)
    target.set_turn_progress(clampf(inward / (2.0 * absf(state.start.x)), 0, 1))
    if state.get("bar_start", false) and state.age <= 0.30 and inward >= 0.10 and inward / maxf(state.age, 0.02) >= 0.65 and absf(point.y - state.start.y) < inward * 0.75:
        target.set_turn_progress(0.51)
        finish(hand)
    return true

func scroll_bar(hand: String, world_tip: Vector3, pinched: bool, delta: float = 0.02) -> bool:
    var target: SpatialBook = reader.book
    var point := target.to_local(world_tip)
    if pinched or not target.visible or target.preview_only or not reader.holder.is_empty() or absf(point.y) > 0.52 or point.z < -0.015 or point.z > 0.18 or absf(point.x) > 0.47:
        samples.erase(hand)
        return false
    var state: Dictionary = samples.get(hand, {})
    if state.get("blocked", false): return false
    if state.is_empty() or state.get("book") != target:
        if absf(point.x) < 0.35: return false
        samples[hand] = {"book": target, "start": point, "side": signf(point.x), "age": 0.0}
        return false
    state.age = float(state.get("age", 0.0)) + delta
    var inward: float = (state.start.x - point.x) * state.side
    var fast: bool = state.age <= 0.30 and inward >= 0.10 and inward / maxf(state.age, 0.02) >= 0.65
    if (point.x * state.side < 0.06 or fast) and inward > 0.065 and inward < 0.8 and absf(point.y - state.start.y) < inward * 0.75:
        reader._turn(int(state.side) * (-1 if target.rtl else 1))
        samples[hand] = {"blocked": true, "book": target}
        return true
    return false
