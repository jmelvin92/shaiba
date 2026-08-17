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
## Mega-dunes: the giant Shaybah-scale ridges the ordinary dune field rides on
## top of. Same wind-aligned sampling as dune_noise, far lower frequency.
@export var mega_noise: FastNoiseLite
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
## Height of the mega-dune ridges, metres. 0 disables the field entirely —
## the desert Phase 4 shipped is exactly mega_amplitude = 0.
@export_range(0.0, 40.0, 0.5) var mega_amplitude: float = 0.0
## Shaping exponent on the mega field — same role as dune_sharpness: widens
## the low ground between ridges and sharpens their crests.
@export_range(1.0, 3.0, 0.05) var mega_sharpness: float = 1.6
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

@export_group("Coast")
## Distance, metres, from the homestead centre west (-X) to the mean waterline.
## 0 disables the coast entirely — the desert exactly as Phase 4 shipped it.
## Joshua's pick (2026-08-17): about a 30-second walk, ≈ 55 m.
@export_range(0.0, 500.0, 1.0) var coast_distance: float = 55.0
## Height of the sea surface, metres. Must stay below the deepest desert
## hollow (measured -3.50 this seed) by more than the visual wave amplitude,
## so no inland basin can ever dip under the water plane and flood — or even
## be lapped by a wave crest.
@export_range(-20.0, 0.0, 0.1) var sea_level: float = -3.8
## Shoreline wander along the coast — bays and headlands, never a ruler line.
@export var coast_noise: FastNoiseLite
## Amplitude of the shoreline wander, metres. Bounded so the waterline can
## never wander into the homestead's blend band (see _choose coast distances).
@export_range(0.0, 40.0, 1.0) var coast_wiggle: float = 10.0
## Width of the dry beach, metres: from the waterline up to where the desert
## takes over.
@export_range(5.0, 80.0, 1.0) var beach_width: float = 28.0
## Height of the beach's top edge above sea level, metres.
@export_range(0.0, 6.0, 0.1) var beach_rise: float = 1.8
## Steepest slope, degrees, of the "ceiling" that caps dune height near the
## coast. Dunes rise gradually inland from the beach instead of towering over
## the waterline — and every coast-manufactured slope stays under the 31°
## budget by construction.
@export_range(5.0, 30.0, 0.5) var coast_slope_max_deg: float = 22.0
## Seabed profile: a gentle near-shore shelf, then the deep. The shelf reaches
## [member seabed_shelf_depth] by [member seabed_shelf_distance] out, and the
## floor continues to [member seabed_deep_depth] by [member seabed_deep_distance].
@export_range(0.5, 10.0, 0.1) var seabed_shelf_depth: float = 4.0
@export_range(10.0, 200.0, 5.0) var seabed_shelf_distance: float = 70.0
@export_range(5.0, 60.0, 0.5) var seabed_deep_depth: float = 24.0
@export_range(50.0, 600.0, 10.0) var seabed_deep_distance: float = 260.0
## How much of the substrate noise survives underwater as seabed relief.
## Damped to zero near the waterline so the wading shallows stay smooth.
@export_range(0.0, 1.0, 0.05) var seabed_relief: float = 0.35
## Sand depth on the dry beach and on the seabed, metres. Beach sand is deep
## enough to take full footprints; both carry a share of the drift patchiness.
@export_range(0.0, 2.0, 0.05) var beach_sand_depth: float = 0.45
@export_range(0.0, 2.0, 0.05) var seabed_sand_depth: float = 0.6
## Height above sea level, metres, over which sand reads dark and wet — the
## swash band. Also where wind ripples fade out (wet sand holds no ripples).
@export_range(0.0, 2.0, 0.05) var wet_band: float = 0.45
## Colour-ramp tone of the dry beach (0 = sand_shadow, 1 = sand_light). High:
## a beach reads as pale dry sand, whatever its literal sand depth.
@export_range(0.0, 1.0, 0.01) var beach_tone: float = 0.78

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
## How much of the mega-dune height counts toward the colour ramp. Mega-dunes
## are tens of metres of sand, which would pin the whole ridge at the ramp's
## sand_light end; discounting most of it keeps the ordinary dune-vs-flat
## tonal read on the mega slopes, with just a gentle lightening toward the
## great crests.
@export_range(0.0, 1.0, 0.05) var mega_tone_weight: float = 0.15

