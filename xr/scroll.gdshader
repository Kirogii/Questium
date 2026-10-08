shader_type spatial;
#include "res://reader_filter.gdshaderinc"
render_mode unshaded, cull_disabled;
uniform sampler2D page_image : source_color, filter_linear_mipmap;
uniform float page_top = 0.0;
uniform float page_height = 1.0;
uniform sampler2D next_image : source_color, filter_linear_mipmap;
uniform float strip_start = 0.0;
uniform float strip_fraction = 1.0;
uniform float next_fraction = 1.0;
uniform float side_padding = 0.0;
uniform vec4 page_crop = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
    vec2 uv = vec2(UV.x, (UV.y - page_top) / page_height);
    uv.x = (uv.x - side_padding) / max(1.0 - 2.0 * side_padding, 0.2);
    if (uv.x < 0.0 || uv.x > 1.0) discard;
    if (uv.y < 0.0 || uv.y > 1.0) discard;
    uv = page_crop.xy + uv * page_crop.zw;
    float y = (uv.y - strip_start) / strip_fraction;
    ALBEDO = uv.y > 1.0 ? vec3(0.97) : (y <= 1.0 ? texture(page_image, vec2(uv.x, y)).rgb : texture(next_image, vec2(uv.x, (uv.y - strip_start - strip_fraction) / next_fraction)).rgb);
    ALBEDO = reader_color(ALBEDO);
}
