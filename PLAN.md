# SHAIBA — Master Plan

A cozy low-poly open-world survival game set in the Arabic desert of **Shaiba**, built in Godot 4.7 with Blender-made assets, viewed from an angled top-down (near-isometric) camera.

This file is the **single source of truth for project progress**. Every Claude Code session starts by reading this file (CLAUDE.md points here), works on exactly **one phase**, and updates the status table before finishing. A phase is not complete until every item in its **Quality Gate** passes — "mostly working" is not done.

---

## Status board

| Phase | Name | Branch | Status |
|-------|------|--------|--------|
| 0 | Plan, repo & conventions | `main` | ✅ Done (2026-08-13) |
| 1 | Godot project scaffold & core architecture | `feature/phase-1-scaffold` | ✅ Done (2026-08-13) |
| 2 | Camera & movement (gray-box) | `feature/phase-2-camera-movement` | ✅ Done (2026-08-13) |
| 3 | Character model & animation | `feature/phase-3-character` | ✅ Done (2026-08-13) |
| 4 | Terrain & chunk streaming | `feature/phase-4-terrain` | 🟡 In progress |
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
- **Camera:** angled perspective camera, narrow FOV (~35°) for the "toy diorama" feel, pitched **19°** down since Phase 4 — low enough that dune backs and a sliver of hazy horizon sit in the upper frame (Joshua compared a 45–16° ladder and picked 19; history: 52° → 45° → 19°, see DECISIONS.md). Keeps a small vertical clearance above terrain; rotatable in 45° steps later if wanted; never free-look.
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
- Input map defined in project settings: `move_up/down/left/right` (WASD + arrows), `interact` (E) — even if unused yet. *(Phase 2 added `sprint` (shift), `jump` (space), `crouch` (ctrl or C) and `camera_zoom_in/out` (wheel).)*
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
- Movement: 8-directional WASD relative to camera, acceleration/deceleration curves (no instant start/stop), gentle rotation of the body toward move direction, `move_and_slide` on floor, gravity for slopes/ledges. Export-var tuned: max speed, accel, friction, turn speed. *(Grew during playtest into a full moveset: walk/run/crouch gaits and a jump — see the notes below.)*
- `scenes/camera/camera_rig.tscn`: separate rig scene — a `Node3D` that smoothly follows the player (lag/damping), holding the angled top-down `Camera3D` per the fixed decision. Zoom in/out on scroll wheel between sensible clamps.
- Test scene `scenes/world/graybox.tscn` with ramps, steps, and obstacles to validate slopes and collisions (kept permanently as a movement test level). *(Also gained, alongside the abilities added after the first playtest: a crouch tunnel, jumpable and too-tall ledges, and a run-only gap.)*
- Tuning documented: final values and *why they feel right* in DECISIONS.md.

