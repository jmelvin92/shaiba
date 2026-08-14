class_name Player
extends CharacterBody3D
## Gray-box player controller.
##
## Camera-relative 8-way movement with acceleration/friction (no instant
## start-stop), gentle turning toward the move direction, gravity, and small
## step climbing so stairs and thresholds don't catch the capsule. Holding
## shift runs; Phase 3's animation tree blends idle/walk/run off the resulting
## planar speed, so the two gaits are speeds here, not states.
##
## The controller never looks up the tree for the camera. Whoever owns the
## level tells it which way "up the screen" is via [method set_view_yaw].
## Tuning values and the reasoning behind them are in docs/DECISIONS.md.

@export_group("Movement")
## Default pace, metres per second. A brisk walk for a 1.75 m character.
@export_range(1.0, 12.0, 0.1) var walk_speed: float = 4.6
## Pace while the sprint key (shift) is held.
@export_range(1.0, 16.0, 0.1) var run_speed: float = 7.4
## How hard the player is pushed toward the target speed (m/s²).
## Lower = more weight.
@export_range(1.0, 100.0, 0.5) var acceleration: float = 16.0
## How hard the player is slowed when there is no input (m/s²).
@export_range(1.0, 100.0, 0.5) var friction: float = 24.0
## Turn smoothing toward the move direction (higher = snappier, less drift).
@export_range(1.0, 40.0, 0.5) var turn_speed: float = 7.0
## How much of the acceleration is lost while the body is still turned away
## from where you asked it to go. 0 = none (you change direction as fast as you
## can press), 1 = no thrust at all until the body has come round. This is what
## gives a sudden reversal its weight; the visible turn alone would not.
@export_range(0.0, 1.0, 0.05) var turn_drag: float = 0.55

@export_group("Ground")
## Tallest ledge the player can walk up without jumping. Kept below
## floor_snap_length at runtime — the snap is what puts the body back down.
@export_range(0.0, 1.0, 0.05) var max_step_height: float = 0.35
## How far ahead to look for a ledge. Needs to exceed the capsule radius,
## otherwise the body is already stopped short of the obstacle when we look.
@export_range(0.1, 2.0, 0.05) var step_probe_distance: float = 0.5
## Multiplier on project gravity. > 1 keeps the fall from feeling floaty.
@export_range(0.0, 5.0, 0.1) var gravity_scale: float = 1.4

## Yaw of the viewing camera, radians. Input is rotated by this so "W" always
## means "away from the camera".
var view_yaw: float = 0.0


func _ready() -> void:
	# The floor snap is what lowers the body again after a step-up probe, so it
	# has to reach at least as far as the tallest step we allow.
	floor_snap_length = maxf(floor_snap_length, max_step_height + 0.05)


## Called by the level that owns both this player and the camera rig.
func set_view_yaw(yaw: float) -> void:
	view_yaw = yaw


func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var direction: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y).rotated(
		Vector3.UP, view_yaw
	)

	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	var target_speed: float = run_speed if Input.is_action_pressed("sprint") else walk_speed
	var planar: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() > 0.0:
		planar = planar.move_toward(
			direction * target_speed, acceleration * _turn_thrust(direction) * delta
		)
		_face_direction(direction, delta)
	else:
		planar = planar.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	if is_on_floor():
		_try_step_up(planar)
	move_and_slide()


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
## Rather than teleporting the body onto the ledge (which pops it forward), we
## lift it by [member max_step_height] just before moving. The floor snap
## inside [method move_and_slide] then puts it down again in the same tick:
## onto the ledge once the body has cleared its face, or straight back where it
## was until then. Nothing visible happens until the step is actually taken.
func _try_step_up(planar_velocity: Vector3) -> void:
	if max_step_height <= 0.0 or planar_velocity.length_squared() < 0.01:
		return

	# Only bother when something wall-like is close ahead. Walkable slopes are
	# left to move_and_slide so climbing them keeps its natural along-the-slope
	# speed instead of being lifted straight up.
	var ahead: KinematicCollision3D = KinematicCollision3D.new()
	var probe: Vector3 = planar_velocity.normalized() * step_probe_distance
	if not test_move(global_transform, probe, ahead):
		return
	if ahead.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return

	var lift: Vector3 = Vector3.UP * max_step_height
	if test_move(global_transform, lift):
		return
	global_position += lift
