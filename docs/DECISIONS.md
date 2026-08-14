# Decisions Log — Shaiba

Append-only log of decisions with reasoning, so future sessions don't re-litigate or accidentally reverse them. Newest at the bottom. Format: date, decision, why, alternatives rejected.

---

**2026-08-13 — Angled top-down perspective camera, not true orthographic isometric.**
A perspective camera pitched ~50–55° with a narrow FOV (~35°) gives the "almost isometric" diorama feel Joshua asked for while keeping depth cues (parallax, dune scale) that pure orthographic loses in an open desert. Rejected: orthographic (flattens dunes), free third-person camera (wrong genre feel).

**2026-08-13 — Chunked streamed terrain from the first terrain implementation (Phase 4).**
The game is open-world on a large map; retrofitting chunking onto a monolithic terrain later would mean rebuilding terrain, collision, prop scattering, and the sand-deformation integration twice. Cost of chunking early is modest; cost of retrofitting is a rewrite.

**2026-08-13 — Sand footprints via world-space deformation texture + vertex-displacement shader, not geometry edits or decals.**
Editing chunk meshes per footstep fights the streaming system and is expensive; plain decals can't depress the surface so prints look painted-on at an angled camera. A SubViewport-accumulated deformation texture is the standard, cheap, fade-able approach. To be validated with a prototype at the start of Phase 5.

**2026-08-13 — Typed GDScript only; no C# unless profiling forces it.**
One language keeps every session's code uniform and godot-mcp-friendly; typed GDScript catches most novice mistakes at parse time. If a hot path (likely chunk generation) ever profiles too slow, revisit here.

**2026-08-13 — Repo root = Godot project root; .blend sources committed alongside .glb exports.**
godot-mcp and version control cover everything with zero path indirection; committed .blend files keep every asset re-editable in later sessions. Git LFS deferred until repo size demands it (~1 GB threshold).

**2026-08-13 — One autoload (`Game`) to start; new autoloads require a logged justification.**
Global singletons are the main spaghetti vector in small Godot projects. Signals + composition first; the log entry requirement forces the discussion.

**2026-08-13 — GitHub repo `jmelvin92/shaiba`, private; `main` (stable) + `development` (integration) + per-phase feature branches, `--no-ff` merges.**
Joshua asked for main to stay protected until testing passes; --no-ff keeps each phase's work legible as one unit in history. Private by default — flip to public anytime.

---

## Phase 2 — camera & movement

**2026-08-13 — Movement tuning, first pass: max_speed 4.6 m/s, acceleration 26 m/s², friction 32 m/s², turn_speed 11.**
Measured on the graybox: full speed in ~0.18 s, stop in 0.15 s. 4.6 m/s is a brisk walk for a 1.75 m character, leaving headroom for a run speed in Phase 3. Superseded below after Joshua played it.

**2026-08-13 — Movement tuning, after playtest: acceleration 16, friction 24, turn_speed 7, and a new `turn_drag` of 0.55. Speed unchanged at 4.6 m/s.**
Joshua's note was "more weight, especially during sudden turns or launches." Lowering acceleration covers launches, but lowering `turn_speed` alone would only have slowed the *visible* rotation — velocity still changed direction the instant you pressed a key, so a reversal would look heavier without feeling it. `turn_drag` fixes that by scaling available acceleration with how well the body already faces where you asked to go: aligned gives full thrust, a full about-face gives `1 - turn_drag`, recovering as the body comes round. Measured after: launch to 90% of top speed 0.27 s (was 0.16), stop 0.20 s, a 180° reversal takes 0.40 s before you move back at all, and a right-angle turn dips to 71% of top speed so corners cost something. Slope, curb and staircase behaviour re-verified unchanged.

**2026-08-13 — `floor_max_angle` 32°, so slopes up to ~30° are walkable and steeper ones are not.**
PLAN's gate asks for ~30° walkable / steeper blocked. Setting the threshold slightly above 30 means the 30° test ramp is comfortably walkable rather than marginal, while the 40° and 50° ramps are firmly refused. Verified on all five graybox ramps.

