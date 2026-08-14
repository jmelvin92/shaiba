# Architecture — Shaiba

How the project is structured and why. Change this doc only alongside a DECISIONS.md entry.

## Principles

1. **Feature folders, co-located scripts.** Everything belonging to a feature (scene, script, feature-specific resources) lives in one folder under `scenes/`. You should be able to understand "the player" by opening `scenes/player/` and nothing else.
2. **Scenes are components.** Each .tscn is self-contained and runnable standalone (F6). Composition over inheritance: the world *contains* a player instance and a camera-rig instance; they don't know about each other's internals.
3. **Call down, signal up.** A script may call methods on its own children. It never uses `get_parent()` or `../` paths. Anything a feature needs to tell the outside world is a signal; whoever instanced it connects.
4. **Autoloads are a last resort.** Start with a single `Game` autoload (world seed, later: game state/pause). A new autoload requires a DECISIONS.md entry explaining why signals/composition couldn't do it. This is the main defense against spaghetti — global singletons are how small Godot projects rot.
5. **Data in resources.** Shared tunables (palette materials, noise settings, curves) are .tres files in `resources/`, referenced by scenes — not duplicated constants in scripts.

## Directory layout

```
project.godot                # repo root IS the Godot project root
CLAUDE.md, PLAN.md, docs/    # process & design docs (Godot ignores them)
autoload/
  game.gd                    # `Game` singleton: world seed, top-level state. Keep small.
scenes/
  player/                    # player.tscn, player.gd (+ later: footstep_stamper.gd …)
  camera/                    # camera_rig.tscn, camera_rig.gd, occluder_fader.gd
  world/
    world.tscn               # main scene: environment, terrain, spawns player+camera
    graybox.tscn             # permanent movement-test level (Phase 2)
    level_root.gd            # `LevelRoot`: shared root script for both level scenes
    desert_environment.tscn  # WorldEnvironment + sun, instanced by both levels
    terrain/                 # chunk_manager.gd, terrain_chunk.gd/.tscn,
                             #   terrain_debug_overlay.gd/.tscn (F3 readout)
  props/
    house/                   # house.tscn (+ collision), from assets/models/house.glb
    camel/                   # camel.tscn, camel.gd
    …                        # one folder per prop
  ui/                        # later: HUD, menus (empty until needed)
resources/
  palette/                   # one flat StandardMaterial3D .tres per ART_DIRECTION color
  terrain/                   # terrain_settings.gd (TerrainSettings), desert.tres,
                             #   sand_terrain_material.tres
shaders/                     # sand_terrain.gdshader (Phase 5 extends it in place)
assets/
  blender/                   # .blend sources — the editable truth for every model
                             # (carries a .gdignore: Godot must not import sources)
  models/                    # exported .glb — what Godot imports
  textures/                  # rare; palette style needs almost none
tools/                       # build and measurement scripts — not shipped, not
                             # part of any scene, safe to run at any time
  build_player.py            # Blender: Meshy source .glb -> player.blend + player.glb
  measure_gaits.gd           # each locomotion clip's natural stride speed
  verify_player.gd           # movement quality-gate probe (see below)
  verify_terrain.gd          # terrain quality-gate probe (see below)
  shoot_player.gd            # screenshots each pose at the gameplay camera
  shoot_terrain.gd           # screenshots characteristic terrain spots
  dump_scene.gd              # prints an imported scene's node tree and animations
```

**`tools/verify_player.gd` is the Phase 3 gate as an executable.** Run headless;
each mode answers one question that an eye cannot judge reliably:

| mode | question |
|---|---|
| *(none)* | does a planted foot stay put, and does every animation state arrive? |
| `--feel` | how long to reach speed, stop, and reverse? |
| `--stairs` | how far does the collider move in a tick, and how far does the *mesh*? |
| `--graybox` | do the level fixtures still behave at the current speeds? |
| `--sweep` | what body speed matches a clip's stride? |

