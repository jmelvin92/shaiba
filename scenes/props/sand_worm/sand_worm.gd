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

## --- Rig constants, mirrored from tools/build_worm.py (change one, change
## both). The body model rests along +Z in Godot space: mouth rim at the
## origin, spine bone k at z = SPINE_ARC[k], nose toward -Z. ---------------
const SPINE_BONES: int = 16
const HEAD_LEN: float = 1.6
const RING_PITCH: float = 1.45
const NOSE_LEN: float = 2.3
const RIM_R: float = 1.55
## Metres of path between stored samples; bones interpolate between them.
const PATH_SAMPLE: float = 0.5
## How far behind the head the path memory must reach (full body + slack).
const PATH_MEMORY: float = 30.0

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
## only to place the rumble emitter; Part 2's body inherits it. The titan's
## spine rides deep — it tunnels through the substrate itself, only its bow
## wave disturbing the sand layer above (which is why [member min_swim_depth]
## stays modest: the worm needs *some* sand to heave, not a body's worth).
@export_range(0.2, 5.0, 0.1) var swim_depth: float = 2.5
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
## Radius of one wake mark, metres — sized to the picked titan scale
## (Joshua, 2026-08-22: rung C, 26 m body).
@export_range(0.2, 6.0, 0.1) var mound_radius: float = 3.8
## Strength of a wake mark, 0–1. The shader caps by local sand depth anyway.
@export_range(0.0, 1.0, 0.05) var mound_strength: float = 1.0
## Metres of travel between wake marks — the travel gate, applied from day
## one (the FootstepStamper min_step_distance lesson).
@export_range(0.2, 4.0, 0.05) var mound_spacing: float = 1.5
## Elongation of each mark along the direction of travel.
@export_range(1.0, 3.0, 0.05) var mound_stretch: float = 1.5

@export_group("Breach")
## Metres of travel the breach arc spans, entry crossing to exit crossing.
@export_range(15.0, 80.0, 1.0) var breach_length: float = 36.0
## Peak height of the head above the surface at the top of the arc, metres.
@export_range(1.0, 15.0, 0.5) var breach_apex: float = 6.5
## Speed multiplier while breaching — the lunge.
@export_range(1.0, 2.0, 0.05) var breach_surge: float = 1.35
## Fully open mouth-lip angle, degrees (hinged at the rim).
@export_range(10.0, 110.0, 1.0) var lip_open_degrees: float = 75.0

@export_group("Debug behaviours")
## Circling distance for ORBIT, metres.
@export_range(4.0, 40.0, 0.5) var orbit_radius: float = 12.0
## How far from the player a summoned worm surfaces its wake, metres.
@export_range(6.0, 60.0, 1.0) var summon_distance: float = 16.0

## Sound of the passing giant, in metres of audibility. The rumble file is on
## Joshua's sourcing list; until it lands there is no emitter at all.
@export_range(20.0, 200.0, 5.0) var rumble_distance: float = 80.0

## Count of sand bursts fired (breach crossings), for verify tooling.
var bursts_fired: int = 0

var _rumble: AudioStreamPlayer3D = null
var _breach_sound: AudioStream = null
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

## The rigged body (Part 2): skeleton driven bone-by-bone along the path.
var _skeleton: Skeleton3D = null
## Rest pose of every bone in skeleton space, captured once — the B in
## pose = skeleton⁻¹ · world-mapping · B.
var _rest: Array[Transform3D] = []
## Arc distance behind the head where each spine bone rides.
var _spine_arc: PackedFloat64Array = PackedFloat64Array()
## Path memory: world positions the head has occupied, one sample per
## PATH_SAMPLE metres of travel, oldest first, with the odometer reading at
## each sample. Bones interpolate between samples.
var _samples: PackedVector3Array = PackedVector3Array()
var _sample_arcs: PackedFloat64Array = PackedFloat64Array()
## Breach state: negative when swimming level, else metres travelled into
## the arc. The head's height rides the arc; the body follows through the
## path memory for free.
var _breach_at: float = -1.0
## Sign of (head height - surface) last tick, for crossing detection.
var _was_above: bool = false
var _mouth_open: float = 0.0
var _burst: GPUParticles3D = null


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
	_breach_sound = SoundBank.stream("creatures/worm_breach_01")
	_setup_body()
	_setup_burst()