**2026-08-13 — Step climbing by lifting the body *before* `move_and_slide`, not teleporting it onto the ledge after.**
The usual up→forward→down probe has to move the body forward by roughly the capsule radius to clear the obstacle's face, which pops it visibly. Instead, when a wall-like surface is within `step_probe_distance` (0.5 m) ahead and there is headroom, the body is raised by `max_step_height` and `move_and_slide`'s floor snap puts it back down in the same tick — onto the ledge once the body has cleared its face, otherwise straight back where it was. Nothing is visible until the step is actually taken. Consequence: `floor_snap_length` must exceed `max_step_height`, so `_ready` clamps it. Verified: 0.20 m and 0.35 m curbs climb, 0.50 m is refused, a 0.25 m staircase walks up cleanly. Walkable slopes are excluded from the probe so they keep their natural along-the-slope speed.

**2026-08-13 — Run is a held `sprint` action (shift) that raises the target speed, not a separate movement state. walk_speed 4.6, run_speed 7.4.**
Joshua wants walk and run as the two gaits, run on held shift. Implementing it as a target-speed swap means the existing acceleration, friction and turn_drag all apply unchanged — winding up to a run takes 0.18 s and dropping back the same, so the gait change has the same weight as everything else, and there is no state machine to keep in sync with the animation one. Phase 3's AnimationTree therefore blends idle↔walk↔run off the resulting planar speed rather than off an input flag, which also makes the blend correct while accelerating, on slopes, and when turn_drag is holding speed down. Re-verified at run speed: 15/30° ramps still walkable, 40/50° still refused, 0.20/0.35 m curbs still climb, 0.50 m still blocked — a faster capsule does not punch over anything. `max_speed` renamed to `walk_speed` while the meaning was still local to this file.

**2026-08-13 — Jump on space (1.1 m), with coyote time, a jump buffer, variable height and reduced air control.**
`jump_height` is expressed in metres and converted to a launch velocity against whatever gravity is in force, so retuning `gravity_scale` doesn't silently change the hop. The three forgivenesses are all standard and all cheap: 0.12 s of coyote time after leaving a ledge, a 0.12 s buffered press so hitting space just before landing still fires, and cutting the rise to 45% if you release early — measured, a held jump clears 1.15 m in 0.85 s and a tap 0.58 m in 0.55 s. `air_control` 0.35 applies to both acceleration and friction mid-air, so a jump largely commits you to the arc you launched with; without it you could hover-steer, which would undo the weight the ground movement just gained. Jumping while crouched is refused rather than auto-standing — one input, one meaning.

**2026-08-13 — Crouch on ctrl or C, held rather than toggled, and you cannot stand up under something.**
Held matches sprint, so both modifiers behave the same way. Bound to two keys because ctrl is awkward on a Mac trackpad. The capsule shrinks 1.75 → 1.15 m over ~0.05 s rather than snapping, with the collision shape and mesh kept sitting on the character's feet, and the shape and mesh resources are marked `resource_local_to_scene` so resizing one player could never resize another. Standing up is gated on sweeping the crouched capsule up through the space the standing one would occupy — exact, and it reuses `test_move` rather than hand-rolling a query. Verified under a 1.4 m ceiling: crouch holds after the key is released and only springs back once clear.

**2026-08-13 — `graybox.tscn` gained fixtures for the new abilities.**
A test level that can't exercise an ability isn't testing it. Added a 1.3 m-clearance crouch tunnel, a 0.9 m ledge (jumpable) beside a 1.6 m one (not), and a 4.0 m gap between two platforms that a walk cannot clear but a sprint can. Each was verified by script to behave as intended, which is also a check on the tuning: if a later change breaks the jump, the gap stops being crossable.

**2026-08-13 — Default camera distance 23 m (was 18), zoom range 9–34 m.**
Joshua wanted the camera further out by default. 23 m puts the character at roughly 12% of screen height — small enough to read the terrain around them, which suits an open desert, and the clamps were widened so there is still real travel in both directions from the new default.