Keep these working as movement changes — they are how a "feels wrong" report
gets turned into a number, and twice now the number has pointed somewhere other
than the obvious culprit.

**`tools/verify_terrain.gd` is the Phase 4 gate as an executable.** Run
headless (`--headless --path . --script res://tools/verify_terrain.gd [-- <mode>]`):

| mode | question |
|---|---|
| *(none)* | same seed ⇒ bit-identical world (+ printable hash)? edges seam-free? slopes < 31°? deep and shallow sand both exist? |
| `--collision` | do raycasts against the physics world land exactly on the rendered mesh, and within the curvature bound of the analytic field? |
| `--walk` | over a 2 km walk: does installing chunks ever cost > 4 ms a frame, does the chunk count plateau, does memory hold, does step-up ever misfire? |
| `--sand` | does walking speed in deep and shallow sand match what the depth predicts, and does the mesh visibly settle? |

`--walk` compresses time via `Engine.time_scale`; run it *without* `--headless`
(add `--realtime`) for honest whole-frame times. `tools/shoot_terrain.gd` (run
windowed) screenshots the spawn, the deepest dune, bare hard ground and the
steepest slope for eyeballing against ART_DIRECTION.

## World / chunk system (as built in Phase 4)

The map is a large open desert, so terrain is **chunked and streamed from its first implementation** — never one big mesh.

