shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 fire_color : source_color = vec4(1.0, 0.28, 0.04, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.28, 1.0);

void vertex() {
    float wave = sin(TIME * 5.0 + VERTEX.y * 9.0 + VERTEX.x * 4.0) * 0.035;
    VERTEX.x += wave * (1.0 - UV.y);
    VERTEX.z += cos(TIME * 4.0 + VERTEX.y * 7.0) * 0.025 * (1.0 - UV.y);
}

void fragment() {
    float flicker = 0.72 + 0.28 * sin(TIME * 8.0 + UV.y * 11.0);
    vec3 color = mix(glow_color.rgb, fire_color.rgb, clamp(UV.y * 1.4, 0.0, 1.0));
    ALBEDO = color * flicker;
    EMISSION = color * 1.8;
    ALPHA = clamp(0.95 - UV.y * 0.30, 0.0, 1.0);
}
