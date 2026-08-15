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

@export_group("Homestead")
## Radius, metres, of the flat pad the homestead stands on. Nothing inside it
## keeps any dune shape: a building needs ground that is actually level.
@export_range(4.0, 40.0, 0.5) var homestead_radius: float = 13.0
## Width, metres, of the band where the pad blends back into the desert. The
## slope this band produces is roughly 1.5 * height_difference / width, so a
## wider band is what keeps the join inside the terrain's 31 deg slope budget.
@export_range(4.0, 40.0, 0.5) var homestead_blend: float = 15.0
## Sand thickness on the pad, metres. Thin on purpose — packed courtyard earth,
## which also means footprints fade out as you approach the door, and the
## colour ramp paints it the darker sand_shadow end.
@export_range(0.0, 1.0, 0.05) var homestead_sand_depth: float = 0.25
## Annulus, metres from the origin, searched for a site.
@export_range(20.0, 300.0, 5.0) var homestead_search_min: float = 45.0
@export_range(20.0, 400.0, 5.0) var homestead_search_max: float = 110.0

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

## Where the homestead stands, and the substrate height it was levelled to.
## Chosen once by [method setup] and never written again, so builder threads
## may read them freely.
var _homestead_center: Vector2 = Vector2.ZERO
var _homestead_base: float = 0.0

## Candidate sites are taken from this many rings and spokes in the search
## annulus, and each is judged against this many directions. Fixed rather than
## exported: they trade setup time (a few milliseconds) against site quality,
## which is not a thing worth tuning per-world.
const SITE_RINGS: int = 6
const SITE_SPOKES: int = 24
const SITE_PROBES: int = 12


## Seeds every noise field from [param world_seed], caches the wind frame and
## picks the homestead site. Must be called once before any sampling; never
## after builder threads start.
func setup(world_seed: int) -> void:
	base_noise.seed = world_seed
	dune_noise.seed = world_seed + 1
	drift_noise.seed = world_seed + 2
	ripple_noise.seed = world_seed + 3
	var wind_yaw: float = deg_to_rad(wind_yaw_degrees)
	_wind_cos = cos(wind_yaw)
	_wind_sin = sin(wind_yaw)
	_choose_homestead(world_seed)


## Centre of the homestead pad, world XZ. Deterministic from the world seed.
func get_homestead_center() -> Vector2:
	return _homestead_center


## Height of the levelled pad the homestead is built on, metres.
func get_homestead_surface() -> float:
	return get_surface_height(_homestead_center)


## Height of the hard ground under the sand, metres.
func get_base_height(world_xz: Vector2) -> float:
	var raw: float = _raw_base_height(world_xz)
	var flatten: float = _homestead_weight(world_xz)
	if flatten <= 0.0:
		return raw
	return lerpf(raw, _homestead_base, flatten)


## Thickness of the sand layer, metres. 0.0 is a valid answer: exposed hard
## ground. This is the number Phase 5's footprints and the player's deep-sand
## movement hooks key off.
func get_sand_depth(world_xz: Vector2) -> float:
	var raw: float = _raw_sand_depth(world_xz)
	var flatten: float = _homestead_weight(world_xz)
	if flatten <= 0.0:
		return raw
	return lerpf(raw, homestead_sand_depth, flatten)


## The desert as it would be with no homestead in it. The site search has to
## sample this rather than the public functions, which would otherwise be
## reading a pad that has not been chosen yet.
func _raw_base_height(world_xz: Vector2) -> float:
	return base_amplitude * base_noise.get_noise_2d(world_xz.x, world_xz.y)


func _raw_sand_depth(world_xz: Vector2) -> float:
	# Rotate into the wind frame and compress the along-wind axis, which
	# stretches the dune pattern across the wind.
	var along: float = (world_xz.x * _wind_cos + world_xz.y * _wind_sin) * wind_stretch
	var across: float = -world_xz.x * _wind_sin + world_xz.y * _wind_cos
	var dune_raw: float = maxf(dune_noise.get_noise_2d(along, across), 0.0)
	var dunes: float = dune_amplitude * pow(dune_raw, dune_sharpness)
	var drift: float = drift_amplitude * drift_noise.get_noise_2d(world_xz.x, world_xz.y)
	return maxf(dunes + drift + depth_floor, 0.0)


## How completely the homestead pad overrides the desert at a point: 1 on the
## pad, easing to 0 across the blend band.
func _homestead_weight(world_xz: Vector2) -> float:
	var distance: float = world_xz.distance_to(_homestead_center)
	if distance <= homestead_radius:
		return 1.0
	var outer: float = homestead_radius + homestead_blend
	if distance >= outer:
		return 0.0
	return 1.0 - smoothstep(homestead_radius, outer, distance)


## Picks the flattest site in the search annulus.
##
## Levelling a pad into a dune body would leave a wall of sand around it far
## steeper than the player can walk, so the site is chosen to need the least
## levelling in the first place: the score is the largest height difference the
## blend band would have to absorb, and the search simply takes the smallest.
func _choose_homestead(world_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed
	# A seeded angular offset so two worlds don't put the homestead on the same
	# bearing, while the lattice itself stays fixed and reproducible.
	var offset: float = rng.randf() * TAU

	var best: Vector2 = Vector2(homestead_search_min, 0.0)
	var best_score: float = INF
	for ring: int in range(SITE_RINGS):
		var t: float = float(ring) / float(maxi(SITE_RINGS - 1, 1))
		var radius: float = lerpf(homestead_search_min, homestead_search_max, t)
		for spoke: int in range(SITE_SPOKES):
			var angle: float = offset + TAU * float(spoke) / float(SITE_SPOKES)
			var candidate: Vector2 = Vector2(cos(angle), sin(angle)) * radius
			var score: float = _site_score(candidate)
			if score < best_score:
				best_score = score
				best = candidate

	_homestead_center = best
	_homestead_base = _raw_base_height(best)


## The worst height step the blend band around [param centre] would have to
## swallow, plus a nudge away from deep sand so the pad prefers a flat between
## dunes over a hollow carved out of one.
func _site_score(centre: Vector2) -> float:
	var pad: float = _raw_base_height(centre) + homestead_sand_depth
	var worst: float = 0.0
	for probe: int in range(SITE_PROBES):
		var angle: float = TAU * float(probe) / float(SITE_PROBES)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		for band: float in [0.0, 0.5, 1.0]:
			var at: Vector2 = centre + direction * (
				homestead_radius + homestead_blend * band
			)
			var surface: float = _raw_base_height(at) + _raw_sand_depth(at)
			worst = maxf(worst, absf(surface - pad))
	return worst + _raw_sand_depth(centre) * 0.5


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
	# Ripples die on the homestead pad. Levelling the base and the sand depth
	# still left a few centimetres of wind texture, which is nothing in open
	# desert and everything under a building: a flat-bottomed floor slab laid
	# on it has sand standing proud of it across most of its area.
	ripple *= 1.0 - _homestead_weight(world_xz)
	return get_base_height(world_xz) + depth + ripple


## Sand depth normalised to the colour ramp, 0–1. Shared by the mesh builder
## (vertex COLOR.a, Phase 5's per-fragment print-depth cap) and anything that
## wants "how sandy is it here" without caring about metres.
func get_normalized_depth(world_xz: Vector2) -> float:
	return clampf(get_sand_depth(world_xz) / tone_full_depth, 0.0, 1.0)
