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
  camera/                    # camera_rig.tscn, camera_rig.gd
  world/
    world.tscn               # main scene: environment, terrain, spawns player+camera
    graybox.tscn             # permanent movement-test level (Phase 2)
    terrain/                 # chunk_manager.gd, terrain_chunk.gd/.tscn (Phase 4)
  props/
    house/                   # house.tscn (+ collision), from assets/models/house.glb
    camel/                   # camel.tscn, camel.gd
    …                        # one folder per prop
  ui/                        # later: HUD, menus (empty until needed)
resources/
  palette/                   # one flat StandardMaterial3D .tres per ART_DIRECTION color
  terrain/                   # FastNoiseLite settings .tres, height curves
shaders/                     # sand_deform.gdshader etc.
assets/
  blender/                   # .blend sources — the editable truth for every model
  models/                    # exported .glb — what Godot imports
  textures/                  # rare; palette style needs almost none
```

## World / chunk system (built in Phase 4, designed now)

The map is a large open desert, so terrain is **chunked and streamed from its first implementation** — never one big mesh.

- **World space:** infinite-capable grid of square chunks (start at **64 m**, tune by profiling). Chunk coords = `Vector2i(floor(x/size), floor(z/size))`.
- **Determinism:** all generation derives from `Game.world_seed` + chunk coords through `FastNoiseLite` (settings stored as .tres in `resources/terrain/`). Same seed ⇒ same world, every run — this is also what makes future save games and POI placement tractable.
- **ChunkManager** (`scenes/world/terrain/chunk_manager.gd`, a node inside world.tscn — *not* an autoload): each frame checks the player's chunk coord; requests missing chunks within `load_radius`, frees chunks beyond `unload_radius` (unload > load to prevent thrashing at borders).
- **Generation off the main thread:** chunk mesh + collision built via `WorkerThreadPool`, then added to the tree on the main thread. Streaming must never hitch the frame (gate: < 4 ms).
- **A chunk owns everything in it:** terrain mesh, collision, and (Phase 6+) scattered props spawned from the same deterministic seed. Unloading a chunk frees its contents.
- **Seams:** neighboring chunks sample the same continuous noise field and share edge vertices exactly — no skirts/welding hacks needed if edge sampling is consistent.
- **Later hooks** (design for, don't build): per-chunk saved-state overlay (for survival-mode changes to the world), POI/biome injection at generation time, nav data per chunk.

## Sand deformation (built in Phase 5, designed now)

Footprints can't be per-chunk geometry edits (too costly, breaks streaming). Instead: a **deformation texture in world space around the player** — a `SubViewport` accumulates "stamp" brushes (footsteps, drag trails); near-terrain material samples it in the vertex shader for depression + darkened `sand_shadow` tint. The region follows the player in snapped increments (avoids swimming artifacts); texture decays slowly = wind refills prints. Anything that should mark the sand implements one small "stamper" interface (player feet, camel feet, later dragged objects). Distant chunks use the plain sand material — zero cost far away.

## Main scene flow

`world.tscn` is the main scene. It owns: `WorldEnvironment` + `DirectionalLight3D` (per ART_DIRECTION lighting), `ChunkManager` (Phase 4+), and instances of `player` and `camera_rig`. The camera rig gets its follow target set by `world.tscn` at ready — the rig itself never searches the tree for the player.
