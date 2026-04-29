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

// Stipple
uniform float stipple_size = 1.0; // 0.5=large blobs, 2.0=fine specks
uniform float stipple_density  = 0.8;  // 0=no ink, 1=full solid
uniform float stipple_scale    = 800.0; // higher=finer dots
uniform float stipple_softness = 0.05; // 0=hard binary, 0.2=soft blend
uniform float ink_opacity      = 0.92; // overprint transparency

// Paper
uniform float paper_grain_amount = 0.03;
uniform float paper_grain_size   = 0.8;

// Misregistration
uniform vec2 offset_top_px   = vec2(3.0, -3.0);   // pixels
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

float stipple_noise(vec2 uv, float size_factor) {
    // size_factor < 1.0 = large blobs, > 1.0 = fine specks
    float a = noise(uv);
    float b = noise(uv * (2.3 * size_factor) + vec2(5.1, 3.7));
    float c = noise(uv * (5.7 * size_factor) + vec2(1.3, 8.2));
    return a * 0.5 + b * 0.3 + c * 0.2;
}

// Stipple hit: density 0=no ink, 1=solid. softness 0=hard, 0.2=soft
float stipple_hit(float pattern, float d) {
    if (d >= 1.0) return 1.0;
    if (d <= 0.0) return 0.0;
    float edge = stipple_softness * 0.5;
    return smoothstep(
        (1.0 - d) - edge,
        (1.0 - d) + edge,
        pattern
    );
}

void fragment() {
    vec3 pixel_base  = texture(TEXTURE, UV).rgb;
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
        bool has_top   = is_red(pixel_top);
        bool has_left  = is_green(pixel_left);
        bool has_right = is_blue(pixel_right);

        // In fragment, replace the three pattern lines with:
		vec2 base_uv = UV * stipple_scale;
		float p1 = stipple_noise(base_uv, stipple_size);
		float p2 = stipple_noise(base_uv + vec2(37.4, 19.2), stipple_size);
		float p3 = stipple_noise(base_uv + vec2(73.1, 51.6), stipple_size);

        float d    = clamp(stipple_density, 0.0, 1.0);
        float hit1 = stipple_hit(p1, d);
        float hit2 = stipple_hit(p2, d);
        float hit3 = stipple_hit(p3, d);

        // Accumulate ink weights
        vec3 ink_accum    = vec3(0.0);
        float weight_total = 0.0;

        if (has_top)   { ink_accum += color_top   * hit1; weight_total += hit1; }
        if (has_left)  { ink_accum += color_left  * hit2; weight_total += hit2; }
        if (has_right) { ink_accum += color_right * hit3; weight_total += hit3; }

        if (weight_total < 0.01) {
            final_color = background;
        } else {
            vec3 ink_color = ink_accum / weight_total;
            float coverage = clamp(weight_total * ink_opacity, 0.0, 1.0);
            final_color = mix(background, ink_color, coverage);
        }
    }

    // Paper grain — entire image including background
    vec2 paper_uv = UV * paper_grain_size;
    float paper_noise = noise(paper_uv + vec2(7.3, 4.1));
    final_color += vec3((paper_noise - 0.5) * paper_grain_amount);

    COLOR = vec4(final_color, 1.0);
}