## Find the rigged body (Part 2). Everything stays null-safe: a scene without
## the Body child (or a rebuilt glb missing bones) degrades to the Part 1
## bodiless agent instead of erroring.
func _setup_body() -> void:
	var body: Node = get_node_or_null(^"Body")
	if body == null:
		return
	var skeletons: Array[Node] = body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_skeleton = skeletons[0] as Skeleton3D
	_spine_arc.clear()
	for k: int in range(SPINE_BONES):
		_spine_arc.append(0.0 if k == 0 else HEAD_LEN + float(k - 1) * RING_PITCH)
	_rest.clear()
	_rest.resize(_skeleton.get_bone_count())
	for k: int in range(_skeleton.get_bone_count()):
		_rest[k] = _skeleton.get_bone_global_rest(k)
	# The skeleton's bones sweep up to a body length from the node; without a
	# generous AABB the mesh pops out of view whenever the node's own origin
	# leaves the frustum.
	for instance: Node in body.find_children("*", "MeshInstance3D", true, false):
		(instance as MeshInstance3D).custom_aabb = AABB(
			Vector3(-32.0, -32.0, -32.0), Vector3(64.0, 64.0, 64.0)
		)


## The sand thrown at a breach crossing: a one-shot burst of palette sand
## chunks, built in code so the scene stays a plain wrapper.
func _setup_burst() -> void:
	_burst = GPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 130
	_burst.lifetime = 1.1
	_burst.explosiveness = 1.0
	_burst.top_level = true
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 50.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 10.0
	process.gravity = Vector3(0.0, -18.0, 0.0)
	process.scale_min = 0.4
	process.scale_max = 1.0
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 2.4
	_burst.process_material = process
	var grain: BoxMesh = BoxMesh.new()
	grain.size = Vector3(0.2, 0.2, 0.2)
	grain.material = load("res://resources/palette/sand_mid.tres")
	_burst.draw_pass_1 = grain
	add_child(_burst)


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
			# Start tangent to the player, not head-on: every mode opens
			# with the mound sweeping past rather than a beeline.
			summon_at(at, direction.angle() + PI * 0.5, mode)
			return true
	return false


## Place the worm exactly: position, heading, mode. The staging entry point —
## shoot tooling today, Part 3's encounter director tomorrow. Does not check
## swimmability; the caller chooses the spot.
func summon_at(at: Vector2, heading: float, mode: Mode = Mode.WANDER) -> bool:
	if _terrain == null:
		return false
	_mode = mode
	global_position = Vector3(
		at.x, _terrain.get_surface_height(at) - swim_depth, at.y
	)
	_heading = heading
	_odometer = 0.0
	_since_mark = 0.0
	_breach_at = -1.0
	_mouth_open = 0.0
	_was_above = false
	_prefill_path()
	_set_active(true)
	return true


## Seed the path memory with a straight run behind the spawn point, so the
## body lies stretched along the sand from its first frame instead of
## collapsing to a point and unfolding.
func _prefill_path() -> void:
	_samples.clear()
	_sample_arcs.clear()
	var back: Vector2 = -Vector2.from_angle(_heading)
	var arc: float = PATH_MEMORY
	while arc >= PATH_SAMPLE:
		var at: Vector2 = _xz() + back * arc
		_samples.append(Vector3(
			at.x, _terrain.get_surface_height(at) - swim_depth, at.y
		))
		_sample_arcs.append(-arc)
		arc -= PATH_SAMPLE


## Start the breach arc: the head lunges up through the surface and back
## under over [member breach_length] metres of travel; the body follows the
## same gate through the path memory. A no-op while dormant or mid-breach.
func breach() -> void:
	if _active and _breach_at < 0.0:
		_breach_at = 0.0


func is_breaching() -> bool:
	return _breach_at >= 0.0


## 0–1 through the breach arc, -1 while swimming level. For shoot tooling.
func get_breach_progress() -> float:
	return -1.0 if _breach_at < 0.0 else _breach_at / breach_length