- **Two-layer sand model:** the surface is `base_height + sand_depth` — a hard substrate under a sand layer of varying thickness. The dunes *are* the sand: dune bodies are metres deep, the inter-dune flats a thin dusting over hard ground. "How much sand is here" is a first-class query because footprints (Phase 5), movement feel, and wind all key off it.
- **`TerrainSettings`** (`resources/terrain/terrain_settings.gd`, saved as `desert.tres`) is the single source of truth: four `FastNoiseLite` fields (base/dune/drift/ripple), every amplitude and wavelength as an export, and the pure sampling functions `get_surface_height(xz)` / `get_base_height(xz)` / `get_sand_depth(xz)` / `get_normalized_depth(xz)`. Queries are **analytic** — they evaluate noise directly, so they work for any position (loaded or not), are thread-safe after `setup(seed)`, and can never disagree with the mesh builder, which samples the same functions. Between vertices they differ from collision by the field's curvature over one cell (≤ ~5 cm, audited); raycast when exact collision height matters. `get_deformed_height` is a name reserved for Phase 5, expected to stay unimplemented (deformation is visual-only).
- **World space:** infinite-capable grid of square chunks (**64 m**, 1 m cells). Chunk coords = `Vector2i(floor(x/size), floor(z/size))`. Slopes are kept below 31° by tuning + the `verify_terrain` slope audit, so the player's 32° `floor_max_angle` and step-up probe can never mistake terrain for a wall.
- **Determinism:** everything derives from `Game.world_seed` + global integer grid indices. Shared edge vertices are computed from the same integers by both neighbours — bit-identical, so seams cannot open and there are no skirts. Same seed ⇒ same world, every run.
- **ChunkManager** (`scenes/world/terrain/chunk_manager.gd`, a node inside world.tscn — *not* an autoload): each frame collects finished builds, installs them under a ~2 ms budget, requests missing chunks within `load_radius` (2 ⇒ 5×5, nearest first) and frees beyond `unload_radius` (3; unload > load prevents border thrashing). `set_tracked(player)` synchronously builds the spawn area so collision exists before the first physics tick; the level then seats the player on `get_surface_height`.
- **Threading:** one `WorkerThreadPool` task per chunk runs the pure `TerrainChunk.build_data` (no tree access); results return via a mutex-guarded queue. The worker builds sample arrays and the `HeightMapShape3D`; the **ArrayMesh is created on the main thread** in `apply()` — creating rendering resources off-thread corrupts RIDs under the headless dummy renderer. Chunks added at runtime call `reset_physics_interpolation()`.
- **Collision = visuals:** `HeightMapShape3D` and the mesh triangulate cells along the same diagonal; `verify_terrain --collision` asserts raycasts match the mesh to ~0.
- **Look:** one `ShaderMaterial` (`shaders/sand_terrain.gdshader`) — albedo from vertex `COLOR.rgb` (palette sand-tone gradient + patchy dither, computed by the builder from the palette .tres files), flat facets from screen-space-derivative normals (correct under any future vertex displacement), roughness 1. Vertex `COLOR.a` carries normalised sand depth for Phase 5.
- **Horizon:** at the 19° camera the top of frame reaches ground several hundred metres out, so the world loads an 11×11 grid (radius 5) and an exponential warm haze in desert_environment.tscn melts the far dunes into the sky's horizon tone before the loaded edge — the horizon is real terrain dissolving into atmosphere, never a backdrop. (At the original 45° pitch no far-field of any kind was needed; DECISIONS.md keeps the math.)
- **A chunk owns everything in it:** terrain mesh, collision, and (Phase 6+) scattered props spawned from the same deterministic seed. Unloading a chunk frees its contents.
- **Later hooks** (design for, don't build): per-chunk saved-state overlay (for survival-mode changes to the world), POI/biome injection at generation time, nav data per chunk.

## Sand deformation (built in Phase 5, designed now)

Footprints can't be per-chunk geometry edits (too costly, breaks streaming). Instead: a **deformation texture in world space around the player** — a `SubViewport` accumulates "stamp" brushes (footsteps, drag trails); the terrain shader samples it in the vertex shader for depression + darkened `sand_shadow` tint. The region follows the player in snapped increments (avoids swimming artifacts); texture decays slowly = wind refills prints. Memory is **"long but local"**: minutes of persistence near the player, distant prints quietly reset (a per-chunk persistent overlay was considered and deferred — see PLAN.md Phase 5). Anything that should mark the sand implements one small "stamper" interface (player feet, camel feet, later dragged objects). Distant chunks keep zero-strength uniforms — zero cost far away.

Phase 4 pre-wired it: print depth is capped per-fragment by the sand that is actually there (vertex `COLOR.a` = normalised depth), the stamps go through `get_sand_depth`, the deformation uniforms extend `sand_terrain.gdshader` rather than swapping materials, and the derivative normals light any displaced geometry correctly for free.

## Main scene flow

`world.tscn` is the main scene. It owns: `desert_environment.tscn` (`WorldEnvironment` + `DirectionalLight3D` per ART_DIRECTION lighting), `ChunkManager` (Phase 4+), and instances of `player` and `camera_rig`. The camera rig gets its follow target set by the level at ready — the rig itself never searches the tree for the player.

Both playable level scenes (`world.tscn`, `graybox.tscn`) use `LevelRoot` as their root script. It does exactly one job, calling only *down* into its own children: hand the camera rig its follow target, and connect the rig's `yaw_changed` signal to the player's `set_view_yaw` so movement input stays camera-relative. Neither feature scene knows the other exists.

## Physics conventions

- **Collision layers:** 1 = world/terrain (and every static prop), 2 = player, 3 = *fadeable occluder*. Anything that should turn see-through when it hides the player sits on layers 1 **and** 3 (`collision_layer = 5`); terrain stays on layer 1 alone so it can never fade out from under the character. The player is on layer 2 by itself and masks layer 1.
- **The camera never moves to avoid geometry.** `scenes/camera/occluder_fader.gd`, a child of the camera rig, fades whatever is in the way instead. Give every new prop `collision_layer = 5` unless it is terrain. One narrow exception since the 19° camera: the rig *lifts vertically* just enough to keep 1.2 m of clearance above the terrain's analytic height under the camera — framing distance never changes, so this is not the rejected ducking (DECISIONS.md).
- **Physics interpolation is on project-wide.** Anything that moves does so in `_physics_process`, never `_process`, so gameplay nodes share one 60 Hz tick and interpolation smooths them to the render rate together. Code that teleports a node must call `reset_physics_interpolation()`.
