shader_type spatial;
render_mode unshaded, cull_disabled;

// A lightweight scene-grade pass for the fallback back wall. It intentionally
// avoids a full-screen post-process so the HUD and popup depth remain intact.
uniform vec4 tint : source_color = vec4(0.25, 0.17, 0.20, 1.0);
uniform float grain_strength : hint_range(0.0, 0.2) = 0.035;

void fragment() {
    float grain = fract(sin(dot(UV * 93.17, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    ALBEDO = max(vec3(0.0), tint.rgb + grain * grain_strength);
    ROUGHNESS = 1.0;
}
