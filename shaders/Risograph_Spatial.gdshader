shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;

// ── Ink color for THIS mesh ───────────────────────────────────────────────────
uniform vec3 ink_color : source_color = vec3(0.85, 0.15, 0.3);
uniform float ink_opacity : hint_range(0.0, 1.0) = 0.85;

// ── Background (should match your global paper color) ─────────────────────────
uniform vec3 background : source_color = vec3(0.93, 0.91, 0.88);

// ── Density control ───────────────────────────────────────────────────────────
uniform sampler2D density_texture : hint_default_white;
uniform float density_scale : hint_range(0.0, 1.0) = 1.0;
uniform float density_dark  : hint_range(0.0, 1.0) = 0.9;
uniform float density_light : hint_range(0.0, 1.0) = 0.6;

// ── Stipple ───────────────────────────────────────────────────────────────────
uniform float stipple_scale    = 1200.0;
uniform float stipple_size     = 1.2;
uniform float stipple_softness = 1.15;
uniform float stipple_jitter   = 0.8;

// ── Halftone irregularity ─────────────────────────────────────────────────────
uniform float dot_size_variation    = 0.5;
uniform float dot_opacity_variation = 0.75;
uniform float dot_shape_variation   = 0.9;

// ── Noise density ─────────────────────────────────────────────────────────────
uniform float noise_density_scale   = 0.9;
uniform float noise_threshold       = 0.7;
uniform float noise_threshold_blend = 0.08;

// ── Paper grain ───────────────────────────────────────────────────────────────
uniform float paper_grain_amount = 0.03;
uniform float paper_grain_size   = 0.8;

// ── Rotation offset ───────────────────────────────────────────────────────────
uniform float screen_angle = 0.0;

// ── Animation ─────────────────────────────────────────────────────────────────
uniform float anim_speed              = 8.0;
uniform float anim_strength           = 0.15;
uniform float anim_density_jitter     = 0.08;
uniform float halftone_anim_strength  = 0.4;
uniform float halftone_size_anim      = 0.2;
uniform float halftone_opacity_anim   = 0.15;

// ── Transparency ──────────────────────────────────────────────────────────────
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

// ── Misregistration ───────────────────────────────────────────────────────────
uniform vec2 uv_offset = vec2(0.0, 0.0);

// ── Screen UV source ──────────────────────────────────────────────────────────
uniform bool use_screen_uv = true;

// ── Edge / shape jitter ───────────────────────────────────────────────────────
// Displaces vertices along their normal in world space using animated noise.
// This makes silhouette edges wobble like imprecise screen-print registration.
uniform float edge_jitter_strength = 0.04;  // world-space units; start small (0.02–0.08)
uniform float edge_jitter_scale    = 3.5;   // spatial frequency of the wobble
uniform float edge_jitter_speed    = 4.0;   // how fast it steps (independent of anim_speed)
// Directional bias: 1.0 = pure normal push/pull, 0.0 = purely tangential slide
// Normal push creates thickness changes; tangential slide shifts edges sideways.
// A mix around 0.4–0.7 looks most like ink spread.
uniform float edge_jitter_normal_bias : hint_range(0.0, 1.0) = 0.5;

varying vec2 screen_uv_interp;

// ─────────────────────────────────────────────────────────────────────────────

float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

// 3D value noise — used for vertex displacement so each axis varies independently
float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep
    return mix(
        mix(
            mix(noise(i.xy + vec2(0.0, 0.0) + i.z * 17.0),
                noise(i.xy + vec2(1.0, 0.0) + i.z * 17.0), f.x),
            mix(noise(i.xy + vec2(0.0, 1.0) + i.z * 17.0),
                noise(i.xy + vec2(1.0, 1.0) + i.z * 17.0), f.x),
            f.y),
        mix(
            mix(noise(i.xy + vec2(0.0, 0.0) + (i.z + 1.0) * 17.0),
                noise(i.xy + vec2(1.0, 0.0) + (i.z + 1.0) * 17.0), f.x),
            mix(noise(i.xy + vec2(0.0, 1.0) + (i.z + 1.0) * 17.0),
                noise(i.xy + vec2(1.0, 1.0) + (i.z + 1.0) * 17.0), f.x),
            f.y),
        f.z);
}

float ink_noise(vec2 uv) {
    float stepped_time = floor(TIME * anim_speed) / anim_speed;
    vec2 anim_offset = vec2(
        noise(vec2(stepped_time * 13.7, 0.0)) - 0.5,
        noise(vec2(0.0, stepped_time * 9.4))  - 0.5
    ) * anim_strength;

    vec2 suv = uv * stipple_scale / stipple_size + anim_offset;
    float a = noise(suv);
    float b = noise(suv * 2.3  + vec2(5.1, 3.7));
    float c = noise(suv * 5.7  + vec2(1.3, 8.2));
    float d = noise(suv * 11.3 + vec2(3.7, 2.1));
    float e = noise(suv * 23.1 + vec2(8.4, 6.3));
    return a * 0.40 + b * 0.25 + c * 0.18 + d * 0.10 + e * 0.07;
}

float noise_hit(vec2 uv, float density) {
    float d       = clamp(density * noise_density_scale, 0.0, 1.0);
    float pattern = ink_noise(uv);
    float edge    = stipple_softness * 0.5;
    return smoothstep((1.0 - d) - edge, (1.0 - d) + edge, pattern);
}