**Quality Gate**
- [x] Moving in all 8 directions feels responsive but weighty; no jitter, no foot-sliding of the capsule, no camera stutter (test at 60 fps+). *(Scripted run: all 8 directions reach exactly 4.60 m/s with diagonals normalised; full speed in ~0.18 s, stop in 0.15 s; zero drift while idle. At 120 fps the player's screen position held within 0.03 px of a straight line over 180 frames while walking.)*
- [x] Slopes up to ~30° walkable, steeper blocked; no getting stuck on step edges in graybox.tscn. *(15/25/30° ramps climbed to full height; 40/50° refused. 0.25 m staircase walks up onto the landing; 0.20 m and 0.35 m curbs climb, 0.50 m refused.)*
- [x] Camera never clips geometry in the graybox scene; zoom clamps work. *(Solved by fading occluders rather than moving the camera — the camera holds 23 m at the 6 m wall, under the overhang and in the crouch tunnel, and the blocking object fades to 22% while the ground stays fully opaque. Screenshot-checked at each spot. Zoom clamps hold at 9.00 and 34.00.)*
- [x] All scripts typed GDScript, zero warnings. *(`--import`, per-script `--check-only`, and headless runs of both level scenes: no errors or warnings.)*
- [x] PLAN.md updated; merged to `development`.

**Notes for later phases**
- Tuning had one playtest pass with Joshua (2026-08-13): he asked for more weight on launches and sudden turns, and a further-out default camera. Result: acceleration 16, friction 24, turn_speed 7, new `turn_drag` 0.55, camera default 23 m (zoom 9–34).
- The moveset then grew, also at Joshua's request: **run** (hold shift, 7.4 m/s), **jump** (space, 1.1 m, with coyote time / input buffer / variable height / reduced air control) and **crouch** (ctrl or C, 1.15 m capsule, 2.0 m/s, can't stand under a ceiling). Every value is an `@export` on `player.tscn` / `camera_rig.tscn`; reasoning and measurements are in DECISIONS.md.
- A final polish pass (2026-08-13, after the gate passed) lowered the camera pitch 52° → 45° for a more cinematic read — Joshua compared 52/45/40 screenshots, played 45° and signed off. Occluder fading re-verified at the new angle. See DECISIONS.md.
- **Knock-on for Phase 3:** the animation set is no longer just idle/walk/run — jump/fall/land and crouch poses are needed too. Phase 3's deliverables have been updated.
- Camera obstruction is handled by fading, not by camera movement — the camera's distance is now purely the player's zoom. **Every new prop from Phase 6 on needs `collision_layer = 5`** (world + occluder) to be fadeable; terrain must stay on layer 1 alone so it never fades.
- `graybox.tscn` is a permanent test level; keep it working as movement changes.

## Phase 3 — Character model & animation

**Goal:** replace the capsule with the real protagonist and prove out the full Blender→Godot pipeline.

**Deliverables**
- Low-poly desert traveler modeled in Blender (via blender-mcp): head-wrap/keffiyeh, loose robes — palette colors only, target ≤ 2,500 tris. Source: `assets/blender/player.blend`; export: `assets/models/player.glb`.
- Simple rig + animations. `idle`, `walk`, `run` are the core three; Phase 2 also shipped jump and crouch, so this phase additionally needs **`jump`/`fall`/`land`** (or at least a credible airborne pose) and **`crouch_idle`/`crouch_walk`**. Root motion NOT used — animation speed matched to movement speed in code.
- `AnimationTree` with a state machine (idle↔walk↔run blended by speed) driven from `player.gd`. **The input side already exists from Phase 2**: holding shift (`sprint`) raises the target speed from `walk_speed` 4.6 to `run_speed` 7.4, so blend off the player's planar speed — not off the input — and the blend stays correct while winding up, on slopes, and mid-turn.
- Export pipeline documented in `docs/ART_DIRECTION.md` (Blender export settings, scale/orientation conventions, checklist) so every later asset follows the identical process.

**Quality Gate**
- [x] Character reads clearly at gameplay camera distance; silhouette and colors match ART_DIRECTION.md (screenshot comparison). *(Idle, walk, run, crouch and jump captured at the real 45° / 23 m camera. All read; the crouch is clearly lower than the stand and the jump reads as a leap. The character takes the warm directional light and casts a proper shadow — the fix that mattered, since the source material was fully self-lit. **Caveat for Joshua:** pale cream on pale sand is low-contrast, and the placeholder ground is a single flat `sand_light` plane; Phase 4's dune tones and shadows should help, but it's worth a look.)*
- [x] No foot-sliding at walk or run speed; blend transitions smooth, no T-pose flashes. *(`tools/verify_player.gd` against the running game: planted foot slips 14% of body speed at both 1.40 and 4.90 m/s — the two agreeing points at stance foot-roll rather than a stride mismatch. Every state entered as expected across idle→walk→crouch→stand→jump→fall→land, with a per-tick bind-pose check that never fired.)*
- [x] .blend and .glb committed; re-export from .blend reproduces the .glb byte-compatibly enough to be repeatable. *(Better than repeatable-by-hand: `tools/build_player.py` rebuilds `player.blend` and `player.glb` from the committed Meshy source in one headless command.)*
- [x] Runs in graybox scene with zero errors; PLAN.md updated; merged to `development`. *(Headless runs of `player.tscn`, `graybox.tscn` and `world.tscn` are clean, as are `--import` and per-script `--check-only`.)*

