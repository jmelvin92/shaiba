class_name TerrainSettings
extends Resource
## The desert's shape as data: every noise field and tunable that defines the
## terrain, plus the pure sampling functions that read them.
##
## This resource is the single source of truth for ground height and sand
## depth. Chunk builder threads, the player's sand hooks, and the verification
## tools all sample the same analytic functions, so they can never disagree
## with each other. Queries work for any world position — loaded or not —
## because they evaluate noise directly rather than reading chunk data.
##
## The model is two layers (see docs/ARCHITECTURE.md): a hard substrate
## ([method get_base_height]) under a sand layer of varying thickness
## ([method get_sand_depth]). The dunes *are* the sand — dune bodies are deep
## sand, the flats between them are a thin skin over hard ground. The visible,
## collidable surface is base + sand (+ ripples, which fade out where the sand
## is thin).
##
## Call [method setup] once with the world seed before sampling. After that the
## noises are never mutated, which is what makes concurrent reads from worker
## threads safe.

@export_group("Grid")
## Cells per chunk side. A chunk is chunk_size × cell_size metres square.
@export_range(16, 256, 16) var chunk_size: int = 64
## Metres per grid cell. Kept at 1.0: HeightMapShape3D's samples are one unit
## apart, so any other value would need the collision shape scaled to match.
@export_range(0.5, 4.0, 0.5) var cell_size: float = 1.0

@export_group("Noise fields")
## Hard substrate: long, gentle rolling ground under the sand.
@export var base_noise: FastNoiseLite
## Dune bodies. Sampled in wind-aligned, stretched coordinates so dunes
## elongate across the wind direction.
@export var dune_noise: FastNoiseLite
## Medium-scale signed variation in sand thickness — patchiness that lets the
## hard ground show through where it goes negative.
@export var drift_noise: FastNoiseLite
## Small surface ripples, visible only where the sand is thick enough to hold
## them.
@export var ripple_noise: FastNoiseLite

@export_group("Heights")
## Peak-to-mean amplitude of the substrate, metres.
@export_range(0.0, 10.0, 0.1) var base_amplitude: float = 3.0
## Height of the tallest dune bodies, metres.
@export_range(0.0, 15.0, 0.1) var dune_amplitude: float = 5.5
## Shaping exponent on the dune field. > 1 widens the flats between dunes and
## rounds the transition where a dune rises out of them.
@export_range(1.0, 3.0, 0.05) var dune_sharpness: float = 1.35
## Amplitude of the signed sand-thickness variation, metres.
@export_range(0.0, 2.0, 0.05) var drift_amplitude: float = 0.5
## Height of the small ripples, metres. Kept subtle: the camera is 23 m out.
@export_range(0.0, 0.3, 0.01) var ripple_amplitude: float = 0.06
## Sand thickness on the open flats, metres — the desert floor is dusted, not
## bare, so depth only reaches zero where the drift digs below this.
@export_range(0.0, 1.0, 0.01) var depth_floor: float = 0.15
## Sand depth below which ripples have fully faded out, metres.
@export_range(0.01, 2.0, 0.01) var ripple_fade_depth: float = 0.5

@export_group("Wind")
## Direction the prevailing wind blows toward, degrees yaw. Dunes stretch
## across this direction, the way real transverse dunes lie.
@export_range(-180.0, 180.0, 1.0) var wind_yaw_degrees: float = 30.0
## How strongly dunes are elongated: the along-wind sample axis is compressed
## by this factor, so 0.4 makes dunes about 2.5× longer across the wind than
## along it. 1.0 disables the stretch.
@export_range(0.1, 1.0, 0.05) var wind_stretch: float = 0.4

@export_group("Color")
## Sand depth, metres, at which the surface tone reaches the palette's
## sand_light (dune crests). Shallower sand grades down through sand_mid
## toward sand_shadow on hard ground.
@export_range(0.5, 10.0, 0.1) var tone_full_depth: float = 4.0
## Amplitude of the seeded per-vertex tone jitter that keeps the depth
## gradient from reading as contour bands. Fraction of the 0–1 tone range.
@export_range(0.0, 0.3, 0.01) var tone_dither: float = 0.08

## Wind rotation applied to dune sample coordinates, cached by [method setup].
var _wind_cos: float = 1.0
var _wind_sin: float = 0.0


## Seeds every noise field from [param world_seed] and caches the wind frame.
## Must be called once before any sampling; never after builder threads start.
func setup(world_seed: int) -> void:
	base_noise.seed = world_seed
	dune_noise.seed = world_seed + 1
	drift_noise.seed = world_seed + 2
	ripple_noise.seed = world_seed + 3
	var wind_yaw: float = deg_to_rad(wind_yaw_degrees)
	_wind_cos = cos(wind_yaw)
	_wind_sin = sin(wind_yaw)


## Height of the hard ground under the sand, metres.
func get_base_height(world_xz: Vector2) -> float:
	return base_amplitude * base_noise.get_noise_2d(world_xz.x, world_xz.y)


## Thickness of the sand layer, metres. 0.0 is a valid answer: exposed hard
## ground. This is the number Phase 5's footprints and the player's deep-sand
## movement hooks key off.
func get_sand_depth(world_xz: Vector2) -> float:
	# Rotate into the wind frame and compress the along-wind axis, which
	# stretches the dune pattern across the wind.
	var along: float = (world_xz.x * _wind_cos + world_xz.y * _wind_sin) * wind_stretch
	var across: float = -world_xz.x * _wind_sin + world_xz.y * _wind_cos
	var dune_raw: float = maxf(dune_noise.get_noise_2d(along, across), 0.0)
	var dunes: float = dune_amplitude * pow(dune_raw, dune_sharpness)
	var drift: float = drift_amplitude * drift_noise.get_noise_2d(world_xz.x, world_xz.y)
	return maxf(dunes + drift + depth_floor, 0.0)


## Height of the walkable sand surface, metres — what the terrain mesh and
## collision are built from.
##
## Between mesh vertices the collision surface is a straight edge while this
## function keeps curving, so they can differ by the field's curvature over
## one cell (a few centimetres at most; tools/verify_terrain.gd measures the
## actual bound). Anything that must sit exactly on collision should raycast.
func get_surface_height(world_xz: Vector2) -> float:
	var depth: float = get_sand_depth(world_xz)
	var ripple: float = ripple_amplitude * ripple_noise.get_noise_2d(world_xz.x, world_xz.y)
	ripple *= smoothstep(0.0, ripple_fade_depth, depth)
	return get_base_height(world_xz) + depth + ripple


## Sand depth normalised to the colour ramp, 0–1. Shared by the mesh builder
## (vertex COLOR.a, Phase 5's per-fragment print-depth cap) and anything that
## wants "how sandy is it here" without caring about metres.
func get_normalized_depth(world_xz: Vector2) -> float:
	return clampf(get_sand_depth(world_xz) / tone_full_depth, 0.0, 1.0)
