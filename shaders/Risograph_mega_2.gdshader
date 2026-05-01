shader_type canvas_item;

// ── Palette ─────────────────────────────────────────────────────────────────
uniform vec3 ink1 = vec3(1.0,  0.15, 0.3);   // red
uniform vec3 ink2 = vec3(0.55, 0.1,  0.8);   // purple
uniform vec3 ink3 = vec3(1.0,  0.85, 0.1);   // yellow
uniform vec3 ink4 = vec3(0.2,  0.8,  0.7);   // cyan
uniform vec3 ink5 = vec3(0.9,  0.2,  0.6);   // magenta
uniform vec3 ink6 = vec3(0.95, 0.75, 0.1);   // gold
uniform vec3 background = vec3(0.93, 0.91, 0.88);

// ── Stipple shared ───────────────────────────────────────────────────────────
uniform float stipple_scale    = 800.0;
uniform float stipple_size     = 1.0;
uniform float stipple_softness = 0.08;
uniform float stipple_jitter   = 0.3;
uniform float ink_opacity      = 0.92;

// ── Density ──────────────────────────────────────────────────────────────────
uniform float density_dark  = 1.0;
uniform float density_light = 0.45;

// Noise-mode density scalar — pull back noise coverage independently
uniform float noise_density_scale = 0.9;

// Crossover: below → halftone, above → noise
uniform float noise_threshold       = 0.65;
uniform float noise_threshold_blend = 0.08; // lower = sharper handoff

// ── Halftone irregularity ────────────────────────────────────────────────────
uniform float dot_size_variation    = 0.35; // per-dot size randomness
uniform float dot_opacity_variation = 0.25; // per-dot opacity randomness
uniform float dot_shape_variation   = 0.2;  // per-dot ellipse squish

// ── Paper ────────────────────────────────────────────────────────────────────
uniform float paper_grain_amount = 0.03;
uniform float paper_grain_size   = 0.8;

// ── Misregistration ──────────────────────────────────────────────────────────
uniform vec2 offset_top_px   = vec2(3.0,  -3.0);
uniform vec2 offset_left_px  = vec2(-1.0,  0.0);
uniform vec2 offset_right_px = vec2( 1.0,  0.0);
uniform vec2 screen_size     = vec2(1920.0, 1080.0);

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

// ── Mode A: multi-octave noise — high density ─────────────────────────────────
float ink_noise(vec2 uv) {
    vec2 suv = uv * stipple_scale / stipple_size;
    float a  = noise(suv);
    float b  = noise(suv * 2.3  + vec2(5.1,  3.7));
    float c  = noise(suv * 5.7  + vec2(1.3,  8.2));
    float d  = noise(suv * 11.3 + vec2(3.7,  2.1));
    float e  = noise(suv * 23.1 + vec2(8.4,  6.3));
    return a * 0.40 + b * 0.25 + c * 0.18 + d * 0.10 + e * 0.07;
}

float noise_hit(vec2 uv, float density) {
    float d       = clamp(density * noise_density_scale, 0.0, 1.0);
    float pattern = ink_noise(uv);
    float edge    = stipple_softness * 0.5;
    return smoothstep((1.0 - d) - edge, (1.0 - d) + edge, pattern);
}

// ── Mode B: irregular jittered halftone dots — low density ───────────────────
float halftone_hit(vec2 uv, float density) {
    float cell   = stipple_scale / stipple_size;
    vec2 scaled  = uv * cell;
    vec2 cell_id = floor(scaled);
    vec2 cell_uv = fract(scaled) - 0.5;

    // Position jitter
    vec2 jitter = vec2(
        noise(cell_id) - 0.5,
        noise(cell_id + vec2(7.3, 4.1)) - 0.5
    ) * stipple_jitter;

    // Per-dot size variation
    float size_rand = noise(cell_id + vec2(13.7, 2.3));
    float size_mult = 1.0 + (size_rand - 0.5) * 2.0 * dot_size_variation;

    // Per-dot shape: random ellipse squish + rotation
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

    // Per-dot opacity variation
    float opacity_rand = noise(cell_id + vec2(29.1, 8.7));
    float opacity_mult = 1.0 + (opacity_rand - 0.5) * 2.0 * dot_opacity_variation;
    dot *= clamp(opacity_mult, 0.0, 1.0);

    return clamp(dot, 0.0, 1.0);
}

// ── Combined ─────────────────────────────────────────────────────────────────
float get_hit(vec2 uv, float density) {
    float h = halftone_hit(uv, density);
    float n = noise_hit(uv, density);
    float t = smoothstep(noise_threshold - noise_threshold_blend,
                         noise_threshold + noise_threshold_blend,
                         density);
    return mix(h, n, t);
}

vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle); float c = cos(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * uv;
}

vec3 apply_ink(vec3 base, vec3 ink_color, float hit) {
    return mix(base, ink_color, hit * ink_opacity);
}

// ── Fragment ─────────────────────────────────────────────────────────────────
void fragment() {
    vec3 pixel_base = texture(TEXTURE, UV).rgb;

    vec2 off_top   = offset_top_px   / screen_size;
    vec2 off_left  = offset_left_px  / screen_size;
    vec2 off_right = offset_right_px / screen_size;

    vec3 pixel_top   = texture(TEXTURE, UV + off_top).rgb;
    vec3 pixel_left  = texture(TEXTURE, UV + off_left).rgb;
    vec3 pixel_right = texture(TEXTURE, UV + off_right).rgb;

    vec3 final_color;

    if (is_background(pixel_base)) {
        final_color = background;
    } else {
        bool has_1 = is_red(pixel_top)     || is_red(pixel_left)     || is_red(pixel_right);
        bool has_2 = is_green(pixel_top)   || is_green(pixel_left)   || is_green(pixel_right);
        bool has_3 = is_blue(pixel_top)    || is_blue(pixel_left)    || is_blue(pixel_right);
        bool has_4 = is_cyan(pixel_top)    || is_cyan(pixel_left)    || is_cyan(pixel_right);
        bool has_5 = is_magenta(pixel_top) || is_magenta(pixel_left) || is_magenta(pixel_right);
        bool has_6 = is_yellow(pixel_top)  || is_yellow(pixel_left)  || is_yellow(pixel_right);

        float dominant     = max(pixel_base.r, max(pixel_base.g, pixel_base.b));
        float density_mult = mix(density_dark, density_light, dominant);

        float hit1 = get_hit(rotate_uv(UV, 0.0),   density_mult);
        float hit2 = get_hit(rotate_uv(UV, 0.261), density_mult);
        float hit3 = get_hit(rotate_uv(UV, 0.523), density_mult);
        float hit4 = get_hit(rotate_uv(UV, 0.785), density_mult);
        float hit5 = get_hit(rotate_uv(UV, 1.047), density_mult);
        float hit6 = get_hit(rotate_uv(UV, 1.309), density_mult);

        final_color = background;
        if (has_4) { final_color = apply_ink(final_color, ink4, hit4); }
        if (has_3) { final_color = apply_ink(final_color, ink3, hit3); }
        if (has_6) { final_color = apply_ink(final_color, ink6, hit6); }
        if (has_2) { final_color = apply_ink(final_color, ink2, hit2); }
        if (has_5) { final_color = apply_ink(final_color, ink5, hit5); }
        if (has_1) { final_color = apply_ink(final_color, ink1, hit1); }
    }

    float paper_noise = noise(UV * paper_grain_size + vec2(7.3, 4.1));
    final_color += vec3((paper_noise - 0.5) * paper_grain_amount);

    COLOR = vec4(final_color, 1.0);
}
