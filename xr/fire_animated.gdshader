shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
float noise(vec2 p) {
    vec2 cell = floor(p), f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
    float a = fract(sin(dot(cell, vec2(127.1,311.7))) * 43758.5453);
    float b = fract(sin(dot(cell + vec2(1,0), vec2(127.1,311.7))) * 43758.5453);
    float c = fract(sin(dot(cell + vec2(0,1), vec2(127.1,311.7))) * 43758.5453);
    float d = fract(sin(dot(cell + vec2(1,1), vec2(127.1,311.7))) * 43758.5453);
    return mix(mix(a,b,f.x), mix(c,d,f.x), f.y);
}
void vertex() {
    // Preserve model scale; per-eye view basis makes this stereo camera-facing.
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment() {
    vec2 uv = floor(UV * 48.0) / 48.0;
    float t = floor(TIME * 18.0) / 18.0;
    float height = 1.0 - uv.y;
    float wobble = sin(t * 5.0 + height * 8.0) * 0.07 * height;
    wobble += (noise(vec2(height * 5.0, t * 2.0)) - 0.5) * 0.16 * height;
    float width = mix(0.24, 0.025, height);
    float core = 1.0 - smoothstep(width * 0.35, width, abs(uv.x - 0.5 + wobble));
    float vertical = smoothstep(0.0, 0.12, uv.y) * smoothstep(0.0, 0.12, height);
    float halo = exp(-length((UV - vec2(0.5,0.58)) * vec2(6.0,3.0)) * 2.0) * 0.12;
    ALBEDO = vec3(1.0);
    // White-hot core with a restrained halo: bloom-safe on Quest while still
    // reading as animated bulb flame in both eyes.
    EMISSION = vec3(1.8);
    ALPHA = clamp(core * vertical * (0.65 + 0.2 * noise(vec2(height * 7.0,t))) + halo, 0.0, 0.92);
}
