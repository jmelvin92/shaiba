# Art Direction — Shaiba

**One sentence:** a warm, cozy, low-poly Arabic desert in late-afternoon light, flat-shaded, every color drawn from the fixed palette below.

References for feel (style, not copying): *Monument Valley* (calm geometry, warm sand tones), *Alba: A Wildlife Adventure* (cozy low-poly outdoors), *Journey* (desert warmth and dune shapes).

## The palette

These are the **only** colors in the game. Each has a matching flat-shaded `StandardMaterial3D` in `resources/palette/` (created in Phase 1). If a new color ever seems necessary, it's a deliberate art-direction decision → discuss with Joshua, add here + as a .tres, log in DECISIONS.md.

| Name | Hex | Use |
|------|-----|-----|
| `sand_light` | `#EFA254` | Sunlit sand, dune tops |
| `sand_mid` | `#D97E2E` | Base sand, mid tones |
| `sand_shadow` | `#A85419` | Dune shadow sides, compacted sand in footprints |
| `clay` | `#B97350` | Terracotta, pottery, roof edges, bricks |
| `plaster` | `#F2E7CF` | Whitewashed walls, cloth, camel-light accents |
| `wood` | `#8A5A3B` | Doors, beams, well frame, palm trunks |
| `palm_green` | `#7FA05B` | Palm fronds, sparse vegetation |
| `oasis_teal` | `#5FA8A0` | Water, glazed tiles, rare cool accent |
| `night_blue` | `#34455E` | Deep shadow accents, night sky later, UI text |
| `accent_gold` | `#E2A93B` | Highlights: lanterns, trims, interactables |

