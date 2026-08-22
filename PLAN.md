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
| 4 | Terrain & chunk streaming | `feature/phase-4-terrain` | ✅ Done (2026-08-13) |
| 5 | Sand footprint physics | `feature/phase-5-footprints` | ✅ Done (2026-08-14) |
| 6 | Environment assets (house & camel) | `feature/phase-6-environment` | 🟡 In progress — Part 1 + door/interaction system done (awaiting look review), Part 2 needs Meshy assets |
| 6.5 | Game clock, day-night cycle & lighting (side-track) | `feature/daynight-lighting` | 🟡 In progress — clock ✅; cycle ✅; lighting built & verified 2026-08-15 (lamp, torch, flames, real windows), awaiting flicker playtest |
| 6.6 | Audio system (side-track) | `feature/audio-system` | 🟡 Engine done; first sound batch in & mix approved by ear 2026-08-15 (sand steps, doors, wind, music); pause menu (Esc) + settings audio sliders + UI sounds in 2026-08-15. Remaining: fire/landing/shuffle/indoor sounds, then final listen-through |
| 6.7 | Ocean biome — the western sea | `feature/ocean-biome` | 🟡 Part 1 ✅ **signed off by Joshua 2026-08-22** ("water test is good") — hard gate lifted, branch pushed to GitHub. Water keeps its palette-only defaults. Only the merge to `development` remains, blocked on the 6.5 → 6.6 chain. Ocean grows later per roadmap: depth/swimming, sound FX, submarine & vehicle mechanics |
| 6.8 | The sand worm — desert mob | `feature/sand-worm` | 🟡 Part 1 build started 2026-08-22 (Joshua's go) — branched off `feature/ocean-biome`, merges after 6.7. Death design still deferred to Part 3 planning |
| 7 | Integration & polish → v0.1 | `feature/phase-7-polish` | 🔲 Not started |

Status legend: 🔲 Not started · 🟡 In progress · 🧪 In testing on `development` · ✅ Done (merged, gate passed)

**Later (out of scope for now):** survival systems (hunger/thirst/heat), inventory, NPCs/dialogue, save games, sound design. Do not build these early "while we're in there" — but do leave clean extension points. *(The day-night cycle was on this list; Joshua pulled it forward on 2026-08-14 — see Phase 6.5. Save games likewise, 2026-08-15 — see the Phase 6.6 detour notes.)*

---

## Vision & pillars

1. **Cozy, not hostile.** The desert is beautiful and calm. Even when survival mechanics arrive later, the tone stays warm.
2. **Uniform look.** Low-poly, flat-shaded, every material sampled from the fixed palette in `docs/ART_DIRECTION.md`. No stray colors, no photo textures.
3. **The sand is alive.** Footprints, trails, and wind-shaped dunes make the ground itself the most memorable "character."
4. **Open world from day one.** The map is large, so terrain is chunked and streamed from the very first terrain implementation — never a single big mesh we'd have to retrofit.

## Fixed decisions (do not re-litigate in later sessions)

- **Engine:** Godot 4.7.1, Forward+ renderer. Repo root **is** the Godot project root.
- **Camera:** angled perspective camera, narrow FOV (~35°) for the "toy diorama" feel, pitched **19°** down since Phase 4 — low enough that dune backs and a sliver of hazy horizon sit in the upper frame (Joshua compared a 45–16° ladder and picked 19; history: 52° → 45° → 19°, see DECISIONS.md). Keeps a small vertical clearance above terrain. **Freely orbits 360° around the player on a left-click drag** (Joshua's call, 2026-08-14 — supersedes the earlier "45° steps if wanted"). **The pitch stays fixed**: this is a turntable, not free-look, so the diorama framing can never be lost.
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
- [x] Walk continuously in one direction for 2+ km of world distance: no hitches > 4 ms from streaming, no visible pop-in gaps or seams between chunks, memory stable (chunks actually unload). *(`verify_terrain --walk`, headless and windowed at the final radius 5: worst chunk-install cost 1.27 ms in any frame; chunk count plateaus at 132 within the 13×13 unload ring; memory +0.9 MB over the full 2 km; step-up never fired on terrain. Seams impossible by construction — shared edges bit-identical, asserted every run.)*
- [x] Same seed ⇒ identical terrain across runs; different seed ⇒ different desert. *(Byte-identical double-build with a printable world hash; different seed produces a different hash.)*
- [x] Collision matches visuals — player never floats or sinks on any dune. *(2,000-ray audit: raycasts land on the rendered mesh to 0.0000 m — HeightMapShape3D and the mesh share the same cell diagonal — and within 5 cm of the analytic field, the documented curvature bound.)*
- [x] 60 fps+ on this Mac at default window size with full load radius. *(~185 fps average over the windowed 2 km walk; 67 of 76,396 frames exceeded 16.8 ms, every one with streaming idle and attributed to macOS window-server activity, including the documented occluded-window stall.)*
- [x] PLAN.md updated; merged to `development`.

**Notes for later phases**
- **The camera changed mid-phase, at Joshua's request:** pitch 45° → **19°** (his pick from a seven-rung screenshot ladder), which brought load radius 5, the warm distance haze, and a terrain-clearance lift on the rig — see DECISIONS.md. **Joshua has not yet played** the 19° camera, the deep-sand movement feel, or the Phase 3 final tuning — the first minutes of Phase 5 (or a quick session before it) should be a playtest.
- The Phase 3 pale-character-on-pale-sand worry mostly resolved itself at 19°: the figure now reads against midground amber dunes rather than pale ground. Judge finally in the Phase 7 pass.
- Watch in playtest: whether dune crests hiding the player at 19° (rare by design) actually bothers, and whether the camera's Y-follow bobs on dune slopes at run speed (the flagged fix is a separate vertical follow damping on CameraRig).
- Phase 5 hooks shipped and verified: `COLOR.a` = normalised sand depth per vertex, `get_sand_depth` everywhere, `jumped`/`landed(impact_speed)` signals, deformation extends `sand_terrain.gdshader` in place.
- Phase 6 props: remember `collision_layer = 5` (fadeable) — terrain stays layer 1 alone. Prop scattering should key off `get_sand_depth` (palms want shallow sand near hard ground, not dune bodies).
- The sand ripples read as soft mottle rather than crisp ripples at the gameplay camera; acceptable now, revisit when Phase 5's prints add surface detail.

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
- [x] Footprints visually match foot placement at walk and run; look correct from the gameplay camera in both direct light and shadow. *(Stamps come from the toe bones at the measured foot-plant moment; `verify_prints` asserts every footfall reads back from the deformation texture at the bone's position and the sand off-trail stays clean. Screenshot-checked at the gameplay camera on lit sand and across the shadowed dune band; Joshua reviewed the look on the Footprint Ladder and approved darkness 0.55 / depth 0.12 m.)*
- [x] Print depth visibly varies with sand depth: a trail crossing deep drift → thin skin → hard ground reads deep → faint → gone. *(Scripted 42 m walk from a 1.52 m drift down to 0.65 m skin, screenshot-verified: bold prints fading along the depth gradient. The cap saturates at 0.3 m of sand and hits zero on bare ground by construction — vertex alpha carries the depth, `tools/shoot_prints.gd` reproduces the evidence.)*
- [x] No shimmer/artifacts at the deformation region boundary as it follows the player across chunk borders. *(Recentres move the region in whole texels only, so carried content is copied texel-for-texel, never resampled — `verify_prints` asserts a marked point survives repeated recentres bit-cleanly, and an isolation harness held a stamp through 6 recentres at 0.998→0.984 (pure decay). The wind drift shares the same whole-texel mechanism.)*
- [x] Frame cost of the whole system ≤ 1 ms on this Mac; zero cost when standing still. *(`verify_prints`: worst main-thread pass 0.8 ms across ~690 passes — and a pass only runs when something changed; the harness asserts the pass counter stops climbing once prints have fully faded, so standing still costs exactly zero.)*
- [x] Prints fade smoothly; walking a circle and returning shows believable partial fading. *(Scripted octagon loop on deep sand: at the moment of return the oldest prints are already visibly softer than the newest — a fade gradient around one loop — and 90 s later the loop is mostly refilled, its remnant drifted slightly downwind. Decay-to-empty and return-to-zero-cost are asserted by `verify_prints`.)*
- [x] PLAN.md updated; merged to `development`.

**Notes for later phases**
- **The stamper interface is one signal + one connect:** a stamper emits `stamped(world_xz, radius, strength, angle, stretch)`, the level connects it to `SandDeformation.stamp()`. Phase 6's camel gets tracks by giving it a stamper child (its own gait logic) and one `connect` in the level — see `scenes/player/footstep_stamper.gd` as the worked example.
- **Tuning approved by Joshua (2026-08-14)** from the Footprint Ladder: `tint_strength` 0.55, `max_print_depth` 0.12 m, `fade_seconds` 180. All exports on `SandDeformation`.
- **Biome readiness is a recorded contract** (DECISIONS 2026-08-14): prints gate on vertex COLOR.a = depressible depth (material-agnostic), and the deformation texture's G channel is reserved for future per-material decay classes. Don't repurpose it.
- **verify tooling:** `tools/verify_prints.gd` (windowed) is the phase gate as an executable; `tools/shoot_prints.gd` and `tools/shoot_print_ladder.gd` reproduce the visual evidence. Wind drift moves prints by design — tests probing fixed points must disable it (the harness does).
- The crouch leaves no prints (crouched feet never "plant" — they slide); consistent with the Phase 3 crouch-walk gap, worth revisiting if crouch clips ever arrive.

## Phase 6 — Environment assets (house & camel)

**Goal:** populate the desert with its first landmarks and life, all through the Phase 3 asset pipeline.

**Restructured into two parts at Joshua's direction (2026-08-14):** the house and the building/interior *systems* come first and are hand-modelled in Blender; the camel becomes Part 2, waiting on a Meshy generation. Both parts share the branch `feature/phase-6-environment`; the quality gate closes and merges after Part 2.

**Two design calls made at planning time, both Joshua's:**
- **The interior is enterable now, with a roof-off cutaway** rather than a blocked door. The camera never moves to dodge geometry (fixed decision), so an indoor player is served by hiding everything above their story. Built as a reusable system, not a house feature — every future building gets it free.
- **Every interior item is an independent, reusable asset** — its own `.blend`, `.glb` and scene folder. The house shell ships empty and *instances* furnishings. This is what lets a bed, rug or tapestry appear in any future building, become interactable on its own later, and be rearranged without re-exporting the house.

**Reference-anchored:** Joshua supplied two screenshots (2026-08-14) that set the look — a two-story ochre adobe cube with protruding roof beams (vigas), an external stair and a cloth door awning; and a ground-floor **majlis** with low striped seating around a patterned rug, poufs, low table and hookah. They anchor proportion and silhouette; everything is rebuilt in our palette and flat-shaded low-poly rules, never copied.

### Part 1 — House & building/interior systems

**Deliverables**
- **Homestead POI flattening** in `resources/terrain/terrain_settings.gd`: a deterministic site chosen near spawn, with the analytic field blended flat inside it and sand thinned to packed courtyard earth. Because mesh, collision, spawn seating, print-depth capping and the camera lift all sample the same functions, they inherit it for free — the "POI injection at generation time" hook ARCHITECTURE.md reserved.
- **Desert house** via `tools/build_house.py` (committed headless Blender script, per the `build_player.py` pattern and the ART_DIRECTION export checklist): two-story adobe, gently irregular walls, flat roof + parapet, vigas, wood-framed windows, cloth awning over the door, external stair to the roof terrace. Palette materials only, ≤ 4,000 tris soft cap. Story slabs and roof are separately named objects so the cutaway can hide them.
- **Reusable furnishing library** via `tools/build_furnishings.py`: `low_sofa`, `pouf`, `floor_cushion`, `low_table`, `rug`, `hookah`, `oil_lamp`, `curtain`, `bed`, `tapestry`, `pottery` — each ≤ 500 tris, each its own asset and scene folder.
- **`scenes/props/house/`** — `house.tscn`/`house.gd` with hand-authored collision (walls `collision_layer = 5` fadeable; slabs and roof on layer 1 only, so the occluder fader never fights the cutaway for the same `transparency` property).
- **`scenes/props/interior_cutaway.gd`** (`InteriorCutaway`) — story-aware: an `Area3D` per story, exported lists of the visuals above it, smooth fade out on entry and back on exit.
- **`scenes/world/homestead.tscn`** — house plus furnishing instances, spawned by `LevelRoot` at the seeded homestead centre; player start moves to the courtyard.
- **Doors & interaction** *(added at Joshua's direction, 2026-08-14)*: a built-in interaction mechanic (`Interactable` on the prop + `Interactor` on the player, E to use, floating prompt) and a reusable `Door` prop (`tools/build_door.py` → `scenes/props/door/`) that swings away from whoever opens it. Both house doorways get one; every future building reuses both systems as-is.

**Part 1 exit bar**
- [x] `tools/verify_house.gd` passes: doorway passable at walk and run, walls block, stair climbs, cutaway fires on entry and exit with roof transparency asserted, the interior floor clears the sand, and four approach lanes get through at both the door and the stair. *(It earned its keep three times over — every bug below was found by it rather than by looking.)*
- [x] `verify_terrain` (all modes) and `verify_player` still pass — flattening did not break determinism, seams or the slope audit. *(World hash unchanged; homestead pad holds 0.084 m of relief with an 11.5° approach against the 31° limit; collision still 0.0000 m off the mesh and 0.047 m off the analytic field. The collision audit learned to ignore rays that land on the homestead — buildings share the world layer, and a ray hitting a roof is not evidence about `HeightMapShape3D`.)*
- [ ] Screenshots at the gameplay camera reviewed by Joshua (approach, doorway, interior with cutaway — now including the closed door and the swung-open leaf). **← the one thing outstanding in Part 1.** Shots are committed at `docs/references/ingame_*.png`.
- [x] Doors work as a mechanic, verified by `verify_house`: the closed front door blocks at walk speed, E opens it (swinging away from the opener), the doorway then passes every lane at both gaits, E from inside closes it and the closed leaf holds the player in, and the upper door admits the player to the upper storey from the stair head. Prompt text flips Open/Close with state; layer audit covers both doors and their interaction volumes.
- [x] Performance with the homestead on screen: 119 fps average, worst frame 8.55 ms over 600 windowed frames — no measurable cost from the building, its thirteen static bodies or the cutaway.
- [x] Zero errors/warnings: headless `--import`, per-script `--check-only`, standalone scene runs. *(One exception, recorded in DECISIONS: a bounded 2–3 instance ObjectDB warning at engine shutdown that appears only with the house present and the player spawning near it. Bisected away from every system involved; does not grow with run length; no gameplay effect.)*

**Handoff notes (2026-08-14)**

Part 1 is complete and verified, and Joshua has played it. Three things came out of that playtest and are all fixed and committed — worth reading before touching movement or building geometry, because two of them are general rules rather than one-off bugs:

1. **The camera now orbits 360° on a left-click drag** (his request, raised as "sooner than later" and correctly so — judging any building depends on being able to walk round it). Yaw is free, **pitch stays fixed**: it is a turntable, not free-look, so the diorama framing can't be lost and the camera can't be driven into a dune. `orbit_sensitivity` and `invert_orbit` are exports if the feel needs tuning. `verify_player --orbit` guards the camera-relative movement contract.
2. **"The floor is sand"** — and the material was never the cause. The slab sat flush with the terrain and the desert stood *above* it at 193 of 195 points across the footprint. Ripples now fade out on the homestead pad (relief 0.084 m → 0.000 m) and the floor is lifted 0.12 m. That lift then shut the front door, because a doorway must clear the player's height *plus* the step-up lift above any threshold; `DOOR_H` is 2.40 m.
3. **"I get hung up on ledges and stairs"** — the step-up probe was being defeated by contact the body was only sliding along, so a doorway with 0.20 m of slack gave 0.12 m you could actually walk through. The probe now runs 7 cm slimmer (`step_probe_slim`) with its reach widened to match; usable doorway width went to 0.50 m. Geometry was widened too (`DOOR_W` 1.30 m, `STAIR_W` 1.50 m). **Every Phase 3 movement number is unchanged.**

**Two constraints now bind every building we ever make**, both in ART_DIRECTION's modelling rules: stair treads must exceed ~0.41 m, and doorways need ~1.2 m of clear width plus the player's height *plus* 0.35 m of headroom above any threshold. Both produced geometry that looked perfect and could not be entered.

**Continuation session (2026-08-14, same day): doors and the interaction mechanic.** Joshua asked for openable doors on every structure, built as a real system rather than house code. What shipped: the `Interactable`/`Interactor` pair on new physics layer 4 (E to use, one signal to connect a prop), the reusable `Door` prop (own `.blend`/`.glb`, hinge-origin leaf, hand-authored box collision on an `AnimatableBody3D`, swings away from the opener), and doors in both house doorways. One engine trap cost a debugging round and is recorded in DECISIONS and ARCHITECTURE: `AnimatableBody3D`'s default `sync_to_physics = true` ignores ancestor moves, so the door's collision was left 90 m behind when the level placed the homestead — doors were visible but intangible. `verify_house` gained the full door gauntlet and everything passes; `verify_player` (all modes) and `verify_terrain` still pass. The review screenshots now include `ingame_door_closed.png` / `ingame_door_open.png`.

**Second playtest round (2026-08-14, Joshua):** two asks, both done. (1) The on-screen "E — Open" prompt is **removed** — players know how to interact; the `prompt` string survives unrendered as the harness/accessibility hook. (2) "Still hung up on ledges and some stairs" — a twelve-scenario measurement sweep found the doorway fine but the stair broken for any approach 15–20° off axis: deflected off the flight, jammed at its foot in the wall/parapet corners, and (the surprise) *walking over the parapet near the stair head and falling off the flight*, because the rail's straight-line top sagged to ~0.15 m above the treads there. Three fixes, in DECISIONS: the step probe measures along input → velocity → square-on against each blocked face; a low-momentum step also advances the body onto the tread it measured (ends the step-then-slide-back jam loop); and the parapet profile got its knee at the stair head. `verify_house._stair_drift_climbs` now gates six angled/wall-pressed climbs (4 of 6 failed before the fixes; all pass now). Every Phase 3 feel/stair number is byte-identical.

What exists now:

- **The house** (`tools/build_house.py` → `house.blend`/`house.glb`, 2,136 tris) — two storeys, vigas, wood-framed windows, cloth awning, external stair to an upper-floor door. Wall tone is one constant with a `--wall <palette>` override that renders a comparison ladder without touching the committed asset, if Joshua wants to see alternatives to `clay`. In-engine, clay reads well against the sand — better than the Blender previews suggested, so no ladder was forced.
- **`InteriorCutaway`** — reusable for every future building; nothing per-storey to configure.
- **Ten furnishing assets**, each independent and reusable, placed as a majlis downstairs and a bedroom upstairs.
- **The homestead POI** — a levelled pad at a seeded site, with the player spawning in its courtyard.

Loose ends worth knowing about, none blocking:
- The **roof is decorative** — the stair stops at the upper-floor landing. Roof access is a future addition (a second short flight, or a stairhead).
- The interior is lit only by ambient and what comes through the door and windows. It reads fine at the gameplay camera; if it ever feels gloomy, the oil lamp is the obvious place to hang a small `OmniLight3D`.
- **Per-prop `.tscn` wrappers do not exist yet** — furnishings are instanced from their `.glb` directly. When a prop first needs behaviour (an interactable lamp), that is the moment to add `scenes/props/<name>/<name>.tscn`.
- No date palm, well or rocks yet; Joshua chose to pick small props as we go.
- **The wall tone has not been laddered.** It is `clay`, and in engine it holds up against the sand better than the Blender previews suggested, so no ladder was forced. `build_house.py --wall <palette name>` renders a comparison set without touching the committed asset if Joshua ever wants to compare.
- **A bounded ObjectDB warning at engine shutdown** (2–3 instances, only with the house present and the player spawning near it). Bisected away from every system involved; does not grow with run length; no gameplay effect. Recorded in DECISIONS rather than chased further.

**Desert restyle (2026-08-14, between Parts 1 and 2, Joshua's direction):** the desert now matches his Shaybah reference photo. Three ladder picks, all verified and committed: **Shaybah-orange sand trio** (`#EFA254`/`#D97E2E`/`#A85419` — ART_DIRECTION's palette table updated), **crisp wind-ripple shading** (new, in `sand_terrain.gdshader` — shading only, collision untouched), and a **15 m mega-dune field** under the ordinary dunes (`mega_*` in terrain settings). Full verify suite green afterwards: slope worst 26.63° vs the 31° budget, collision/streaming/sand audits, house gauntlet, player and prints. The world hash changed by design (terrain gained an octave); the homestead re-seats itself. `tools/shoot_desert_look.gd` renders the whole comparison ladder again if any value needs revisiting. Watch-items for the Phase 6 gate: one cohesion look at the homestead against the new orange (props were palette-picked against cream sand), and whether the haze should warm up now that distant mega-crests sit in it. Details in DECISIONS.

### Part 2 — Camel & the missing player clips

Blocked on Joshua generating in Meshy: a rigged **camel** (`idle` + `walk`) and the **player clips** Phase 3 left missing (forward crouch-walk, a real fall, a landing). *(Added 2026-08-15 from the Phase 6.5 torch work: a **torch-carry clip** — or idle/walk variants with the right arm raised holding something — so the carried torch stops riding a hanging-arm pose; the grip transform is tuned as far as geometry can take it.)*

**Deliverables**
- **Camel** conditioned by `tools/build_camel.py` per the imported-asset audit (facing, emission/material fixes, texture downscale, `measure_gaits` stride numbers, root-motion check), ≤ 3,000 tris target.
- `scenes/props/camel/camel.tscn` + `camel.gd`: ambles within a home radius, avoids the house, animates off planar speed (the Phase 3 pattern), never intersects house or player, `collision_layer = 5`.
- **Camel tracks** via its own stamper child + one `connect` — exactly what the Phase 5 stamper interface was built for.
- **Player clips folded in**: rebuild through `build_player.py`, wire into the AnimationTree, closing the known crouch foot-slide gap; re-measure gaits and retune `crouch_speed`.
- Small props chosen as-we-go with Joshua (well, palms, rocks…); chunk-scattered vegetation keys off `get_sand_depth` when scatter props exist.

**Quality Gate** (whole phase)
- [ ] Screenshot of the homestead at gameplay angle looks cohesive — one style, one palette, cozy (side-by-side check against ART_DIRECTION.md).
- [ ] Camel wanders, animates without sliding, leaves believable tracks, never intersects the house or player.
- [ ] All assets: .blend + .glb committed, correct collision, no errors, stable 60 fps+ with everything on screen.
- [ ] Interior reads clearly at the gameplay camera: walking in and out never leaves the player hidden or the roof stuck faded.
- [ ] PLAN.md updated; merged to `development`.

## Phase 6.5 — Game clock, day-night cycle & lighting enhancements (side-track)

**Added 2026-08-14 at Joshua's direction** — a deliberate stray from the original roadmap while he generates Phase 6 Part 2 assets in parallel. The day-night cycle was on the "later" list; it moves up now. Three pieces, each **planned out with Joshua before any build**, tackled strictly in order (each is the foundation of the next):

1. **Game clock** — the timekeeping backbone: time-of-day state, tunable day length, signals for anything that reacts to time. No visuals of its own; everything later (sun, sky, lamps, future survival mechanics) reads from this one source.
2. **Day-night cycle** — the sun actually travels: sun angle/color/energy, sky gradient, ambient and haze all keyed to the clock, so dawn, noon, dusk and night each read correctly in the palette.
3. **Lighting enhancements** — the polish layer the cycle exposes: interior light (the oil lamp finally earns its `OmniLight3D`), shadow tuning, night visibility, whatever laddering the cycle reveals. This subsumes part of Phase 7's "full lighting pass" — record what's covered so Phase 7 reconciles rather than redoes. *(Scope grew with the night pick, 2026-08-15: night is **properly dark by design**, so piece 3 must deliver a **carried light source** (torch/lamp in hand) as the way to move through it — Joshua wants torches to be useful and night to carry a little horror.)*

Deliverables and a quality gate are filled in **per piece at its planning session** (this keeps the phase honest — no gate written before the design conversation that defines it).

### Piece 1 — Game clock (planned & built 2026-08-14; gate passed)

**Joshua's three calls at planning:** one full day = **24 real minutes** (1 real minute = 1 game hour); the game starts at **16:00** so every launch opens on the signature golden-hour look; time readout is **debug-only** (F3 overlay + debug keys — no HUD clock until a real UI phase).

**Design (the plain-terms version):** the clock is a small piece of *game state*, not a lighting feature — so it lives in the existing `Game` autoload, which Phase 1 explicitly reserved for exactly this kind of growth (no new autoload needed). Everything that reacts to time — the sun in piece 2, the oil lamp in piece 3, survival mechanics someday — reads from this one source, so time can never disagree with itself.

**Deliverables**
- `autoload/game.gd` grows the clock: `time_of_day` in hours (0–24, wraps; `day_count` increments at midnight), advancing every frame scaled by `day_length_minutes` (24.0), starting at `start_hour` (16.0). All tunables typed vars with the usual export treatment.
- Helpers the later pieces were designed against: `normalized_time` (0–1 around the full day), `is_daytime`, and a formatted `clock_text` ("16:42") for overlays.
- Signals for *discrete* reactions: `hour_passed(hour: int)` and `period_changed(period)` over four named periods (night / dawn / day / dusk, boundaries as constants). Continuous consumers (the moving sun) sample `time_of_day` directly each frame — smooth motion never rides on signals.
- Clock ticks in `_process` (it isn't physical, and this makes it respect pause for free); `time_paused` bool for cutscene/debug freezing.
- Debug affordances: current time + day on the F3 overlay, plus `debug_time_forward`/`debug_time_back` input actions (scrub time quickly) — essential for piece 2's lighting ladders as much as for testing.
- `tools/verify_clock.gd` (headless): a scaled run asserts the day length lands within tolerance, wrap increments `day_count`, `hour_passed` fires exactly once per hour in order, `period_changed` fires at the constant boundaries, and pausing halts time.

**Quality gate** *(all verified 2026-08-14 by `tools/verify_clock.gd` — headless, instantiates the clock and drives it through a simulated day of 60 Hz frames)*
- [x] A full day takes 24±0.1 real minutes; launch shows 16:00; midnight wrap increments `day_count`. *(Simulated frame time to the 24th `hour_passed`: 24.000 real minutes; launch state 16:00 / day 0 / "day" asserted.)*
- [x] Signals fire exactly once per boundary, in order, including across the midnight wrap. *(All 24 hours in order 17→16; period trail exactly dusk→night→dawn→day; landing exactly on a boundary fires once and never re-fires.)*
- [x] F3 overlay shows time/day; debug scrub keys move time both ways; `time_paused` freezes it. *(The overlay scene renders "time 09:30 day 0 day" from a clock instance; the scrub test injects real `]`/`[` key events through `Input.parse_input_event`, so the project.godot InputMap bindings themselves are what passed; pause held 16:00 through 600 frames while scrub deliberately still works.)*
- [x] Zero warnings (`--check-only`), `--import` clean, graybox and world both still run standalone; `verify_player`/`verify_terrain` untouched and green. *(All re-run after the change.)*
- [x] DECISIONS.md entry: the clock lives in `Game` (why no new node/autoload), day length + start hour rationale.

**Constraints already binding on the planning sessions:**
- The palette rule holds at night: night tones lean on `night_blue`; any genuinely new color (a night sky, moonlight) is an ART_DIRECTION discussion + DECISIONS entry, not an improvisation.
- The 19° camera's warm distance haze is tuned for late afternoon; the cycle must keep the horizon melt (real terrain dissolving into sky) working at every hour — the streaming edge must never become visible at night.
- The "warm late-afternoon" identity in ART_DIRECTION is the game's signature look; the cycle should treat it as the golden hour the day passes *through*, not discard it.
- Visual tuning (sky colors, sun angles, night darkness) goes through same-vantage screenshot ladders for Joshua's picks, per the established pattern.

**Planning status:** clock ✅ built & verified · cycle ✅ built, verified & picked (properly dark) · lighting 🟡 built & verified, awaiting Joshua's flicker playtest

### Piece 3 — Lighting enhancements (planned 2026-08-15 with Joshua)

**Joshua's calls at planning:** flame flicker matters ("the flicker of a flame looking really good"); the house should **glow from inside through the windows** when the oil lamp is lit at night; the torch is **taken from a stand at the homestead** (E takes it, E returns it — being caught in the dark far from home is part of the game); the oil lamp is **lit by the player** (E, dark until someone lights it); the night sky gets **subtle stars**. He consistently picked the interactive option over the convenient one — light is something you do.

**Deliverables**
- **`FlameLight`** (`scenes/props/flame_light.gd`, reusable component): OmniLight3D + small flame visual, noise-driven flicker (energy + position dance, never a strobe), warm palette color, `lit` switch. One component serves lamp, torch, and any future campfire.
- **Oil lamp becomes a real prop** — the first per-prop scene wrapper, exactly as the Part 1 handoff notes reserved: `scenes/props/oil_lamp/oil_lamp.tscn` + script wrapping the existing glb, with a FlameLight and an Interactable (Light/Snuff). Shadows on, so the lit lamp spills real light through the door and window openings — the glow-from-outside moment.
- **Torch + stand** via `tools/build_torch.py` (≤ 500 tris each): a wall-mounted or free-standing torch stand by the house door holding a torch; E takes the torch into the player's hand (bone attachment), E at the stand returns it. The stand uses the standard Interactable; the player script stays untouched.
- **Stars**: the sky becomes a small custom sky shader reproducing today's four-color gradient exactly, plus a sparse procedural starfield faded in by the cycle after dusk and out at dawn (`star_strength` driven like every other keyframed value). *(Built and verified — but measured invisible in normal play: the fixed 19°/35° camera tops out 1.5° above horizontal, where the horizon is always fog-melted terrain by design. The starfield stays in the shader, free and correct, for any future view that tilts up. See DECISIONS.)*
- **`tools/verify_lighting.gd`**: lamp lights and snuffs via real interaction; torch is taken and returned and its light truly travels with the player; flicker stays inside bounds (no strobe, no dead flame while lit); stars are zero by day and present at night; the 16:00 golden-hour reproduction still holds after the sky-shader swap.
- Night screenshots at the gameplay camera: lamp-lit house from outside, torch-lit walk in the dark.

**Quality gate**
- [x] `verify_lighting` passes; `verify_cycle` (incl. 16:00 reproduction + fog contract) still passes after the sky swap; `verify_clock`, `verify_player`, `verify_terrain`, `verify_house` all still green. *(Full battery re-run 2026-08-15, all green. verify_lighting drives real E-key interaction: lamp lights/snuffs with prompt tracking, torch take/carry/return with the light truly travelling, flicker bounded and alive, stars zero by day / full at deep night.)*
- [x] The glow-from-outside screenshot reads: lit windows and doorway visible from the courtyard at night, dark when the lamp is snuffed. *(The majlis window burns warm through the real opening — Joshua's mid-build call made windows actual holes; the recess panels are gone from `build_house.py` and `verify_house` still passes on the rebuilt model.)*
- [ ] Flame flicker approved by Joshua in the running game (feel, not measurable). **← the open item: playtest.**
- [x] Performance: no measurable regression with lamp + torch lit and shadows on. *(120 fps average, worst frame 10.78 ms measured with both shadowed flames burning at night — at the baseline.)*
- [x] Zero warnings; standalone scene runs clean; docs updated (ART_DIRECTION gains the flame/emissive rule + real-openings rule, DECISIONS the choices and the two traps).

### Piece 2 — Day-night cycle (planned 2026-08-14 with Joshua)

**Joshua's call at planning:** night's character (cozy moonlit vs. properly dark) is **not decided in the abstract** — the cycle ships with night darkness as a tunable, and he picks from a same-vantage screenshot ladder before the values lock.

**Design:** a script on `desert_environment.tscn` (scene-owned, per convention) samples `Game.time_of_day` every frame and drives everything the scene already contains — Sun rotation/color/energy, the four `ProceduralSkyMaterial` colors, fog color — plus a new dim, cool Moon `DirectionalLight3D` for night. Ambient follows the sky automatically (the Environment's ambient source is already the sky background). Two hard constraints: **16:00 must reproduce today's committed golden-hour light exactly** (sun at 40° elevation / 30° yaw, `#FFE9C4`, energy 1.2, today's sky colors — the arc is calibrated backward from this anchor), and **fog color stays locked to the sky horizon color at every hour** so the streaming edge stays melted into the haze all night (the Phase 4 horizon contract). The sun's disc is never in frame at the 19° camera — the sky is a sliver — so the cycle is purely light and color: no sun/moon discs, no stars (revisit in piece 3 if the night band feels empty).

**Deliverables**
- `scenes/world/desert_environment.gd` (`DesertEnvironment`): keyframed lighting table (night → dawn → day → golden 16:00 anchor → dusk → night) with linear blends and midnight wrap; sun arc (elevation/azimuth) solved from the 16:00 calibration; sunrise/sunset at the clock's constants; guarded `/root/Game` fetch with a 16:00 standalone fallback.
- Moon light during night hours with soft shadows, energy scaled by `night_darkness`; sun hidden below the horizon.
- `night_darkness` 0–1 export blending the whole night look between a bright-moonlit anchor and a properly-dark anchor — the ladder's axis.
- `tools/verify_cycle.gd` (headless gate): standalone scene reproduces the committed 16:00 values exactly; a full-day fine-step sweep shows no discontinuities in sun direction, color, or energy; fog == sky horizon at every step; sun never lit below the horizon; moon never lit by day; darkness rungs order night luminance monotonically.
- `tools/shoot_daynight.gd` (windowed): same-vantage day sweep (sunrise → noon → golden → sunset → night) + night darkness rungs for the ladder.
- After Joshua's picks: lighting-palette additions documented in ART_DIRECTION, DECISIONS entry, values locked.

**Quality gate**
- [x] `verify_cycle` passes (16:00 reproduction, continuity, fog contract, sun/moon discipline, darkness monotonicity). *(Full-day sweep at 0.005 h steps: worst sun step 0.111°, color step 0.0036, energy step 0.007 — all far under the pop thresholds; the standalone scene reproduces the committed golden-hour values exactly, which is also the no-Game fallback test.)*
- [x] Joshua picks night darkness (and any dusk adjustments) from the ladder; picked values committed and re-verified. *(Picked 2026-08-15: **properly dark, `night_darkness = 1.0`** — night should make carried torches useful and add a little horror aspect. No day-sweep adjustments requested. Committed as the export default and re-verified.)*
- [x] Performance unchanged with the cycle running. *(`verify_cycle --perf`, windowed, sky re-rendering a full day every 24 s: 120 fps average, worst frame 10.85 ms over 600 frames — at the Phase 6 baseline of 119 fps / 8.55 ms. An earlier 1010 ms outlier reproduced as the documented macOS focus-call stall, not the cycle.)*
- [x] Zero warnings; graybox, world and desert_environment run standalone; `verify_player`/`verify_terrain`/`verify_clock` all re-run green after the change.
- [x] ART_DIRECTION lighting palette + DECISIONS updated with the final colors. *(The lighting palette section now documents the whole day as keyframes, with night's darkness as intent, not accident.)*

**Handoff note (2026-08-15):** one trap found and recorded — the `Game` autoload DOES run under `--script` (older comments in `shoot_desert_look.gd` say otherwise); a tool that injects a node named "Game" gets silently auto-renamed while the environment keeps listening to the real autoload. Both new tools fetch `/root/Game` first and only inject as a fallback. The first ladder shoot produced 17 identical golden-hour frames because of exactly this.

## Phase 6.6 — Audio system (side-track)

**Added 2026-08-15 at Joshua's direction** — a second deliberate side-track (sound design was on the "later" list; he pulled the *system* forward). Branch `feature/audio-system`, branched off `feature/daynight-lighting` rather than `development` because the system hooks into the torch/lamp/FlameLight props that only exist there — it merges after 6.5 does.

**Division of labor:** Joshua sources every sound file (checklist with exact filenames, formats and take counts: **`assets/audio/README.md`** — the ever-growing list); Claude builds the engine with **no placeholder sounds**. Missing files are silent, never errors; when a sourced file lands, `tools/build_audio_libraries.py` rebuilds the libraries from the naming convention — no hand-wiring.

**Design principles (agreed at planning):** sounds are data (resources + surface tags), not code — adding a material, building or prop must never mean writing logic; buses and resources carry all shared structure (**no new autoload**); props own their sounds (self-contained scenes rule); a new building assembled from tagged pieces + one `AcousticZone` gets correct audio for free.

**Deliverables**
- **Bus layout** (`default_bus_layout.tres`): `Master → Music (reserved, empty) / Ambience / SFX`, plus an `Interior` reverb bus for indoor routing; low-pass on Ambience for indoor muffling.
- **Listener**: `AudioListener3D` at the *player's* position with the *camera's* yaw (ears where you are, panning matching the screen), owned by the camera rig. Doppler tracking enabled system-wide on emitters.
- **Footstep system**: fires off the Phase 5 foot-plant stamper signal (audio and prints in sync by construction) plus `jumped`/`landed(impact_speed)`. Loudness and clip set by gait (run > walk; crouch never plants → quiet shuffle loop instead — sneaking is genuinely quiet). Surface resolved per step: terrain → sand graded by `get_sand_depth` (deep drift vs packed pad); anything else → a `surface` tag on the collider, sensible default when untagged. Per-surface `FootstepLibrary` resources under `resources/audio/`, generated by `tools/build_audio_libraries.py`. A `noise_made(position, loudness)` signal nothing listens to yet — the future stealth/creature hook.
- **`AcousticZone`** (reusable Area3D component, the InteriorCutaway pattern): routes contained sounds through the Interior reverb bus (native Area3D feature) and muffles the ambience bed while the player is inside. One instance in the house.
- **Ambience**: world-scene-owned node crossfading day/night wind beds off `Game.time_of_day` (the `desert_environment.gd` pattern — dawn/dusk are blends, not separate assets), plus intermittent spatialized gust one-shots around the player (a doppler user).
- **Prop sounds**: door creak/thud on its existing open/close signals; torch and lamp burn loops tied to their existing `FlameLight.lit` state; torch take/return/whoosh.
- **`tools/verify_audio.gd`**: the gate as an executable, all silent-safe (must pass with zero sound files present).

**Quality gate**
- [x] `verify_audio` passes with the sound folders empty (silent-safe) *and* the full battery stays green: `verify_player`, `verify_terrain`, `verify_house`, `verify_lighting`, `verify_cycle`, `verify_clock`. *(All seven run 2026-08-15, all green.)*
- [x] Footsteps: correct library chosen on deep sand / packed pad / stone floor / wood upper storey (surface switching asserted — courtyard resolves `packed` at its measured 0.25 m against the 0.35 m threshold, a 0.80 m drift resolves `sand`); loudness ordering run > walk asserted (−1 dB > −7 dB) with crouch making no step sound at all (shuffle loop instead); step events ride the stamper's plant edge via the new `foot_planted` signal, never a timer.
- [x] Acoustic zone: entering the house closes the ambience low-pass (20500 → ~1080 Hz) and ducks the bus (−7.9 dB); leaving restores both (asserted). No cutaway fight — the zone is its own Area3D and touches only AudioServer state.
- [x] Ambience crossfade anchored (noon/16:00 pure day, midnight pure night) and monotonic through dusk, driven only by the clock's own period constants.
- [ ] With sourced sounds present (whenever Joshua's files land): a windowed listen-through — footsteps on all four surfaces, door, torch carry, lamp, day and night beds — and Joshua signs off on the feel. **← in progress.** *(2026-08-15, ~8 live tuning rounds with Joshua: sand footsteps (his own left/right recordings), doors, wind bed and the first music loop are in and the mix balance is his, approved by ear — "the relative between wind and footsteps are perfect". Still to source: fire group (torch/lamp loops + one-shots — matters most for the night-torch experience), jump/landings, crouch shuffle, indoor-floor replacement (current concrete disliked), packed-earth walk, dedicated night bed, gusts.)*
- [x] Zero warnings (`--import`, per-script `--check-only`); world, graybox, player, house, ambience, torch stand, oil lamp and camera rig all run standalone clean; DECISIONS.md entry written (structure, listener placement, branch choice, no new autoload); merged to `development` after 6.5. *(Merge pending 6.5's flicker playtest. One accepted exception, in DECISIONS: an ogg bed playing at the instant of exit reports 4 leaked playback objects — bounded, same category as the Phase 6 house shutdown warning.)*

**Handoff notes (2026-08-15, end of the sound-tuning session)**

The engine is stable and the tuning loop with Joshua converged. What the next session inherits:

- **How sounds work now** (all decided by Joshua across ~8 rounds, recorded in DECISIONS): footsteps are **deterministic per-foot samples** (`footsteps/<surface>_left/right.wav`) fired by the print system's plant events — no randomized variation sets (cross-library takes "too different"), no movement loops (tried, rejected). Runs reuse the walk samples louder. The mix hierarchy from quiet to loud is **footsteps → wind ≈ doors**, with **music below everything** (`music/ambient_NN.ogg`, first track loops; the plan is a random rotation with silent gaps once more tracks land).
- **The tuning traps that cost rounds today**, so they aren't relearned: the plant detector chattered at low speeds until a per-foot **travel gate** (`min_step_distance`) was added to the stamper — Phase 5's prints hid duplicate stamps, audio exposed them; the **packed-vs-sand depth threshold silenced the entire homestead surround** (where Joshua always tests) for three rounds — it's now 0.05 m, and any future surface/zone logic must behave at the homestead first; wav loops need `loop_end` set from *duration* (importer compresses to QOA, so byte math lies).
- **Workflow**: he pastes file paths + a word of intent; `tools/prepare_sounds.py` conditions everything (slice/trim/normalize/loop-seam); relaunch the game after every change (`pkill` the old instance first). Volume verdicts come fast and by ear — implement literally, relaunch, ask nothing.
- **Sourcing still open** (the ever-growing list lives in `assets/audio/README.md`): fire group, jump/landings, crouch shuffle, indoor floor replacement, packed earth, night bed, gusts, more music.
- Sliders later attach to the buses (Master/Music/Ambience/SFX) — mix-level tuning already lives there (SFX −6), per-sound tuning in exports.
- **Pause menu detour (2026-08-15, Joshua's request):** Esc pauses and opens a palette-styled menu (Resume / Settings → Audio) with Music and Sound sliders, persisted to `user://settings.cfg`. The bus layout gained a parent `Sound` bus over Ambience + SFX so the slider never fights the AcousticZone's ducking — mix baselines untouched. Hover/click UI sounds sourced by Joshua live in `assets/audio/ui/`; music keeps playing under the menu. Gate: `tools/verify_pause.gd` (all pass, plus `verify_audio` re-run green on the new layout). See DECISIONS.
- **Save/load detour (2026-08-15, Joshua's request, same session):** Save Game / Load Game in the pause menu, one slot (`user://saves/save_01.json`). Built as the persistence contract Joshua asked to future-proof — stable keys, group-walked, unknown keys warn-and-skip (ARCHITECTURE → Persistence). Saves today: clock+seed, player, camera, both doors, lamp, carried torch; footprints deliberately ephemeral. Gate: `tools/verify_save.gd` all pass; full battery re-run green (pause, audio, clock, house, lighting, cycle, player). This removes save/load from the "later" list.

## Phase 6.7 — Ocean biome: the western sea (major expansion)

**Added 2026-08-17 at Joshua's direction.** The map grows a coastline: **west of the desert**, the dunes descend to a shore and the world continues as open ocean. This is a *natural extension of the existing map*, not a replacement — **the desert stays exactly as it is**, the ocean joins it the way a real desert meets a real sea. The bar is explicit and higher than usual: **incredible depth, absolutely stunning** — this biome is meant to be a second signature alongside the living sand, and it gets at least the care Phases 4–5 gave the desert. It is numbered as a side-track but scoped as a major phase (Phase 6-sized, in parts).

### ⚠️ Hard gate — Joshua tests before GitHub sees any of it

**Branch parentage:** `feature/ocean-biome` branches off `feature/audio-system` rather than `development` — the same reasoning as 6.6 off 6.5: the ocean extends the day-night/fog contract (6.5) and the audio hooks (6.6) that only exist on that line. It merges after 6.6 does.

**Nothing from this phase is ever pushed to the GitHub remote — not the feature branch, not a merge to `development` — until Joshua has played the ocean in the running game and signed off.** Local commits on `feature/ocean-biome` are fine and expected (that is how work is saved and handed between sessions), but `git push` of any ocean work waits for his approval. This deliberately supersedes the usual "merge and push when the gate passes" flow for this phase; every session working on it must respect it, including partial/handoff sessions. The rule is also recorded in DECISIONS.md.

### Planning session first (the Phase 6.5 pattern)

Deliverables below are the intended shape; the first ocean session is a **planning conversation with Joshua** before any build, where his calls get made and recorded:

1. **Where the shore lies** — ✅ **decided (Joshua, 2026-08-17): about a 30-second walk west of the homestead.** At walk speed 1.8 m/s that puts the waterline ≈ 55 m west (an 11-second run). Close enough that the sea is part of the homestead's view and daily life, not an expedition — the exact shoreline curve still comes from the seeded coastline, this fixes its mean distance. Note for the build: at ~55 m the coast sits well inside the fog-free zone (fog starts at 100 m), so the water is seen crisp and full-color from the courtyard — the golden-hour ladder must be shot from there.
2. **How far in the player goes** — ✅ **decided (Joshua, 2026-08-17): knee-deep, for now.** The player wades in and is gently stopped around knee depth — no swimming yet. The long-term vision is recorded in the roadmap below and it is big: full swimming, then diving, eventually a **submarine simulation**. The ocean is planned as a huge feature that grows over many sessions; this phase ships the shore of it, built so none of that is blocked.
3. **The water palette** — ocean blues/turquoise, foam white, wet sand are all *new colors*, which the palette rule says means an ART_DIRECTION amendment chosen from same-vantage screenshot ladders, not improvisation.
4. **What lives there** — ✅ **decided (Joshua, 2026-08-17): eventually all of it** — fish schools in the shallows, crabs on the beach, gulls overhead, something big surfacing offshore — **added gradually over time as we see fit**. None of it gates this phase: the current job is a beautiful, *functioning* biome. Survival-layer shore hooks (fishing, fresh water) stay an open question for a later planning talk.

### Part 1 — Coastline & the sea surface (the stunning look)

**Deliverables**
- **Coastline in the analytic terrain model** (`resources/terrain/terrain_settings.gd`): a deterministic, seeded shoreline west of spawn — gently irregular bays and headlands, never a straight line — blending desert → back-dunes → beach → seabed that keeps descending underwater. The existing analytic queries (`get_surface_height` / `get_base_height` / `get_sand_depth`) extend naturally (the seabed *is* terrain), plus new helpers the other systems key off: `get_water_depth(world_xz)` and `distance_to_shore(world_xz)`. The desert body and the homestead stay unchanged in character; the world hash will change (as it did in the restyle) and the homestead re-seats — the full verify battery must stay green.
- **The sea surface**: `scenes/world/ocean/` + `shaders/ocean_water.gdshader` — stylized low-poly flat-shaded water in the game's language: vertex-displaced rolling waves (visual only; derivative normals like the sand), color graded by true water depth (bright shallow → deep blue), a foam band where water meets sand, breakers rolling onto the beach, and sun/moon glint driven by the day-night cycle. **The 16:00 golden hour over water is the money shot** — calibrate for it the way the cycle calibrates the desert.
- **The Phase 4 horizon contract extends over the sea**: fog melt at every hour over water too, streaming edge never visible looking out to sea. `verify_cycle`'s fog contract grows a west-facing check.
- **Wet sand band**: darker, firmer sand near the waterline — and **footprints in wet sand persist longer**, finally cashing in the deformation texture's reserved G-channel material-class hook from Phase 5 (DECISIONS 2026-08-14 said don't repurpose it; this is what it was for).
- **Streaming**: ocean chunks must be cheap (far-out seabed is simple) and the water surface either per-chunk tiles or a player-following sheet — a profiled choice, recorded in DECISIONS. Same streaming budget as Phase 4: no hitches > 4 ms.
- **Beach props** through the established pipeline (committed headless Blender scripts, palette-only, `collision_layer = 5`): rocks, driftwood, shells, beach grass — picked with Joshua as-we-go like the desert props.
- **Audio hooks, silent-safe per 6.6**: a waves bed whose volume/character keys off `distance_to_shore`, gull and gust one-shots; `assets/audio/README.md` grows the sourcing checklist (Joshua sources, as ever).
- **Wading, capped at the knees**: walking into the water is felt — the deep-sand movement pattern reapplied to water (slow-down as it deepens, small splash-step feedback) — and around knee depth (water depth ≈ 0.4 m, tunable export) a *gentle* stop keeps the player from going deeper: a soft push back toward shore, never a wall-bump. Wading/splash sounds join the silent-safe audio hooks.
- **Ladders for every visual pick**: water colors, wave scale/speed, foam intensity, wet-sand tone — same-vantage screenshot ladders (artifact flip-page), Joshua picks, values locked and documented.
- `tools/verify_ocean.gd` (determinism, seams, collision-vs-visual at the shoreline, fog contract at sea, perf) and `tools/shoot_ocean.gd` (reproduces the visual evidence) — the gate as executables, per house style.

### Part 2 — deferred: the ocean roadmap (Joshua's direction, 2026-08-17)

**Not this phase's work and not its gate** — recorded so every ocean session builds toward it instead of accidentally against it. The ocean is planned as a **huge, long-term feature** that grows gradually, roughly in this order, each stage getting its own planning session and gate when Joshua pulls it forward:

1. **Surface swimming** (the knee-deep cap lifts; swim animations join the Meshy sourcing list when this starts).
2. **Diving / underwater traversal** — will need its own conversation about the fixed-pitch camera, breath, underwater rendering.
3. **Submarine simulation & vehicle mechanics** — Joshua's stated end-goal for the deep water; at the 2026-08-22 sign-off he broadened it to vehicle mechanics generally (likely submarine plus other vehicles).
4. **Sea life, added piecemeal as we see fit**: fish schools in the shallows (the main payoff of looking down into water at our camera angle), crabs on the beach (tiny tracks via the Phase 5 stamper), gulls overhead (audio + simple silhouettes), and something big surfacing far offshore.

**What Part 1 must therefore get right now, so none of this is blocked**: `get_water_depth` stays correct at *every* depth, not just the wading band; the seabed is real terrain (mesh + analytic + collision) all the way out, not a painted floor; the depth-graded water color is honest so deep water already *reads* deep from the surface; and the visual budget favors the shallows — seabed detail (seagrass, rocks, sand ripples continuing underwater, light-dapple suggestion in the palette's language) fading into deep-blue mystery, because at the fixed 19° camera looking *into* the shallows is the view the ocean lives in.

**Quality Gate** (whole phase)
- [x] **The hard gate above: Joshua has played the ocean — walked the coast, waded in, seen it at golden hour and at night — and signed off. Only after that does anything get pushed to GitHub or merged to `development`.** *(Playtested and signed off 2026-08-22 — "water test is good". Branch pushed to GitHub the same day.)*
- [x] Approaching from the desert reads as one continuous, natural world: dunes → beach → sea with no visible seam between the biomes. *(Approved via Joshua's live playtest 2026-08-22 rather than the screenshot set; the committed `docs/references/ocean_*.png` shots remain the record of what he approved.)*
- [x] Water look approved; no off-palette color anywhere in the biome. *(Joshua kept the committed **palette-only defaults** after playing — oasis_teal shallow / night_blue deep / plaster foam / sand_shadow wet sand, documented in ART_DIRECTION. No new colors, so no palette amendment needed. The four-rung ladder stays reproducible via `tools/shoot_ocean.gd` if the look is ever revisited during the later ocean stages.)*
- [x] `verify_ocean` passes and the full existing battery stays green — the desert and homestead are provably unharmed. *(2026-08-17: verify_ocean all modes — analytic, --wade, --wetprints, --perf. The far desert is asserted **bit-identical** to a coast-disabled twin; the homestead pad audit is unchanged (relief 0.000 m, approach 14.79°); battery re-run green: terrain (all modes incl. collision 0.0000 m and the 2 km walk, streaming apply worst 0.37 ms), player, house, prints, cycle, clock, audio, pause, save. World hash changed by design.)*
- [x] Wading feels right to Joshua: entering the water slows you believably, the knee-deep stop is gentle (no wall-bump, no jitter, no getting trapped where waves meet sand), and walking the surf line is comfortable. *(Measured side: held at exactly 0.40 m with 0.06 m cross-shore drift over ~30 s of pressing seaward, along-shore walking free, walks straight back out. Feel approved in the 2026-08-22 playtest.)*
- [x] 60 fps+ with the full ocean vista on screen at default window size; streaming budget holds along/across the coastline. *(120 fps average over 600 windowed frames at the beach vantage (worst single frame 25.4 ms — an isolated outlier in the documented macOS window-server family). The 2 km streaming walk runs parallel to the coast ~60 m inland, so its loaded ring built beach and ocean chunks the whole way: apply worst 0.37 ms against the 4 ms budget, chunks plateau at 132, memory +7.6 MB.)*
- [x] Footprints on wet sand behave (deeper-reading, slower-fading) and ordinary desert prints are byte-identical in behavior. *(--wetprints: waterline print at 0.52 while the dry-beach print has fully faded, on a beach whose sand takes a full-depth print (cap ≥ 1.0); verify_prints — the whole Phase 5 gate — re-run green, and dry stamps write G = 0, which is exactly the pre-coast decay path.)*
- [ ] PLAN.md updated; DECISIONS entries for every call; merged to `development` **only after** the Joshua gate. *(Gate passed 2026-08-22 and the branch is pushed; the merge itself waits on the branch chain — 6.5's flicker playtest closes 6.5, 6.6 merges after it, then 6.7 follows.)*

**Handoff notes (2026-08-17, end of the first build session)**

Part 1 is built end-to-end and every measurable gate is green. What exists: the coast field in `TerrainSettings` (ceiling-clamped dunes, seeded shoreline ~49 m west of this seed's homestead, beach → swash → shelf → 24 m deep), the `Ocean` water plane + `shaders/ocean_water.gdshader` (depth-buffer color/foam, world-anchored waves, golden-hour glint), knee-deep wading in `player.gd`, wet-sand prints via the G channel, the silent-safe surf bed in `Ambience`, and `verify_ocean`/`shoot_ocean` tooling. Architecture and art docs updated; DECISIONS carries the seven load-bearing calls.

**Resolution (2026-08-22):** Joshua playtested and signed off — "water test is good." The water keeps its committed palette-only defaults (no ladder swap), the hard gate is lifted, and the branch is pushed to GitHub. He confirmed the ocean grows in later sessions: depth, swimming, sound FX, and likely submarine/vehicle mechanics (roadmap above updated). The original open items are kept below for the record:

**Everything that remains is Joshua's eye and ear — the hard gate:**
1. **Playtest** (walk west, wade, walk the surf line, see golden hour and night at the water) — a build is left running for him after this session.
2. **Water-color ladder pick** — four rungs at the golden vantage (`ladder_a_palette` = the committed defaults … `d_tropical`); current defaults are palette-only.
3. **Screenshot review** of the committed set in `docs/references/ocean_*.png`.

Worth his eyes specifically: the **swash zone reads as wide foamy wash with occasional tide-pools** where the shoreline curves (deliberate after two rounds of fixes — see DECISIONS on the dry floor and the waterline slope); and the night sea is properly dark with faint foam lines (the night pick carrying over the water). Known open ends, none blocking: surf/wading/splash sounds are on the sourcing list (`assets/audio/README.md`); the footstep system will want a `wet` surface class when those land; beach props (rocks, driftwood, shells) were deliberately left for the as-we-go prop sessions; the fog contract over water is screenshot-verified but has no automated west-facing assert yet.

## Phase 6.8 — The sand worm: a desert mob (planned 2026-08-22, not yet started)

**Added at Joshua's direction.** A giant worm that swims through the dunes — the desert's first creature threat, borrowed knowingly from *Tremors*. Most of the time the worm is never seen: its presence is a **traveling mound of rising sand** in its wake. Occasionally it **breaches** and the body is visible arcing through the sand. Once fully implemented it is an **enemy with kill animations**, encounters are **incredibly rare**, and it is **attracted to noise** — loud footsteps above all. It pairs deliberately with the properly-dark night pick (6.5): the worm is the horror the dark was designed to carry.

**Planning calls recorded (Joshua, 2026-08-22):**
- **Scale: decided from an in-game size ladder**, not in the abstract — a placeholder worm (segmented palette tube, no rigging needed) shown at ~3 sizes mound-and-breaching at the real gameplay camera; Joshua picks before his model is conditioned or rigged. (The scale sets everything downstream: mound width, sand displacement, breach read, encounter framing.)
- **Death design: deferred to Part 3's planning session.** There is no health/damage/death system in the game yet — the worm would be the first thing that can kill the player. The two candidate shapes on the table when that talk happens: cinematic kill (dragged under, reload last save — no health bar; the save system from 6.6 already provides the respawn path) vs. a full health/damage system (the start of the survival combat layer). Not decided now, on purpose.
- **Timing: plan only.** Building starts in a future session when Joshua says go — ideally after the 6.5 → 6.6 → 6.7 merge chain has closed, since Part 1 extends the same deformation shader the ocean's wet prints just touched.
- **The model is Joshua's** — he supplies the sand worm model (any format; it does not need to come rigged); `tools/build_worm.py` conditions and rigs it through the established pipeline when Part 2 starts.

**Why the game is already half-ready for this** (recorded so the parts below read as extensions, not new systems): the Phase 5 stamper interface was built for "any object that moves sand"; the deformation texture and `sand_terrain.gdshader` are the mound's natural home (prints press down — the wake needs the same machinery raising sand up, a signed extension of the R channel that must leave `verify_prints` green and the wet-sand G class untouched); the 6.6 audio system's `noise_made(position, loudness)` signal was explicitly reserved as "the future stealth/creature hook" — run loud and it hears you, crouch-sneak and you are genuinely quiet, exactly the Tremors rule; and the two-layer sand model means "safe ground" already exists physically — the worm needs deep sand to swim, so packed earth, the homestead pad and hard substrate are natural refuges (the Tremors rooftop rule, free of charge — **flag for Joshua at Part 3 planning**, since it turns terrain reading into survival skill).

### Part 1 — The presence (no model required)
The worm as pure phenomenon: an underground agent following a curved burrow path through deep sand (analytic terrain queries say where swimming is possible; it avoids shallow sand, packed ground, the homestead pad and the sea), the **traveling mound** rising in its wake via the raise extension to the deformation system, settling behind it like prints fade; a low rumble bed keyed to distance (silent-safe per 6.6, files on Joshua's sourcing list); debug spawn/steer controls + F3 readout. **Ends with the size ladder** — placeholder tube at ~3 scales, mound and breach vantage shots, Joshua picks.

**Part 1 deliverables (planned 2026-08-22, build started same day)**
- **Raise extension** to the sand deformation system: `SandDeformation` gains a raise path alongside `stamp()` — sand lifted, not pressed — with its own faster settle rate (a mound collapses in seconds, not print-minutes). Channel choice made against the real texture budget and recorded in DECISIONS; the press (R) and wet (G) behaviors stay byte-identical, asserted by re-running the Phase 5 and ocean print gates.
- **`scenes/props/sand_worm/`** — `sand_worm.tscn`/`sand_worm.gd` (`SandWorm`): a bodiless underground agent in Part 1. Smooth wander steering (turn-rate-limited, no teleports), swim depth and speed as exports, terrain-query guardrails: never into sand shallower than a swimmable minimum, never onto the homestead pad, never into the sea. Emits travel-gated raise stamps along its path (the `min_step_distance` lesson applied from day one).
- **Rumble, silent-safe**: an `AudioStreamPlayer3D` on the worm looping `creatures/worm_rumble_loop` through `SoundBank` (null until sourced — `assets/audio/README.md` grows the entry), distance attenuation doing the "keyed to distance" work.
- **Debug affordances**: F3 overlay worm lines (state, distance, local sand depth); debug actions to summon/dismiss the worm near the player and cycle behavior (wander / orbit player / approach player) so the mound can be seen without waiting for it.
- **`tools/verify_worm.gd`** — the gate as an executable — and **`tools/shoot_worm_ladder.gd`** (placeholder segmented tube at ~3 scales, mound + breach-arc vantage shots at the gameplay camera).

**Part 1 exit bar**
- [ ] `verify_worm` passes: raise stamps land where the worm swims and read back from the texture; the mound settles to zero after passage; the wander path over a long sample never violates a guardrail (shallow sand / homestead pad / sea); dormant cost is zero (no worm ⇒ no deformation passes, no processing); perf with the mound churning stays at the phase baseline.
- [ ] `verify_prints` (the whole Phase 5 gate) and the ocean `--wetprints` mode re-run green — prints provably untouched by the raise channel.
- [ ] The traveling mound reads at the gameplay camera in screenshots — a moving swell of sand, not a glitch and not a wall.
- [ ] Size ladder shot from a fixed vantage; **Joshua picks the worm scale** — the pick closes Part 1 and sets Part 2's rig dimensions.
- [ ] Zero warnings; standalone scene runs clean; PLAN/DECISIONS updated.

### Part 2 — The body (Joshua's model arrives)
`tools/build_worm.py` conditions and rigs the model — a single spine chain (a worm is the simplest rig there is) driven **procedurally**: the body follows its burrow path and the bones bend to match, so breaches read correctly at any angle and speed with no baked-clip seams. Breach spectacle: the mesh arcing out of and back into the dune, sand burst at entry and exit (deformation stamp + the palette's language for thrown sand), breach audio hooks. The worm at this stage is ambient spectacle — rare, harmless, unforgettable.

### Part 3 — The threat (its own planning session first)
Noise attraction via `noise_made` (footstep loudness already varies by gait — running calls it, sneaking doesn't); a rarity/encounter director (incredibly rare, tunable — never a spawn timer the player can feel); stalk → mound-approach → strike behavior; **kill animations** on the rigged spine; the death design call (deferred above) resolved and built; the safe-ground rule surfaced to Joshua as a design opportunity. Feel items (fear pacing, fairness of the noise rule, rarity) gate on his playtests, as ever.

**Constraints binding from day one:** every visual stays palette-only and flat-shaded; the raise extension may not disturb print behavior (`verify_prints` and the wet-print gates stay green — asserted, not assumed); the worm's agent must cost ~nothing while dormant (it is rare by design, so its idle cost is its usual cost); and everything tunable is an `@export`. Gate checklists are written per part at each part's planning session — none exist yet by design.

## Phase 7 — Integration & polish → v0.1

**Goal:** everything together, tuned as one game; ship the first stable `main`.

**Deliverables**
- Full pass on lighting/environment: warm late-afternoon sun, soft shadows tuned, subtle fog/height haze for depth, sky gradient matched to palette.
- Performance pass: profile, fix any regressions, confirm all gates from phases 2–6 still pass in the combined game.
- Consistency sweep: naming, folder hygiene, dead code/scenes removed, every script typed and warning-free, docs updated to reality.
- A 5-minute "playtest loop": spawn near the homestead, walk the dunes, watch prints fade, meet the camel — and if Phase 6.7 has merged by then, continue west to the shore — verified start-to-finish with no errors.
- Merge `development` → `main`, tag `v0.1.0`.

**Quality Gate**
- [ ] Fresh clone + open in Godot + run: works first try, zero errors.
- [ ] 10-minute free-play session: no crashes, no fps drops below 60, no visual bugs at the gameplay camera.
- [ ] Joshua has played it and signed off.
- [ ] `main` updated and tagged `v0.1.0`.

---

## After v0.1 (future planning session)

Survival layer (thirst/heat/shade), day-night cycle, inventory, more POIs and biome variation within the desert, sound & music, save/load. Plan these in a dedicated session that writes PLAN-v0.2.md or extends this file. *(Biome expansion started early: Joshua pulled an ocean biome forward on 2026-08-17 — see Phase 6.7.)*
