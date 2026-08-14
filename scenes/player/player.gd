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

## Emitted the moment a jump actually launches, not when the key is pressed.
signal jumped
## Emitted on touchdown, carrying the downward speed at impact in m/s.
signal landed(impact_speed: float)

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
## Counts down after a step; the character still counts as footed while positive.
var _step_grace_left: float = 0.0
## velocity.y captured before move_and_slide, so a landing can report the speed
## it arrived at rather than the zero it has afterwards.
var _fall_speed: float = 0.0


func _ready() -> void:
	# The floor snap is what lowers the body again after a step-up probe, so it
	# has to reach at least as far as the tallest step we allow.
	floor_snap_length = maxf(floor_snap_length, max_step_height + 0.05)
	_stand_height = _capsule.height
	_current_height = _stand_height


## Called by the level that owns both this player and the camera rig.
func set_view_yaw(yaw: float) -> void:
	view_yaw = yaw


## Called by a level that has terrain, so movement can feel the sand depth.
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain = terrain


func _physics_process(delta: float) -> void:
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
		_try_step_up(planar, delta)
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
	_was_on_floor = footed
	_animator.set_locomotion(_planar_speed, footed, _crouched)


## The pace being asked for: crouching beats sprinting, sprinting beats walking.
func _target_speed() -> float:
	if _crouched:
		return crouch_speed
	if Input.is_action_pressed("sprint"):
		return run_speed
	return walk_speed


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


func _settle_step(delta: float) -> void:
	if is_zero_approx(_step_offset) and is_zero_approx(_visual.position.y):
		return
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-step_smoothing * delta))
	if absf(_step_offset) < 0.001:
		_step_offset = 0.0
	_visual.position.y = _step_offset


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
		velocity.y = sqrt(2.0 * get_gravity().length() * gravity_scale * jump_height)
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_animator.play_jump()
		jumped.emit()
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
## Returns how far the body was raised, or 0.0 if it did not step.
func _try_step_up(planar_velocity: Vector3, delta: float) -> void:
	if max_step_height <= 0.0 or planar_velocity.length_squared() < 0.01:
		return

	# Trigger only when this tick's travel is actually blocked. Looking further
	# ahead lifts the body while it is still short of the step, which reads as
	# floating up to the stairs.
	var direction: Vector3 = planar_velocity.normalized()
	var motion: Vector3 = direction * (planar_velocity.length() * delta + step_probe_margin)

	# Walkable slopes are left to move_and_slide, so climbing them keeps its
	# natural along-the-slope speed instead of being lifted straight up.
	var ahead: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(global_transform, motion, ahead):
		return
	if ahead.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return

	var headroom: Vector3 = Vector3.UP * max_step_height
	if test_move(global_transform, headroom):
		return

	# Measuring the tread needs a longer reach than moving does: the capsule
	# only sits over the step once its centre has cleared its own radius past
	# the face, and probing any shorter measures the face instead of the tread.
	var over: Vector3 = direction * (_capsule.radius + step_probe_margin)
	var raised: Transform3D = global_transform
	raised.origin += headroom
	if test_move(raised, over):
		# Still blocked from up there, so it is a wall rather than a step.
		return

	raised.origin += over
	var tread: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(raised, -headroom, tread):
		# Nothing to stand on over there — a gap, not a step.
		return

	var rise: float = max_step_height - tread.get_travel().length()
	if rise <= 0.001:
		return
	# Raising by the step's own height would leave the capsule exactly flush with
	# the lip, where it catches; STEP_CLEARANCE is the hair that clears it.
	global_position.y += rise + STEP_CLEARANCE
	# Don't let leftover downward velocity pull us straight back off the tread.
	velocity.y = maxf(velocity.y, 0.0)
