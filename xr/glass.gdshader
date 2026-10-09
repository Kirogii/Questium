shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D scene : hint_screen_texture, filter_linear_mipmap;
uniform vec2 panel_size = vec2(1.2, 0.82);
uniform sampler2D room_texture : source_color, filter_linear, repeat_disable;
uniform bool has_room = false;
void fragment() {
    vec2 p = abs(UV - 0.5) * panel_size;
    float radius = min(0.035, min(panel_size.x, panel_size.y) * 0.5);
    vec2 q = p - panel_size * 0.5 + vec2(radius);
    float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    if (edge > 0.0) discard;
    vec3 blur = vec3(0.0);
    // Quest compositor passthrough is absent from SCREEN_TEXTURE. Camera frames
    // are already blurred on a worker, avoiding screen taps on the headset.
    if (has_room) {
        blur = texture(room_texture, SCREEN_UV).rgb;
    } else {
        float weight_sum = 0.0;
        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                float weight = exp(-float(x*x + y*y) * 0.3);
                blur += textureLod(scene, SCREEN_UV + vec2(float(x), float(y)) * 0.0025, 4.0).rgb * weight;
                weight_sum += weight;
            }
        }
        blur /= weight_sum;
    }
    ALBEDO = mix(blur, vec3(0.30, 0.31, 0.33), 0.32);
    float rim = smoothstep(-0.0025, 0.0, edge);
    ALBEDO += vec3(0.13) * rim + vec3(0.025) * (1.0 - UV.y);
    ALPHA = has_room ? 0.93 : 0.78;
}
