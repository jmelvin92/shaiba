class_name SandWorm
extends Node3D
## The desert's buried giant (Phase 6.8 Part 1): an underground agent that
## swims through deep sand and announces itself only by the traveling mound
## of sand heaved in its wake. There is no body yet — Part 2 rigs Joshua's
## model onto this same agent — and no threat: behaviours exist for the
## debug keys, not for hunting. That arrives in Part 3.
##
## The worm is pure phenomenon: it reports its wake by signal only (the
## Phase 5 stamper pattern — the level connects [signal raised] to
## SandDeformation.raise), reads the analytic terrain for where swimming is
## possible, and never touches physics — nothing collides with something
## that is not there.
##
## Guardrails: it swims only where the sand is deep enough to hide it, and
## never onto the homestead pad or into the sea. Steering probes candidate
## headings ahead and takes the closest-to-desired one whose path stays
## swimmable, so it curves away from hard ground the way a fish curves away
## from a bank — it cannot strand itself.
##
## Dormant cost is zero by construction: physics processing is off until
## [method summon], and with no stamps flowing the deformation system idles.

## Steering aims to keep this much slack on every constraint (~0.2 m of
## extra sand depth or 2 m of extra distance): the worm starts avoiding
## trouble well before the legal line, so its turn arcs never cross it.
const COMFORT_MARGIN: float = 2.0
## A summon spot must be this comfortable — placement into a cramped pocket
## is what forces grazing escapes.
const SUMMON_MARGIN: float = 3.0

## Sand heaved up along the worm's path — same contract as FootstepStamper's
## `stamped`, but for the deformation system's raise channel.
signal raised(
	world_xz: Vector2, radius: float, strength: float, angle: float, stretch: float
)

## Debug behaviours for seeing the mound without waiting for it. WANDER
## curves through the dunes on its own; ORBIT circles the player; APPROACH
## swims at the player and passes beneath — a harmless flyby.
enum Mode { WANDER, ORBIT, APPROACH }

@export_group("Swimming")
## Cruise speed through the sand, metres per second. Faster than the player
## runs (4.9) — being outrun is not what makes the worm survivable.
@export_range(0.5, 15.0, 0.1) var swim_speed: float = 5.5
## How fast the worm can turn, degrees per second. Low values make the long
## body believable: it carves arcs, never pivots.
@export_range(10.0, 180.0, 1.0) var turn_rate_degrees: float = 55.0
## How far below the sand surface the body travels, metres. Part 1 uses it
## only to place the rumble emitter; Part 2's body inherits it.
@export_range(0.2, 5.0, 0.1) var swim_depth: float = 1.2
## Steering probe distance, metres — how far ahead a candidate heading is
## tested for swimmable sand. Must comfortably exceed the turn radius
## (swim_speed / turn rate, ~5.7 m at the defaults): the worm commits to
## arcs, so it has to see trouble at least a full turn before reaching it.
@export_range(2.0, 30.0, 0.5) var lookahead: float = 10.0

@export_group("Guardrails")
## Minimum local sand depth the worm will swim into, metres. Keeps it inside
## dune bodies and off the thin desert flats where a buried giant could not
## plausibly fit.
@export_range(0.1, 2.0, 0.05) var min_swim_depth: float = 0.5
## Closest the worm may come to the waterline, metres inland. Sized above a
## full U-turn's sweep (2 × the ~5.7 m turn radius): steering rejects a
## heading before this line, but the arc it turns away on still eats sand.
@export_range(0.0, 40.0, 0.5) var shore_margin: float = 14.0
## Clearance kept beyond the homestead pad's blended edge, metres.
@export_range(0.0, 40.0, 0.5) var homestead_margin: float = 6.0

@export_group("Mound")
## Radius of one wake mark, metres — sized to the worm, so the size ladder
## revisits it.
@export_range(0.2, 6.0, 0.1) var mound_radius: float = 2.4
## Strength of a wake mark, 0–1. The shader caps by local sand depth anyway.
@export_range(0.0, 1.0, 0.05) var mound_strength: float = 1.0
## Metres of travel between wake marks — the travel gate, applied from day
## one (the FootstepStamper min_step_distance lesson).
@export_range(0.2, 4.0, 0.05) var mound_spacing: float = 0.9
## Elongation of each mark along the direction of travel.
@export_range(1.0, 3.0, 0.05) var mound_stretch: float = 1.5