## The sand tones the chunk builder bakes into vertex colours. Filled from the
## resources/palette/ .tres files by [method load_palette] on the main thread
## before any builds start — a worker thread calling load() gets its own cache
## view, so a builder-side load would silently miss any runtime palette change
## (that exact failure is why these live here). Defaults mirror the committed
## palette so a settings resource used without load_palette still renders sane.
var sand_shadow_color: Color = Color("A85419")
var sand_mid_color: Color = Color("D97E2E")
var sand_light_color: Color = Color("EFA254")

## Wind rotation applied to dune sample coordinates, cached by [method setup].
var _wind_cos: float = 1.0
var _wind_sin: float = 0.0

## Where the homestead stands, and the substrate height it was levelled to.
## Chosen once by [method setup] and never written again, so builder threads
## may read them freely.
var _homestead_center: Vector2 = Vector2.ZERO
var _homestead_base: float = 0.0

## Coast frame, cached by [method setup]: the mean waterline x, the ceiling
## slope as a gradient, and the shore distance beyond which the coast provably
## changes nothing (the early-out that keeps the far desert byte-identical).
var _coast_enabled: bool = false
var _coast_x: float = 0.0
var _coast_slope: float = 0.4
var _coast_free_d: float = 0.0

## Softness, metres, of the smooth-min that presses dunes under the coast
## ceiling — big enough that clipped crests round off instead of creasing.
const COAST_SMIN_K: float = 3.0

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
	if mega_noise != null:
		mega_noise.seed = world_seed + 4
	if coast_noise != null:
		coast_noise.seed = world_seed + 5
	var wind_yaw: float = deg_to_rad(wind_yaw_degrees)
	_wind_cos = cos(wind_yaw)
	_wind_sin = sin(wind_yaw)
	# The homestead is chosen on the raw desert; only then is the coast framed
	# relative to it (the sea sits west of wherever the pad landed). The flag
	# stays false during the search so the site score never reads a shoreline
	# that has not been placed yet.
	_coast_enabled = false
	_choose_homestead(world_seed)
	_coast_enabled = coast_distance > 0.0 and coast_noise != null
	_coast_x = _homestead_center.x - coast_distance
	_coast_slope = tan(deg_to_rad(coast_slope_max_deg))
	# Beyond this shore distance the ceiling clears the tallest possible dune
	# stack by more than the smooth-min softness, so the clamp is exactly a
	# no-op and the desert stays bit-identical to a coastless world.
	_coast_free_d = beach_width + (
		base_amplitude + dune_amplitude + mega_amplitude + drift_amplitude
		+ depth_floor + COAST_SMIN_K - sea_level - beach_rise
	) / maxf(_coast_slope, 0.05)


## Reads the sand tones out of the palette .tres files (still the single
## source of truth for the hex values). Main thread only, before builds start.
func load_palette() -> void:
	sand_shadow_color = _palette_color("sand_shadow")
	sand_mid_color = _palette_color("sand_mid")
	sand_light_color = _palette_color("sand_light")


static func _palette_color(palette_name: String) -> Color:
	var material: StandardMaterial3D = load(
		"res://resources/palette/%s.tres" % palette_name
	) as StandardMaterial3D
	return material.albedo_color


## Centre of the homestead pad, world XZ. Deterministic from the world seed.
func get_homestead_center() -> Vector2:
	return _homestead_center


## Height of the levelled pad the homestead is built on, metres.
func get_homestead_surface() -> float:
	return get_surface_height(_homestead_center)


## --- Coast queries (Phase 6.7) ---------------------------------------------


## Whether this world has an ocean west of the desert.
func has_coast() -> bool:
	return _coast_enabled


## Height of the sea surface, metres.
func get_sea_level() -> float:
	return sea_level


## Signed distance to the waterline, metres: positive inland (east), negative
## out to sea. INF when the coast is disabled, which keeps every consumer's
## "am I near water" check a plain comparison.
func get_shore_distance(world_xz: Vector2) -> float:
	if not _coast_enabled:
		return INF
	return world_xz.x - _shore_x(world_xz.y)


## Depth of water over this point, metres. 0.0 on dry land (and everywhere,
## when the coast is disabled) — the wading limit and the audio bed key off it.
func get_water_depth(world_xz: Vector2) -> float:
	if not _coast_enabled:
		return 0.0
	return maxf(sea_level - get_surface_height(world_xz), 0.0)