float halftone_hit(vec2 uv, float density) {
    float stepped_time = floor(TIME * anim_speed) / anim_speed;

    float cell   = stipple_scale / stipple_size;
    vec2 scaled  = uv * cell;
    vec2 cell_id = floor(scaled);
    vec2 cell_uv = fract(scaled) - 0.5;

    vec2 static_jitter = vec2(
        noise(cell_id) - 0.5,
        noise(cell_id + vec2(7.3, 4.1)) - 0.5
    ) * stipple_jitter;

    float dot_anim_seed_x = noise(cell_id + vec2(stepped_time * 23.1, 4.4));
    float dot_anim_seed_y = noise(cell_id + vec2(7.7, stepped_time * 19.3));
    vec2 anim_jitter = vec2(dot_anim_seed_x - 0.5, dot_anim_seed_y - 0.5)
                       * halftone_anim_strength / cell;

    vec2 jitter = static_jitter + anim_jitter;

    float size_rand = noise(cell_id + vec2(13.7, 2.3));
    float size_mult = 1.0 + (size_rand - 0.5) * 2.0 * dot_size_variation;
    float size_anim_rand = noise(cell_id + vec2(stepped_time * 7.1, stepped_time * 3.3));
    size_mult += (size_anim_rand - 0.5) * 2.0 * halftone_size_anim;

    float shape_rand = noise(cell_id + vec2(3.1, 17.9));
    float squish     = 1.0 + (shape_rand - 0.5) * 2.0 * dot_shape_variation;
    float rot_angle  = shape_rand * 3.14159;
    float sr = sin(rot_angle); float cr = cos(rot_angle);
    vec2 rotated = mat2(vec2(cr, sr), vec2(-sr, cr)) * (cell_uv - jitter);
    rotated.x *= squish;
    float dist = length(rotated);

    float radius = sqrt(density) * 0.5 * size_mult;
    float dot    = 1.0 - smoothstep(radius - stipple_softness,
                                     radius + stipple_softness, dist);

    float opacity_rand = noise(cell_id + vec2(29.1, 8.7));
    float opacity_mult = 1.0 + (opacity_rand - 0.5) * 2.0 * dot_opacity_variation;
    float opacity_anim_rand = noise(cell_id + vec2(stepped_time * 11.3, stepped_time * 6.7));
    opacity_mult += (opacity_anim_rand - 0.5) * 2.0 * halftone_opacity_anim;

    dot *= clamp(opacity_mult, 0.0, 1.0);
    return clamp(dot, 0.0, 1.0);
}

float get_hit(vec2 uv, float density) {
    float h = halftone_hit(uv, density);
    float n = noise_hit(uv, density);
    float t = smoothstep(noise_threshold - noise_threshold_blend,
                         noise_threshold + noise_threshold_blend, density);
    return mix(h, n, t);
}

vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle); float c = cos(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * uv;
}

// ─────────────────────────────────────────────────────────────────────────────

void vertex() {
    // ── Edge jitter ───────────────────────────────────────────────────────────
    // Step time so jitter snaps between frames rather than flowing smoothly.
    // This mimics the frame-by-frame feel of hand-printed registration shift.
    float jitter_time = floor(TIME * edge_jitter_speed) / edge_jitter_speed;

    // Sample 3D noise at world position + time, with two octaves for character
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 noise_coord = world_pos * edge_jitter_scale + vec3(jitter_time * 7.3);
    float n1 = noise3(noise_coord)                    - 0.5;
    float n2 = noise3(noise_coord * 2.1 + vec3(5.4)) - 0.5;
    float jitter_val = (n1 * 0.65 + n2 * 0.35) * 2.0; // [-1, 1] range

    // Split displacement into normal and tangential components.
    // Normal: pushes the surface in/out (thickens or thins the mesh silhouette)
    // Tangential: slides vertices sideways along the surface (shifts edges laterally)
    vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

    // Build a tangent from the normal (Gram-Schmidt with a stable up vector)
    vec3 up = abs(world_normal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent   = normalize(cross(up, world_normal));
    vec3 bitangent = cross(world_normal, tangent);

    // Use different noise channels per tangent axis so X and Y slide independently
    float tang_n  = noise3(noise_coord + vec3(13.1)) - 0.5;
    float bitang_n = noise3(noise_coord + vec3(27.3)) - 0.5;

    vec3 normal_disp    = world_normal * jitter_val * edge_jitter_normal_bias;
    vec3 tangent_disp   = (tangent * tang_n + bitangent * bitang_n)
                          * (1.0 - edge_jitter_normal_bias);

    vec3 world_displaced = world_pos
        + (normal_disp + tangent_disp) * edge_jitter_strength;

    // Write back into clip space
    POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_displaced, 1.0);

    screen_uv_interp = (VIEW_MATRIX * vec4(world_displaced, 1.0)).xy;
}

void fragment() {
    vec2 base_uv = use_screen_uv ? SCREEN_UV : UV;
    vec2 suv = rotate_uv(base_uv + uv_offset, screen_angle);

    float tex_density = texture(density_texture, UV).r;
    float density_mult = mix(density_light, density_dark, tex_density * density_scale);

    density_mult *= alpha;

    float stepped_time   = floor(TIME * anim_speed) / anim_speed;
    float density_wobble = (noise(vec2(stepped_time * 5.1, stepped_time * 8.3)) - 0.5)
                           * 2.0 * anim_density_jitter;
    float noise_zone  = smoothstep(noise_threshold - 0.2, noise_threshold + 0.2, density_mult);
    density_mult = clamp(density_mult + density_wobble * noise_zone, 0.0, 1.0);

    float hit = get_hit(suv, density_mult);

    vec3 color = mix(background, ink_color, hit * ink_opacity);

    float grain = noise(UV * paper_grain_size + vec2(7.3, 4.1));
    color += vec3((grain - 0.5) * paper_grain_amount);
   ALBEDO = color;
    ALPHA  = 1.0;
}