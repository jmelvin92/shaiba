class_name Player
extends CharacterBody3D
## Gray-box player controller.
##
## Camera-relative 8-way movement with acceleration/friction (no instant
## start-stop), gentle turning toward the move direction, gravity, and small
## step climbing so stairs and thresholds don't catch the capsule. Holding
## shift runs; the animation tree blends idle/walk/run off the resulting planar
## speed, so the two gaits are speeds here, not states.
##
## This script knows nothing about clips or blending. It reports its own state
## down to the [PlayerAnimator] child once a tick, and that node decides what
## the character should look like.
##
## The controller never looks up the tree for the camera. Whoever owns the
## level tells it which way "up the screen" is via [method set_view_yaw].
## Tuning values and the reasoning behind them are in docs/DECISIONS.md.

## Slack added on top of a measured step so the capsule rides over the lip
## rather than arriving exactly flush with it and catching.
const STEP_CLEARANCE: float = 0.02

@export_group("Movement")
## Default pace, metres per second. The walk animation's own stride is 1.4 m/s;
## above that the blend leans slightly toward the run, which stays stride-matched
## because the blend anchors sit at each clip's measured speed.
@export_range(0.5, 12.0, 0.1) var walk_speed: float = 1.8
## Pace while the sprint key (shift) is held. Matched to the run animation.
@export_range(1.0, 16.0, 0.1) var run_speed: float = 4.9
## How hard the player is pushed toward the target speed (m/s²).
## Lower = more weight.
@export_range(1.0, 100.0, 0.5) var acceleration: float = 12.0
## How hard the player is slowed when there is no input (m/s²).
@export_range(1.0, 100.0, 0.5) var friction: float = 14.0
## Turn smoothing toward the move direction (higher = snappier, less drift).
@export_range(1.0, 40.0, 0.5) var turn_speed: float = 7.0
## How much of the acceleration is lost while the body is still turned away
## from where you asked it to go. 0 = none (you change direction as fast as you
## can press), 1 = no thrust at all until the body has come round. This is what
## gives a sudden reversal its weight; the visible turn alone would not.
@export_range(0.0, 1.0, 0.05) var turn_drag: float = 0.45

@export_group("Air")
## Peak height of a full jump, metres. Converted to a launch velocity against
## whatever gravity is in force, so tuning gravity doesn't change the hop.
@export_range(0.0, 4.0, 0.05) var jump_height: float = 1.1
## How much of the rise is kept when the jump key is released early. 1 = no
## variable height, 0.4 = a tap gets you noticeably less than a hold.
@export_range(0.0, 1.0, 0.05) var jump_release_damping: float = 0.45
## Grace period after walking off a ledge during which a jump still counts.
@export_range(0.0, 0.4, 0.01) var coyote_time: float = 0.12
## How early a jump press is remembered if you hit it just before landing.
@export_range(0.0, 0.4, 0.01) var jump_buffer_time: float = 0.12
## Share of ground acceleration and friction that applies mid-air. Low values
## mean a jump commits you to roughly the arc you launched with.
@export_range(0.0, 1.0, 0.05) var air_control: float = 0.35

@export_group("Crouch")
## Pace while crouched. Kept slow because the source animation set has no
## forward crouch walk, so crouched movement holds a pose.
@export_range(0.5, 6.0, 0.1) var crouch_speed: float = 1.0
## Capsule height when crouched. Standing height is read from the scene.
@export_range(0.6, 2.0, 0.05) var crouch_height: float = 1.15
## How quickly the capsule shrinks and grows again.
@export_range(1.0, 40.0, 0.5) var crouch_transition_speed: float = 14.0