@export_group("Debug behaviours")
## Circling distance for ORBIT, metres.
@export_range(4.0, 40.0, 0.5) var orbit_radius: float = 12.0
## How far from the player a summoned worm surfaces its wake, metres.
@export_range(6.0, 60.0, 1.0) var summon_distance: float = 16.0

## Sound of the passing giant, in metres of audibility. The rumble file is on
## Joshua's sourcing list; until it lands there is no emitter at all.
@export_range(20.0, 200.0, 5.0) var rumble_distance: float = 80.0

var _rumble: AudioStreamPlayer3D = null
var _terrain: TerrainSettings = null
var _focus: Node3D = null
var _mode: Mode = Mode.WANDER
var _active: bool = false
var _heading: float = 0.0
## Metres travelled since summon — the 1D coordinate the wander drift noise
## is sampled along, so the path curves smoothly at any frame rate.
var _odometer: float = 0.0
var _since_mark: float = 0.0
var _drift: FastNoiseLite = null


func _ready() -> void:
	visible = false
	set_physics_process(false)
	_drift = FastNoiseLite.new()
	# The worm's wander is not part of the world's determinism contract — a
	# fixed seed just keeps verify runs repeatable.
	_drift.seed = 1337
	_drift.frequency = 0.03
	# Silent-safe per Phase 6.6: no file, no emitter, no error.
	var stream: AudioStream = SoundBank.stream("creatures/worm_rumble_loop", true)
	if stream != null:
		_rumble = AudioStreamPlayer3D.new()
		_rumble.stream = stream
		_rumble.bus = &"SFX"
		_rumble.max_distance = rumble_distance
		# Doppler on: a low rumble sweeping past is half the dread.
		_rumble.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(_rumble)


## Called by the owning level once terrain exists. Without terrain the worm
## cannot know where sand is and stays dormant forever — the graybox and
## standalone-scene contract.
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain = terrain


## Called by the owning level: who the debug behaviours centre on.
func set_focus(focus: Node3D) -> void:
	_focus = focus


func is_active() -> bool:
	return _active


func get_mode() -> Mode:
	return _mode


## Wake the worm near the focus, scanning expanding rings of candidate spots
## for swimmable sand — the near ring first, out to ~4× summon_distance,
## because the player is often somewhere the worm itself may not go (the
## homestead courtyard, the surf) and the nearest legal sand lies beyond the
## keep-out. Returns false (and stays dormant) when even the far rings hold
## nothing.
func summon(mode: Mode = Mode.WANDER) -> bool:
	if _terrain == null or _focus == null:
		return false
	var centre: Vector2 = Vector2(_focus.global_position.x, _focus.global_position.z)
	for ring: float in [1.0, 1.75, 2.75, 4.0]:
		for i: int in range(16):
			var direction: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
			var at: Vector2 = centre + direction * (summon_distance * ring)
			if _swim_margin(at) < SUMMON_MARGIN:
				continue
			_mode = mode
			global_position = Vector3(
				at.x, _terrain.get_surface_height(at) - swim_depth, at.y
			)
			# Start tangent to the player, not head-on: every mode opens
			# with the mound sweeping past rather than a beeline.
			_heading = direction.angle() + PI * 0.5
			_odometer = 0.0
			_since_mark = 0.0
			_set_active(true)
			return true
	return false


func dismiss() -> void:
	_set_active(false)


## One line for the F3 overlay; the overlay pulls it, the worm pushes nothing.
func get_debug_text() -> String:
	if not _active:
		return "worm dormant"
	var line: String = "worm %s" % Mode.keys()[_mode].to_lower()
	if _focus != null:
		line += "   dist %.1f m" % _focus.global_position.distance_to(global_position)
	if _terrain != null:
		line += "   sand %.2f m" % _terrain.get_sand_depth(_xz())
	return line


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_worm_summon"):
		if _active:
			dismiss()
		else:
			summon(_mode)
	elif event.is_action_pressed("debug_worm_mode"):
		_mode = ((int(_mode) + 1) % Mode.size()) as Mode


func _set_active(on: bool) -> void:
	_active = on
	set_physics_process(on)
	if _rumble != null:
		if on:
			_rumble.play()
		else:
			_rumble.stop()


