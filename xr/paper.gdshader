shader_type spatial;
#include "res://reader_filter.gdshaderinc"
render_mode unshaded, cull_disabled;

uniform sampler2D front_image : source_color, filter_linear_mipmap;
uniform sampler2D back_image : source_color, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float side = 1.0;
uniform float width = 0.28;
uniform float curvature = 0.002;
uniform float rest_angle = 0.035;
uniform float grab_y = 0.5;

void vertex() {
    float u = UV.x;
    float angle = mix(rest_angle, 3.14159265 - rest_angle, progress);
    // A corner pull twists the free edge while the spine remains fixed.
    float twist = (UV.y - (1.0 - grab_y)) * sin(progress * 3.14159265) * 0.14;
    angle += twist * u;
    // Integrate a curved tangent along the sheet, preserving its arc length.
    // The page stays thin: its changing bend supplies the apparent volume.
    float bend = sin(progress * 3.14159265) * 0.95;
    float radius = u * width;
    float x = radius * cos(angle);
    float z = radius * sin(angle);
    if (bend > 0.001) {
        float root_angle = angle - bend * 0.5;
        x = width * (sin(root_angle + bend * u) - sin(root_angle)) / bend;
        z = width * (cos(root_angle) - cos(root_angle + bend * u)) / bend;
    }
    float resting_curve = sin(rest_angle) * curvature * sin(u * 3.14159265);
    VERTEX.x = side * (x - resting_curve);
    VERTEX.z = z + resting_curve;
}

void fragment() {
    // The reversed mesh's winding is inverted for a left-hand leaf.
    bool front = (side < 0.0) == FRONT_FACING;
    vec2 page_uv = vec2(side > 0.0 ? UV.x : 1.0 - UV.x, UV.y);
    vec2 image_size = front ? vec2(textureSize(front_image, 0)) : vec2(textureSize(back_image, 0));
    float image_aspect = image_size.x / max(image_size.y, 1.0);
    float page_aspect = width / 0.40;
    vec2 image_uv = front ? page_uv : vec2(1.0 - page_uv.x, page_uv.y);
    vec2 fit = vec2(max(page_aspect / image_aspect, 1.0), max(image_aspect / page_aspect, 1.0));
    image_uv = (image_uv - 0.5) * fit + 0.5;
    vec4 ink = front ? texture(front_image, image_uv) : texture(back_image, image_uv);
    float edge = step(0.012, page_uv.x) * step(page_uv.x, 0.988) * step(0.01, page_uv.y) * step(page_uv.y, 0.99);
    edge *= step(0.0, image_uv.x) * step(image_uv.x, 1.0) * step(0.0, image_uv.y) * step(image_uv.y, 1.0);
    ALBEDO = mix(vec3(0.97), ink.rgb, edge * ink.a);
    ALBEDO *= 1.0 - 0.12 * exp(-UV.x * 18.0);
    ALBEDO = reader_color(ALBEDO);
}
