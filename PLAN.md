# SHAIBA — Master Plan

A cozy low-poly open-world survival game set in the Arabic desert of **Shaiba**, built in Godot 4.7 with Blender-made assets, viewed from an angled top-down (near-isometric) camera.

This file is the **single source of truth for project progress**. Every Claude Code session starts by reading this file (CLAUDE.md points here), works on exactly **one phase**, and updates the status table before finishing. A phase is not complete until every item in its **Quality Gate** passes — "mostly working" is not done.

---

## Status board

| Phase | Name | Branch | Status |
|-------|------|--------|--------|
| 0 | Plan, repo & conventions | `main` | ✅ Done (2026-08-13) |
| 1 | Godot project scaffold & core architecture | `feature/phase-1-scaffold` | ✅ Done (2026-08-13) |
| 2 | Camera & movement (gray-box) | `feature/phase-2-camera-movement` | 🟡 In progress |
| 3 | Character model & animation | `feature/phase-3-character` | 🔲 Not started |
| 4 | Terrain & chunk streaming | `feature/phase-4-terrain` | 🔲 Not started |
| 5 | Sand footprint physics | `feature/phase-5-footprints` | 🔲 Not started |
| 6 | Environment assets (house & camel) | `feature/phase-6-environment` | 🔲 Not started |
| 7 | Integration & polish → v0.1 | `feature/phase-7-polish` | 🔲 Not started |

Status legend: 🔲 Not started · 🟡 In progress · 🧪 In testing on `development` · ✅ Done (merged, gate passed)

**Later (out of scope for now):** survival systems (hunger/thirst/heat), day-night cycle, inventory, NPCs/dialogue, save games, sound design. Do not build these early "while we're in there" — but do leave clean extension points.

---

## Vision & pillars

1. **Cozy, not hostile.** The desert is beautiful and calm. Even when survival mechanics arrive later, the tone stays warm.
2. **Uniform look.** Low-poly, flat-shaded, every material sampled from the fixed palette in `docs/ART_DIRECTION.md`. No stray colors, no photo textures.
3. **The sand is alive.** Footprints, trails, and wind-shaped dunes make the ground itself the most memorable "character."
4. **Open world from day one.** The map is large, so terrain is chunked and streamed from the very first terrain implementation — never a single big mesh we'd have to retrofit.

## Fixed decisions (do not re-litigate in later sessions)

- **Engine:** Godot 4.7.1, Forward+ renderer. Repo root **is** the Godot project root.
- **Camera:** angled top-down / near-isometric — perspective camera, pitched ≈ 50–55° down, slight FOV (~35°) for a "toy diorama" feel. Rotatable in 45° steps later if wanted; never free-look.
- **Art:** low-poly flat-shaded, palette-only materials (see `docs/ART_DIRECTION.md`). Blender sources in `assets/blender/`, exported `.glb` in `assets/models/`.
- **World:** chunked terrain streamed around the player (see `docs/ARCHITECTURE.md`). Deterministic generation from a world seed.
- **Code:** GDScript (typed), feature-folder organization, conventions in CLAUDE.md. No C# unless a profiled performance need forces it (record it in `docs/DECISIONS.md` if so).
- **Branches:** `main` = stable & playable, `development` = integration, `feature/phase-N-*` = one per phase. Details in CLAUDE.md → Git workflow.

---

## Phase 1 — Godot project scaffold & core architecture

**Goal:** an empty but *correctly structured* Godot project that opens, runs, and encodes all our conventions, so every later phase drops into place.

**Deliverables**
- `project.godot` (Godot 4.7.1, Forward+, project name "Shaiba"), window/stretch settings sensible for desktop.
- Folder structure created exactly as in `docs/ARCHITECTURE.md` (feature folders under `scenes/`, `autoload/`, `resources/`, `shaders/`, `assets/`).
- Input map defined in project settings: `move_up/down/left/right` (WASD + arrows), `interact` (E) — even if unused yet.
- Palette as a Godot resource: `resources/palette/` with named `StandardMaterial3D` .tres files for every color in ART_DIRECTION.md (flat-shaded: roughness 1.0, no metallic).
- One autoload only for now: `autoload/game.gd` (`Game`) — holds world seed + will grow into pause/state later. No premature managers.
- `scenes/world/world.tscn` main scene: DirectionalLight3D (warm, angled like late afternoon), WorldEnvironment with the sky/ambient colors from ART_DIRECTION.md, and a temporary 50×50 m flat ground plane using the sand material.
- `.gitattributes` for Git LFS-free binary handling (or LFS if .glb sizes demand it — decide, record in DECISIONS.md).
- Verify godot-mcp works against the project (open editor, run project, read debug output) and note any quirks in CLAUDE.md.