func _physics_process(delta: float) -> void:
	var desired: float = _desired_heading()
	_heading = rotate_toward(
		_heading, _steer(desired), deg_to_rad(turn_rate_degrees) * delta
	)

	var step: float = swim_speed * delta
	var direction: Vector2 = Vector2.from_angle(_heading)
	global_position.x += direction.x * step
	global_position.z += direction.y * step
	_odometer += step

	# The body rides under the surface it is displacing; smooth the follow so
	# dune slopes never pop the (future) body or the rumble emitter.
	var surface: float = _terrain.get_surface_height(_xz())
	global_position.y = lerpf(
		global_position.y, surface - swim_depth, 1.0 - exp(-4.0 * delta)
	)

	_since_mark += step
	while _since_mark >= mound_spacing:
		_since_mark -= mound_spacing
		raised.emit(_xz(), mound_radius, mound_strength, _heading, mound_stretch)


## Where the current behaviour wants to go, before the sand has its say.
func _desired_heading() -> float:
	match _mode:
		Mode.ORBIT when _focus != null:
			var to_worm: Vector2 = _xz() - Vector2(
				_focus.global_position.x, _focus.global_position.z
			)
			# Tangent around the focus, bent inward or outward toward the
			# orbit radius — a spiral that settles into a circle.
			var radial_error: float = to_worm.length() - orbit_radius
			var tangent: Vector2 = to_worm.orthogonal().normalized()
			var inward: Vector2 = -to_worm.normalized()
			return (tangent + inward * clampf(radial_error * 0.15, -0.8, 0.8)).angle()
		Mode.APPROACH when _focus != null:
			var to_focus: Vector2 = Vector2(
				_focus.global_position.x, _focus.global_position.z
			) - _xz()
			return to_focus.angle()
		_:
			# Wander: the heading drifts with smooth noise over distance
			# travelled, tracing long organic curves through the dune field.
			return _heading + _drift.get_noise_1d(_odometer) * 1.2


## Take the candidate heading closest to desired whose whole probe run keeps
## comfortable slack. In open dunes the first candidate wins and the wander
## is free; anywhere tighter, the pick becomes the max-margin arc — the worm
## climbs the margin gradient away from trouble instead of skimming the
## legal line, which is what keeps turn-arc overshoot from ever crossing it.
func _steer(desired: float) -> float:
	var best: float = _heading
	var best_margin: float = -INF
	for offset: float in [
		0.0, 0.35, -0.35, 0.8, -0.8, 1.4, -1.4, 2.2, -2.2, PI
	]:
		var heading: float = desired + offset
		var margin: float = _path_margin(heading)
		if margin >= COMFORT_MARGIN:
			return heading
		if margin > best_margin:
			best_margin = margin
			best = heading
	return best


## Worst constraint margin along a heading's probe run — five probes out to
## lookahead, dense enough that a few-metre shallow pocket cannot slip
## between them. >= 0 means the whole run is swimmable.
func _path_margin(heading: float) -> float:
	var direction: Vector2 = Vector2.from_angle(heading)
	var worst: float = INF
	for fraction: float in [0.2, 0.4, 0.6, 0.8, 1.0]:
		worst = minf(worst, _swim_margin(_xz() + direction * (lookahead * fraction)))
	return worst


## How comfortably a buried giant may swim here, as the tightest of three
## margins: sand deep enough to hide in, clearance from the sea, clearance
## from the homestead pad. Sand metres are scaled up so a 0.1 m depth
## shortfall weighs like a metre of missing distance — depth is the scarcer
## resource. Negative means unswimmable.
func _swim_margin(at: Vector2) -> float:
	if _terrain == null:
		return -INF
	var margin: float = (_terrain.get_sand_depth(at) - min_swim_depth) * 10.0
	margin = minf(margin, _terrain.get_shore_distance(at) - shore_margin)
	var keep_out: float = (
		_terrain.homestead_radius + _terrain.homestead_blend + homestead_margin
	)
	return minf(
		margin, at.distance_to(_terrain.get_homestead_center()) - keep_out
	)


func _swimmable(at: Vector2) -> bool:
	return _swim_margin(at) >= 0.0


func _xz() -> Vector2:
	return Vector2(global_position.x, global_position.z)
