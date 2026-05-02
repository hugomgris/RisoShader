shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled;

uniform sampler2D SCREEN_TEXTURE  : hint_screen_texture,         filter_nearest;
uniform sampler2D NORMAL_TEXTURE  : hint_normal_roughness_texture, filter_nearest;
uniform sampler2D DEPTH_TEXTURE   : hint_depth_texture,           filter_nearest;

// ── Outline color ─────────────────────────────────────────────────────────────
uniform vec4 outline_color : source_color = vec4(0.12, 0.08, 0.10, 1.0);

// ── Outer edge (silhouette: geometry vs background) ───────────────────────────
uniform float outer_width  = 3.0;   // pixels
uniform float bg_threshold = 0.92;  // what counts as "white background"

// ── Inner edge (face normals via Sobel) ───────────────────────────────────────
uniform float inner_width     = 1.0;  // sampling offset multiplier
uniform float inner_threshold = 0.3;  // lower = more edges detected

// ── Opacity ───────────────────────────────────────────────────────────────────
uniform float outline_opacity = 1.0;

// ── Helpers ───────────────────────────────────────────────────────────────────
bool is_bg(vec3 c) {
    return c.r > bg_threshold && c.g > bg_threshold && c.b > bg_threshold;
}

vec3 get_normal(sampler2D nt, vec2 uv) {
    return normalize(texture(nt, uv).rgb * 2.0 - 1.0);
}

void vertex() {
    // Lock quad to screen — ignores camera entirely
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 px = 1.0 / VIEWPORT_SIZE;

    vec3 self_color = texture(SCREEN_TEXTURE, uv).rgb;
    bool self_is_bg = is_bg(self_color);

    // ── Pass 1: Silhouette ────────────────────────────────────────────────────
    bool is_outer_edge = false;
    if (!self_is_bg) {
        for (int y = -int(outer_width); y <= int(outer_width); y++) {
            for (int x = -int(outer_width); x <= int(outer_width); x++) {
                // Circular kernel so corners don't square off
                if (float(x*x + y*y) > outer_width * outer_width) { continue; }
                vec2 o = uv + vec2(float(x), float(y)) * px;
                if (o.x < 0.0 || o.x > 1.0 || o.y < 0.0 || o.y > 1.0) { continue; }
                if (is_bg(texture(SCREEN_TEXTURE, o).rgb)) {
                    is_outer_edge = true;
                }
            }
        }
    }

    // ── Pass 2: Inner edges via Sobel on normals ──────────────────────────────
    bool is_inner_edge = false;
    if (!self_is_bg && !is_outer_edge) {
        vec2 s = px * inner_width;

        vec3 c  = get_normal(NORMAL_TEXTURE, uv);
        vec3 n  = get_normal(NORMAL_TEXTURE, uv + vec2( 0.0, -s.y));
        vec3 sf = get_normal(NORMAL_TEXTURE, uv + vec2( 0.0,  s.y));
        vec3 e  = get_normal(NORMAL_TEXTURE, uv + vec2( s.x,  0.0));
        vec3 w  = get_normal(NORMAL_TEXTURE, uv + vec2(-s.x,  0.0));
        vec3 nw = get_normal(NORMAL_TEXTURE, uv + vec2(-s.x, -s.y));
        vec3 ne = get_normal(NORMAL_TEXTURE, uv + vec2( s.x, -s.y));
        vec3 sw = get_normal(NORMAL_TEXTURE, uv + vec2(-s.x,  s.y));
        vec3 se = get_normal(NORMAL_TEXTURE, uv + vec2( s.x,  s.y));

        float gx = length(ne-c) + 2.0*length(e-c) + length(se-c)
                 - length(nw-c) - 2.0*length(w-c) - length(sw-c);
        float gy = length(sw-c) + 2.0*length(sf-c) + length(se-c)
                 - length(nw-c) - 2.0*length(n-c)  - length(ne-c);

        float edge = sqrt(gx*gx + gy*gy);
        if (edge > inner_threshold) {
            is_inner_edge = true;
        }
    }

    // ── Output ────────────────────────────────────────────────────────────────
    if (is_outer_edge || is_inner_edge) {
        ALBEDO = outline_color.rgb;
        ALPHA  = outline_color.a * outline_opacity;
    } else {
        ALBEDO = vec3(0.0);
        ALPHA  = 0.0; // fully transparent
    }
}
