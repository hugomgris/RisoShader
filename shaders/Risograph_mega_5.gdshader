shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

// ── Palette ─────────────────────────────────────────────────────────────────
uniform vec3 ink1 = vec3(.85,  0.15, 0.3);
uniform vec3 ink2 = vec3(0.1,  0.85, 0.0);
uniform vec3 ink3 = vec3(.55,  0.525, 0.65);
uniform vec3 ink4 = vec3(0.2,  0.8,  0.7);
uniform vec3 ink5 = vec3(0.9,  0.2,  0.6);
uniform vec3 ink6 = vec3(0.95, 0.75, 0.1);
uniform vec3 background = vec3(0.93, 0.91, 0.88);

// ── Per-ink opacity ───────────────────────────────────────────────────────────
uniform float ink1_opacity = 0.85;
uniform float ink2_opacity = 0.85;
uniform float ink3_opacity = 0.85;
uniform float ink4_opacity = 0.85;
uniform float ink5_opacity = 0.85;
uniform float ink6_opacity = 0.85;

// ── Stipple shared ───────────────────────────────────────────────────────────
uniform float stipple_scale    = 1200.0;
uniform float stipple_size     = 1.2;
uniform float stipple_softness = 1.15;
uniform float stipple_jitter   = 0.8;

// ── Density ──────────────────────────────────────────────────────────────────
uniform float density_dark          = 0.9;
uniform float density_light         = 0.6;
uniform float noise_density_scale   = 0.9;
uniform float noise_threshold       = 0.7;
uniform float noise_threshold_blend = 0.08;

// ── Halftone irregularity ────────────────────────────────────────────────────
uniform float dot_size_variation    = 0.5;
uniform float dot_opacity_variation = 0.75;
uniform float dot_shape_variation   = 0.9;

// ── Paper ────────────────────────────────────────────────────────────────────
uniform float paper_grain_amount = 0.03;
uniform float paper_grain_size   = 0.8;

// ── Misregistration ──────────────────────────────────────────────────────────
uniform vec2 offset_top_px   = vec2(0.0, 0.0);
uniform vec2 offset_left_px  = vec2(0.0, 0.0);
uniform vec2 offset_right_px = vec2(0.0, 0.0);
uniform vec2 screen_size     = vec2(1920.0, 1080.0);

// ── Animation ────────────────────────────────────────────────────────────────
uniform float anim_speed          = 8.0;
uniform float anim_strength       = 0.15;
uniform float anim_density_jitter = 0.08;

uniform float halftone_anim_strength  = 0.4;
uniform float halftone_size_anim      = 0.2;
uniform float halftone_opacity_anim   = 0.15;

// ── Global frame jitter ───────────────────────────────────────────────────────
// The "handcrafted cel" effect: every frame the whole plate shifts/breathes
// as if each print pass was laid down by hand.
uniform float global_frame_jitter   = 0.003;  // UV plate shift   (0.001–0.006)
uniform float frame_density_jitter  = 0.06;   // density pulse    (0.02–0.10)
uniform float frame_warp_strength   = 0.004;  // low-freq UV warp (0.0–0.008)
uniform float frame_ink_shimmer     = 0.04;   // per-ink color drift (0.0–0.08)

uniform bool transparent_background = false;

// ── Detection ────────────────────────────────────────────────────────────────
bool is_red(vec3 c)        { return c.r > c.g * 2.0 && c.r > c.b * 2.0 && c.r > 0.15; }
bool is_green(vec3 c)      { return c.g > c.r * 2.0 && c.g > c.b * 2.0 && c.g > 0.15; }
bool is_blue(vec3 c)       { return c.b > c.r * 2.0 && c.b > c.g * 2.0 && c.b > 0.15; }
bool is_cyan(vec3 c)       { return c.g > c.r * 2.0 && c.b > c.r * 2.0 && c.g > 0.15; }
bool is_magenta(vec3 c)    { return c.r > c.g * 2.0 && c.b > c.g * 2.0 && c.r > 0.15; }
bool is_yellow(vec3 c)     { return c.r > c.b * 2.0 && c.g > c.b * 2.0 && c.r > 0.15; }
bool is_background(vec3 c) { return c.r > 0.9 && c.g > 0.9 && c.b > 0.9; }

// ── Noise base ───────────────────────────────────────────────────────────────
float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

// ── Mode A: animated multi-octave noise ──────────────────────────────────────
float ink_noise(vec2 uv, float stepped_time) {
    vec2 anim_offset = vec2(
        noise(vec2(stepped_time * 13.7, 0.0)) - 0.5,
        noise(vec2(0.0, stepped_time * 9.4))  - 0.5
    ) * anim_strength;

    vec2 suv = uv * stipple_scale / stipple_size + anim_offset;
    float a  = noise(suv);
    float b  = noise(suv * 2.3  + vec2(5.1,  3.7));
    float c  = noise(suv * 5.7  + vec2(1.3,  8.2));
    float d  = noise(suv * 11.3 + vec2(3.7,  2.1));
    float e  = noise(suv * 23.1 + vec2(8.4,  6.3));
    return a * 0.40 + b * 0.25 + c * 0.18 + d * 0.10 + e * 0.07;
}

