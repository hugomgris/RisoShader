# Zappy Risograph Pipeline — Architecture Overview (v2)

## Core Mental Model

This pipeline simulates physical risograph printing. A risograph prints by running paper through a drum machine N times, once per ink color. Each pass lays down one ink across the whole sheet. The final image is the result of those inks sitting on top of each other on paper.

**The fundamental unit is an ink layer, not an object.**

Color variety doesn't come from assigning different colors to different objects. It comes from independent ink layers overlapping each other. Where two inks overlap, you get a third color for free — just like real printing. This is what gives riso its characteristic richness from a limited palette.

```
Ink A (coral)   ░░░▓▓▓▓▓░░░    — covers top faces + fades with screen Y
Ink B (purple)  ░░▓▓▓▓░░░░░    — covers left faces + players
Ink C (yellow)  ▓▓▓░░░▓▓▓▓▓   — covers right faces + ground
Paper           ████████████   — cream base, shows through gaps

Result at overlap of A+B = dark warm purple
Result at overlap of B+C = green
Result at A only = coral
Result at C only = yellow
```

---

## What Changes From v1

**Removed:** Per-object palette routing. Objects do not own colors.

**Removed:** 6-ink RGB+CMY detection system. CMY was a workaround that conflicted with gradients.

**Added:** Global ink layers with independent masks. Each ink covers the whole scene but its mask controls where and how densely it prints.

**Added:** Multiplicative overprinting. Inks composite like real ink on paper, not like digital alpha blending.

**Simplified:** Vertex colors stay as pure face ID only (R/G/B per face). No gradient encoding needed in vertex data.

---

## Render Pass Architecture

```
┌─────────────────────────────────────────────┐
│  PASS 1: Face ID Map (SubViewport)           │
│  Unshaded, flat vertex colors                │
│  Output: which face direction per pixel      │
│  R=top, G=left, B=right                      │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  PASS 2: Object Group Map (SubViewport)      │
│  Unshaded, flat solid colors per group       │
│  Output: which scene zone per pixel          │
│  (ground, player, resource, ornament, UI)    │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  PASS 3: Risograph Shader (canvas_item)      │
│  Reads both maps + screen position           │
│  Computes per-ink masks                      │
│  Prints each ink layer multiplicatively      │
│  Adds halftone pattern + paper grain         │
│  Output: final image                         │
└─────────────────────────────────────────────┘
```

---

## Vertex Color Encoding

Single color attribute, pure discrete values per face. Never blended.

| Vertex Color | Meaning |
|---|---|
| (1, 0, 0) pure red | Top-facing face |
| (0, 1, 0) pure green | Left-facing face |
| (0, 0, 1) pure blue | Right-facing face |
| (1, 1, 1) pure white | Special / unshaded (ornaments, UI details) |
| (0, 0, 0) pure black | Masked out / shadow layer |

No gradients in vertex colors. No intermediate values. The face ID is always determined by dominant channel.

---

## Object Group Map

A second SubViewport renders all scene objects with flat unlit materials, one solid color per group:

| Object Group | ID Color |
|---|---|
| Ground / tiles | (1, 0, 0) red |
| Players | (0, 1, 0) green |
| Resources | (0, 0, 1) blue |
| World Ornaments | (1, 1, 0) yellow |
| UI | (0, 1, 1) cyan |

These colors are chosen to be maximally distinct. They are never seen by the player — only sampled by the shader.

---

## Ink Layer System

The scene is rendered as N independent ink layers. Each layer has:

- **ink_color** — the physical ink color (uniform)
- **mask** — a float 0→1 per pixel, computed from face ID + object group + screen position
- **density** — global scale on the mask (uniform, controls how much ink prints)

### Mask Composition

Each ink's mask is built from three independent inputs multiplied together:

```
mask = face_contribution * zone_contribution * gradient_contribution
```

**face_contribution** — which face directions this ink covers:
```glsl
// Example: ink A covers top faces
float face_contrib = face_id.r; // 1.0 on red faces, 0.0 elsewhere
```

**zone_contribution** — which scene zones this ink covers:
```glsl
// Example: ink D only covers players
float zone_contrib = float(obj_group == GROUP_PLAYER);
```

**gradient_contribution** — how ink density varies across the screen:
```glsl
// Screen Y gradient: full density at top, fades toward bottom
float gradient_contrib = 1.0 - UV.y;
// Or constant: gradient_contrib = 1.0
```

### Overprinting

Inks composite multiplicatively, like real ink on paper:

```glsl
vec3 overprint(vec3 base, vec3 ink_color, float coverage) {
    // Ink absorbs light — overlapping inks multiply, they don't average
    return mix(base, base * ink_color, coverage);
}

// Print each ink in sequence
vec3 result = background;
result = overprint(result, ink_color_A, hit_A);
result = overprint(result, ink_color_B, hit_B);
result = overprint(result, ink_color_C, hit_C);
// ... etc
```

This means:
- Ink A (coral) alone on cream paper → coral
- Ink B (blue) alone on cream paper → blue
- Ink A + Ink B overlapping → dark purple-brown (coral × blue)
- No ink → cream paper shows through

This is physically correct and produces color richness automatically.

---

## Scene Gradient

A global screen-space gradient shifts ink densities across the whole image. Since the camera is fixed axonometric, screen Y maps reliably to world height.

Each ink has its own gradient curve — some inks are denser at the top, some at the bottom, some constant. This is what creates the blended look across the whole scene without any per-vertex data.

```glsl
uniform float gradient_top    = 0.0;  // screen Y where gradient starts (0=top)
uniform float gradient_bottom = 1.0;  // screen Y where gradient ends (1=bottom)

float scene_t = smoothstep(gradient_top, gradient_bottom, UV.y);

// Per-ink gradient control
// ink_A_top_density = density at top of screen
// ink_A_bot_density = density at bottom of screen
float ink_A_density = mix(ink_A_top_density, ink_A_bot_density, scene_t);
```

---

## Checkerboard

Dark tiles are a separate object group (or a variant material) that contributes a reduced density to whichever inks cover the ground zone. No vertex color changes needed.

```glsl
float ground_darkness = (obj_group == GROUP_GROUND_DARK) ? 0.65 : 1.0;
float ink_C_mask = face_contrib * zone_ground * ground_darkness * gradient_contrib;
```

---

## Halftone Pattern

Applied identically to all ink layers. Each ink drum is sampled at a slightly rotated UV angle (15° apart) to prevent moiré — matching real riso drum angle offsets.

The halftone function takes a UV and a density value (the mask) and returns 0 or 1 (with softness). High density = large dots = more ink coverage.

---

## Paper Grain

A single noise layer added to the final composited image. Simulates uncoated paper texture. Applied after all inks have been composited — not per-ink.

---

## What This Handles

| Scenario | Mechanism |
|---|---|
| 3-face axonometric cubes | Face ID R/G/B → face_contribution per ink |
| Non-axonometric faces | Additional face ID colors (white/black or new discrete values) |
| Scene-wide color gradient | gradient_contribution varies ink density with screen Y |
| Multiple zone palettes | zone_contribution gates inks to specific object groups |
| Checkerboard darkening | Ground dark group reduces ink density |
| Ink overlap colors | Multiplicative compositing produces them automatically |
| Paper texture | Single noise pass on final image |
| Misregistration | Per-ink UV offset on halftone sample |
