shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec2 panel_size = vec2(1.2, 0.82);
uniform sampler2D room_texture : source_color, filter_linear, repeat_disable;
uniform bool has_room = false;
uniform vec3 theme_tint : source_color = vec3(0.30, 0.31, 0.33);
void fragment() {
    vec2 p = abs(UV - 0.5) * panel_size;
    float radius = min(0.035, min(panel_size.x, panel_size.y) * 0.5);
    vec2 q = p - panel_size * 0.5 + vec2(radius);
    float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    if (edge > 0.0) discard;
    vec3 blur = vec3(0.12, 0.13, 0.15);
    // Quest compositor passthrough is absent from SCREEN_TEXTURE. Camera frames
    // are already blurred on a worker, avoiding screen taps on the headset.
    if (has_room) {
        blur = texture(room_texture, SCREEN_UV).rgb;
    }
    ALBEDO = mix(blur, theme_tint, 0.32);
    float rim = smoothstep(-0.0025, 0.0, edge);
    ALBEDO += vec3(0.13) * rim + vec3(0.025) * (1.0 - UV.y);
    ALPHA = has_room ? 0.93 : 0.78;
}
