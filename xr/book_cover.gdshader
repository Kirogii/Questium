shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform sampler2D cover_image : source_color, filter_linear_mipmap;
void fragment() {
    vec2 q = abs(UV - 0.5) * vec2(0.28, 0.40) - vec2(0.138, 0.198);
    float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.002;
    if (edge > 0.0) discard;
    vec4 cover = texture(cover_image, UV);
    ALBEDO = cover.rgb;
    ALPHA = cover.a;
}
