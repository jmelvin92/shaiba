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

1. Model at origin, feet/base at Z=0, facing **+Y** in Blender. Blender's glTF exporter maps `(x, y, z)` → `(x, z, −y)`, so **+Y in Blender becomes −Z in Godot**, which is Godot's forward. (This step used to say −Y; that is the opposite, and it would have shipped every asset facing backwards. Caught in Phase 3.)
2. Apply all transforms (`Ctrl+A` → All Transforms). Scale must read 1.0 everywhere.
3. Materials named exactly like their palette entry (`sand_mid`, `clay`, …) so Godot-side material mapping is automatic.
4. Save source as `assets/blender/<name>.blend` (committed — models must stay re-editable).
5. Export glTF: **glb**, `assets/models/<name>.glb`. Settings: +Y up, apply modifiers ON, export only selected/needed objects. When rigged, `export_animations=True` with `export_animation_mode='ACTIONS'` — that exports one named glTF animation per Blender action, so actions named `idle`/`walk`/`run` arrive in Godot under those names. (No NLA work needed; the older "push each action to an NLA track" instruction predates this exporter mode.)
6. In Godot, confirm import: scale 1:1, forward −Z, animations listed. **Hand-modelled assets use the `resources/palette/` .tres materials** — that is the default and the rule. Assets are *not* remapped by a Godot import script; whatever material an asset should have is set in Blender before export, so the .blend stays the single source of truth.
7. Set animation loop modes in the `.glb.import` file's `_subresources` block (`settings/loop_mode` 1 for cycles like idle/walk/run, 0 for one-shots like jump/land). Godot imports everything as non-looping by default.
8. Screenshot the asset at gameplay camera angle and compare against this doc before calling it done.

## Imported / AI-generated assets

Assets that arrive already modelled (Meshy and similar) skip steps 1–4 but need their own audit, because a generated glb is tuned to look right in the generator's own viewer, not in our scene. Do all of it in a committed script — `tools/build_player.py` is the worked example — so the conditioning is reproducible rather than a remembered sequence of clicks.

- **Keep the untouched download** as `assets/blender/<name>_source.glb`, and put a `.gdignore` in `assets/blender/` so Godot never imports sources as game assets.
- **Check the facing.** Generators commonly face +Z in glTF, which is backwards in Godot. Rotating the *object* 180° (rather than applying it into the rest pose) leaves every action untouched and the exporter bakes it into the node. Note the glTF importer leaves objects in quaternion rotation mode, where assigning `rotation_euler` silently does nothing.
- **Audit the material.** Expect to fix: emission (generators often make the whole model self-lit, so it ignores our sun entirely), `alphaMode: BLEND`, double-sidedness, metallic, and roughness. Downscale oversized textures — at a 23 m camera a character does not need 2048².
- **Check the units.** A rig authored in centimetres arrives with a 0.01 scale on its armature. That imports correctly and is fine to leave; just do not "fix" it by applying scale without also rescaling every location F-curve, which is a silent way to break the animation.
- **Measure each locomotion clip's natural stride speed** (`tools/measure_gaits.gd`) and record it beside the asset. The movement speeds and the blend-space anchors both key off those numbers.
- **Check for root motion.** A clip that travels in place is what we want; one that carries the character forward will slide out from under the physics body.

Two Blender 5.x API notes that cost time in Phase 3, since every later asset script hits them: actions are *layered* (4.4+), so F-curves live at `action.layers[…].strips[…].channelbags[…].fcurves` and the flat `action.fcurves` shortcut is gone; and `bpy_struct` hands back a fresh wrapper on each attribute access, so node/link/image comparisons must use `==`, never `is`.
