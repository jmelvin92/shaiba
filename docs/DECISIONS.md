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

**2026-08-13 — The protagonist is AI-generated (Meshy.ai), not hand-modelled, and the whole conditioning pass is a committed script.**
Joshua generated a rigged, animated desert traveler in Meshy and downloaded one glb holding the mesh, a 24-bone rig and seven motion clips. That skips the modelling this phase was scoped for, but an as-downloaded asset is not a game asset: it faced the wrong way, its jump carried 3.65 m of forward travel, its material ignored light entirely, and it had no fall, land or crouch idle. All of that is fixed in `tools/build_player.py`, run headless against `assets/blender/player_source.glb` (committed) to produce `player.blend` and `player.glb`. Scripting it rather than clicking through Blender is what makes the quality gate's "re-export reproduces the glb" claim true, and it doubles as the documentation of what was done to the asset.

**2026-08-13 — The character keeps its baked texture. A deliberate exception to the palette-only rule.**
ART_DIRECTION says palette materials and no textures. Joshua chose to keep Meshy's baked texture rather than have it rebuilt with flat palette materials, on the grounds that the model already reads as a desert traveler in sand and cream tones. The exception is the *colour source* only — the material settings were still corrected (below), and the rule stands for every asset built from scratch. Worth revisiting if the character ends up looking foreign next to Phase 6's hand-made house and camel; a screenshot at the gameplay angle beside those props is the test.

**2026-08-13 — The material is made opaque, lit and matte even though the texture stays.**
As exported, Meshy's material was `alphaMode: BLEND`, double-sided, fully metallic, roughness 0.41, and — the real problem — `emissiveFactor [1,1,1]` with a full emissive map, which makes the character self-lit. It would have rendered as a flat cut-out that ignored the warm sun, cast no believable shadow, sorted badly against terrain and fought the occluder fader's own transparency. The build script zeroes emission and metallic, sets roughness 1.0 to match the palette `.tres` look, makes it opaque and single-sided, and deletes the emissive map. Verified in-game: the character now takes the directional light and casts a proper shadow. Dropping the emissive map and halving the base colour to 1024² also took the glb from 11 MB to 2.2 MB, which is why the repo is nowhere near the LFS threshold.

**2026-08-13 — The character keeps 9,300 tris against a 2,500-tri budget.**
Joshua chose not to decimate. One character at 9.3k costs nothing on this machine, and decimating a skinned mesh risks pulling the weights around. The budget still governs anything we model ourselves; this is a note that the number in ART_DIRECTION is a target for hand-made assets, not a ceiling enforced on imports. Revisit if crowds of NPCs ever appear.

**2026-08-13 — Movement speeds are retuned to the animations' own strides. Supersedes the Phase 2 tuning.**
The clips are paced for a real human: measured against the imported rig, the walk covers 1.40 m/s and the run 4.90 m/s. Phase 2's 4.6 / 7.4 were roughly three times faster, which would have meant playing the walk at 3.1× — frantic and obviously wrong. Offered the choice between stretching the clips and slowing the character, Joshua chose to slow the character, so `walk_speed` 4.6 → 1.4, `run_speed` 7.4 → 4.9, `crouch_speed` 2.0 → 1.0. `acceleration` 16 → 8 and `friction` 24 → 12 are rescaled to keep roughly Phase 2's *feel* (about 0.18 s to reach walking pace, a 0.6 s wind-up into a run) rather than its numbers. This is a real change to how the game plays and is the main thing to judge at playtest; every value is an `@export`, so reversing it is a number change. Knock-on: the graybox run-only gap was 4.0 m and a running jump now spans about 3.9 m, so the far platform moved to make the gap 2.8 m — still uncrossable at a walk (1.1 m). The 1.3 m crouch tunnel needed no change: the crouched traveler stands 1.19 m.

**2026-08-13 — The locomotion blend space is anchored at each clip's measured stride speed, which removes the need for any playback-rate correction.**
`tools/measure_gaits.gd` plays each clip against the real rig and measures how fast the planted foot travels backwards relative to the hips — that is the speed the clip "wants" to move at. Those numbers (0, 1.4, 4.9) are the blend-space anchor positions, and the blend position is simply the player's planar speed. Because idle is anchored at 0 m/s, blending it toward walk shortens the stride in proportion, so the blended pose's own ground speed always equals the blend position across the whole range. The usual `TimeScale` node correcting playback rate against speed is therefore unnecessary, and the tree is two blend spaces and three clips rather than a pair of nested blend trees. Measured in the running game by `tools/verify_player.gd`: the planted foot slips 14% of body speed at both walk and run. The two gaits agreeing to the same figure is the evidence that what remains is the foot rolling through its stance, not a stride mismatch.

**2026-08-13 — The animator tracks the state it asked for, rather than reading back the current one.**
`AnimationNodeStateMachinePlayback.travel()` only takes effect when the tree next processes, so `get_current_node()` still reports the previous state within the same tick. Driving off it meant the jump was cancelled the instant it was requested: `play_jump()` travelled to `jump`, then the same tick's `set_locomotion()` saw "still in locomotion, and airborne" and travelled to `fall`. The animator now remembers its own request, and a one-shot (jump or landing) holds the machine for that clip's length before locomotion may speak again. Caught by `tools/verify_player.gd`, which asserts the expected state after each input — not something a screenshot would ever have shown.

**2026-08-13 — Crouched movement holds a pose. A known gap, not an oversight.**
Meshy's `Cautious_Crouch_Walk_Right` is a lateral strafe: its planted foot travels 1.01 m/s sideways and 0.00 m/s forward. No rotation fixes that, because rotating the clip turns the facing and the travel together. The source set has no forward crouch walk, so `crouch_walk` is a held crouch pose and the feet slide while crouch-moving. Crouch is deliberately slow (1.0 m/s) to keep that quiet, and the Phase 3 gate asks for no foot-sliding at walk and run specifically. The crouch clips come from `CrouchLookAroundBow` instead, whose 1.10–1.19 m head height happens to match the 1.15 m crouch capsule almost exactly — which is why no collider or tunnel retuning was needed. The fix, when it matters, is a handful of extra Meshy clips (forward crouch walk, a real fall, a real landing).

**2026-08-13 — `assets/blender/` carries a `.gdignore`.**
Godot 4 imports `.blend` files natively and tried to, failing on a missing Blender path in headless mode, and would otherwise have imported the raw Meshy source as a second game asset. The `.gdignore` keeps the whole sources folder outside the import pipeline: `assets/blender/` is for editing, `assets/models/` is for the game.
