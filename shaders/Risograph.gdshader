shader_type canvas_item;

// --- Ink colors (physical ink pigments) ---
uniform vec3 ink_A = vec3(1.0, 0.2, 0.3);   // e.g. coral/red
uniform vec3 ink_B = vec3(0.3, 0.1, 0.8);   // e.g. purple/violet
uniform vec3 ink_C = vec3(1.0, 0.85, 0.1);  // e.g. yellow
uniform vec3 ink_D = vec3(0.1, 0.7, 0.6);   // e.g. teal (players)
uniform vec3 ink_E = vec3(0.9, 0.3, 0.6);   // e.g. pink (resources)

uniform vec3 background = vec3(0.93, 0.91, 0.88);

// --- Object group map ---
uniform sampler2D group_map;

// --- Group ID thresholds ---
// Detected by dominant channel in group_map sample
// Red-dominant   = ground normal
// Red dim        = ground dark
// Green-dominant = player
// Blue-dominant  = resource
// RG both high   = ornament
// GB both high   = UI

// --- Face ID thresholds ---
uniform float face_threshold = 0.6;

// --- Per-ink gradient control ---
// Each ink has density at top and bottom of screen
uniform float ink_A_density_top = 1.0;
uniform float ink_A_density_bot = 0.4;
uniform float ink_B_density_top = 0.6;
uniform float ink_B_density_bot = 1.0;
uniform float ink_C_density_top = 0.8;
uniform float ink_C_density_bot = 0.8;
uniform float ink_D_density_top = 1.0;
uniform float ink_D_density_bot = 1.0;
uniform float ink_E_density_top = 1.0;
uniform float ink_E_density_bot = 1.0;

// --- Stipple ---
uniform int   stipple_mode     = 1;
uniform float stipple_scale    = 40.0;
uniform float stipple_size     = 1.0;
uniform float stipple_softness = 0.05;
uniform float stipple_jitter   = 0.2;

// --- Misregistration ---
uniform vec2 offset_A_px = vec2( 2.0, -2.0);
uniform vec2 offset_B_px = vec2(-1.0,  0.0);
uniform vec2 offset_C_px = vec2( 1.0,  0.0);
uniform vec2 offset_D_px = vec2( 0.0,  1.0);
uniform vec2 offset_E_px = vec2(-2.0,  1.0);
uniform vec2 screen_size  = vec2(1920.0, 1080.0);

// --- Paper ---
uniform float paper_grain_amount = 0.04;
uniform float paper_grain_size   = 0.8;

float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle); float c = cos(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * uv;
}

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
    float radius = sqrt(clamp(density, 0.0, 1.0)) * 0.5;
    return 1.0 - smoothstep(radius - stipple_softness,
                             radius + stipple_softness, dist);
}

// Multiplicative overprint — physically correct ink on paper
vec3 overprint(vec3 base, vec3 ink, float coverage) {
    return mix(base, base * ink, coverage);
}

bool is_background(vec3 c) {
    return c.r > 0.9 && c.g > 0.9 && c.b > 0.9;
}

void fragment() {
    vec3 face_id  = texture(TEXTURE, UV).rgb;
    vec3 group_id = texture(group_map, UV).rgb;

    if (is_background(face_id)) {
        // Paper grain on background
        float g = noise(UV * paper_grain_size + vec2(7.3, 4.1));
        COLOR = vec4(background + vec3((g - 0.5) * paper_grain_amount), 1.0);
    }

    // --- Face contributions ---
    float face_top   = step(face_threshold, face_id.r) 
                     * (1.0 - step(face_threshold, face_id.g)) 
                     * (1.0 - step(face_threshold, face_id.b));
    float face_left  = step(face_threshold, face_id.g) 
                     * (1.0 - step(face_threshold, face_id.r)) 
                     * (1.0 - step(face_threshold, face_id.b));
    float face_right = step(face_threshold, face_id.b) 
                     * (1.0 - step(face_threshold, face_id.r)) 
                     * (1.0 - step(face_threshold, face_id.g));

    // --- Zone contributions ---
    bool is_ground      = group_id.r > 0.4 && group_id.g < 0.3 && group_id.b < 0.3;
    bool is_ground_dark = group_id.r > 0.2 && group_id.r < 0.4 
                        && group_id.g < 0.2 && group_id.b < 0.2;
    bool is_player      = group_id.g > 0.4 && group_id.r < 0.3;
    bool is_resource    = group_id.b > 0.4 && group_id.r < 0.3;
    bool is_ornament    = group_id.r > 0.4 && group_id.g > 0.4;
    bool is_ui          = group_id.g > 0.4 && group_id.b > 0.4;

    float zone_ground    = float(is_ground) * 1.0 
                         + float(is_ground_dark) * 0.65;
    float zone_player    = float(is_player);
    float zone_resource  = float(is_resource);
    float zone_ornament  = float(is_ornament);
    float zone_world     = 1.0 - zone_player - zone_resource; // everything non-character

    // --- Scene gradient (screen Y → world height proxy) ---
    float scene_t = UV.y; // 0=top, 1=bottom

    float density_A = mix(ink_A_density_top, ink_A_density_bot, scene_t);
    float density_B = mix(ink_B_density_top, ink_B_density_bot, scene_t);
    float density_C = mix(ink_C_density_top, ink_C_density_bot, scene_t);
    float density_D = mix(ink_D_density_top, ink_D_density_bot, scene_t);
    float density_E = mix(ink_E_density_top, ink_E_density_bot, scene_t);

    // --- Per-ink masks ---
    // Ink A: top faces, world objects, gradient
    float mask_A = face_top * zone_world * density_A;

    // Ink B: left faces, world objects, gradient
    float mask_B = face_left * zone_world * density_B;

    // Ink C: right faces + ground, gradient
    float mask_C = (face_right * zone_world + face_top * zone_ground) * density_C;

    // Ink D: all faces of players
    float mask_D = (face_top + face_left + face_right) * zone_player * density_D;

    // Ink E: all faces of resources
    float mask_E = (face_top + face_left + face_right) * zone_resource * density_E;

    // --- Halftone per ink (different rotation angles + misregistration) ---
    vec2 off_A = offset_A_px / screen_size;
    vec2 off_B = offset_B_px / screen_size;
    vec2 off_C = offset_C_px / screen_size;
    vec2 off_D = offset_D_px / screen_size;
    vec2 off_E = offset_E_px / screen_size;

    float hit_A = halftone(rotate_uv(UV + off_A, 0.000), mask_A);
    float hit_B = halftone(rotate_uv(UV + off_B, 0.261), mask_B);
    float hit_C = halftone(rotate_uv(UV + off_C, 0.523), mask_C);
    float hit_D = halftone(rotate_uv(UV + off_D, 0.785), mask_D);
    float hit_E = halftone(rotate_uv(UV + off_E, 1.047), mask_E);

    // --- Multiplicative overprinting ---
    vec3 result = background;
    result = overprint(result, ink_A, hit_A);
    result = overprint(result, ink_B, hit_B);
    result = overprint(result, ink_C, hit_C);
    result = overprint(result, ink_D, hit_D);
    result = overprint(result, ink_E, hit_E);

    // --- Paper grain (whole image) ---
    float g = noise(UV * paper_grain_size + vec2(7.3, 4.1));
    result += vec3((g - 0.5) * paper_grain_amount);

    COLOR = vec4(result, 1.0);
}