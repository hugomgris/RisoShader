shader_type canvas_item;

// Palette - RGB group
uniform vec3 ink1 = vec3(1.0, 0.15, 0.3);   // red faces
uniform vec3 ink2 = vec3(0.55, 0.1, 0.8);   // green faces
uniform vec3 ink3 = vec3(1.0, 0.85, 0.1);   // blue faces

// Palette - CMY group
uniform vec3 ink4 = vec3(0.2, 0.8, 0.7);    // cyan faces
uniform vec3 ink5 = vec3(0.9, 0.2, 0.6);    // magenta faces
uniform vec3 ink6 = vec3(0.95, 0.75, 0.1);  // yellow faces

uniform vec3 background = vec3(0.93, 0.91, 0.88);

// Detection
uniform float red_threshold   = 0.7;
uniform float green_threshold = 0.3;
uniform float blue_threshold  = 0.3;

// Stipple
uniform int   stipple_mode     = 1;
uniform float stipple_density  = 0.8;
uniform float stipple_scale    = 40.0;
uniform float stipple_size     = 1.0;
uniform float stipple_softness = 0.05;
uniform float stipple_jitter   = 0.2;
uniform float ink_opacity      = 0.92;

// Paper
uniform float paper_grain_amount = 0.03;
uniform float paper_grain_size   = 0.8;

uniform float density_dark  = 1.0;   // ink density for darkest variant
uniform float density_light = 0.55;  // ink density for brightest variant

// Misregistration
uniform vec2 offset_top_px   = vec2(3.0, -3.0);
uniform vec2 offset_left_px  = vec2(-1.0, 0.0);
uniform vec2 offset_right_px = vec2(1.0, 0.0);
uniform vec2 screen_size     = vec2(1152.0, 648.0);

// --- Detection helpers ---
bool is_red(vec3 c)     { return c.r > c.g * 2.0 && c.r > c.b * 2.0 && c.r > 0.15; }
bool is_green(vec3 c)   { return c.g > c.r * 2.0 && c.g > c.b * 2.0 && c.g > 0.15; }
bool is_blue(vec3 c)    { return c.b > c.r * 2.0 && c.b > c.g * 2.0 && c.b > 0.15; }
bool is_cyan(vec3 c)    { return c.g > c.r * 2.0 && c.b > c.r * 2.0 && c.g > 0.15; }
bool is_magenta(vec3 c) { return c.r > c.g * 2.0 && c.b > c.g * 2.0 && c.r > 0.15; }
bool is_yellow(vec3 c)  { return c.r > c.b * 2.0 && c.g > c.b * 2.0 && c.r > 0.15; }
bool is_background(vec3 c) { return c.r > 0.9 && c.g > 0.9 && c.b > 0.9; }

float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

float stipple_noise(vec2 uv) {
    vec2 suv = uv * stipple_scale / stipple_size;
    float a = noise(suv);
    float b = noise(suv * 2.3 + vec2(5.1, 3.7));
    float c = noise(suv * 5.7 + vec2(1.3, 8.2));
    return a * 0.5 + b * 0.3 + c * 0.2;
}

float stipple_hit_noise(float pattern) {
    if (stipple_density >= 1.0) return 1.0;
    if (stipple_density <= 0.0) return 0.0;
    float edge = stipple_softness * 0.5;
    return smoothstep((1.0 - stipple_density) - edge,
                      (1.0 - stipple_density) + edge,
                      pattern);
}

vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle); float c = cos(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * uv;
}

float halftone(vec2 uv) {
    float cell    = stipple_scale / stipple_size;
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

float get_hit(vec2 uv) {
    if (stipple_mode == 0) return stipple_hit_noise(stipple_noise(uv));
    else return halftone(uv);
}

float halftone_density(vec2 uv, float density) {
    float cell    = stipple_scale / stipple_size;
    vec2 scaled   = uv * cell;
    vec2 cell_id  = floor(scaled);
    vec2 cell_uv  = fract(scaled) - 0.5;
    vec2 jitter_offset = vec2(
        noise(cell_id) - 0.5,
        noise(cell_id + vec2(7.3, 4.1)) - 0.5
    ) * stipple_jitter;
    float dist   = length(cell_uv - jitter_offset);
    float radius = sqrt(stipple_density * density) * 0.5;  // <-- density scales radius
    return 1.0 - smoothstep(radius - stipple_softness,
                             radius + stipple_softness, dist);
}

float stipple_hit_noise_density(float pattern, float density) {
    float effective = stipple_density * density;
    if (effective >= 1.0) return 1.0;
    if (effective <= 0.0) return 0.0;
    float edge = stipple_softness * 0.5;
    return smoothstep((1.0 - effective) - edge,
                      (1.0 - effective) + edge, pattern);
}

float get_hit_density(vec2 uv, float density) {
    if (stipple_mode == 0) return stipple_hit_noise_density(stipple_noise(uv), density);
    else return halftone_density(uv, density);
}

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

        // Brightness of the source pixel drives stipple density
        // Full saturated color = 1.0, darkened variant = less coverage
		
		float dominant = max(pixel_base.r, max(pixel_base.g, pixel_base.b));
		float density_mult = mix(density_dark, density_light, dominant);

        float hit1 = get_hit_density(rotate_uv(UV, 0.0),   density_mult);
        float hit2 = get_hit_density(rotate_uv(UV, 0.261), density_mult);
        float hit3 = get_hit_density(rotate_uv(UV, 0.523), density_mult);
        float hit4 = get_hit_density(rotate_uv(UV, 0.785), density_mult);
        float hit5 = get_hit_density(rotate_uv(UV, 1.047), density_mult);
        float hit6 = get_hit_density(rotate_uv(UV, 1.309), density_mult);

        vec3  ink_accum    = vec3(0.0);
        float weight_total = 0.0;

        if (has_1) { ink_accum += ink1 * hit1; weight_total += hit1; }
        if (has_2) { ink_accum += ink2 * hit2; weight_total += hit2; }
        if (has_3) { ink_accum += ink3 * hit3; weight_total += hit3; }
        if (has_4) { ink_accum += ink4 * hit4; weight_total += hit4; }
        if (has_5) { ink_accum += ink5 * hit5; weight_total += hit5; }
        if (has_6) { ink_accum += ink6 * hit6; weight_total += hit6; }

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