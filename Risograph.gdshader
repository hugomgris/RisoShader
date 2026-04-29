shader_type canvas_item;

// Palette
uniform vec3 color_top   = vec3(1.0, 0.15, 0.3);
uniform vec3 color_left  = vec3(0.55, 0.1, 0.8);
uniform vec3 color_right = vec3(1.0, 0.85, 0.1);
uniform vec3 background  = vec3(0.93, 0.91, 0.88);

// Detection
uniform float red_threshold   = 0.7;
uniform float green_threshold = 0.3;
uniform float blue_threshold  = 0.3;

// Stipple — shared
uniform int   stipple_mode     = 1;    // 0 = noise, 1 = halftone
uniform float stipple_density  = 0.8;
uniform float stipple_scale    = 40.0;
uniform float stipple_size     = 1.0;
uniform float stipple_softness = 0.05;
uniform float stipple_jitter   = 0.2;  // halftone only
uniform float ink_opacity      = 0.92;

// Paper
uniform float paper_grain_amount = 0.03;
uniform float paper_grain_size   = 0.8;

// Misregistration
uniform vec2 offset_top_px   = vec2(3.0, -3.0);
uniform vec2 offset_left_px  = vec2(-1.0, 0.0);
uniform vec2 offset_right_px = vec2(1.0, 0.0);
uniform vec2 screen_size     = vec2(1152.0, 648.0);

// --- Helpers ---
bool is_red(vec3 c)        { return c.r > red_threshold   && c.g < green_threshold && c.b < blue_threshold; }
bool is_green(vec3 c)      { return c.g > red_threshold   && c.r < green_threshold && c.b < blue_threshold; }
bool is_blue(vec3 c)       { return c.b > red_threshold   && c.r < green_threshold && c.g < blue_threshold; }
bool is_background(vec3 c) { return c.r > 0.9 && c.g > 0.9 && c.b > 0.9; }

float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

// --- Noise pipeline ---
float stipple_noise(vec2 uv) {
    vec2 scaled_uv = uv * stipple_scale / stipple_size;
    float a = noise(scaled_uv);
    float b = noise(scaled_uv * 2.3 + vec2(5.1, 3.7));
    float c = noise(scaled_uv * 5.7 + vec2(1.3, 8.2));
    return a * 0.5 + b * 0.3 + c * 0.2;
}

float stipple_hit(float pattern) {
    if (stipple_density >= 1.0) return 1.0;
    if (stipple_density <= 0.0) return 0.0;
    float edge = stipple_softness * 0.5;
    return smoothstep((1.0 - stipple_density) - edge,
                      (1.0 - stipple_density) + edge,
                      pattern);
}

// --- Halftone pipeline ---
vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle); float c = cos(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * uv;
}

float halftone(vec2 uv) {
    float cell = stipple_scale / stipple_size;
    vec2 scaled   = uv * cell;
    vec2 cell_id  = floor(scaled);
    vec2 cell_uv  = fract(scaled) - 0.5;

    vec2 jitter_offset = vec2(
        noise(cell_id) - 0.5,
        noise(cell_id + vec2(7.3, 4.1)) - 0.5
    ) * stipple_jitter;

    float dist   = length(cell_uv - jitter_offset);
    float radius = sqrt(stipple_density) * 0.5;
    return 1.0 - smoothstep(radius - stipple_softness,
                             radius + stipple_softness, dist);
}

// --- Dispatch ---
float get_hit(vec2 uv) {
    if (stipple_mode == 0) {
        return stipple_hit(stipple_noise(uv));
    } else {
        return halftone(uv);
    }
}

void fragment() {
    vec3 pixel_base = texture(TEXTURE, UV).rgb;
    vec2 off_top    = offset_top_px   / screen_size;
    vec2 off_left   = offset_left_px  / screen_size;
    vec2 off_right  = offset_right_px / screen_size;

    vec3 pixel_top   = texture(TEXTURE, UV + off_top).rgb;
    vec3 pixel_left  = texture(TEXTURE, UV + off_left).rgb;
    vec3 pixel_right = texture(TEXTURE, UV + off_right).rgb;

    vec3 final_color;

    if (is_background(pixel_base)) {
        final_color = background;
    } else {
        bool has_top   = is_red(pixel_top);
        bool has_left  = is_green(pixel_left);
        bool has_right = is_blue(pixel_right);

        float hit1 = get_hit(rotate_uv(UV, 0.0));
        float hit2 = get_hit(rotate_uv(UV, 0.261));  // 15°
        float hit3 = get_hit(rotate_uv(UV, 0.523));  // 30°

        vec3  ink_accum    = vec3(0.0);
        float weight_total = 0.0;

        if (has_top)   { ink_accum += color_top   * hit1; weight_total += hit1; }
        if (has_left)  { ink_accum += color_left  * hit2; weight_total += hit2; }
        if (has_right) { ink_accum += color_right * hit3; weight_total += hit3; }

        if (weight_total < 0.01) {
            final_color = background;
        } else {
            vec3  ink_color = ink_accum / weight_total;
            float coverage  = clamp(weight_total * ink_opacity, 0.0, 1.0);
            final_color     = mix(background, ink_color, coverage);
        }
    }

    vec2  paper_uv    = UV * paper_grain_size;
    float paper_noise = noise(paper_uv + vec2(7.3, 4.1));
    final_color += vec3((paper_noise - 0.5) * paper_grain_amount);

    COLOR = vec4(final_color, 1.0);
}