@export_group("Ground")
## Tallest ledge the player can walk up without jumping. Kept below
## floor_snap_length at runtime — the snap is what puts the body back down.
@export_range(0.0, 1.0, 0.05) var max_step_height: float = 0.35
## Skin added to one tick of travel when looking ahead for a step. The probe is
## deliberately short: looking half a metre ahead used to lift the body while it
## was still well clear of the step, which reads as floating up to the stairs.
@export_range(0.01, 0.3, 0.01) var step_probe_margin: float = 0.06
## How much slimmer the step probe's body is than the real one, metres. This is
## the width of contact the probe is allowed to ignore — enough to slide along
## a door jamb or the wall a stair runs against without that contact being
## mistaken for the obstacle in front.
@export_range(0.0, 0.2, 0.01) var step_probe_slim: float = 0.07
## How quickly the mesh catches up after the collider steps up (higher =
## snappier). The collider has to move in one tick or the physics is wrong, but
## the character we actually see slides that height off over a moment instead.
@export_range(1.0, 60.0, 1.0) var step_smoothing: float = 16.0
## Smallest one-tick height change treated as a step rather than as ground
## following. A 30° ramp at walking pace moves the body about 1 cm a tick.
@export_range(0.01, 0.3, 0.01) var step_pop_threshold: float = 0.05
## How long after a step the character still counts as on its feet, covering
## the moment it is at tread height but has not yet walked onto the tread.
@export_range(0.0, 0.5, 0.01) var step_grace_time: float = 0.2
## Multiplier on project gravity. > 1 keeps the fall from feeling floaty.
@export_range(0.0, 5.0, 0.1) var gravity_scale: float = 1.4

@export_group("Sand")
## Sand depth at which the deep-sand effects reach full strength, metres.
## Shallower sand scales every effect down proportionally.
@export_range(0.05, 2.0, 0.05) var deep_sand_depth: float = 1.5
## Multiplier on movement speed when the sand is fully deep — wading through
## a dune should cost something.
@export_range(0.2, 1.0, 0.05) var deep_sand_speed_scale: float = 0.6
## Multiplier on jump height in fully deep sand: soft ground gives a soft
## launch.
@export_range(0.2, 1.0, 0.05) var deep_sand_jump_scale: float = 0.75
## Fraction of the local sand depth the feet visibly sink into the surface.
@export_range(0.0, 1.0, 0.05) var sand_sink_ratio: float = 0.35
## Deepest the feet ever sink visually, metres — past this the effect would
## read as clipping, not sinking.
@export_range(0.0, 0.3, 0.01) var sand_sink_max: float = 0.12
## How quickly the visible sink follows changes in depth underfoot.
@export_range(1.0, 40.0, 0.5) var sand_sink_speed: float = 8.0

## Emitted the moment a jump actually launches, not when the key is pressed.
signal jumped
## Emitted on touchdown, carrying the downward speed at impact in m/s.
signal landed(impact_speed: float)
## Emitted whenever the feet mark the sand (footfall, deep-sand drag,
## landing splat) — re-raised from the FootstepStamper child so levels only
## ever wire against the player. Position/radius in world metres, strength
## 0–1, angle radians, stretch elongates the mark along its angle.
signal stamped(
	world_xz: Vector2, radius: float, strength: float, angle: float, stretch: float
)
## Emitted whenever the player makes an audible amount of noise (a step, a
## jump, a landing) — re-raised from the FootstepAudio child so future
## listeners (a startled camel, a night creature) only ever wire against the
## player. Nothing connects it yet.
signal noise_made(world_position: Vector3, loudness: float)

## Yaw of the viewing camera, radians. Input is rotated by this so "W" always
## means "away from the camera".
var view_yaw: float = 0.0

## Terrain query source for the deep-sand movement hooks, handed in by the
## level. Stays null on levels without terrain (the graybox), which turns
## every sand effect into a no-op.
var _terrain: TerrainSettings = null

@onready var _collision: CollisionShape3D = $Collision
@onready var _capsule: CapsuleShape3D = _collision.shape
@onready var _animator: PlayerAnimator = $AnimationTree
@onready var _visual: Node3D = $Visual
@onready var _stamper: FootstepStamper = $FootstepStamper
@onready var _footsteps: FootstepAudio = $FootstepAudio

