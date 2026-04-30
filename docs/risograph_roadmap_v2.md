# Zappy Risograph Pipeline — Implementation Roadmap (v2)

## Current State

- Single SubViewport + canvas_item shader
- 6-ink system with continuous weight detection (working but gradient-conflicted)
- Halftone + noise dual mode, jitter, paper grain, misregistration
- No object group routing
- No scene gradient
- No multiplicative overprinting

## Target State

- 2 SubViewports (Face ID map + Object Group map) feeding 1 Risograph shader
- N ink layers with independent masks (face + zone + gradient)
- Multiplicative overprinting
- Scene-wide Y gradient per ink
- 5 object zones: ground, players, resources, ornaments, UI
- Checkerboard via ground_dark zone

---

## Dependency Map

```
Phase 1 (Blender — face ID cleanup)
    └── Phase 2 (Object Group materials in Godot)
            └── Phase 3 (Scene structure — add group SubViewport)
                    └── Phase 4 (control.gd update)
                            └── Phase 5 (Risograph shader rewrite)
                                    ├── Phase 6 (gradient tuning)
                                    └── Phase 7 (checkerboard)
                                            └── Phase 8 (polish)
```

---

## Phase 1 — Blender: Clean Up Face ID Encoding

**Goal:** Ensure every face has a pure, discrete, single-channel vertex color. No intermediate values, no gradient blending between faces.

### Step 1.1 — Audit existing models

Open each model in Blender. In Edit Mode with the vertex color layer active, visually confirm:
- Top faces are exactly (1, 0, 0)
- Left faces are exactly (0, 1, 0)  
- Right faces are exactly (0, 0, 1)
- No face has a value like (0.8, 0.2, 0) — this would be a gradient bleed

If colors look washed out or interpolated across face boundaries, the issue is that vertex color is being painted in Vertex mode rather than Face mode.

### Step 1.2 — Fix interpolation at face boundaries

In Blender's vertex paint mode, set the brush to **Face Select** painting mode (not vertex). This ensures each vertex gets the color of its face, preventing blending at shared edges between differently-colored faces.

Repaint any face that shows blending.

### Step 1.3 — GLB export settings

In the Blender GLB export dialog:
- Data → Mesh → Color Attributes: enabled
- Color Space: **Linear** (not sRGB — this is the bug that corrupted colors previously)

### Step 1.4 — Verify in Godot

After import, select the mesh in the 3D editor. Switch to Vertex Color display mode. Faces should show flat saturated R, G, or B — no blending between faces.

**Test shader (paste temporarily into BaseMeshColor.gdshader):**
```glsl
shader_type spatial;
render_mode unshaded;
void fragment() {
    // Should show pure red, green, or blue per face, never intermediate
    ALBEDO = COLOR.rgb;
}
```

---

## Phase 2 — Godot: Object Group Materials

**Goal:** Create one flat unlit material per scene zone.

### Step 2.1 — Create ObjectGroup.gdshader

```glsl
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 group_color : source_color = vec3(1.0, 0.0, 0.0);

void fragment() {
    ALBEDO = group_color;
}
```

Save as `res://shaders/ObjectGroup.gdshader`.

### Step 2.2 — Create material instances

Create one ShaderMaterial per zone using ObjectGroup.gdshader:

| File | group_color | Zone |
|---|---|---|
| `grp_ground.tres` | (1, 0, 0) | Ground / tiles |
| `grp_ground_dark.tres` | (0.5, 0, 0) | Dark checkerboard tiles |
| `grp_player.tres` | (0, 1, 0) | Players |
| `grp_resource.tres` | (0, 0, 1) | Resources |
| `grp_ornament.tres` | (1, 1, 0) | World ornaments |
| `grp_ui.tres` | (0, 1, 1) | UI elements |

Save all to `res://materials/groups/`.

### Step 2.3 — Do NOT assign these yet

These will be assigned only in the Group Map SubViewport at runtime via script. Main scene objects keep their existing face ID materials.

---

## Phase 3 — Godot: Scene Structure

**Goal:** Add a second invisible SubViewport that renders the object group map.

### Step 3.1 — Current structure (reference)

```
Control
└── SubViewportContainer (RisoViewport) ← shader applied here
    └── SubViewport
        ├── Camera3D
        ├── WorldEnvironment
        └── [all scene objects]
```

### Step 3.2 — Target structure

```
Control
├── SubViewportContainer (RisoViewport) ← Risograph shader here
│   └── SubViewport
│       ├── Camera3D  ← main camera
│       ├── WorldEnvironment
│       └── [all scene objects with face ID materials]
│
└── SubViewportContainer (GroupMapViewport) ← NO shader, invisible
    └── SubViewport
        ├── Camera3D  ← synced to main camera by script
        ├── WorldEnvironment  ← same white background
        └── [same scene objects with group materials as override]
```

### Step 3.3 — Add GroupMapViewport in editor

Duplicate the existing SubViewportContainer. Rename to `GroupMapViewport`. Set:
- `visible = false`
- Remove any shader material from the container
- SubViewport: `render_target_update_mode = 4` (Always)
- SubViewport: same size as RisoViewport

### Step 3.4 — Assign group material overrides

For each object instance under GroupMapViewport/SubViewport, set Material Override to the appropriate group material. This does NOT affect the main RisoViewport — overrides are per-instance.

**Important:** Only set overrides on the GroupMapViewport instances, never on the RisoViewport instances.

---

## Phase 4 — control.gd Update

**Goal:** Sync cameras, pass group map texture to shader, expose palette API.

