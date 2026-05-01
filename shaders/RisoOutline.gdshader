shader_type spatial;
render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;
uniform vec4  outline_color : source_color = vec4(0.15, 0.1, 0.12, 1.0);
uniform float outline_width = 2.0;

// Threshold for "is this pixel the white background?"
// Matches your viewport clear color (white)
uniform float bg_threshold = 0.92;

void fragment() {
    vec4 self = texture(SCREEN_TEXTURE, SCREEN_UV);
    ALBEDO = self.rgb;
    ALPHA  = self.a;

    vec2 pixel_size = 1.0 / VIEWPORT_SIZE;

    bool on_edge = false;
    for (int y = -int(outline_width); y <= int(outline_width); y++) {
        for (int x = -int(outline_width); x <= int(outline_width); x++) {
            vec2 offset_uv = SCREEN_UV + vec2(float(x), float(y)) * pixel_size;
            // Stay within screen bounds
            if (offset_uv.x < 0.0 || offset_uv.x > 1.0 ||
                offset_uv.y < 0.0 || offset_uv.y > 1.0) { continue; }

            vec3 neighbor = texture(SCREEN_TEXTURE, offset_uv).rgb;
            // Neighbor is background if all channels are above threshold
            bool neighbor_is_bg = neighbor.r > bg_threshold
                                && neighbor.g > bg_threshold
                                && neighbor.b > bg_threshold;
            if (neighbor_is_bg) {
                on_edge = true;
            }
        }
    }

    if (on_edge) {
        ALBEDO = outline_color.rgb;
        ALPHA  = outline_color.a;
    }
}