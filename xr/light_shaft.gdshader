shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

// A small transparent cone is used instead of a full-screen volumetric pass.
// It gives fixtures a little haze while keeping HUD and popup depth untouched.
uniform vec4 tint : source_color = vec4(0.82, 0.42, 0.20, 1.0);
uniform float opacity : hint_range(0.0, 0.25) = 0.045;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.7;

void fragment() {
    float end_fade = smoothstep(0.0, 0.16, UV.y) * smoothstep(1.0, 0.78, UV.y);
    float soft_variation = 0.88 + 0.12 * sin(UV.x * 18.0 + UV.y * 4.0);
    ALBEDO = tint.rgb;
    EMISSION = tint.rgb * emission_strength;
    ALPHA = opacity * end_fade * soft_variation;
}
