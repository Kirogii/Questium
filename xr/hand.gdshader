shader_type spatial;
render_mode unshaded;

void fragment() {
    float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
    ALBEDO = mix(vec3(0.035, 0.025, 0.045), vec3(0.62, 0.20, 0.88), rim);
}