## 0 closed to 1 fully open — rises as the head clears the sand.
func get_mouth_open() -> float:
	return _mouth_open


## The rigged body's skeleton, for verify tooling. Null on a body-less scene.
func get_skeleton() -> Skeleton3D:
	return _skeleton


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
	elif event.is_action_pressed("debug_worm_breach"):
		breach()


func _set_active(on: bool) -> void:
	_active = on
	# The body exists only while the worm does — dormant means invisible,
	# not merely still. (Cost a phantom-empty breach shoot: the driven
	# skeleton was verifying perfectly inside a hidden node.)
	visible = on
	set_physics_process(on)
	if _rumble != null:
		if on:
			_rumble.play()
		else:
			_rumble.stop()


func _physics_process(delta: float) -> void:
	var breaching: bool = _breach_at >= 0.0
	if not breaching:
		# A breach is a committed lunge: steering pauses so the arc stays
		# clean, and resumes the moment the head is back under.
		var desired: float = _desired_heading()
		_heading = rotate_toward(
			_heading, _steer(desired), deg_to_rad(turn_rate_degrees) * delta
		)

	var step: float = swim_speed * (breach_surge if breaching else 1.0) * delta
	var direction: Vector2 = Vector2.from_angle(_heading)
	global_position.x += direction.x * step
	global_position.z += direction.y * step
	_odometer += step

	var surface: float = _terrain.get_surface_height(_xz())
	if breaching:
		_breach_at += step
		if _breach_at >= breach_length:
			_breach_at = -1.0
			global_position.y = surface - swim_depth
		else:
			# A bell over the run: -swim_depth at both crossings, apex at the
			# top. The head's height IS the animation; the body inherits it
			# through the path memory.
			var bell: float = pow(
				sin(PI * _breach_at / breach_length), 1.3
			)
			global_position.y = surface + lerpf(-swim_depth, breach_apex, bell)
	else:
		# The body rides under the surface it is displacing; smooth the
		# follow so dune slopes never pop the body or the rumble emitter.
		global_position.y = lerpf(
			global_position.y, surface - swim_depth, 1.0 - exp(-4.0 * delta)
		)

	# The mouth opens as the head clears the sand and closes as it dives.
	var above: float = global_position.y - surface
	_mouth_open = clampf(above / maxf(breach_apex * 0.5, 0.1), 0.0, 1.0)
	var now_above: bool = above > 0.0
	if now_above != _was_above:
		_fire_burst()
	_was_above = now_above

	_record_sample()
	_drive_bones()

	_since_mark += step
	while _since_mark >= mound_spacing:
		_since_mark -= mound_spacing
		# An airborne head displaces no sand — the wake pauses over the arc;
		# the crossing bursts own those two moments instead.
		if not now_above:
			raised.emit(_xz(), mound_radius, mound_strength, _heading, mound_stretch)


## Sand explodes where the body crosses the surface, both directions.
func _fire_burst() -> void:
	bursts_fired += 1
	var at: Vector2 = _xz()
	var ground: float = _terrain.get_surface_height(at)
	if _burst != null:
		_burst.global_position = Vector3(at.x, ground + 0.6, at.y)
		_burst.restart()
	# The crossing heaves a wide ring of sand beyond the ordinary wake.
	raised.emit(at, mound_radius * 1.7, 1.0, _heading, 1.0)
	if _breach_sound != null:
		var boom: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		boom.stream = _breach_sound
		boom.bus = &"SFX"
		boom.max_distance = rumble_distance * 1.5
		boom.finished.connect(boom.queue_free)
		add_child(boom)
		boom.global_position = Vector3(at.x, ground, at.y)
		boom.play()


## Append a path sample once the head has travelled PATH_SAMPLE since the
## last one, and forget samples the tail can no longer reach.
func _record_sample() -> void:
	if (
		_sample_arcs.is_empty()
		or _odometer - _sample_arcs[_sample_arcs.size() - 1] >= PATH_SAMPLE
	):
		_samples.append(global_position)
		_sample_arcs.append(_odometer)
	while _sample_arcs.size() > 2 and _odometer - _sample_arcs[0] > PATH_MEMORY:
		_samples.remove_at(0)
		_sample_arcs.remove_at(0)


