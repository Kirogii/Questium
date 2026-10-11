shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, blend_add, depth_draw_never;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color = vec4(0.84,0.78,0.71,1.0);
uniform float opacity = 0.48;
uniform float height = 2.7;
uniform float top_radius = 0.12;
uniform float bottom_radius = 0.65;
varying vec3 local_vertex;
varying vec3 camera_local;
void vertex() {
    local_vertex = VERTEX;
    // MODELVIEW includes the current eye; INV_VIEW_MATRIX can use the head center.
    camera_local = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}
void fragment() {
    float camera_y = camera_local.y / height + 0.5;
    float camera_radius = mix(bottom_radius, top_radius, clamp(camera_y, 0.0, 1.0));
    bool inside = camera_y > 0.0 && camera_y < 1.0 && length(camera_local.xz) < camera_radius;
    if ((!inside && !FRONT_FACING) || (inside && FRONT_FACING)) discard;
    float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    // Inverse projection handles reverse-Z and the active stereo eye. GL uses
    // [-1,1] NDC depth; Vulkan Mobile/Forward+ use [0,1].
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        ndc.z = depth * 2.0 - 1.0;
    #endif
    vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc,1.0);
    float scene_distance = length(scene.xyz / scene.w);
    vec3 ray = normalize(local_vertex - camera_local);
    float surface_distance = length(VERTEX);
    // Integrate the visible cone thickness, clipped by the scene depth. A
    // bounding sphere restricts the samples to the beam even from far away.
    float radius = length(vec2(height * 0.5, bottom_radius));
    float b = dot(camera_local, ray);
    float h = max(b*b - dot(camera_local, camera_local) + radius*radius, 0.0);
    float ray_start = max(0.0, -b - sqrt(h));
    float ray_end = min(-b + sqrt(h), scene_distance * length(local_vertex - camera_local) / max(surface_distance, 0.001));
    float step_length = max(ray_end - ray_start, 0.0) / 24.0;
    float optical_depth = 0.0;
    for (int i = 0; i < 24; i++) {
        vec3 p = camera_local + ray * (ray_start + (float(i) + 0.5) * step_length);
        float y = p.y / height + 0.5;
        float cone_radius = mix(bottom_radius, top_radius, clamp(y, 0.0, 1.0));
        float radial = 1.0 - smoothstep(0.35, 1.0, length(p.xz) / max(cone_radius, 0.001));
        float axial = smoothstep(0.0, 0.1, y) * (1.0 - smoothstep(0.92, 1.0, y));
        // Stable angular streaks run away from the bulb, so this reads as
        // light rays through dust instead of a uniformly glowing solid cone.
        vec2 beam_uv = p.xz / max(cone_radius, 0.001);
        float streaks = 0.78 + 0.14 * sin(beam_uv.x * 9.0 + beam_uv.y * 7.0)
            + 0.08 * sin(beam_uv.x * 15.0 - beam_uv.y * 11.0);
        optical_depth += radial * axial * streaks * mix(0.45, 1.0, y) * step_length;
    }
    float facing_boost = 1.0 + pow(abs(dot(ray, vec3(0.0, 1.0, 0.0))), 4.0) * 0.5;
    float distance_fade = smoothstep(0.01, 0.4, surface_distance) * (1.0 - smoothstep(9.0, 18.0, surface_distance));
    ALBEDO = tint.rgb;
    ALPHA = clamp(opacity * optical_depth * facing_boost * distance_fade, 0.0, 0.55);
}
