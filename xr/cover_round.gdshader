shader_type canvas_item;

void fragment() {
    vec2 q = abs(UV - 0.5) - vec2(0.45, 0.465);
    float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.035;
    COLOR = texture(TEXTURE, UV) * COLOR;
    COLOR.a *= 1.0 - smoothstep(-0.002, 0.002, distance);
}