**Quality Gate**
- [x] Project opens in Godot 4.7.1 with zero errors/warnings in the output panel (verified via headless `--import` pass and debug run, both clean).
- [x] `mcp godot run_project` runs the main scene: warm-lit sand plane, correct sky, no script errors (screenshot-verified; a temporary `PreviewCamera` at the fixed 52°/35° FOV angle was added so the scene is visible — Phase 2's camera rig replaces it).
- [x] Every folder in ARCHITECTURE.md exists and contains either real files or a `.gitkeep`.
- [x] All palette materials exist as .tres and render flat-shaded (roughness 1.0, metallic 0; hex values spot-checked against ART_DIRECTION.md).
- [x] PLAN.md status updated; work merged `feature/phase-1-scaffold` → `development`.

## Phase 2 — Camera & movement (gray-box)

**Goal:** the game *feels* right with placeholder art. Movement + camera are the foundation everything else sits on, so they get tuned to top-notch before any real art exists.

**Deliverables**
- `scenes/player/player.tscn`: `CharacterBody3D` + capsule placeholder mesh (palette material), `player.gd` with typed GDScript.
- Movement: 8-directional WASD relative to camera, acceleration/deceleration curves (no instant start/stop), gentle rotation of the body toward move direction, `move_and_slide` on floor, gravity for slopes/ledges. Export-var tuned: max speed, accel, friction, turn speed.
- `scenes/camera/camera_rig.tscn`: separate rig scene — a `Node3D` that smoothly follows the player (lag/damping), holding the angled top-down `Camera3D` per the fixed decision. Zoom in/out on scroll wheel between sensible clamps.
- Test scene `scenes/world/graybox.tscn` with ramps, steps, and obstacles to validate slopes and collisions (kept permanently as a movement test level).
- Tuning documented: final values and *why they feel right* in DECISIONS.md.

**Quality Gate**
- [ ] Moving in all 8 directions feels responsive but weighty; no jitter, no foot-sliding of the capsule, no camera stutter (test at 60 fps+).
- [ ] Slopes up to ~30° walkable, steeper blocked; no getting stuck on step edges in graybox.tscn.
- [ ] Camera never clips geometry in the graybox scene; zoom clamps work.
- [ ] All scripts typed GDScript, zero warnings.
- [ ] PLAN.md updated; merged to `development`.

## Phase 3 — Character model & animation

**Goal:** replace the capsule with the real protagonist and prove out the full Blender→Godot pipeline.

**Deliverables**
- Low-poly desert traveler modeled in Blender (via blender-mcp): head-wrap/keffiyeh, loose robes — palette colors only, target ≤ 2,500 tris. Source: `assets/blender/player.blend`; export: `assets/models/player.glb`.
- Simple rig + three animations minimum: `idle`, `walk`, `run`. Root motion NOT used — animation speed matched to movement speed in code.
- `AnimationTree` with a state machine (idle↔walk↔run blended by speed) driven from `player.gd`.
- Export pipeline documented in `docs/ART_DIRECTION.md` (Blender export settings, scale/orientation conventions, checklist) so every later asset follows the identical process.

**Quality Gate**
- [ ] Character reads clearly at gameplay camera distance; silhouette and colors match ART_DIRECTION.md (screenshot comparison).
- [ ] No foot-sliding at walk or run speed; blend transitions smooth, no T-pose flashes.
- [ ] .blend and .glb committed; re-export from .blend reproduces the .glb byte-compatibly enough to be repeatable.
- [ ] Runs in graybox scene with zero errors; PLAN.md updated; merged to `development`.

## Phase 4 — Terrain & chunk streaming

**Goal:** the open desert. Chunked, streamed, seeded — the permanent world foundation, built right the first time.

**Deliverables**
- `scenes/world/terrain/` chunk system per `docs/ARCHITECTURE.md`: `chunk_manager.gd` (loads/unloads a radius of chunks around the player), `terrain_chunk.gd` (builds one chunk's mesh + collision from the world-seeded `FastNoiseLite` dune heightfield).
- Chunk size and radius chosen by profiling (start 64 m chunks, ~5×5 loaded), generation off the main thread (`WorkerThreadPool` or thread) so streaming never hitches.
- Dunes: layered noise for large dune waves + small ripple detail; flat-shaded sand material; subtle vertex-color variation between the two sand tones for visual interest.
- Far-field: simple distant-ring lower-LOD chunks or a horizon skirt so the horizon is never a hard edge (pick simplest approach that looks right; record in DECISIONS.md).
- Debug overlay (toggle with F3): current chunk coords, loaded chunk count, frame time.
- Player + camera dropped into the real desert as the new main scene flow.

**Quality Gate**
- [ ] Walk continuously in one direction for 2+ km of world distance: no hitches > 4 ms from streaming, no visible pop-in gaps or seams between chunks, memory stable (chunks actually unload).
- [ ] Same seed ⇒ identical terrain across runs; different seed ⇒ different desert.
- [ ] Collision matches visuals — player never floats or sinks on any dune.
- [ ] 60 fps+ on this Mac at default window size with full load radius.
- [ ] PLAN.md updated; merged to `development`.

## Phase 5 — Sand footprint physics

**Goal:** the signature feature — the player leaves footprints and trails in the sand that persist believably and fade over time.

**Planned approach** (validate before building, record final in DECISIONS.md): a "sand deformation" texture accumulated in a `SubViewport` that follows the player — footstep brushes stamped as the character walks — sampled by the near-terrain shader for vertex displacement (depression) + a slightly darker/compacted sand color in the print. Deformation region covers only nearby chunks; texture slowly decays so old prints fill in like wind-blown sand. Distant chunks skip it entirely.

**Deliverables**
- `shaders/sand_deform.gdshader` + the SubViewport stamping rig, integrated with the Phase 4 chunk terrain.
- Footstep stamps timed to the walk/run animation (alternating left/right), plus a soft drag trail when moving.
- Decay: prints visibly soften and vanish over ~1–2 minutes (tunable export var).
- Hooks for the future: any object (camel, dragged items) can register as a "sand stamper" — small, clean interface.

**Quality Gate**
- [ ] Footprints visually match foot placement at walk and run; look correct from the gameplay camera in both direct light and shadow.
- [ ] No shimmer/artifacts at the deformation region boundary as it follows the player across chunk borders.
- [ ] Frame cost of the whole system ≤ 1 ms on this Mac; zero cost when standing still.
- [ ] Prints fade smoothly; walking a circle and returning shows believable partial fading.
- [ ] PLAN.md updated; merged to `development`.

## Phase 6 — Environment assets (house & camel)

**Goal:** populate the desert with its first landmarks and life, all through the Phase 3 asset pipeline.

**Deliverables**
- **Desert house** in Blender: single-story mud-brick/adobe home with a wind-tower (barjeel), flat roof, arched doorway — palette plaster/clay colors, ≤ 4,000 tris. Placed as an enterable-later landmark (blocked door for now) with proper collision.
- **Camel** in Blender: low-poly, ≤ 3,000 tris, `idle` + `walk` animations. Simple wander behavior (`camel.gd`): ambles within a home radius, avoids the house, registers as a sand stamper so it leaves tracks.
- 2–3 small props from the same sessions' style: date palm, rocks, a well or cloth awning — enough to compose one scene.
- A handcrafted "homestead" POI composed from these assets, spawned at a fixed seeded location near the player start; scattered rocks/palms hooked into chunk generation sparsely.

**Quality Gate**
- [ ] Screenshot of the homestead at gameplay angle looks cohesive — one style, one palette, cozy (side-by-side check against ART_DIRECTION.md).
- [ ] Camel wanders, animates without sliding, leaves believable tracks, never intersects the house or player.
- [ ] All assets: .blend + .glb committed, correct collision, no errors, stable 60 fps+ with everything on screen.
- [ ] PLAN.md updated; merged to `development`.

## Phase 7 — Integration & polish → v0.1

**Goal:** everything together, tuned as one game; ship the first stable `main`.

**Deliverables**
- Full pass on lighting/environment: warm late-afternoon sun, soft shadows tuned, subtle fog/height haze for depth, sky gradient matched to palette.
- Performance pass: profile, fix any regressions, confirm all gates from phases 2–6 still pass in the combined game.
- Consistency sweep: naming, folder hygiene, dead code/scenes removed, every script typed and warning-free, docs updated to reality.
- A 5-minute "playtest loop": spawn near the homestead, walk the dunes, watch prints fade, meet the camel — verified start-to-finish with no errors.
- Merge `development` → `main`, tag `v0.1.0`.

**Quality Gate**
- [ ] Fresh clone + open in Godot + run: works first try, zero errors.
- [ ] 10-minute free-play session: no crashes, no fps drops below 60, no visual bugs at the gameplay camera.
- [ ] Joshua has played it and signed off.
- [ ] `main` updated and tagged `v0.1.0`.

---

## After v0.1 (future planning session)

Survival layer (thirst/heat/shade), day-night cycle, inventory, more POIs and biome variation within the desert, sound & music, save/load. Plan these in a dedicated session that writes PLAN-v0.2.md or extends this file.
