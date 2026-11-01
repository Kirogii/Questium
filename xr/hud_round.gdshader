shader_type canvas_item;
render_mode blend_premul_alpha;
uniform vec2 panel_size = vec2(1520.0, 900.0);
uniform float radius = 40.0;

void fragment() {
    vec2 q = abs((UV - 0.5) * panel_size) - (panel_size * 0.5 - vec2(radius));
    float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    float mask = 1.0 - smoothstep(-1.0, 1.0, distance);
    COLOR = texture(TEXTURE, UV) * COLOR * mask;
}
