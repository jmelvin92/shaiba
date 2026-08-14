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

**2026-08-13 — Default camera distance 23 m (was 18), zoom range 9–34 m.**
Joshua wanted the camera further out by default. 23 m puts the character at roughly 12% of screen height — small enough to read the terrain around them, which suits an open desert, and the clamps were widened so there is still real travel in both directions from the new default.

**2026-08-13 — Camera obstruction: own `ShapeCast3D` rather than `SpringArm3D`.**
SpringArm3D does the same cast but snaps the camera in *and* out instantly, and offers no control over the result. Rolling our own is ~15 lines and buys eased return (ducking in stays immediate — nothing should ever pop through the lens — while easing back out over ~0.3 s), a tunable floor, and a `get_camera_distance()` worth testing against.

**2026-08-13 — When obstructed the camera ducks all the way in; framing loses to visibility.**
At a 52° pitch there is no camera distance that both frames the scene nicely *and* sees a player standing 2 m from a 6 m wall — clearing the wall top requires a pitch above ~72°, and any distance floor large enough to help puts the camera *past* the obstruction, i.e. inside it. So the floor is 1 m (effectively "never"), and pressed against something very tall the view does get cramped. Accepted for now because the desert has almost nothing tall; the real answer, once Phase 6 adds a house and awnings, is to fade occluders instead of moving the camera. Alternative rejected: swinging the pitch toward vertical when blocked — it works geometrically but the cast result depends on the pitch, so it hunts without hysteresis machinery that this phase does not need.

**2026-08-13 — `physics/common/physics_interpolation = true`; player and camera both update in `_physics_process`.**
Both move on the same 60 Hz tick, so there is no relative jitter between them, and interpolation smooths the pair together to the render rate. Measured while walking at 120 fps: the player's screen position holds to within 0.03 px of a straight line over 180 frames.

**2026-08-13 — `graybox.tscn` is built from `CSGBox3D` nodes with `use_collision`.**
One node per block instead of a StaticBody3D + MeshInstance3D + CollisionShape3D trio, which keeps a 30-block test level readable and editable. CSG is documented as a prototyping tool and a graybox is exactly that; if it ever costs frames it becomes a baked mesh.

**2026-08-13 — Collision layers: 1 = world/terrain, 2 = player.**
The camera's obstruction cast masks layer 1 only, so it can never be blocked by the player it is framing.

**2026-08-13 — `level_root.gd` is shared by `world.tscn` and `graybox.tscn`, and the lighting lives in `desert_environment.tscn`.**
A deliberate exception to "one script per scene": both level scenes need the identical six lines of wiring (tell the rig what to follow, tell the player which way the camera faces), which is the second real user the conventions ask for before extracting. Same reasoning for the environment: one place to do Phase 7's lighting pass instead of two copies to keep in sync.