## How wet the sand is here, 0 dry to 1 soaked: 1 underwater, fading to 0
## across the swash band above the waterline. Footprint decay classes and the
## wet-sand look both read this.
func get_wetness(world_xz: Vector2) -> float:
	if not _coast_enabled:
		return 0.0
	var height: float = get_surface_height(world_xz)
	return 1.0 - smoothstep(0.0, wet_band, height - sea_level)


## The waterline's x at a given z: the mean coast line plus the seeded wander.
func _shore_x(world_z: float) -> float:
	return _coast_x + coast_wiggle * coast_noise.get_noise_2d(world_z, 0.0)


## The surface the coast wants at a signed shore distance: the beach profile
## climbing from sea level, or the seabed dropping away — continuous through
## d = 0 by construction (both end exactly at sea_level there).
func _coast_surface_target(d: float, raw_base: float) -> float:
	if d >= 0.0:
		return sea_level + beach_rise * pow(clampf(d / beach_width, 0.0, 1.0), 1.4)
	var out: float = -d
	var drop: float = seabed_shelf_depth * smoothstep(0.0, seabed_shelf_distance, out) + (
		seabed_deep_depth - seabed_shelf_depth
	) * smoothstep(seabed_shelf_distance, seabed_deep_distance, out)
	var relief: float = raw_base * seabed_relief * smoothstep(0.0, 60.0, out)
	return sea_level - drop + relief


## Sand thickness the coast zone carries: beach sand blending into seabed
## sand, with a share of the drift patchiness so neither reads as a flat coat.
func _coast_sand_target(d: float, world_xz: Vector2) -> float:
	var patch: float = drift_amplitude * 0.4 * drift_noise.get_noise_2d(
		world_xz.x, world_xz.y
	)
	var flat: float = lerpf(
		beach_sand_depth, seabed_sand_depth, smoothstep(0.0, 30.0, -d)
	)
	return maxf(flat + patch, 0.05)


## The height cap dune sand must stay under near the coast — rising inland at
## coast_slope_max_deg, so dunes shrink toward the sea on a bounded gradient
## instead of being sliced off in a narrow blend. The 0.5 m slack keeps the
## beach's own gentle relief from being shaved flat.
func _coast_ceiling(d: float) -> float:
	var inland: float = maxf(d - beach_width, 0.0)
	var beach_t: float = clampf(d / beach_width, 0.0, 1.0)
	return sea_level + beach_rise * pow(beach_t, 1.4) + _coast_slope * inland + 0.5


