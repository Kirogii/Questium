uniform vec4 reader_tint : source_color = vec4(0.0);
uniform float reader_hue = 0.0;
uniform bool reader_grayscale = false;
uniform bool reader_inverted = false;
uniform float reader_brightness = 1.0;
uniform float reader_contrast = 1.0;
uniform int reader_blend = 0;

vec3 reader_color(vec3 color) {
    vec3 axis = normalize(vec3(1.0));
    float angle = reader_hue * 0.0174532925;
    color = color * cos(angle) + cross(axis, color) * sin(angle) + axis * dot(axis, color) * (1.0 - cos(angle));
    if (reader_grayscale) color = vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
    if (reader_inverted) color = vec3(1.0) - color;
    vec3 tint = reader_tint.rgb;
    if (reader_blend == 1) tint *= color;
    else if (reader_blend == 2) tint = vec3(1.0) - (vec3(1.0) - color) * (vec3(1.0) - tint);
    else if (reader_blend == 3) tint = mix(2.0 * color * tint, vec3(1.0) - 2.0 * (vec3(1.0) - color) * (vec3(1.0) - tint), step(vec3(0.5), color));
    else if (reader_blend == 4) tint = max(color, tint);
    else if (reader_blend == 5) tint = min(color, tint);
    color = mix(color, tint, reader_tint.a);
    return clamp(((color - vec3(0.5)) * reader_contrast + vec3(0.5)) * reader_brightness, vec3(0.0), vec3(1.0));
}
