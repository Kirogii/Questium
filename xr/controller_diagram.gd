extends Control

var hand := "right"
var bindings: Dictionary = {}
var labels: Dictionary = {}

func _draw() -> void:
    var font := ThemeDB.fallback_font
    var white := Color(0.92, 0.93, 0.95)
    var dark := Color(0.2, 0.22, 0.25)
    # Ringless Touch Plus controller silhouette, with face, index trigger and grip.
    draw_style_box(_shell(), Rect2(118, 38, 95, 75))
    draw_style_box(_shell(), Rect2(139, 90, 53, 94))
    draw_circle(Vector2(143, 65), 15, dark)
    draw_circle(Vector2(180, 82), 9, dark)
    draw_circle(Vector2(193, 59), 9, dark)
    draw_circle(Vector2(164, 95), 5, dark)
    draw_string(font, Vector2(175, 87), "X" if hand == "left" else "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)
    draw_string(font, Vector2(188, 64), "Y" if hand == "left" else "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)
    draw_string(font, Vector2(130, 20), str(labels.get(hand, hand.capitalize())), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, white)
    var points := {"trigger_click": Vector2(207, 45), "grip_click": Vector2(190, 125), "ax_button": Vector2(180, 82), "by_button": Vector2(193, 59), "primary_click": Vector2(143, 65)}
    var index := 0
    for action in points:
        var start: Vector2 = points[action]
        var right := index < 3
        var end := Vector2(232 if right else 105, 40 + index * 30)
        draw_line(start, end, white, 1.2, true)
        draw_circle(start, 2, white)
        var text := str(labels.get(bindings.get(hand + ":" + action, ""), bindings.get(hand + ":" + action, "")))
        draw_string(font, Vector2(end.x + 3 if right else 2, end.y - 3), text, HORIZONTAL_ALIGNMENT_LEFT, 100, 13, white)
        index += 1
    if hand == "right":
        draw_string(font, Vector2(5, 193), str(labels.get("Meta button: system menu", "Meta button: system menu")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, white)
    else:
        draw_line(Vector2(164, 95), Vector2(90, 180), white, 1, true)
        draw_string(font, Vector2(3, 179), str(bindings.get("left:menu_button", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, white)

func _shell() -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = Color(0.83, 0.84, 0.86)
    box.set_corner_radius_all(26)
    return box
