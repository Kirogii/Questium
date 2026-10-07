shader_type spatial;
render_mode unshaded;
uniform float interaction : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
    vec3 outline = mix(vec3(0.94, 0.94, 0.96), vec3(0.70, 0.35, 1.0), interaction);
    ALBEDO = mix(vec3(0.035, 0.025, 0.045), outline, rim);
}
