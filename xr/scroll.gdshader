shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D page_image : source_color, filter_linear_mipmap;
uniform float page_top = 0.0;
uniform float page_height = 1.0;
uniform sampler2D next_image : source_color, filter_linear_mipmap;
uniform float strip_start = 0.0;
uniform float strip_fraction = 1.0;
uniform float next_fraction = 1.0;
void fragment() {
    vec2 uv = vec2(UV.x, (UV.y - page_top) / page_height);
    if (uv.y < 0.0 || uv.y > 1.0) discard;
    float y = (uv.y - strip_start) / strip_fraction;
    ALBEDO = uv.y > 1.0 ? vec3(0.97) : (y <= 1.0 ? texture(page_image, vec2(uv.x, y)).rgb : texture(next_image, vec2(uv.x, (uv.y - strip_start - strip_fraction) / next_fraction)).rgb);
}