**2026-08-13 — Camera obstruction, first attempt: duck the camera in along its arm (own `ShapeCast3D`, not `SpringArm3D`).**
Kept the player visible and the camera out of geometry, but at a 52° pitch there is no distance that both frames the scene nicely and sees a player standing 2 m from a 6 m wall, so the view went cramped. **Superseded below** — Joshua played it and asked for the camera to stop moving.

**2026-08-13 — The camera never moves to avoid geometry. Obstructing objects fade instead (`scenes/camera/occluder_fader.gd`).**
This is what the previous entry said the real answer was, brought forward because the ducking was as intrusive in practice as predicted. The camera now holds its zoom distance unconditionally; an `OccluderFader` child of the rig traces sight-lines from the camera to three heights on the character, walking each line hit-by-hit rather than stopping at the first, and fades everything it finds to 22% opacity. Fading uses `GeometryInstance3D.transparency`, a per-instance multiplier — no duplicated materials, no changes to the palette `.tres` files, and it needs Forward+, which we are on. Ducking is now impossible to trigger: with the camera 18 m above the character, only something taller than that could reach it. Cost is ~18 raycasts a tick, which is nothing.

**2026-08-13 — Fading is opt-in via collision layer 3, so terrain can never dissolve.**
The fader masks layer 3 only. Ground and (from Phase 4) terrain chunks sit on layer 1 alone and are therefore never candidates — important, because at this camera angle a tall dune between the camera and the player would otherwise fade the world out from under them. Props and buildings opt in by sitting on layers 1 and 3 (`collision_layer = 5`). The fader also resolves a hit body to its meshes by checking the body itself, then its descendants, then its parent's — so it works both for CSG shapes, which are their own geometry, and for imported props where the collider and the mesh are siblings.

**2026-08-13 — `physics/common/physics_interpolation = true`; player and camera both update in `_physics_process`.**
Both move on the same 60 Hz tick, so there is no relative jitter between them, and interpolation smooths the pair together to the render rate. Measured while walking at 120 fps: the player's screen position holds to within 0.03 px of a straight line over 180 frames.

**2026-08-13 — `graybox.tscn` is built from `CSGBox3D` nodes with `use_collision`.**
One node per block instead of a StaticBody3D + MeshInstance3D + CollisionShape3D trio, which keeps a 30-block test level readable and editable. CSG is documented as a prototyping tool and a graybox is exactly that; if it ever costs frames it becomes a baked mesh.

**2026-08-13 — Collision layers: 1 = world/terrain, 2 = player.**
The camera's obstruction cast masks layer 1 only, so it can never be blocked by the player it is framing.

**2026-08-13 — `level_root.gd` is shared by `world.tscn` and `graybox.tscn`, and the lighting lives in `desert_environment.tscn`.**
A deliberate exception to "one script per scene": both level scenes need the identical six lines of wiring (tell the rig what to follow, tell the player which way the camera faces), which is the second real user the conventions ask for before extracting. Same reasoning for the environment: one place to do Phase 7's lighting pass instead of two copies to keep in sync.

**2026-08-13 — Camera pitch lowered 52° → 45° for a more cinematic angle; Joshua's request in a follow-up pass.**
At 52° the graybox read almost like a flat map — block tops and shadows, no vertical faces. At 45° walls and ledges show their faces and the scene gains real depth, while the framing still reads as the angled top-down diorama (screenshot-compared 52/45/40 from the same spawn; 40° was noticeably more dramatic and is one export-var away if wanted). The occluder fading was re-verified at 45°: player spawned 2 m behind the 6 m TallWall, wall ghosted correctly with the player fully visible. The original 50–55° range in PLAN's fixed decisions is superseded by this entry. Note for screenshot automation: check `pgrep -fl Godot` for stale game processes before trusting a window capture — a leftover debug window from an earlier session produced identical-looking "before/after" screenshots and cost a debugging round.