**Lighting palette** (WorldEnvironment / DirectionalLight3D — since Phase 6.5 these are the day-night cycle's keyframes in `desert_environment.gd`, not static values):
- **Golden hour (16:00), the signature look:** sun `#FFE9C4` at energy 1.2, pitched like ~4pm; sky `#FFEFD6` horizon → `#8FB8C9` overhead. The cycle reproduces this *exactly* — it is the anchor the whole day is calibrated around.
- **Noon:** sun whitens toward `#FFF3DC` at energy 1.3; same sky.
- **Dawn (05:00–06:30) / dusk (17:30–19:30):** sun warms through `#FFDCA8`/`#FFCE96` to the horizon glows `#FFB36B` (dawn) and `#FF9E63` (dusk); horizon sky passes through `#E8A06A` / `#F0975C`.
- **Night (properly dark — Joshua's ladder pick, 2026-08-15):** sky `#101828` overhead, `#1F2B44` at the horizon (both are `night_blue` territory); a faint cool moon light `#BFD2E8` at energy 0.06. Night is *meant* to be dark: carried light (torches, the oil lamp) is useful, and a touch of dread is intended. `night_darkness` on `DesertEnvironment` blends back toward a bright-moonlit look if this ever needs revisiting.
- Ambient always follows the sky (the Environment's ambient source), and fog color always equals the sky horizon color — at every hour, so the far dunes melt into haze by night exactly as by day.
- **The haze is distance-only** (Joshua's ladder pick, 2026-08-15): depth fog, crystal clear to 100 m, full melt by 330 m — inside the ~350 m streaming edge. The playable frame carries no fog wash at all; the haze exists solely to dissolve the horizon. `verify_cycle` asserts the shape.
- Shadows soft-edged, never pure black (lift toward `night_blue`).
- **Flames are the one emissive thing in the game** (piece 3, 2026-08-15): `FlameLight`'s flame color is `#FFC873` (between `accent_gold` and the dusk sun tones), used for the tiny flame mesh (emissive) and its flickering OmniLight3D. Nothing else may emit — a light source visibly glowing is the point; glowing props that aren't fire are not.
- **Window openings are real holes** (Joshua's call, 2026-08-15 — supersedes the shadowed-recess panel in the original house): interior lamplight must spill through them at night. Model windows as openings, never as dark panels.

Rule of thumb for cohesion: **large areas = sand tones; buildings = plaster/clay/wood; green and teal are scarce and precious; gold marks things you can interact with.**

## Reference images

`docs/references/` holds the visual references Joshua has supplied, committed so later sessions build against the same target rather than a remembered description. (`docs/` carries a `.gdignore` so Godot never imports them as game textures.)

| File | What it anchors |
|------|-----------------|
| `house_exterior.png` | The desert house (Phase 6): two-story ochre adobe cube, flat roof + parapet, protruding roof-beam ends (vigas) in a row under the roofline, dark wood-framed windows, cloth awning on poles over the door, external stair up one side to the roof terrace. |
| `house_interior_majlis.png` | The ground-floor **majlis** (Phase 6): low striped seating along two walls, patterned rug, poufs and floor cushions, low table with tray, hookah, curtained windows. |
| `shaybah_dunes.jpg` | The desert itself (Phase 6 restyle): rich Shaybah orange sand — source of the 2026-08-14 sand trio — fine wind-combed ripples lying across the wind, and mega-dune ridges dwarfing the ordinary dune field. |

A reference anchors **proportion, silhouette and the set of features** — never materials. Everything is rebuilt flat-shaded in the palette above: the references' photo-textures, stucco noise and off-palette fabrics (the reds, greens and blues of the majlis) become palette colors, with fabric pattern carried by colored faces rather than texture.

## Modeling rules (low-poly, flat-shaded)

- **Flat shading always**: shade-flat in Blender (or split normals); materials use roughness 1.0, metallic 0, no textures. Color comes from palette materials (or vertex colors sampled from the palette for terrain variation).
- **Tri budgets** (soft caps — going over needs a reason): player ≤ 2,500 · camel ≤ 3,000 · house ≤ 4,000 · small props ≤ 500 · terrain chunk driven by performance gates.
- Chunky, readable silhouettes — the camera is far and angled, so detail smaller than ~10 cm won't read; spend polygons on silhouette, not surface detail.
- Slight imperfection is cozy: gently tilt/scale prop instances, avoid perfect right angles on organic/handmade things (mud-brick walls can bulge a little).
- Scale: **1 Blender unit = 1 meter = 1 Godot meter.** Player character ≈ 1.75 m tall. Model at real-world scale, always.

**Anything the player walks on has gameplay dimensions, not just visual ones:**
- **Stairs need ~0.9 m of clear width** between whatever bounds them (a wall on one side, a parapet on the other both count), for the same aiming reason as a doorway.
- **Stair treads must be deeper than ~0.41 m** and risers no taller than 0.35 m. The player's step-up probe raises the capsule and reaches forward by its own radius plus the probe margin (0.35 + 0.06 m) to find the tread; a shallower tread puts the next riser inside that reach, the probe reads it as a wall, and the player stops dead at the bottom of the flight. A 0.34 m tread looks completely normal and is completely unclimbable — Phase 6 shipped one by accident and only a scripted walk found it.
- **Doorways**: give **1.2 m of clear width between the jambs**, not between the wall faces — trim eats the opening. The player is 0.7 m across, so that leaves ±0.25 m to aim with; at 0.9 m clear it was ±0.10 m and read as getting snagged on the frame. Height is the subtle one: **if the doorway has a threshold to step over, it must clear 2.1 m above that threshold** (the player's 1.75 m plus the 0.35 m the step-up probe lifts the capsule to feel for the tread). A 2.1 m door is fine over a flush floor and becomes a locked door the moment the floor is raised — the raised capsule hits the lintel and the probe calls the step a wall.
- **Interior floors must stand proud of the ground the building sits on** (0.12 m here). A floor level with the terrain z-fights with it, and any unevenness at all leaves sand drawn *over* the floor — which looks exactly like having chosen a sand-coloured floor material, and survives "fixing" the material.
- **Rails and parapets must hold more than 0.35 m of height over every walking surface they run beside** — measured against the *treads and landings*, not against an idealised slope line. Anything lower is a step to the controller, and the player will walk over it: the stair parapet's top was first drawn as one straight line to the far end of the landing, sagged to ~0.15 m above the treads near the stair head, and drifting against the "rail" there carried you over it and off the outside of the flight. The fix is a knee in the profile at the stair head (see `build_house.py`).
- Interior ceilings at 2.6 m give a 1.75 m character real headroom at the gameplay camera.

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
