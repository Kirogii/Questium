shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool has_texture = false;
// Keep the imported room readable while leaving indirect areas decisively dark.
// This is intentionally a material exposure rather than a post-process grade so
// HUD/compositor layers never pay for a fullscreen pass.
uniform float exposure = 0.70;
uniform float floor_fill = 0.012;
uniform float bulb_emission = 0.0;
uniform float surface_roughness = 0.72;
uniform float surface_specular = 0.35;
void fragment() {
    ALBEDO = base_color.rgb * (has_texture ? texture(albedo_texture, UV).rgb : vec3(1.0)) * exposure;
    // Roughness also controls the room probe reflection on glossy surfaces.
    ROUGHNESS = surface_roughness;
    SPECULAR = surface_specular;
    EMISSION = ALBEDO * floor_fill + vec3(bulb_emission);
}
void light() {
    float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
    // Let the real fixture pools dominate; the small ambient term prevents the
    // floor and chair silhouettes from collapsing to black between pools.
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * half_lambert * ATTENUATION / PI;
    vec3 half_vector = normalize(LIGHT + VIEW);
    float exponent = mix(160.0, 8.0, surface_roughness * surface_roughness);
    float highlight = pow(max(dot(NORMAL, half_vector), 0.0), exponent);
    float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(VIEW, half_vector), 0.0), 5.0);
    SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * highlight * fresnel * surface_specular * (exponent + 2.0) / (8.0 * PI);
}
