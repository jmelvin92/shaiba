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
    house/                   # house.tscn + house.gd, from assets/models/house.glb
    interior_cutaway.gd      # `InteriorCutaway`: shared by every enterable building
    camel/                   # camel.tscn, camel.gd (Phase 6 Part 2)
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
  lowpoly.py                 # shared box/drum/profile mesh builder + palette
  build_player.py            # Blender: Meshy source .glb -> player.blend + player.glb
  build_house.py             # Blender: the desert house -> house.blend + house.glb
  build_furnishings.py       # Blender: ten reusable interior props, one glb each
  map_palette_materials.py   # points a .glb.import's materials at palette .tres
  verify_house.gd            # Phase 6 Part 1 gate (see below)
  shoot_house.gd             # homestead screenshots at the gameplay camera
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
| `--orbit` | with the camera turned to any bearing, is "forward" still away from it? |

Keep these working as movement changes — they are how a "feels wrong" report
gets turned into a number, and three times now the number has pointed somewhere
other than the obvious culprit.

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

## Sand deformation (as built in Phase 5)

Footprints can't be per-chunk geometry edits (too costly, breaks streaming). Instead: a **deformation texture in world space around the player**, owned by `SandDeformation` (`scenes/world/terrain/sand_deformation.gd`, a node in world.tscn).

- **Storage:** a ping-pong pair of `SubViewport`s (RGBA16F, 2048² over a 128 m region — a footprint needs 4+ texels to resolve; 1024 aliased). Each update renders the previous accumulation into the other viewport through `shaders/sand_deform_copy.gdshader` (shifted on recentre, reduced by decay) with new stamps drawn additively on top. The region follows the player in **whole-texel** steps, so carried content is copied texel-for-texel — recentring can never blur or swim prints.
- **Stamping:** anything marks the sand by emitting `stamped(world_xz, radius, strength, angle, stretch)`; the level connects that signal to `SandDeformation.stamp()`. The player's `FootstepStamper` child watches the toe bones and stamps at the measured foot-plant moment (a planted foot nearly stops; a swinging one moves at ~2× body speed), adds faint drag stamps while wading deep sand, and splats on landing. The camel (Phase 6) needs only its own stamper child + one connect.
- **Display:** `sand_terrain.gdshader` samples the texture for vertex depression (lit correctly for free by the derivative normals) and a **multiplicative** darkening (a fixed tint vanishes where the colour ramp already paints thin sand dark). Print strength is capped by vertex `COLOR.a` = depressible depth, rescaled to saturate at 0.3 m of sand — hard ground takes nothing. `deform_strength = 0` (the default) keeps every level without a SandDeformation node inert.
- **Memory is "long but local":** prints fade over `fade_seconds` (180 s, Joshua-approved) and the whole accumulation migrates downwind (`wind_drift_per_minute`, whole-texel steps) so old trails smear the way the dunes lie. Walk beyond the region and distant prints quietly reset — the per-chunk persistent overlay stays deferred.
- **Cost:** passes run only when something changed (stamps/recentre, rate-capped) or while prints are still fading (4 Hz); once everything has faded the system is fully idle — zero cost standing still. Worst measured main-thread pass: 0.8 ms.
- **Biome contract (recorded in DECISIONS):** the texture stores material-blind "pressed" values in R; **G is reserved** for future per-material decay classes (mud/snow); COLOR.a gating is what confines prints to ground that can take them.

`tools/verify_prints.gd` is the phase gate as an executable (run windowed): stamp↔bone alignment, off-trail cleanliness, landing splat, recentre survival, wind drift, decay-to-idle, pass cost.

## Buildings and props (as built in Phase 6, Part 1)

A building is an imported model plus two small scripts; there is no building framework and there should not be one until a second building exists.

