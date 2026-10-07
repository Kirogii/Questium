extends RefCounted

var reader: Node3D
var corners: Dictionary = {}
var swipes: Dictionary = {}
var initial_distance := 0.0
var initial_scale := Vector3.ONE
var initial_position := Vector3.ZERO
var initial_midpoint := Vector3.ZERO
var hud_corners: Dictionary = {}
var hud_distance := 0.0
var hud_scale := Vector3.ONE
var joy_owner := ""
var joy_samples: Dictionary = {}
var scroll_owner := ""

func finger_extended(tracker: XRHandTracker) -> bool:
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    for joint in [XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP]:
        if (tracker.get_hand_joint_flags(joint) & flags) == 0: return false
    var base := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL).origin
    var tip := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
    return base.distance_to(tip) > 0.055

func forward(tracker: XRHandTracker) -> Vector3:
    for joint in [XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL]:
        if (tracker.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED) == 0:
            return -reader.camera.global_basis.z.normalized()
    var wrist := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).origin
    var knuckle := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL).origin
    var vector := knuckle - wrist
    if vector.length() < 0.015:
        return -reader.camera.global_basis.z.normalized()
    return (reader.origin.global_basis * vector).normalized()

func thumb_up(tracker: XRHandTracker) -> bool:
    if not is_fist(tracker, joy_owner != ""): return false
    var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
    for joint in [XRHandTracker.HAND_JOINT_THUMB_TIP, XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL]:
        if (tracker.get_hand_joint_flags(joint) & flags) == 0: return false
    var thumb := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
    var base := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL).origin
    var axis: Vector3 = reader.origin.global_basis * (thumb - base)
    return axis.length() > 0.025 and axis.normalized().dot(Vector3.UP) > 0.72

func open_hand(tracker: XRHandTracker) -> bool:
    var open := 0
    for pair in [[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP], [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP], [XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP], [XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]]:
        if (tracker.get_hand_joint_flags(pair[0]) & XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED) == 0 or (tracker.get_hand_joint_flags(pair[1]) & XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED) == 0: continue
        if tracker.get_hand_joint_transform(pair[0]).origin.distance_to(tracker.get_hand_joint_transform(pair[1]).origin) > 0.045: open += 1
    return open >= 2

func edge_hand(tracker: XRHandTracker, holding: bool = false) -> bool:
    if not open_hand(tracker): return false
    var normal: Vector3 = reader.origin.global_basis * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).basis.y
    return absf(normal.normalized().dot(reader.book.global_basis.x.normalized())) > (0.15 if holding else 0.30)

func seeker_facing(tracker: XRHandTracker) -> bool:
    if (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM) & XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED) == 0 or not open_hand(tracker): return false
    var palm: Transform3D = reader.origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
    var toward_head: Vector3 = reader.camera.global_position - palm.origin
    return toward_head.length() > 0.12 and toward_head.length() < 0.85 and absf(palm.basis.y.normalized().dot(toward_head.normalized())) > 0.55

func joystick(hand: String, tracker: XRHandTracker, valid: bool, delta: float) -> bool:
    if not valid or not thumb_up(tracker) or not reader.holder.is_empty() or not reader.ui_owner.is_empty() or not reader.window_holder.is_empty():
        joy_samples.erase(hand)
        if joy_owner == hand: joy_owner = ""
        return false
    var palm: Vector3 = reader.origin.global_transform * tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
    if reader._reader_at(palm) != null or reader.workspace.handle_at(palm) != null:
        joy_samples.erase(hand)
        if joy_owner == hand: joy_owner = ""
        return false
    if not joy_owner.is_empty() and joy_owner != hand: return false
    var state: Dictionary = joy_samples.get(hand, {"age": 0.0, "last": palm, "axis": -reader.camera.global_basis.z.normalized()})
    state.age += delta
    joy_samples[hand] = state
    if state.age < 0.18:
        state.last = palm
        return true
    joy_owner = hand
    var travel: float = (palm - state.last).dot(state.axis)
    if absf(travel) > 0.003:
        reader.workspace.move_depth(travel * 1.5)
        state.last = palm
    return true

