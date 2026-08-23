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
  player/                    # player.tscn, player.gd, footstep_stamper.gd,
                             #   interactor.gd (the player half of interaction)
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
    interactable.gd          # `Interactable`: the prop half of interaction
    door/                    # door.tscn + door.gd, from assets/models/door.glb —
                             #   one reusable swinging door for every building
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
  build_door.py              # Blender: the shared door leaf -> door.blend + door.glb
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

### Raised sand — the mound channel (added in Phase 6.8, Part 1)

The deformation texture's **B channel heaves sand up** instead of pressing it down — the sand worm's traveling wake. `SandDeformation.raise()` mirrors `stamp()` exactly (same signal-and-connect contract, `SandWorm.raised` → `sand.raise` in the level), but the mark lives entirely in B with its own fast decay (`mound_settle_seconds`, ~1.4 s — a churned heap slumps in seconds, so the wake is a collapsing swell behind the worm, never a berm wall). Three rendering rules bought with visible failures, all in the shaders: raises use a **coreless brush** (a flat core saturates overlaps into a plateau the 1 m flat-shaded mesh draws as terraced cliffs); the terrain shader saturates B **softly** (`x/(1+x)`, never a hard clamp — same mesa problem); and lift only begins above a small **raise floor** (flat shading flips a whole facet's tone over centimetres, so a nearly-settled mound must release the surface completely). Prints are provably untouched: raise writes nothing into R/G, press writes nothing into B, and `verify_worm` plus the whole Phase 5 gate assert it.

## The sand worm (as built in Phase 6.8, Part 1)

`scenes/props/sand_worm/` — `SandWorm`, a bodiless underground agent in Part 1 (the rigged body is Part 2, the threat behaviour Part 3). It swims the analytic terrain, never physics: position integrates a heading at `swim_speed` with a turn-rate limit, Y follows `get_surface_height - swim_depth`, and travel-gated `raised` marks (the `min_step_distance` lesson, applied from day one) draw the mound.

- **Steering is margin-based**: `_swim_margin(xz)` returns the tightest of three constraint margins (sand deeper than `min_swim_depth`, `shore_margin` from the waterline, clearance beyond the homestead pad + blend + `homestead_margin`), sand metres weighted ×10. Candidate headings around the desired one are probed at five points out to `lookahead`; the first with **comfortable** slack (≥ 2.0) wins, otherwise the max-margin arc — the worm climbs the margin gradient away from trouble instead of skimming the legal line, which is what keeps turn-arc overshoot from crossing it. Margins are sized to the turn radius (speed / turn rate, ~5.7 m): `lookahead` and `shore_margin` must stay comfortably above it.
- **Dormant is free**: physics processing off until `summon()` (F7 in debug; F8 cycles WANDER/ORBIT/APPROACH), no stamps ⇒ the deformation system idles. Summon scans expanding rings (1×–4× `summon_distance`) because the player often stands where the worm may not go (the courtyard, the surf).
- **Rumble is silent-safe** per 6.6: `creatures/worm_rumble_loop` through `SoundBank`, an `AudioStreamPlayer3D` created only when the file exists, distance attenuation doing the distance work.
- **F3 shows a worm line** (state / distance / local sand depth): the overlay pulls `get_debug_text()`, wired down through `ChunkManager.get_debug_overlay()` by LevelRoot.

`tools/verify_worm.gd` is the Part 1 gate as an executable (windowed): dormant zero-cost, the real F7 binding, raise marks landing in B and nothing but B, channel isolation both directions, a 180 sim-second wander with every guardrail asserted, settle-to-idle, pass cost. `tools/shoot_worm_ladder.gd` reproduces the size-ladder evidence (three scales, staged wake + posed placeholder breach, plus the live mound mid-orbit).

**The body (Part 2)** is hand-built by `tools/build_worm.py` (26 × 3.4 m — the rig contract from the ladder pick; ~1,900 tris of shingled ring plates, a tri-lobed mouth on three lip bones, teeth rings, night_blue gullet) and driven **procedurally**: the worm keeps a path memory (one sample per 0.5 m of head travel) and every spine bone is posed each tick at its rest arc-distance behind the head, facing along the path — `pose = skeleton⁻¹ · M · rest` with rigid per-ring skinning, so plates hinge like armor. **The breach is not an animation**: `breach()` lifts the *head's* height along a bell over ~36 m of travel, and the body follows through the same surface crossings via the path memory — correct at any angle and speed by construction. Mouth lips hinge open with height above the sand; a palette-sand particle burst + an oversized raise stamp + a silent-safe one-shot fire at each crossing; the wake pauses while the head is airborne. The body has **no collision** even as a hunter — the strike's bite is a distance check (`kill_radius` from the head while it is out of the sand), never physics. Dormant means invisible and processing-free. `tools/shoot_worm.gd` stages and captures the breach sequence at the gameplay camera.

### The hunt (Part 3)

**The worm hears; it never sees.** Two nodes split the threat cleanly:

- **`WormDirector`** (`scenes/world/worm_director.gd`, a plain node in the world scene) decides *when the worm exists*. LevelRoot connects `player.noise_made(position, loudness)` to `director.hear_noise` — one signal, one connect, and deliberately generic: any future noisemaker (thrown rock, radio, jukebox) is the same contract. The director gates each noise by **sand depth at the noise's position** (`min_carry_depth`, matched to the worm's swimmable minimum — packed pads, thin skins and the courtyard are physically silent), charges an attraction meter that decays during quiet play, and wakes the worm (`SandWorm.hunt`) far away (`hunt_spawn_distance`) when it crests. While a hunt runs it forwards gated noise to `SandWorm.hear`; when the hunt ends (`hunt_ended`) it enforces a `calm_seconds` cooldown so encounters never chain. F10 skips the meter for playtesting. Rarity is emergent — there is no spawn timer anywhere.
- **`SandWorm`'s hunt state machine** rides on top of the Part 1 steering (which keeps every guardrail for free): **SEEK** swims to the last-heard point → **STALK** circles the *sound* in rings that tighten with each fresh noise, then turns straight in once the ring is inside commit range (the closing rush) → **STRIKE** commits to the captured point: churn stamps + a silent-safe telegraph one-shot boil the sand there while the worm charges, the breach fires at the bell's entry distance so the head erupts exactly on the point, and anything within `kill_radius` of the out-of-sand head is `swallowed`. A quiet spell drops STALK to **PROWL** (circle the stale point, then give up); **DEPART** swims away and despawns to zero cost. The strike targets a *point, never a homing body* — displacement during the telegraph always dodges — and commits only onto swimmable ground (`_swimmable(_heard_at)`), which is the safe-ground rule made mechanical.