- **Assets are generated by committed Blender scripts.** `tools/build_house.py` and `tools/build_furnishings.py` build everything out of boxes, drums and extruded profiles from the shared `tools/lowpoly.py`. Reproducible export, and every dimension is a named constant the Godot side can be checked against.
- **Collision comes from the glTF `-col` name suffix**: the importer generates a `StaticBody3D` with a trimesh shape from the mesh itself, so collision cannot drift from what is drawn. The body hangs *under* the `MeshInstance3D` — `occluder_fader.gd` was extended to resolve that layout.
- **One mesh object per wall side per storey.** The fader ghosts a whole `GeometryInstance3D`, so this is what lets the wall in the way ghost by itself instead of taking the room's far wall and floor with it.
- **`scenes/props/house/house.gd`** (`House`) does the two things the model can't carry: sorts each part onto the right physics layer, and hands the parts above the floor — structure *and* furnishings — to the cutaway.
- **`scenes/props/interior_cutaway.gd`** (`InteriorCutaway`) opens a building up when someone walks in. An `Area3D` reports occupants; the cut plane sits `cut_margin` above the occupant's feet; parts wholly above it fade out and hide, parts the plane crosses ghost to `ghost_transparency`, parts below stay solid. Deriving the plane from the occupant's height is what makes one node serve any number of storeys, and makes furnishings sort themselves by which floor they stand on.
- **The single-writer rule:** `OccluderFader` and `InteriorCutaway` both write `GeometryInstance3D.transparency`, so no part may be visible to both. Cutaway-managed parts (upper slab, upper walls, roof, all furnishings) sit on layer 1 alone; fader-managed parts (ground walls, stair, awning) sit on layer 5. `verify_house.gd` asserts it.
- **Furnishings are independent assets** — one `.blend`/`.glb` each, instanced under a `Furnishings` node. `tools/map_palette_materials.py` points each model's materials at the palette `.tres` files through its `.import`, so palette edits reach every asset without a re-export.
- **POI ground:** `TerrainSettings` levels a pad at a seeded site (`get_homestead_center`), and because everything samples the same analytic functions, mesh, collision, spawn seating, print depth and camera lift all inherit it. `LevelRoot` moves `homestead.tscn` onto the pad and takes the player's start from its `PlayerSpawn` marker.

`tools/verify_house.gd` is Part 1's gate as an executable (headless): doorway passable at walk and run, walls block, the stair climbs to the upper floor, the cutaway opens *and closes*, and the layer partition holds. `tools/shoot_house.gd` (windowed) captures the review screenshots at the real gameplay camera.

## Main scene flow

`world.tscn` is the main scene. It owns: `desert_environment.tscn` (`WorldEnvironment` + `DirectionalLight3D` per ART_DIRECTION lighting), `ChunkManager` (Phase 4+), and instances of `player` and `camera_rig`. The camera rig gets its follow target set by the level at ready — the rig itself never searches the tree for the player.

Both playable level scenes (`world.tscn`, `graybox.tscn`) use `LevelRoot` as their root script. It does exactly one job, calling only *down* into its own children: hand the camera rig its follow target, and connect the rig's `yaw_changed` signal to the player's `set_view_yaw` so movement input stays camera-relative. Neither feature scene knows the other exists.

## Physics conventions

- **Collision layers:** 1 = world/terrain (and every static prop), 2 = player, 3 = *fadeable occluder*. Anything that should turn see-through when it hides the player sits on layers 1 **and** 3 (`collision_layer = 5`); terrain stays on layer 1 alone so it can never fade out from under the character. The player is on layer 2 by itself and masks layer 1.
- **The camera never moves to avoid geometry.** `scenes/camera/occluder_fader.gd`, a child of the camera rig, fades whatever is in the way instead. Give every new prop `collision_layer = 5` unless it is terrain. One narrow exception since the 19° camera: the rig *lifts vertically* just enough to keep 1.2 m of clearance above the terrain's analytic height under the camera — framing distance never changes, so this is not the rejected ducking (DECISIONS.md).
- **Physics interpolation is on project-wide.** Anything that moves does so in `_physics_process`, never `_process`, so gameplay nodes share one 60 Hz tick and interpolation smooths them to the render rate together. Code that teleports a node must call `reset_physics_interpolation()`. Input that arrives at the render rate — mouse motion, notably — is banked and applied on the tick, for the same reason.
- **The camera orbits, the pitch does not.** A left-click drag (`camera_orbit`) turns the rig freely around the player; the vertical component of the drag is ignored. Movement stays camera-relative through `yaw_changed` → `player.set_view_yaw`, which is the part that can silently break — `verify_player --orbit` walks four bearings and asserts "forward" is still away from the camera at each.

## Walking on things that were modelled

Geometry the player walks on is constrained by the controller, not only by looks. Two numbers in `player.gd` govern more level design than their names suggest, and both have already produced architecture that looked perfect and could not be used (see ART_DIRECTION's modelling rules, and DECISIONS):

- **`max_step_height`** (0.35 m) sets the tallest step, and — because the probe lifts the capsule by it before reaching forward — also the *headroom* a doorway needs above any threshold: the player's height plus this.
- **`step_probe_margin` + the capsule radius** set the shallowest usable stair tread (~0.41 m). A shallower tread puts the next riser inside the probe's reach, and the whole flight reads as a wall.

`step_probe_slim` (0.07 m) is why grazing a jamb or a side wall no longer defeats the probe. Before it, a doorway with 0.20 m of geometric slack had 0.12 m you could actually walk through; the fix is what makes the *modelled* clearance the real clearance. When adding a doorway or stair, sweep several approach lanes rather than walking the middle once — `verify_house._lanes_are_wide_enough` is the worked example.