float noise_hit(vec2 uv, float density, float stepped_time) {
    float d       = clamp(density * noise_density_scale, 0.0, 1.0);
    float pattern = ink_noise(uv, stepped_time);
    float edge    = stipple_softness * 0.5;
    return smoothstep((1.0 - d) - edge, (1.0 - d) + edge, pattern);
}

// ── Mode B: animated irregular halftone dots ──────────────────────────────────
float halftone_hit(vec2 uv, float density, float stepped_time) {
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

// ── Combined ─────────────────────────────────────────────────────────────────
float get_hit(vec2 uv, float density, float stepped_time) {
    float h = halftone_hit(uv, density, stepped_time);
    float n = noise_hit(uv, density, stepped_time);
    float t = smoothstep(noise_threshold - noise_threshold_blend,
                         noise_threshold + noise_threshold_blend,
                         density);
    return mix(h, n, t);
}

vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle); float c = cos(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * uv;
}

vec3 apply_ink(vec3 base, vec3 ink_color, float hit, float ink_op) {
    return mix(base, ink_color, hit * ink_op);
}

// ── Fragment ─────────────────────────────────────────────────────────────────
void fragment() {
    // ── Compute stepped time once ─────────────────────────────────────────
    float stepped_time = floor(TIME * anim_speed) / anim_speed;

    // ── Global frame jitter: plate shift ─────────────────────────────────
    // Offsets the entire UV each frame — like the print plate shifting
    // slightly between passes. This is the #1 contributor to the cel feel.
    vec2 frame_shift = vec2(
        noise(vec2(stepped_time * 31.7, 1.1)) - 0.5,
        noise(vec2(2.3, stepped_time * 27.3)) - 0.5
    ) * global_frame_jitter;

    // ── Global frame warp: low-frequency UV distortion ────────────────────
    // A very subtle per-frame warp, as if the paper had slight registration
    // variation across its surface — not a uniform shift but a gentle lean.
    float warp_angle = (noise(vec2(stepped_time * 7.1, stepped_time * 5.3)) - 0.5)
                       * frame_warp_strength * 6.28318;
    float warp_scale = (noise(vec2(stepped_time * 3.7, stepped_time * 11.1)) - 0.5)
                       * frame_warp_strength;
    vec2 frame_warp = vec2(
        sin(UV.y * 3.14159 + warp_angle) * warp_scale,
        cos(UV.x * 3.14159 + warp_angle) * warp_scale
    );

    vec2 jittered_UV = UV + frame_shift + frame_warp;

    // ── Sample texture using jittered UV ──────────────────────────────────
    vec3 pixel_base = texture(TEXTURE, jittered_UV).rgb;

    vec2 off_top   = offset_top_px   / screen_size;
    vec2 off_left  = offset_left_px  / screen_size;
    vec2 off_right = offset_right_px / screen_size;

    vec3 pixel_top   = texture(TEXTURE, jittered_UV + off_top).rgb;
    vec3 pixel_left  = texture(TEXTURE, jittered_UV + off_left).rgb;
    vec3 pixel_right = texture(TEXTURE, jittered_UV + off_right).rgb;

    vec3 final_color;

    if (is_background(pixel_base)) {
        if (transparent_background) {
            COLOR = vec4(0.0);
            
        } else {
            float paper_noise = noise(jittered_UV * paper_grain_size + vec2(7.3, 4.1));
            COLOR = vec4(background + vec3((paper_noise - 0.5) * paper_grain_amount), 1.0);
           
        }
    }

    // ── Ink detection ─────────────────────────────────────────────────────
    bool has_1 = is_red(pixel_top)     || is_red(pixel_left)     || is_red(pixel_right);
    bool has_2 = is_green(pixel_top)   || is_green(pixel_left)   || is_green(pixel_right);
    bool has_3 = is_blue(pixel_top)    || is_blue(pixel_left)    || is_blue(pixel_right);
    bool has_4 = is_cyan(pixel_top)    || is_cyan(pixel_left)    || is_cyan(pixel_right);
    bool has_5 = is_magenta(pixel_top) || is_magenta(pixel_left) || is_magenta(pixel_right);
    bool has_6 = is_yellow(pixel_top)  || is_yellow(pixel_left)  || is_yellow(pixel_right);

    // ── Density ───────────────────────────────────────────────────────────
    float dominant     = max(pixel_base.r, max(pixel_base.g, pixel_base.b));
    float density_mult = mix(density_dark, density_light, dominant);

    float density_wobble = (noise(vec2(stepped_time * 5.1, stepped_time * 8.3)) - 0.5)
                           * 2.0 * anim_density_jitter;
    float noise_zone = smoothstep(noise_threshold - 0.2,
                                  noise_threshold + 0.2, density_mult);
    density_mult = clamp(density_mult + density_wobble * noise_zone, 0.0, 1.0);

    // ── Global frame density pulse ────────────────────────────────────────
    // As if ink coverage varied between print passes — some frames denser,
    // some lighter, like slightly different ink viscosity each cel.
    float frame_density_pulse = (noise(vec2(stepped_time * 19.1, stepped_time * 7.7)) - 0.5)
                                * 2.0 * frame_density_jitter;
    density_mult = clamp(density_mult + frame_density_pulse, 0.0, 1.0);

    // ── Per-frame ink shimmer ─────────────────────────────────────────────
    // Subtle per-ink color drift each frame, as if ink concentration or
    // paper absorption varied slightly — each ink drifts independently.
    float shimmer_base = noise(vec2(stepped_time * 43.1, 0.5)) - 0.5;
    float shimmer1 = (noise(vec2(stepped_time * 43.1, 1.0)) - 0.5) * 2.0 * frame_ink_shimmer;
    float shimmer2 = (noise(vec2(stepped_time * 37.3, 2.0)) - 0.5) * 2.0 * frame_ink_shimmer;
    float shimmer3 = (noise(vec2(stepped_time * 29.7, 3.0)) - 0.5) * 2.0 * frame_ink_shimmer;
    float shimmer4 = (noise(vec2(stepped_time * 53.9, 4.0)) - 0.5) * 2.0 * frame_ink_shimmer;
    float shimmer5 = (noise(vec2(stepped_time * 23.1, 5.0)) - 0.5) * 2.0 * frame_ink_shimmer;
    float shimmer6 = (noise(vec2(stepped_time * 61.3, 6.0)) - 0.5) * 2.0 * frame_ink_shimmer;

    // Drift across channels so each ink shifts in a unique direction
    vec3 ink1_frame = clamp(ink1 + vec3(shimmer1, -shimmer1 * 0.5,  shimmer1 * 0.3),  0.0, 1.0);
    vec3 ink2_frame = clamp(ink2 + vec3(-shimmer2 * 0.3, shimmer2, -shimmer2 * 0.5),  0.0, 1.0);
    vec3 ink3_frame = clamp(ink3 + vec3(shimmer3 * 0.5, -shimmer3 * 0.3, shimmer3),   0.0, 1.0);
    vec3 ink4_frame = clamp(ink4 + vec3(-shimmer4, shimmer4 * 0.5, shimmer4 * 0.7),   0.0, 1.0);
    vec3 ink5_frame = clamp(ink5 + vec3(shimmer5 * 0.7, shimmer5 * 0.3, -shimmer5),   0.0, 1.0);
    vec3 ink6_frame = clamp(ink6 + vec3(shimmer6, shimmer6 * 0.8, -shimmer6 * 0.4),   0.0, 1.0);

    // ── Halftone hits — use jittered_UV as the base ───────────────────────
    float hit1 = get_hit(rotate_uv(jittered_UV, 0.0),   density_mult, stepped_time);
    float hit2 = get_hit(rotate_uv(jittered_UV, 0.261), density_mult, stepped_time);
    float hit3 = get_hit(rotate_uv(jittered_UV, 0.523), density_mult, stepped_time);
    float hit4 = get_hit(rotate_uv(jittered_UV, 0.785), density_mult, stepped_time);
    float hit5 = get_hit(rotate_uv(jittered_UV, 1.047), density_mult, stepped_time);
    float hit6 = get_hit(rotate_uv(jittered_UV, 1.309), density_mult, stepped_time);

    // ── Sequential layering ───────────────────────────────────────────────
    final_color = background;
    if (has_4) { final_color = apply_ink(final_color, ink4_frame, hit4, ink4_opacity); }
    if (has_3) { final_color = apply_ink(final_color, ink3_frame, hit3, ink3_opacity); }
    if (has_6) { final_color = apply_ink(final_color, ink6_frame, hit6, ink6_opacity); }
    if (has_2) { final_color = apply_ink(final_color, ink2_frame, hit2, ink2_opacity); }
    if (has_5) { final_color = apply_ink(final_color, ink5_frame, hit5, ink5_opacity); }
    if (has_1) { final_color = apply_ink(final_color, ink1_frame, hit1, ink1_opacity); }

    // ── Paper grain ───────────────────────────────────────────────────────
    float paper_noise = noise(jittered_UV * paper_grain_size + vec2(7.3, 4.1));
    final_color += vec3((paper_noise - 0.5) * paper_grain_amount);
    COLOR = vec4(final_color, 1.0);
}
