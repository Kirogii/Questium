shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// The fallback room is deliberately underexposed; warm local lights provide
// the readable accents instead of brightening the whole scene.
uniform vec4 base_color : source_color = vec4(0.16, 0.09, 0.07, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;

void fragment() {
    ALBEDO = base_color.rgb;
    ROUGHNESS = 0.84;
    EMISSION = emission_color.rgb * emission_strength;
}