## Full standing capsule height, taken from the scene at load.
var _stand_height: float = 1.75
## Where the capsule is between crouched and standing right now, in metres.
var _current_height: float = 1.75
var _crouched: bool = false
## Counts down after leaving the floor; a jump is still allowed while positive.
var _coyote_left: float = 0.0
## Counts down after a jump press; spends itself the moment a jump is possible.
var _jump_buffer_left: float = 0.0
## Horizontal speed at the end of the last tick, m/s. Cached because the
## animation blends off the speed the body actually reached, not off the input.
var _planar_speed: float = 0.0
var _was_on_floor: bool = true
## How far the mesh is currently held below the collider while it catches up
## after a step, in metres.
var _step_offset: float = 0.0
## World-space horizontal displacement still to be worked out of the mesh after
## a low-momentum step advanced the body onto a tread (see _try_step_up).
var _step_shift: Vector3 = Vector3.ZERO
## Counts down after a step; the character still counts as footed while positive.
var _step_grace_left: float = 0.0
## velocity.y captured before move_and_slide, so a landing can report the speed
## it arrived at rather than the zero it has afterwards.
var _fall_speed: float = 0.0
## Every steep face the failed step probes ran into this tick — what the
## face-normal fallback in [method _try_step_up] measures against. More than
## one matters: wedged into a corner, the sweep meets the unclimbable flanking
## wall *and* the climbable riser, and only the riser can get you out.
var _probe_faces: Array[Vector3] = []
## Sand depth under the player this tick, metres. 0 whenever there is no
## terrain, which is what keeps every sand effect inert on the graybox.
var _sand_depth: float = 0.0
## How far the mesh is currently lowered to show the feet settling into sand.
var _sink_offset: float = 0.0


func _ready() -> void:
	# The floor snap is what lowers the body again after a step-up probe, so it
	# has to reach at least as far as the tallest step we allow.
	floor_snap_length = maxf(floor_snap_length, max_step_height + 0.05)
	_stand_height = _capsule.height
	_current_height = _stand_height
	_stamper.setup(_visual.find_child("Skeleton3D", true, false) as Skeleton3D)
	_stamper.stamped.connect(
		func(at: Vector2, radius: float, strength: float, angle: float, stretch: float) -> void:
			stamped.emit(at, radius, strength, angle, stretch)
	)
	_stamper.foot_planted.connect(_footsteps.on_foot_planted)
	_footsteps.noise_made.connect(
		func(world_position: Vector3, loudness: float) -> void:
			noise_made.emit(world_position, loudness)
	)


## Called by the level that owns both this player and the camera rig.
func set_view_yaw(yaw: float) -> void:
	view_yaw = yaw


## Called by a level that has terrain, so movement can feel the sand depth.
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain = terrain
	_footsteps.set_terrain(terrain)


