shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D scene : hint_screen_texture, filter_linear_mipmap;
uniform vec2 panel_size = vec2(1.2, 0.82);
void fragment() {
    vec2 p = abs(UV - 0.5) * panel_size;
    float radius = min(0.035, min(panel_size.x, panel_size.y) * 0.5);
    vec2 q = p - panel_size * 0.5 + vec2(radius);
    float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    if (edge > 0.0) discard;
    vec3 blur = vec3(0.0);
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            blur += textureLod(scene, SCREEN_UV + vec2(float(x), float(y)) * 0.005, 3.0).rgb / 25.0;
        }
    }
    ALBEDO = mix(blur, vec3(0.38, 0.37, 0.35), 0.55);
    ALBEDO += vec3(0.12) * (1.0 - smoothstep(-0.003, -0.001, edge));
    ALPHA = 0.94;
}
