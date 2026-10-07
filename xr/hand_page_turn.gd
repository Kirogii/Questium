extends RefCounted

# Work in book coordinates so a tilted or resized book has the same gesture.
# The palm sits inward from the fingertips at the white bar. Capture its
# outer-page region instead of requiring the palm itself to touch the bar.
const EDGE := SpatialBook.PAGE_WIDTH * 0.60
const INTENT_TRAVEL := 0.018
const MAX_SAMPLE_JUMP := 0.34
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
    return absf(point.x) <= SpatialBook.PAGE_WIDTH + 0.17 and absf(point.y) <= SpatialBook.PAGE_HEIGHT * 0.5 + 0.10 and point.z >= -0.065 and point.z <= 0.27

func fast_stroke(state: Dictionary, point: Vector3) -> bool:
    var inward: float = (state.start.x - point.x) * state.side
    return state.age <= 0.35 and inward >= 0.07 and inward / maxf(state.age, 0.02) >= 0.55 and absf(point.y - state.start.y) < inward * 1.1

func finish(hand: String) -> void:
    owned_book.release_turn()
    samples[hand] = {"blocked": true, "book": owned_book, "side": int(samples[hand].side)}
    owner = ""
    owned_book = null

func update(hand: String, world_tip: Vector3, valid_hand: bool, pinched: bool, delta: float) -> bool:
    var target: SpatialBook = reader.book
    if not valid_hand or delta > 0.20:
        # Quest can briefly lose fingers behind the chopping palm. Preserve a
        # captured leaf through a few missing frames, without moving it.
        if owner == hand and delta <= 0.20:
            var lost: Dictionary = samples.get(hand, {})
            lost["missing"] = float(lost.get("missing", 0.0)) + delta
            if lost.missing <= 0.12: return true
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
            samples[hand] = {"book": target, "start": point, "last": point, "side": int(state.side), "age": 0.0, "peak": 0.0, "bar_start": true}
        return false
    if owner == hand:
        if point.distance_to(state.last) > MAX_SAMPLE_JUMP:
            cancel()
            return false
        state.age += maxf(delta, 0)
        state.missing = 0.0
        state.last = point
        var progress := clampf((state.start.x - point.x) * state.side / (2.0 * absf(state.start.x)), 0, 1)
        target.set_turn_progress(progress)
        target.turning_material.set_shader_parameter("grab_y", clampf(point.y / SpatialBook.PAGE_HEIGHT + 0.5, 0, 1))
        state.peak = maxf(state.peak, progress)
        if state.get("bar_start", false) and (point.x * state.side <= 0.035 or fast_stroke(state, point)):
            target.set_turn_progress(maxf(0.51, progress))
            finish(hand)
            return true
        if not in_volume(point) or progress >= 0.90 or state.age > 3.0 or (progress < 0.02 and state.peak > 0.16):
            finish(hand)
        return true
    if target.turn_direction != 0 or not in_volume(point):
        samples.erase(hand)
        return false
    if state.is_empty():
        if absf(point.x) < EDGE: return false
        samples[hand] = {"book": target, "start": point, "last": point, "side": 1 if point.x > 0 else -1, "age": 0.0, "peak": 0.0, "bar_start": true}
        return false
    if point.distance_to(state.last) > MAX_SAMPLE_JUMP:
        samples.erase(hand)
        return false
    state.last = point
    state.age += maxf(delta, 0)
    var inward: float = (state.start.x - point.x) * state.side
    if inward < INTENT_TRAVEL:
        if absf(point.x) >= EDGE and inward < 0.003:
            state.start = point
            state.age = 0.0
        return false
    if absf(point.y - state.start.y) > maxf(0.05, inward * 1.4):
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
    target.turning_material.set_shader_parameter("grab_y", clampf(point.y / SpatialBook.PAGE_HEIGHT + 0.5, 0, 1))
    if state.get("bar_start", false) and (point.x * state.side <= 0.035 or fast_stroke(state, point)):
        target.set_turn_progress(0.51)
        finish(hand)
    return true

func scroll_bar(hand: String, world_tip: Vector3, pinched: bool, delta: float = 0.02) -> bool:
    var target: SpatialBook = reader.book
    var point := target.to_local(world_tip)
    if pinched or not target.visible or target.preview_only or not reader.holder.is_empty() or absf(point.y) > 0.56 or point.z < -0.065 or point.z > 0.27 or absf(point.x) > 0.50:
        samples.erase(hand)
        return false
    var state: Dictionary = samples.get(hand, {})
    if state.get("blocked", false):
        if point.x * float(state.get("side", 1)) >= 0.32:
            samples.erase(hand)
        return false
    if state.is_empty() or state.get("book") != target:
        if absf(point.x) < 0.32: return false
        samples[hand] = {"book": target, "start": point, "side": signf(point.x), "age": 0.0}
        return false
    state.age = float(state.get("age", 0.0)) + delta
    var inward: float = (state.start.x - point.x) * state.side
    if inward < 0.003:
        state.start = point
        state.age = 0.0
    if (point.x * state.side < 0.06 or fast_stroke(state, point)) and inward > 0.065 and inward < 0.8 and absf(point.y - state.start.y) < inward * 1.1:
        reader._turn(int(state.side) * (-1 if target.rtl else 1))
        samples[hand] = {"blocked": true, "book": target, "side": int(state.side)}
        return true
    return false
