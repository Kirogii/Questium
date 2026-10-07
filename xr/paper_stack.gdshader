shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
    float lines = smoothstep(0.35, 0.65, fract(UV.y * 28.0));
    ALBEDO = mix(vec3(0.78, 0.76, 0.72), vec3(0.93, 0.92, 0.89), lines);
}