## Polynomial smooth minimum: exactly min() once |a - b| > k, softly rounded
## inside — how dune crests meet the coast ceiling without a crease.
static func _smin(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


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
	var raw: float = base_amplitude * base_noise.get_noise_2d(world_xz.x, world_xz.y)
	if not _coast_enabled:
		return raw
	var d: float = world_xz.x - _shore_x(world_xz.y)
	if d >= beach_width:
		return raw
	# Inside the beach band (and everywhere out to sea) the substrate blends to
	# the coast profile minus the sand it carries, so base + sand lands exactly
	# on the profile — and on sea level right at the waterline.
	var w: float = 1.0 - smoothstep(0.0, beach_width, d)
	var target: float = _coast_surface_target(d, raw) - _coast_sand_target(d, world_xz)
	return lerpf(raw, target, w)


func _raw_sand_depth(world_xz: Vector2) -> float:
	# Rotate into the wind frame and compress the along-wind axis, which
	# stretches the dune pattern across the wind.
	var along: float = (world_xz.x * _wind_cos + world_xz.y * _wind_sin) * wind_stretch
	var across: float = -world_xz.x * _wind_sin + world_xz.y * _wind_cos
	var dune_raw: float = maxf(dune_noise.get_noise_2d(along, across), 0.0)
	var dunes: float = dune_amplitude * pow(dune_raw, dune_sharpness)
	var drift: float = drift_amplitude * drift_noise.get_noise_2d(world_xz.x, world_xz.y)
	var depth: float = maxf(dunes + drift + depth_floor + _mega_height(along, across), 0.0)
	if not _coast_enabled:
		return depth
	var d: float = world_xz.x - _shore_x(world_xz.y)
	if d >= _coast_free_d:
		# The ceiling provably clears any dune here — the far desert stays
		# bit-identical to a coastless world.
		return depth
	# Press the dune stack under the coast ceiling: sand may only be as thick
	# as the ceiling leaves room for above the local substrate.
	var raw_base: float = base_amplitude * base_noise.get_noise_2d(world_xz.x, world_xz.y)
	var allowed: float = maxf(_coast_ceiling(d) - raw_base, 0.0)
	depth = maxf(_smin(depth, allowed, COAST_SMIN_K), 0.0)
	if d < beach_width:
		var w: float = 1.0 - smoothstep(0.0, beach_width, d)
		depth = lerpf(depth, _coast_sand_target(d, world_xz), w)
	return maxf(depth, 0.0)


## The mega-dune ridge height at a point already rotated into the wind frame.
## Mega-dunes are sand, so they live in the depth field: prints, deep-sand
## movement and the colour ramp all see them without any new plumbing.
func _mega_height(along: float, across: float) -> float:
	if mega_amplitude <= 0.0 or mega_noise == null:
		return 0.0
	var raw: float = maxf(mega_noise.get_noise_2d(along, across), 0.0)
	return mega_amplitude * pow(raw, mega_sharpness)


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
	var base: float = get_base_height(world_xz)
	var ripple: float = ripple_amplitude * ripple_noise.get_noise_2d(world_xz.x, world_xz.y)
	ripple *= smoothstep(0.0, ripple_fade_depth, depth)
	# Ripples die on the homestead pad. Levelling the base and the sand depth
	# still left a few centimetres of wind texture, which is nothing in open
	# desert and everything under a building: a flat-bottomed floor slab laid
	# on it has sand standing proud of it across most of its area.
	ripple *= 1.0 - _homestead_weight(world_xz)
	if _coast_enabled:
		# Wet sand holds no wind ripples: fade them out through the swash band,
		# which also keeps them off the seabed.
		ripple *= smoothstep(sea_level + 0.02, sea_level + wet_band, base + depth)
	return base + depth + ripple


## Sand depth normalised to the colour ramp, 0–1. Shared by the mesh builder
## (vertex COLOR.a, Phase 5's per-fragment print-depth cap) and anything that
## wants "how sandy is it here" without caring about metres.
##
## Most of the mega-dune height is discounted first (see mega_tone_weight);
## the print-depth cap doesn't care — anywhere on a mega-dune is still far
## deeper than a full print needs — and the tonal read is what's at stake.
func get_normalized_depth(world_xz: Vector2) -> float:
	var depth: float = get_sand_depth(world_xz)
	if mega_amplitude > 0.0:
		var along: float = (world_xz.x * _wind_cos + world_xz.y * _wind_sin) * wind_stretch
		var across: float = -world_xz.x * _wind_sin + world_xz.y * _wind_cos
		var discount: float = _mega_height(along, across) * (1.0 - mega_tone_weight)
		depth = maxf(depth - discount * (1.0 - _homestead_weight(world_xz)), 0.0)
	return clampf(depth / tone_full_depth, 0.0, 1.0)


## Colour-ramp input for the mesh builder's vertex tint, 0 (sand_shadow) to 1
## (sand_light). Identical to [method get_normalized_depth] everywhere the
## coast has no say — vertex COLOR.a (the print-depth cap) keeps reading the
## true normalised depth, this shapes only what the sand *looks* like:
## a pale dry beach, a dark wet swash band, and a seabed that shows pale
## through the shallows before fading into the deep.
func get_surface_tone(world_xz: Vector2) -> float:
	var tone: float = get_normalized_depth(world_xz)
	if not _coast_enabled:
		return tone
	var d: float = get_shore_distance(world_xz)
	if d >= beach_width:
		return tone
	var height: float = get_surface_height(world_xz)
	var w: float = 1.0 - smoothstep(0.0, beach_width, d)
	tone = lerpf(tone, beach_tone, w)
	if height >= sea_level:
		var wet: float = 1.0 - smoothstep(0.0, wet_band, height - sea_level)
		return lerpf(tone, 0.04, wet * 0.9)
	# Underwater: pale sand in the wading shallows, darkening with true water
	# depth so the deep already reads deep from above.
	return lerpf(0.3, 0.0, smoothstep(0.3, 7.0, sea_level - height))