func resize_hud(hand: String, tip: Vector3, valid: bool, pinched: bool) -> bool:
    var hud: Dictionary = reader.workspace.hud
    if not valid or not pinched or not hud.node.visible:
        var consumed := hud_corners.has(hand)
        hud_corners.erase(hand)
        hud_distance = 0.0
        return consumed
    var point: Vector3 = hud.node.to_local(tip)
    if not hud_corners.has(hand):
        if absf(absf(point.x) - hud.size.x * 0.5) > 0.08 or absf(point.y - hud.size.y * 0.5) > 0.08 or absf(point.z) > 0.12 or not reader.ui_owner.is_empty(): return false
        hud_corners[hand] = {"side": signf(point.x), "tip": tip}
    hud_corners[hand].tip = tip
    if hud_corners.size() == 2:
        var values := hud_corners.values()
        if values[0].side == values[1].side: return true
        var distance: float = values[0].tip.distance_to(values[1].tip)
        if hud_distance == 0:
            hud_distance = distance
            hud_scale = hud.node.scale
        elif hud_distance > 0.05:
            reader.workspace.set_hud_scale(hud_scale.x * distance / hud_distance)
    return true

func _init(host: Node3D) -> void:
    reader = host

func is_fist(tracker: XRHandTracker, holding: bool = false) -> bool:
    var palm := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
    var curled := 0
    for joint in [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
        if (tracker.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED) == 0:
            return false
        if tracker.get_hand_joint_transform(joint).origin.distance_to(palm) < (0.078 if holding else 0.065):
            curled += 1
    return curled == 4

func cancel() -> void:
    corners.clear()
    swipes.clear()
    initial_distance = 0.0
    hud_corners.clear()
    hud_distance = 0.0
    joy_owner = ""
    joy_samples.clear()
    scroll_owner = ""

func corner_at(point: Vector3, closed: bool = false) -> int:
    if absf(point.y - SpatialBook.PAGE_HEIGHT * 0.5) > 0.045 or absf(point.z) > 0.065:
        return 0
    if closed:
        if absf(point.x) < 0.045: return -1
        if absf(point.x - SpatialBook.PAGE_WIDTH) < 0.045: return 1
        return 0
    if absf(absf(point.x) - SpatialBook.PAGE_WIDTH) < 0.045:
        return 1 if point.x > 0 else -1
    return 0

func resize(hand: String, tip: Vector3, valid: bool, pinched: bool) -> bool:
    var book: SpatialBook = reader.book
    if not valid or not pinched or not book.visible or book.scroll_mode or (book.openness > 0.05 and book.openness < 0.8):
        var consumed := corners.has(hand)
        corners.erase(hand)
        initial_distance = 0.0
        return consumed
    if not corners.has(hand):
        var side := corner_at(book.to_local(tip), book.openness < 0.05)
        if side == 0 or not reader.holder.is_empty() or not reader.ui_owner.is_empty(): return false
        corners[hand] = {"side": side, "tip": tip}
        book.cancel_turn()
    corners[hand].tip = tip
    if corners.size() == 2:
        var values := corners.values()
        if values[0].side == values[1].side: return true
        var distance: float = values[0].tip.distance_to(values[1].tip)
        var midpoint: Vector3 = (values[0].tip + values[1].tip) * 0.5
        if initial_distance == 0.0:
            initial_distance = distance
            initial_scale = book.scale
            initial_position = book.global_position
            initial_midpoint = midpoint
        elif initial_distance > 0.03:
            var ratio := clampf(distance / initial_distance, 0.45 / initial_scale.x, 1.6 / initial_scale.x)
            book.scale = initial_scale * ratio
            book.global_position = midpoint + (initial_position - initial_midpoint) * ratio
    return true

func swipe(hand: String, tip: Vector3, valid: bool, pinched: bool, delta: float) -> bool:
    var book: SpatialBook = reader.book
    if not valid or pinched or not book.visible or not book.scroll_mode or book.preview_only or not reader.holder.is_empty() or reader.tracked.get(hand, {}).get("fist", false) or not reader.tracked.get(hand, {}).get("finger_extended", true):
        swipes.erase(hand)
        if scroll_owner == hand: scroll_owner = ""
        return false
    if not scroll_owner.is_empty() and scroll_owner != hand: return false
    var point := book.to_local(tip)
    if absf(point.x) > 0.35 or absf(point.y) > 0.52 or point.z < -0.04 or point.z > (0.16 if scroll_owner == hand else 0.10):
        swipes.erase(hand)
        if scroll_owner == hand: scroll_owner = ""
        return false
    var previous: Dictionary = swipes.get(hand, {})
    swipes[hand] = {"point": point, "active": previous.get("active", false), "start": previous.get("start", point)}
    if previous.is_empty() or delta > 0.12 or point.distance_to(previous.point) > 0.12: return false
    var travel: float = point.y - previous.point.y
    var displacement: Vector3 = point - swipes[hand].start
    if (absf(displacement.y) > 0.002 and absf(displacement.y) > absf(displacement.x) * 0.75) or previous.get("active", false):
        swipes[hand].active = true
        scroll_owner = hand
        reader._scroll_reader(travel)
        return true
    return false