func _physics_process(delta: float) -> void:
	if _terrain != null:
		_sand_depth = _terrain.get_sand_depth(
			Vector2(global_position.x, global_position.z)
		)

	var input_vector: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var direction: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y).rotated(
		Vector3.UP, view_yaw
	)

	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	_update_crouch(delta)
	_update_jump(delta)

	# Mid-air you get only a share of your usual grip, so a jump largely
	# commits you to the arc you left the ground with.
	var control: float = 1.0 if is_on_floor() else air_control
	var planar: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() > 0.0:
		var thrust: float = acceleration * _turn_thrust(direction) * control
		planar = planar.move_toward(direction * _target_speed(), thrust * delta)
		_face_direction(direction, delta)
	else:
		planar = planar.move_toward(Vector3.ZERO, friction * control * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	_planar_speed = planar.length()

	var was_grounded: bool = is_on_floor()
	var height_before: float = global_position.y
	if was_grounded:
		_try_step_up(planar, direction, delta)
	_fall_speed = maxf(-velocity.y, 0.0)
	move_and_slide()

	# is_on_floor() only means anything after move_and_slide, so the touchdown
	# test has to come after it.
	var grounded: bool = is_on_floor()

	# Measure the step from what the body actually did, not from what the probe
	# asked for: a step is often attempted a tick or two before it takes, and
	# the floor snap quietly puts the body back until it does.
	var climbed: float = global_position.y - height_before
	if was_grounded and absf(climbed) >= step_pop_threshold:
		_absorb_step(climbed)
		# Stepping up leaves the body briefly unsupported — at tread height but
		# not yet over the tread. Without this grace it reads as falling on
		# every stair.
		_step_grace_left = step_grace_time
	_step_grace_left = maxf(_step_grace_left - delta, 0.0)
	_settle_step(delta)

	# A step is not a fall and its arrival is not a landing.
	var footed: bool = grounded or _step_grace_left > 0.0
	if footed and not _was_on_floor:
		_animator.play_land(_fall_speed)
		landed.emit(_fall_speed)
		_stamper.notify_landed(_fall_speed)
		_footsteps.on_landed(_fall_speed)
	_was_on_floor = footed
	_animator.set_locomotion(_planar_speed, footed, _crouched)
	_stamper.tick(delta, velocity, footed, _sand_factor())
	_footsteps.tick(delta, _planar_speed, _crouched, footed)


## The pace being asked for: crouching beats sprinting, sprinting beats
## walking — then deep sand takes its share of whichever gait won. Because the
## animation blends off the speed actually reached, slowing the target here
## slows the stride to match for free.
func _target_speed() -> float:
	var base: float = walk_speed
	if _crouched:
		base = crouch_speed
	elif Input.is_action_pressed("sprint"):
		base = run_speed
	return base * lerpf(1.0, deep_sand_speed_scale, _sand_factor())


## How deep in sand the player is, 0 (none/hard ground) to 1 (full effect).
func _sand_factor() -> float:
	return clampf(_sand_depth / deep_sand_depth, 0.0, 1.0)


## True while crouched, for anyone driving animation off this controller.
func is_crouching() -> bool:
	return _crouched


## Horizontal speed reached on the last tick, m/s.
func get_planar_speed() -> float:
	return _planar_speed


## Takes a sudden change in the collider's height out of the mesh, so a step
## the physics has to take in one tick is not one the eye has to.
##
## Only sudden changes qualify: walking a ramp moves the body a fraction of a
## centimetre a tick, which should follow the ground exactly.
func _absorb_step(rise: float) -> void:
	if absf(rise) < step_pop_threshold:
		return
	_step_offset = clampf(_step_offset - rise, -max_step_height, max_step_height)


## Single writer of the visual's height: the step-absorb offset decays back to
## zero while the sand sink eases toward the local depth, and the mesh shows
## the sum of both.
func _settle_step(delta: float) -> void:
	var weight: float = 1.0 - exp(-step_smoothing * delta)
	_step_offset = lerpf(_step_offset, 0.0, weight)
	if absf(_step_offset) < 0.001:
		_step_offset = 0.0
	_step_shift = _step_shift.lerp(Vector3.ZERO, weight)
	if _step_shift.length_squared() < 0.000001:
		_step_shift = Vector3.ZERO

	# Feet only settle while they are on the ground; a jump lifts them out.
	var sink_target: float = 0.0
	if is_on_floor() or _step_grace_left > 0.0:
		sink_target = minf(_sand_depth * sand_sink_ratio, sand_sink_max)
	_sink_offset = lerpf(_sink_offset, sink_target, 1.0 - exp(-sand_sink_speed * delta))
	if _sink_offset < 0.001 and sink_target == 0.0:
		_sink_offset = 0.0

	# The shift is banked in world space; the visual hangs under a body that
	# turns, so it is converted to local axes fresh each tick.
	var local_shift: Vector3 = global_basis.inverse() * _step_shift
	_visual.position = Vector3(
		local_shift.x, _step_offset - _sink_offset, local_shift.z
	)


## Follows the crouch key, except that you cannot stand up under something.
## The capsule resizes toward the target height rather than snapping, and is
## kept sitting on the character's feet.
func _update_crouch(delta: float) -> void:
	if Input.is_action_pressed("crouch"):
		_crouched = true
	elif _crouched and _has_standing_room():
		_crouched = false

	var wanted: float = crouch_height if _crouched else _stand_height
	if is_equal_approx(_current_height, wanted):
		return
	_current_height = move_toward(
		_current_height, wanted, crouch_transition_speed * delta
	)
	_apply_height(_current_height)


## Sweeps the crouched capsule up through the space standing would occupy.
func _has_standing_room() -> bool:
	var needed: float = _stand_height - _current_height
	if needed <= 0.0:
		return true
	return not test_move(global_transform, Vector3.UP * needed)


## Only the collider changes shape. The crouched silhouette comes from the
## crouch animation, so there is no mesh left to keep in sync with it.
func _apply_height(height: float) -> void:
	_capsule.height = height
	_collision.position.y = height * 0.5


## Jump with the two forgivenesses players never notice until they are missing:
## a moment of coyote time after leaving a ledge, and a buffered press so
## hitting the key just before landing still fires.
func _update_jump(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time
	else:
		_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	if _jump_buffer_left > 0.0 and _coyote_left > 0.0 and not _crouched:
		# Deep sand softens the launch the same way it slows the stride.
		var height: float = jump_height * lerpf(1.0, deep_sand_jump_scale, _sand_factor())
		velocity.y = sqrt(2.0 * get_gravity().length() * gravity_scale * height)
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_animator.play_jump()
		jumped.emit()
		_footsteps.on_jumped()
	elif Input.is_action_just_released("jump") and velocity.y > 0.0:
		# Released mid-rise — cut it short once, so a tap is a smaller hop.
		velocity.y *= jump_release_damping


## Fraction of full acceleration available right now, based on how far the body
## still has to turn. Facing the way you asked gives 1.0; a full about-face
## gives `1 - turn_drag`, recovering as the body comes round.
func _turn_thrust(direction: Vector3) -> float:
	if is_zero_approx(turn_drag):
		return 1.0
	var facing: Vector3 = -global_basis.z
	var alignment: float = maxf(facing.dot(direction), 0.0)
	return lerpf(1.0, alignment, turn_drag)


## Rotates the body toward [param direction] over time instead of snapping,
## so quick direction changes read as a turn rather than a teleport.
func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-direction.x, -direction.z)
	var weight: float = 1.0 - exp(-turn_speed * delta)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)