**Notes for later phases**
- **Movement speeds changed** to match the animations' own strides — Joshua's call. Final values after his playtest: `walk_speed` 4.6 → **1.8**, `run_speed` 7.4 → **4.9**, `crouch_speed` 2.0 → **1.0**, `acceleration` 16 → **12**, `friction` 24 → **14**, `turn_drag` 0.55 → **0.45**. Phase 4's terrain scale and Phase 7's tuning should assume this slower pace. The graybox run-only gap shrank 4.0 → 2.8 m to stay crossable at the shorter jump.
- **Playtested by Joshua**, who raised two things, both fixed and re-measured: stairs were not smooth (a real bug — the body was launched airborne on every tread; see DECISIONS.md) and movement felt too heavy (the 180° reversal had regressed to 0.53 s against the 0.40 s he approved in Phase 2; now 0.38 s). The final tuning was verified by measurement but he has not re-played it since.
- **`tools/verify_player.gd` is this phase's gate as a runnable script** — foot sliding, animation states, stair smoothness, level fixtures and response times. Run it after any movement change; see `docs/ARCHITECTURE.md` for the modes.
- **Crouched movement holds a pose** — the source set has no forward crouch walk (see DECISIONS.md). A few more Meshy clips (forward crouch walk, a dedicated fall and landing) would close it, and Joshua is generating a camel in Meshy for Phase 6 anyway.
- **Camera distance is untouched at 23 m.** It was chosen for a player moving nearly three times faster; still worth comparing against ~16 m.
- **The character is low-contrast against sand** — pale cream on pale ground. Phase 4's dune tones and shadows are the real test of whether it needs addressing.
- Phase 5's footstep stamping has its hook: `player.gd` emits `landed(impact_speed)` and `jumped`, and the toe bones (`LeftToeBase`/`RightToeBase`) are what `verify_player.gd` already tracks for foot contact.
- **Phase 4 watch-item:** `_try_step_up` runs every grounded tick and probes ahead. It deliberately ignores anything walkable (surfaces within `floor_max_angle`), so smooth dunes should never trigger it — but confirm that on real terrain, because a chunk seam presenting a near-vertical sliver would look like a step.

## Phase 4 — Terrain & chunk streaming

**Goal:** the open desert. Chunked, streamed, seeded — the permanent world foundation, built right the first time.

**Scope expanded at session start (Joshua):** the sand itself is a core system — variable *depth* across the map (deep drifts, thin skins over hard ground), and depth is felt in movement, not just seen. Footprint memory and wind stay in Phase 5, but the terrain is architected for them now.

