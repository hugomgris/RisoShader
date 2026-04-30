shader_type canvas_item;

// Ink colors - one per channel
uniform vec3 ink_red   = vec3(1.0, 0.15, 0.3);
uniform vec3 ink_green = vec3(0.2, 0.75, 0.3);
uniform vec3 ink_blue  = vec3(0.2, 0.4, 0.9);
// ink_alpha: reserved for future use

uniform vec3 background = vec3(0.93, 0.91, 0.88);

// Stipple
uniform int   stipple_mode     = 1;
uniform float stipple_scale    = 40.0;
uniform float stipple_size     = 1.0;
uniform float stipple_softness = 0.05;
uniform float stipple_jitter   = 0.2;
uniform float ink_opacity      = 0.92;

// Paper
uniform float paper_grain_amount = 0.03;
uniform float paper_grain_size   = 0.8;

// Misregistration (kept for future multi-ink use)
uniform vec2 offset_r_px = vec2(0.0, 0.0);
uniform vec2 offset_g_px = vec2(0.0, 0.0);
uniform vec2 offset_b_px = vec2(0.0, 0.0);
uniform vec2 screen_size  = vec2(1152.0, 648.0);

// Density curve: controls how channel value maps to stipple density.
// gamma < 1.0 = more coverage in shadows; gamma > 1.0 = coverage only in brights
uniform float density_gamma = 1.0;
// Threshold below which the channel is considered empty (no ink)
uniform float channel_threshold = 0.1;

float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle); float c = cos(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * uv;
}

// Halftone dot: density drives dot radius
float halftone(vec2 uv, float density) {
    float cell   = stipple_scale / stipple_size;
    vec2 scaled  = uv * cell;
    vec2 cell_id = floor(scaled);
    vec2 cell_uv = fract(scaled) - 0.5;
    vec2 jitter  = vec2(
        noise(cell_id) - 0.5,
        noise(cell_id + vec2(7.3, 4.1)) - 0.5
    ) * stipple_jitter;
    float dist   = length(cell_uv - jitter);
    float radius = sqrt(density) * 0.5;
    return 1.0 - smoothstep(radius - stipple_softness,
                             radius + stipple_softness, dist);
}

// Noise stipple: density shifts the threshold
float stipple_noise_hit(vec2 uv, float density) {
    vec2 suv = uv * stipple_scale / stipple_size;
    float a  = noise(suv);
    float b  = noise(suv * 2.3 + vec2(5.1, 3.7));
    float c  = noise(suv * 5.7 + vec2(1.3, 8.2));
    float pattern = a * 0.5 + b * 0.3 + c * 0.2;
    float edge = stipple_softness * 0.5;
    return smoothstep((1.0 - density) - edge,
                      (1.0 - density) + edge, pattern);
}

float get_hit(vec2 uv, float density) {
    if (stipple_mode == 0) return stipple_noise_hit(uv, density);
    else                   return halftone(uv, density);
}

// Composite one ink layer onto the accumulator using riso-style multiply-ish blend
vec3 blend_ink(vec3 base, vec3 ink_color, float hit) {
    return mix(base, ink_color, hit * ink_opacity);
}

void fragment() {
    vec4 pixel = texture(TEXTURE, UV);
    bool is_bg = (pixel.r > 0.95 && pixel.g > 0.95 && pixel.b > 0.95);

    vec2  paper_uv    = UV * paper_grain_size;
    float paper_noise = noise(paper_uv + vec2(7.3, 4.1));
    vec3  paper_color = background + vec3((paper_noise - 0.5) * paper_grain_amount);

    if (is_bg) {
        COLOR = vec4(paper_color, 1.0);
    } else {
        float ch_r = texture(TEXTURE, UV + offset_r_px / screen_size).r;
		float ch_g = texture(TEXTURE, UV + offset_g_px / screen_size).g;
		float ch_b = texture(TEXTURE, UV + offset_b_px / screen_size).b;

        float density_r = pow(ch_r, density_gamma);
        float density_g = pow(ch_g, density_gamma);
        float density_b = pow(ch_b, density_gamma);

        vec3 final_color = background;

        if (density_b > channel_threshold) {
            float hit = get_hit(rotate_uv(UV, 0.523), density_b);
            final_color = blend_ink(final_color, ink_blue, hit);
        }
        if (density_g > channel_threshold) {
            float hit = get_hit(rotate_uv(UV, 0.261), density_g);
            final_color = blend_ink(final_color, ink_green, hit);
        }
        if (density_r > channel_threshold) {
            float hit = get_hit(rotate_uv(UV, 0.0), density_r);
            final_color = blend_ink(final_color, ink_red, hit);
        }

        final_color += vec3((paper_noise - 0.5) * paper_grain_amount);
        COLOR = vec4(final_color, 1.0);
    }
}