## World position of the path at an arc distance behind the head, by linear
## interpolation between stored samples.
func _path_point(arc_behind: float) -> Vector3:
	var target: float = _odometer - arc_behind
	if _sample_arcs.is_empty() or target >= _odometer:
		return global_position
	var last: int = _sample_arcs.size() - 1
	if target >= _sample_arcs[last]:
		# Between the newest stored sample and the live head.
		var head_span: float = _odometer - _sample_arcs[last]
		var head_t: float = (
			0.0 if head_span <= 0.0 else (target - _sample_arcs[last]) / head_span
		)
		return _samples[last].lerp(global_position, head_t)
	var i: int = last
	while i > 0 and _sample_arcs[i - 1] > target:
		i -= 1
	if i == 0:
		return _samples[0]
	var span: float = _sample_arcs[i] - _sample_arcs[i - 1]
	var t: float = 0.0 if span <= 0.0 else (target - _sample_arcs[i - 1]) / span
	return _samples[i - 1].lerp(_samples[i], t)


## Pose every bone along the path: bone k sits its rest arc behind the head,
## facing along the path's tangent. pose = skeleton⁻¹ · M · rest, where M
## maps the rest spine axis (+Z, nose -Z) onto the path.
func _drive_bones() -> void:
	if _skeleton == null:
		return
	var to_skeleton: Transform3D = _skeleton.global_transform.affine_inverse()
	var poses: Array[Transform3D] = []
	poses.resize(SPINE_BONES)
	for k: int in range(SPINE_BONES):
		var arc: float = _spine_arc[k]
		var at: Vector3 = global_position if k == 0 else _path_point(arc)
		var ahead: Vector3 = (
			global_position if k == 0 else _path_point(maxf(arc - 1.0, 0.0))
		)
		var behind: Vector3 = _path_point(arc + 1.0)
		var forward: Vector3 = ahead - behind
		if forward.length_squared() < 0.0001:
			forward = Vector3(
				cos(_heading + PI * 0.5), 0.0, sin(_heading + PI * 0.5)
			)
		forward = forward.normalized()
		# Rest nose points -Z, so the basis' +Z is the tailward axis.
		var up_ref: Vector3 = (
			Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		)
		var z_axis: Vector3 = -forward
		var x_axis: Vector3 = up_ref.cross(z_axis).normalized()
		var y_axis: Vector3 = z_axis.cross(x_axis)
		var rotation: Basis = Basis(x_axis, y_axis, z_axis)
		var mapping: Transform3D = Transform3D(
			rotation, at - rotation * Vector3(0.0, 0.0, arc)
		)
		poses[k] = mapping
		var bone: int = _skeleton.find_bone("spine_%02d" % k)
		if bone >= 0:
			_skeleton.set_bone_global_pose(
				bone, to_skeleton * mapping * _rest[bone]
			)
	# Lips hinge on the mouth rim, swinging outward with _mouth_open. The
	# hinge points/axes mirror tools/build_worm.py's lip_hinge().
	var open_angle: float = deg_to_rad(lip_open_degrees) * _mouth_open
	for lip: int in range(3):
		var bone: int = _skeleton.find_bone("lip_%d" % lip)
		if bone < 0:
			continue
		var angle: float = TAU * float(lip) / 3.0 + PI * 0.5
		# Blender rim circle (XZ) lands in Godot's XY plane: x stays x,
		# Blender z becomes Godot y.
		var hinge_point: Vector3 = Vector3(
			cos(angle) * RIM_R, sin(angle) * RIM_R, 0.0
		)
		var hinge_axis: Vector3 = Vector3(-sin(angle), cos(angle), 0.0)
		var swing: Transform3D = (
			Transform3D(Basis.IDENTITY, hinge_point)
			* Transform3D(Basis(hinge_axis, -open_angle), Vector3.ZERO)
			* Transform3D(Basis.IDENTITY, -hinge_point)
		)
		_skeleton.set_bone_global_pose(
			bone, to_skeleton * poses[0] * swing * _rest[bone]
		)


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