**Deliverables**
- `scenes/world/terrain/` chunk system per `docs/ARCHITECTURE.md`: `chunk_manager.gd` (loads/unloads a radius of chunks around the player, builds threaded via `WorkerThreadPool`), `terrain_chunk.gd` (one chunk's mesh + `HeightMapShape3D` collision from the world-seeded noise fields).
- **Two-layer sand model** in `resources/terrain/terrain_settings.gd` + `desert.tres`: hard substrate + variable-thickness sand layer (the dunes *are* the sand), with analytic queries `get_surface_height` / `get_base_height` / `get_sand_depth` that work anywhere, loaded or not.
- Chunk size and radius chosen by profiling (64 m chunks, 5×5 loaded / unload at 7×7), generation off the main thread, installs time-budgeted so streaming never hitches.
- Dunes: wind-stretched dune waves + drift patchiness + ripples that fade where sand is thin; flat-shaded via derivative normals in `shaders/sand_terrain.gdshader`; vertex-color sand-tone gradient with patchy dither; vertex alpha carries normalised sand depth for Phase 5's print-depth cap.
- **Deep sand affects movement**: speed multiplier, softened jump, visible foot-sink — all keyed off `get_sand_depth`, all inert off-terrain (graybox unchanged).
- Far-field: **warm distance haze + load radius 5** — the far dunes melt into the horizon before the streaming edge, which stays invisible (screenshot-verified). At the original 45° camera nothing at all was needed; the 19° pick changed that (see DECISIONS.md).
- Debug overlay (toggle with F3): current chunk coords, loaded/building counts, streaming cost, frame time, memory.
- Player + camera dropped into the real desert as the new main scene flow, spawn-seated on the surface after a synchronous first build.
- `tools/verify_terrain.gd`: determinism/seams/slope/depth audits, collision-vs-mesh raycast audit, 2 km streaming walk, deep-sand movement checks.

**Quality Gate**
- [ ] Walk continuously in one direction for 2+ km of world distance: no hitches > 4 ms from streaming, no visible pop-in gaps or seams between chunks, memory stable (chunks actually unload).
- [ ] Same seed ⇒ identical terrain across runs; different seed ⇒ different desert.
- [ ] Collision matches visuals — player never floats or sinks on any dune.
- [ ] 60 fps+ on this Mac at default window size with full load radius.
- [ ] PLAN.md updated; merged to `development`.

## Phase 5 — Sand footprint physics (expanded with the sand-memory vision)

**Goal:** the signature feature — the sand *remembers*. The player (and later anything else) leaves footprints and trails that persist believably, are deeper where the sand is deeper, and are slowly erased as wind refills them.

**Memory model — "long but local" (decided with Joshua in the Phase 4 planning session):** a large deformation region around the player remembers prints for several minutes; walk a long way off and distant prints quietly reset. Prints are *not* per-chunk persistent world state — that was considered and deferred (cost/complexity vs. payoff; revisit if the trail-behind-you ever needs to survive a kilometre round trip).

**Planned approach** (validate with a prototype first, record final in DECISIONS.md): a "sand deformation" texture accumulated in a `SubViewport` whose region follows the player in snapped increments — footstep brushes stamped as the character walks — sampled by `shaders/sand_terrain.gdshader` (extended with deformation uniforms, not swapped) for vertex depression + a darker compacted tint toward `sand_shadow`. Texture slowly decays = wind refilling prints. Distant chunks keep zero-strength uniforms and cost nothing.

**Phase 4 already shipped the hooks:** vertex `COLOR.a` carries normalised sand depth, so the shader caps print depth by the sand that is actually there (shallow sand ⇒ faint prints, hard ground ⇒ none); `get_sand_depth` says how deep any stamp may go; `player.gd` emits `jumped`/`landed(impact_speed)` and its toe bones are already tracked by verify tooling; the movement/sink feel of deep sand is done.

**Deliverables**
- The SubViewport stamping rig + deformation uniforms in `sand_terrain.gdshader`, integrated with the chunk terrain.
- Footstep stamps timed to the walk/run animation (alternating left/right), scaled by local sand depth; a soft drag trail when moving; a deeper landing stamp off `landed(impact_speed)`.
- Decay: prints visibly soften and vanish over minutes (tunable export var), reading as wind-blown refill.
- **Wind as a first idea, not a system:** decay direction/rate may lean with the terrain's `wind_yaw_degrees` so prints fade the way the dunes lie; a real wind-blows-sand-up system is future work, but nothing here may block it.
- Hooks for the future: any object (camel, dragged items) can register as a "sand stamper" — small, clean interface.

**Quality Gate**
- [ ] Footprints visually match foot placement at walk and run; look correct from the gameplay camera in both direct light and shadow.
- [ ] Print depth visibly varies with sand depth: a trail crossing deep drift → thin skin → hard ground reads deep → faint → gone.
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