## Lets the capsule walk up small ledges — stair treads, doorway thresholds —
## that [method move_and_slide] would otherwise stop dead against.
##
## The body is raised by exactly the height of the step in front of it, found by
## lifting a test transform, reaching over the obstacle and dropping back down
## onto whatever is there. Lifting by the full [member max_step_height] instead
## (as this used to) launches the character off every tread: it ends the tick
## above the step with nothing underneath, so it counts as airborne, falls for a
## tenth of a second, and plays the fall animation on each stair.
##
## The step is looked for in up to three directions, because one is not enough
## (measured; see DECISIONS on the stair-foot jam). What the player is
## *pressing* comes first — velocity is useless the moment sliding has turned
## it parallel to a riser, which is exactly how drifting into a flight used to
## deflect you off it instead of climbing. Velocity is the fallback when there
## is no input worth reading. And when both of those are blocked by a steep
## face, the step is measured square against that face itself: a diagonal
## approach sweeps a longer path over the tread and clips the next riser or a
## flanking wall, so measuring along the approach reads a climbable flight as a
## wall — perpendicular to the face is the one direction the measurement is
## honest in. Face-normal climbing only happens when the input genuinely
## pushes into the face, so brushing past a curb never hoists you onto it.
func _try_step_up(planar_velocity: Vector3, wish_direction: Vector3, delta: float) -> void:
	if max_step_height <= 0.0 or planar_velocity.length_squared() < 0.01:
		return

	var candidates: Array[Vector3] = []
	if wish_direction.length_squared() > 0.5:
		candidates.append(wish_direction.normalized())
	var travel: Vector3 = planar_velocity.normalized()
	if candidates.is_empty() or travel.dot(candidates[0]) < 0.999:
		candidates.append(travel)

	# The probe runs against a slightly slimmer body than we collide with.
	#
	# It asks one question — "is there a step in front of me?" — by sweeping
	# the capsule, and at full width anything merely *brushing* the body's side
	# answers it too. So taking a step while grazing a door jamb, or the house
	# wall an outside stair runs against, reports "blocked" and the step is
	# read as a wall: the player stops dead half-in a doorway or part-way up a
	# flight, for no reason they can see. Measured before this: a doorway with
	# 0.20 m of geometric slack had only 0.12 m you could actually walk
	# through, the difference being contact the body was merely sliding along.
	#
	# The probe's reach is widened by the same amount, so it still meets a real
	# obstacle at exactly the distance it used to.
	var full_radius: float = _capsule.radius
	var reach: float = (
		planar_velocity.length() * delta + step_probe_margin + step_probe_slim
	)
	_capsule.radius = maxf(full_radius - step_probe_slim, 0.05)

	var rise: float = -1.0
	var stepped: Vector3 = Vector3.ZERO
	_probe_faces.clear()
	for direction: Vector3 in candidates:
		rise = _measure_step(direction, direction * reach, full_radius)
		if rise > 0.001:
			stepped = direction
			break
	if rise <= 0.001:
		# The approaches read a wall, but they did meet steep faces. Measure
		# square against each face the input is actually pushing into — in a
		# corner that skips the flanking wall and finds the riser beside it.
		for normal: Vector3 in _probe_faces.duplicate():
			var face: Vector3 = -normal
			face.y = 0.0
			if face.length_squared() <= 0.01:
				continue
			face = face.normalized()
			if wish_direction.dot(face) <= 0.4:
				continue
			rise = _measure_step(face, face * reach, full_radius)
			if rise > 0.001:
				stepped = face
				break
	_capsule.radius = full_radius
	if rise <= 0.001:
		return

	# Raising by the step's own height would leave the capsule exactly flush with
	# the lip, where it catches; STEP_CLEARANCE is the hair that clears it.
	global_position.y += rise + STEP_CLEARANCE
	# Don't let leftover downward velocity pull us straight back off the tread.
	velocity.y = maxf(velocity.y, 0.0)

	# With walking momentum, the raise is all the help that is needed — the next
	# few centimetres of ordinary movement put the body onto the tread. Pressed
	# into a corner there is no momentum: the raise leaves the capsule perched
	# on the tread's lip over its old footing, it slides straight back off, and
	# the cycle repeats forever a few times a second (measured — this was the
	# stair-foot jam). So at low speed the body is also advanced to the spot the
	# measurement just proved out: the drop that found the tread was taken one
	# reach past the face, with the path onto it swept clear. The visual absorbs
	# the shift the same way it absorbs the vertical pop.
	if _planar_speed < 1.0:
		var advance: Vector3 = stepped * (full_radius + step_probe_margin)
		global_position += advance
		_step_shift -= advance