**The kill chain keeps every arrow clean**: worm emits `swallowed(prey)` → LevelRoot cuts control (`Player.set_control_enabled(false)` — the whole physics tick early-returns, so the sequence may write the player's position directly), drags the body down with the diving head, fades **`ScreenFade`** (`scenes/ui/screen_fade/` — reusable awaitable CanvasLayer fade, layer 15: above the game, below the pause menu) to black, dismisses the worm, reloads the last save (`SaveSystem.load_game`) or re-seats at the homestead spawn when no save exists, restores control, snaps the camera, fades back in. No health system exists; death is the reload.

`verify_worm` (grown for Part 3) drives the whole loop through the real nodes: pad noise never charges the meter, sustained deep-sand noise wakes a distant hunter, seek → stalk → strike escalation, the telegraph landing at the committed point, a strike at a stale point missing the distant player, silence winding down to despawn + the director's calm window, prey inside the homestead keep-out never being struck, and the kill: swallow → control cut → sequence completes → control and screen restored, worm gone.

## Coast & ocean (as built in Phase 6.7)

West of the desert the map becomes ocean. The whole biome is an extension of the analytic terrain model — no new world system, no second mesh pipeline:

- **The coast lives in `TerrainSettings`**, framed relative to the homestead after the site is chosen: the mean waterline runs `coast_distance` (55 m, Joshua's 30-second-walk pick) west of the pad, wandering by seeded `coast_noise` into bays and headlands. Everything below is ordinary streamed terrain — the seabed has real mesh, real `HeightMapShape3D` collision, and real analytic queries all the way down (~24 m by 260 m out), because the future (swimming, diving, a submarine) must never have to retrofit it.
- **Dunes shrink toward the sea on a bounded gradient**: a "ceiling" rising inland at `coast_slope_max_deg` presses the dune/mega stack down via a smooth-min, so no coast-manufactured slope can exceed the 31° budget and the far desert is **bit-identical** to a coastless world (`verify_ocean` proves it against a `coast_distance = 0` twin). The beach blends base ground onto a profile that crosses sea level exactly at the shoreline; a **dry-floor invariant** keeps every beach point past the swash a wave's amplitude above sea level, and `sea_level` (-3.8) sits below the deepest possible desert hollow — so the water plane can never flood anything inland.
- **New queries** consumers key off: `has_coast()`, `get_sea_level()`, `get_shore_distance()` (signed, +inland, INF when coastless), `get_water_depth()`, `get_wetness()`, and `get_surface_tone()` — the last splitting the *visible* sand tint (pale dry beach, dark swash band, seabed fading pale→deep) from vertex `COLOR.a`, which keeps carrying true normalised depth for the print cap.
- **The sea surface is `scenes/world/ocean/`**: one player-following plane at sea level whose vertices snap to a fixed world lattice, waves computed from world position (visual only — the analytic sea never moves). `shaders/ocean_water.gdshader` needs no terrain data at all: it reads the **depth buffer** for the water's optical thickness per fragment — color grade, opacity, contact foam at the waterline and rolling foam lines that ride equal-thickness bands shoreward all fall out of that one number. Facet normals + low roughness make the golden-hour glint. On a coastless world (or the graybox) the node hides itself and costs nothing.
- **Wading, not swimming (yet)**: the player reads `get_water_depth` each tick; walking in slows like deep sand, and at `wade_depth_limit` (0.4 m, knee-deep — Joshua's call) the deeper-ward velocity component is eased out, with a gentle shoreward push past the limit. A soft wall: motion along the waterline is never touched. All inert off-coast.
- **Wet sand remembers longer**: `SandDeformation.stamp` resolves `get_wetness` at each stamp and writes press × wetness into the deformation texture's **G channel — the per-material decay-class slot the Phase 5 contract reserved**. The copy shader decays wet prints at `wet_fade_scale` of the dry rate, G scaling with R so the class survives every pass.
- **Surf bed**: `Ambience` gains an `ocean_surf_loop.ogg` bed (silent-safe like everything in 6.6) whose volume follows `get_shore_distance` — full on the beach, a murmur at the homestead, gone in the desert.

**`tools/verify_ocean.gd` is the phase gate as an executable**:

| mode | question |
|---|---|
| *(none)* | shoreline where the pick put it, deterministic per seed? knee-deep band on every transect? seabed reaches the deep? nothing inland floods? coast slopes < 31°? far desert bit-identical to a coastless world? |
| `--wade` | does the real controller wade to the knee and hold there without bobbing, walk the surf line freely, and come straight back ashore? |
| `--wetprints` | (windowed) does a print at the waterline outlive one up the dry beach? |
| `--perf` | (windowed) 60 fps+ with the full ocean vista on screen? |

`tools/shoot_ocean.gd` (windowed) reproduces the review shots, the day sweep and the water-color ladder.

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

`tools/verify_house.gd` is Part 1's gate as an executable (headless): the closed front door blocks and E opens/closes it from both sides, the doorway is passable at walk and run, walls block, the stair climbs to the upper floor and its door admits you, the cutaway opens *and closes*, and the layer partition holds. `tools/shoot_house.gd` (windowed) captures the review screenshots at the real gameplay camera.

## Interaction (as built in the Phase 6 continuation)

Pressing **E** near something usable uses it. Two components, wired only by physics overlap and one signal, so any prop can join without touching player code:

- **`Interactable`** (`scenes/props/interactable.gd`, an `Area3D`) is the prop half: a `prompt` string, a `prompt_anchor`, an `enabled` switch and an `interacted(actor)` signal. It forces itself onto layer 4, where nothing physical can see it. The owning prop shapes its volume to cover everywhere the prop should be reachable from and connects the signal — the Phase 5 stamper shape: one signal, one connect.
- **`Interactor`** (`scenes/player/interactor.gd`, an `Area3D` child of the player) is the player half: masks layer 4 only and calls `interact(owner)` on the nearest enabled Interactable when E is pressed. `player.gd` does not know it exists. **There is no on-screen prompt** (Joshua's call — players know what E does); the Interactable's `prompt` string stays maintained for the verify harness and a possible future accessibility toggle.
- **`Door`** (`scenes/props/door/`) is the first customer and the template for prop-side use: wraps `door.glb` (origin on the hinge) with an `AnimatableBody3D` box collider that turns with the leaf, connects its own Interactable, rewrites the prompt Open/Close, swings *away* from whoever opens it, and idles at zero cost once settled. A building instances it per doorway; the one thing the building says is whether the door is fader-managed (layer 5, like the ground walls) or cutaway-managed (`fadeable` off — the house hands the upper door's leaf to the cutaway so it vanishes with its storey).

## Persistence (as built on the Phase 6.6 branch, 2026-08-15)

Save/load is a walk over a group, not a registry. Any node with state worth saving joins the `"persistent"` group in `_ready` and implements three methods — the whole contract:

- **`get_persistence_key() -> String`** — a stable ID the state files under. Singletons return a literal (`"player"`, `"game_clock"`, `"camera"`); multi-instance props expose an `@export var persistence_id` and pass it through `SaveSystem.key_for(self, persistence_id)`, which falls back to the node's tree path when empty. Hand-pick IDs for anything placed more than once (`house_front_door`) — path-derived keys break the moment a scene is reorganized, and saves must outlive refactors.
- **`capture_state() -> Dictionary`** — JSON-safe values only (numbers, strings, bools, arrays). Vectors go in as `[x, y, z]`.
- **`restore_state(state, context)`** — read with `.get(key, default)` so older saves missing a field restore to something sensible. `context` is a Dictionary of level references a restore may need (`"actor"`: the player — the torch stand uses it to put a carried torch back in the hand); ignore keys you don't use, and it may grow more.

**`SaveSystem`** (`scenes/world/save_system.gd`, a plain Node the level owns) knows no prop types: save walks the group and files dictionaries by key into `user://saves/save_01.json` (versioned, timestamped); load hands them back, warns-and-skips saved keys no node answers to (old saves stay loadable forever), then re-runs `ChunkManager.set_tracked` so the ground under a far-teleported player has collision before the next physics tick. The pause menu only *announces* (`save_requested`/`load_requested` signals); `LevelRoot` connects them down into the SaveSystem and reports outcomes back — the UI never touches files. Restores are **silent and instant** (doors snap, no creak): sound belongs to actions, and nobody acted. Deliberately not saved: footprints (Phase 5's memory is ephemeral by design) and player motion state (a load lands you standing still). User *settings* are separate (`user://settings.cfg`, the pause menu's own) — preferences are not world state.

## Main scene flow

`world.tscn` is the main scene. It owns: `desert_environment.tscn` (`WorldEnvironment` + `DirectionalLight3D` per ART_DIRECTION lighting), `ChunkManager` (Phase 4+), and instances of `player` and `camera_rig`. The camera rig gets its follow target set by the level at ready — the rig itself never searches the tree for the player.

Both playable level scenes (`world.tscn`, `graybox.tscn`) use `LevelRoot` as their root script. It does exactly one job, calling only *down* into its own children: hand the camera rig its follow target, and connect the rig's `yaw_changed` signal to the player's `set_view_yaw` so movement input stays camera-relative. Neither feature scene knows the other exists.

## Physics conventions

- **Collision layers:** 1 = world/terrain (and every static prop), 2 = player, 3 = *fadeable occluder*, 4 = *interaction volumes*. Anything that should turn see-through when it hides the player sits on layers 1 **and** 3 (`collision_layer = 5`); terrain stays on layer 1 alone so it can never fade out from under the character. The player is on layer 2 by itself and masks layer 1. Layer 4 is `Interactable` areas only — nothing physical collides with it, and only the player's `Interactor` queries it.
- **Moving colliders under a relocated ancestor:** `AnimatableBody3D` defaults to `sync_to_physics = true`, which only tracks *local* transform changes — a body under anything `LevelRoot` moves (the homestead, notably) is silently left behind in physics space. Set `sync_to_physics = false` (as `door.tscn` does); the body then follows ancestor moves like any imported `StaticBody3D`, and a swinging part still pushes the player by depenetration. (Cost a debugging round — see DECISIONS.)
- **The camera never moves to avoid geometry.** `scenes/camera/occluder_fader.gd`, a child of the camera rig, fades whatever is in the way instead. Give every new prop `collision_layer = 5` unless it is terrain. One narrow exception since the 19° camera: the rig *lifts vertically* just enough to keep 1.2 m of clearance above the terrain's analytic height under the camera — framing distance never changes, so this is not the rejected ducking (DECISIONS.md).
- **Physics interpolation is on project-wide.** Anything that moves does so in `_physics_process`, never `_process`, so gameplay nodes share one 60 Hz tick and interpolation smooths them to the render rate together. Code that teleports a node must call `reset_physics_interpolation()`. Input that arrives at the render rate — mouse motion, notably — is banked and applied on the tick, for the same reason.
- **The camera orbits, the pitch does not.** A left-click drag (`camera_orbit`) turns the rig freely around the player; the vertical component of the drag is ignored. Movement stays camera-relative through `yaw_changed` → `player.set_view_yaw`, which is the part that can silently break — `verify_player --orbit` walks four bearings and asserts "forward" is still away from the camera at each.

## Walking on things that were modelled

Geometry the player walks on is constrained by the controller, not only by looks. Two numbers in `player.gd` govern more level design than their names suggest, and both have already produced architecture that looked perfect and could not be used (see ART_DIRECTION's modelling rules, and DECISIONS):

- **`max_step_height`** (0.35 m) sets the tallest step, and — because the probe lifts the capsule by it before reaching forward — also the *headroom* a doorway needs above any threshold: the player's height plus this.
- **`step_probe_margin` + the capsule radius** set the shallowest usable stair tread (~0.41 m). A shallower tread puts the next riser inside the probe's reach, and the whole flight reads as a wall.

`step_probe_slim` (0.07 m) is why grazing a jamb or a side wall no longer defeats the probe. Before it, a doorway with 0.20 m of geometric slack had 0.12 m you could actually walk through; the fix is what makes the *modelled* clearance the real clearance. When adding a doorway or stair, sweep several approach lanes rather than walking the middle once — `verify_house._lanes_are_wide_enough` is the worked example.

Three more probe behaviours came out of the second "hung up on stairs" report (2026-08-14, all measured — see DECISIONS):

- **The step is looked for in up to three directions**: the input direction first (velocity turns parallel to a riser the moment sliding starts, which used to deflect an angled approach clean off the flight), then velocity, then — when both read a wall — square against each steep face the sweeps actually met. Perpendicular to the face is the one direction the reach geometry is honest in, and it is gated on the input pushing into that face (`dot > 0.4`), so brushing past a curb never hoists you onto it.
- **A low-momentum step also advances the body** to the spot the measurement proved out (one capsule-radius past the face). Without this, stepping up from a standstill leaves the capsule perched on the tread's lip over its old footing; it slides straight back off and the cycle repeats forever — the stair-foot jam. The visual absorbs the shift (`_step_shift`) exactly as it absorbs the vertical pop, and ordinary walking-speed climbs never trigger it, so the Phase 3 stair numbers are untouched.
- **Rails must out-climb the probe**: any top surface within `max_step_height` of an adjacent tread *is* a step and will be climbed — see the parapet rule in ART_DIRECTION's modelling rules. `verify_house._stair_drift_climbs` walks six angled/wall-pressed climbs and fails if any misses the top.