```gdscript
extends Control

@onready var riso_vp       = $RisoViewport/SubViewport
@onready var riso_container = $RisoViewport
@onready var riso_cam      = $RisoViewport/SubViewport/Camera3D

@onready var group_vp      = $GroupMapViewport/SubViewport
@onready var group_cam     = $GroupMapViewport/SubViewport/Camera3D

var riso_mat: ShaderMaterial

func _ready():
    riso_mat = riso_container.material as ShaderMaterial
    
    # Match viewport sizes
    group_vp.size = riso_vp.size
    
    # Pass group map texture to shader
    riso_mat.set_shader_parameter("group_map", group_vp.get_texture())

func _process(_delta):
    # Sync group camera to main camera every frame
    group_cam.global_transform = riso_cam.global_transform
    group_cam.projection       = riso_cam.projection
    group_cam.size             = riso_cam.size
    
    # Keep sizes in sync on window resize
    if group_vp.size != riso_vp.size:
        group_vp.size = riso_vp.size

# Public API for changing ink colors at runtime
func set_ink(index: int, color: Color):
    riso_mat.set_shader_parameter("ink_color_" + str(index), 
        Vector3(color.r, color.g, color.b))

func set_gradient(top_density: float, bottom_density: float):
    riso_mat.set_shader_parameter("gradient_top_density",    top_density)
    riso_mat.set_shader_parameter("gradient_bottom_density", bottom_density)
```

---

## Phase 5 — Risograph Shader Rewrite

**Goal:** Replace the 6-ink detection system with N ink layers using mask composition and multiplicative overprinting.

### Step 5.1 — Uniforms

```glsl
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
```

### Step 5.2 — Helper functions

```glsl
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
```

### Step 5.3 — Fragment function

```glsl
void fragment() {
    vec3 face_id  = texture(TEXTURE, UV).rgb;
    vec3 group_id = texture(group_map, UV).rgb;

    if (is_background(face_id)) {
        // Paper grain on background
        float g = noise(UV * paper_grain_size + vec2(7.3, 4.1));
        COLOR = vec4(background + vec3((g - 0.5) * paper_grain_amount), 1.0);
        return;
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
```

---

## Phase 6 — Gradient Tuning

**Goal:** Dial in the scene gradient to feel like the blender/fish reference images.

With the shader running, adjust these uniforms in the Inspector:

- `ink_A_density_top` / `ink_A_density_bot` — control how ink A fades top to bottom
- `ink_B_density_top` / `ink_B_density_bot` — same for ink B
- Etc.

A good starting point for a warm-top/cool-bottom feel:
```
Ink A (coral):  top=1.0, bot=0.3  — strong at top, fades down
Ink B (purple): top=0.3, bot=1.0  — fades in toward bottom
Ink C (yellow): top=0.7, bot=0.7  — consistent, provides warmth everywhere
```

---

## Phase 7 — Checkerboard

**Goal:** Arena tiles alternate between normal and dark variants.

### Step 7.1 — Two tile materials in group map

`grp_ground.tres` → group_color = (1.0, 0, 0)  
`grp_ground_dark.tres` → group_color = (0.35, 0, 0)

The shader already handles this via `zone_ground` which reads the red channel value — 1.0 for normal, 0.35 for dark, producing 65% density on dark tiles.

### Step 7.2 — Tile placement in GDScript

```gdscript
for x in range(grid_width):
    for z in range(grid_height):
        var tile = tile_scene.instantiate()
        var is_dark = (x + z) % 2 == 1
        
        # Set group material on the GroupMapViewport instance only
        var group_mat = grp_ground_dark if is_dark else grp_ground
        tile.get_node("Mesh").material_override = group_mat
        
        group_viewport_root.add_child(tile)
        tile.position = Vector3(x * tile_size, 0, z * tile_size)
```

---

## Phase 8 — Polish and Non-Axonometric Geometry

### Step 8.1 — Aux face colors for stars/ramps

Non-standard faces (angled sides of extruded stars, ramps, decorative geometry) can use additional discrete vertex colors. Add detection in the shader:

```glsl
// White vertex color = special unshaded (UI overlays, ornament highlights)
bool face_special = face_id.r > 0.8 && face_id.g > 0.8 && face_id.b > 0.8;
```

For angled faces that fall between top/left/right, the dominant-channel detection naturally picks the closest match, which produces a reasonable result in most cases.

### Step 8.2 — Performance

Three SubViewports render the full scene each frame. On target hardware, profile and consider:
- GroupMapViewport: switch to `UPDATE_WHEN_PARENT_VISIBLE` and only trigger updates when scene objects move
- Camera sync: use signals instead of `_process` polling

### Step 8.3 — Shader parameter API in control.gd

Expose clean methods for game logic to change visual theme:

```gdscript
func apply_theme(theme: RisoTheme):
    set_ink(0, theme.ink_a)
    set_ink(1, theme.ink_b)
    set_ink(2, theme.ink_c)
    set_gradient(theme.gradient_top, theme.gradient_bottom)
```

This allows level transitions to smoothly shift the whole scene's color palette — a powerful tool for communicating game state visually.

---

## Open Questions

1. **Ink count** — 5 inks (A-E) covers the 5 zones. Is there a need for zone-independent inks that cover everything? For example, a "shadow ink" that prints only on certain face angles regardless of zone?

2. **Ornament rendering** — world ornaments and UI may need to bypass the face ID system entirely (they're 2D shapes, not 3D cubes). These might be better handled as a separate CanvasLayer rendered on top of the riso output.

3. **Player ink isolation** — if players move in front of world geometry, their group map pixels will correctly isolate them to ink D. But the world inks will still print on top due to the sequential overprinting. Is this desirable (players blend into world) or problematic (players should stand out cleanly)?
