# Art Direction — Shaiba

**One sentence:** a warm, cozy, low-poly Arabic desert in late-afternoon light, flat-shaded, every color drawn from the fixed palette below.

References for feel (style, not copying): *Monument Valley* (calm geometry, warm sand tones), *Alba: A Wildlife Adventure* (cozy low-poly outdoors), *Journey* (desert warmth and dune shapes).

## The palette

These are the **only** colors in the game. Each has a matching flat-shaded `StandardMaterial3D` in `resources/palette/` (created in Phase 1). If a new color ever seems necessary, it's a deliberate art-direction decision → discuss with Joshua, add here + as a .tres, log in DECISIONS.md.

| Name | Hex | Use |
|------|-----|-----|
| `sand_light` | `#EFD9A7` | Sunlit sand, dune tops |
| `sand_mid` | `#DFB878` | Base sand, mid tones |
| `sand_shadow` | `#C4914E` | Dune shadow sides, compacted sand in footprints |
| `clay` | `#B97350` | Terracotta, pottery, roof edges, bricks |
| `plaster` | `#F2E7CF` | Whitewashed walls, cloth, camel-light accents |
| `wood` | `#8A5A3B` | Doors, beams, well frame, palm trunks |
| `palm_green` | `#7FA05B` | Palm fronds, sparse vegetation |
| `oasis_teal` | `#5FA8A0` | Water, glazed tiles, rare cool accent |
| `night_blue` | `#34455E` | Deep shadow accents, night sky later, UI text |
| `accent_gold` | `#E2A93B` | Highlights: lanterns, trims, interactables |

**Lighting palette** (WorldEnvironment / DirectionalLight3D):
- Sun color `#FFE9C4`, energy tuned for soft warm shadows, pitched like ~4pm sun.
- Sky: gradient from `#FFEFD6` at the horizon to `#8FB8C9` overhead.
- Ambient light tinted faintly warm; shadows soft-edged, never pure black (lift toward `night_blue`).

Rule of thumb for cohesion: **large areas = sand tones; buildings = plaster/clay/wood; green and teal are scarce and precious; gold marks things you can interact with.**

## Modeling rules (low-poly, flat-shaded)

- **Flat shading always**: shade-flat in Blender (or split normals); materials use roughness 1.0, metallic 0, no textures. Color comes from palette materials (or vertex colors sampled from the palette for terrain variation).
- **Tri budgets** (soft caps — going over needs a reason): player ≤ 2,500 · camel ≤ 3,000 · house ≤ 4,000 · small props ≤ 500 · terrain chunk driven by performance gates.
- Chunky, readable silhouettes — the camera is far and angled, so detail smaller than ~10 cm won't read; spend polygons on silhouette, not surface detail.
- Slight imperfection is cozy: gently tilt/scale prop instances, avoid perfect right angles on organic/handmade things (mud-brick walls can bulge a little).
- Scale: **1 Blender unit = 1 meter = 1 Godot meter.** Player character ≈ 1.75 m tall. Model at real-world scale, always.

## Blender → Godot export checklist (follow exactly, every asset)

1. Model at origin, feet/base at Z=0, facing **−Y** in Blender (becomes −Z forward in Godot).
2. Apply all transforms (`Ctrl+A` → All Transforms). Scale must read 1.0 everywhere.
3. Materials named exactly like their palette entry (`sand_mid`, `clay`, …) so Godot-side material mapping is automatic.
4. Save source as `assets/blender/<name>.blend` (committed — models must stay re-editable).
5. Export glTF: **glb**, `assets/models/<name>.glb`. Settings: +Y up, apply modifiers ON, export only selected/needed objects, animations ON when rigged (each action pushed to NLA, named `idle`/`walk`/`run`/…).
6. In Godot, confirm import: scale 1:1, forward −Z, animations listed, then swap imported materials for the `resources/palette/` .tres equivalents (or set up an import script to do it — Phase 3 decides, log it).
7. Screenshot the asset at gameplay camera angle and compare against this doc before calling it done.