## How far the body must rise to stand on what is blocking it, or -1 if there
## is nothing there, nothing to stand on, or a wall rather than a step.
##
## [param full_radius] is the body's real radius, which the forward reach is
## measured against even while the probe itself runs slim.
func _measure_step(direction: Vector3, motion: Vector3, full_radius: float) -> float:
	# Walkable slopes are left to move_and_slide, so climbing them keeps its
	# natural along-the-slope speed instead of being lifted straight up.
	var ahead: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(global_transform, motion, ahead, 0.001, false, 4):
		return -1.0
	if ahead.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return -1.0
	for i: int in range(ahead.get_collision_count()):
		var normal: Vector3 = ahead.get_normal(i)
		if normal.angle_to(Vector3.UP) > floor_max_angle:
			_probe_faces.append(normal)

	var headroom: Vector3 = Vector3.UP * max_step_height
	if test_move(global_transform, headroom):
		return -1.0

	# Measuring the tread needs a longer reach than moving does: the capsule
	# only sits over the step once its centre has cleared its own radius past
	# the face, and probing any shorter measures the face instead of the tread.
	var over: Vector3 = direction * (full_radius + step_probe_margin)
	var raised: Transform3D = global_transform
	raised.origin += headroom
	if test_move(raised, over):
		# Still blocked from up there, so it is a wall rather than a step.
		return -1.0

	raised.origin += over
	var tread: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(raised, -headroom, tread):
		# Nothing to stand on over there — a gap, not a step.
		return -1.0

	return max_step_height - tread.get_travel().length()
