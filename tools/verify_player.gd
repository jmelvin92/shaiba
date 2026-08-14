extends SceneTree
## Phase 3 quality-gate probe: foot sliding, animation state, and bind-pose flashes.
##
##   Godot --headless --path . --script res://tools/verify_player.gd
##
## Drives the real player through the graybox level and measures what the eye
## cannot judge reliably: whether a planted foot stays put in world space while
## the body moves, and whether any state change flashes the bind pose.

## Foot measurements need open flat ground; graybox is full of things to trip
## over, and a player who leaves the floor makes every frame look "planted".
const LEVEL: String = "res://scenes/world/world.tscn"
## Upwind end of the ground plane: "forward" is -Z, so starting at +Z leaves the
## whole plane as runway instead of two metres and a cliff.
const START: Vector3 = Vector3(0.0, 0.5, 20.0)
const SETTLE_TICKS: int = 90
const SAMPLE_TICKS: int = 120
## A foot counts as planted while it sits in the lowest slice of its own range.
const PLANTED_BAND: float = 0.35

var _player: Player
var _skeleton: Skeleton3D
var _animator: PlayerAnimator
var _left: int
var _right: int
var _failures: PackedStringArray = []
## How many samples the last _slip() call actually counted, for diagnostics.
var _planted_count: int = 0


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	_run()


func _run() -> void:
	var level: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await physics_frame

	_player = level.find_child("Player", true, false) as Player
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_animator = _player.find_child("AnimationTree", true, false) as PlayerAnimator
	_left = _skeleton.find_bone("LeftToeBase")
	_right = _skeleton.find_bone("RightToeBase")

	if _player == null or _skeleton == null or _animator == null:
		push_error("probe could not find the player, skeleton or animator")
		quit(1)
		return

	if OS.get_cmdline_user_args().has("--sweep"):
		await _sweep()
		quit()
		return

	print("=== foot sliding ===")
	await _gait("walk", false)
	await _gait("run", true)

	print("\n=== animation states ===")
	await _states()

	print("\n=== result ===")
	if _failures.is_empty():
		print("all checks passed")
	else:
		for line: String in _failures:
			print("FAIL  %s" % line)
	quit(0 if _failures.is_empty() else 1)


## Finds a clip's true stride speed by pinning the blend to that clip alone and
## sweeping how fast the body travels underneath it. World-space foot slip is
## smallest where the body speed matches the stride, so the low point of this
## table is the number the blend anchor should use.
func _sweep() -> void:
	print("body speed -> planted-foot slip, blend pinned to the pure run clip")
	for candidate: float in [3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0]:
		_player.run_speed = candidate
		await _reset()
		Input.action_press("move_up")
		Input.action_press("sprint")
		for i: int in range(SETTLE_TICKS):
			await physics_frame
			_pin_run()

		var heights: Array[float] = []
		var positions: Array[Vector3] = []
		var grounded: Array[bool] = []
		for i: int in range(SAMPLE_TICKS):
			var toe: Vector3 = _planted_toe()
			heights.append(toe.y)
			positions.append(toe)
			grounded.append(_player.is_on_floor())
			await physics_frame
			_pin_run()

		var on_floor: int = grounded.count(true)
		print("  %.1f m/s -> slip %.2f m/s   (grounded %d/%d, planted %d)" % [
			_player.get_planar_speed(), _slip(heights, positions, grounded),
			on_floor, grounded.size(), _planted_count])
	_release()


## Teleports back to open ground so a fast run never reaches the plane's edge.
func _reset() -> void:
	_release()
	_player.velocity = Vector3.ZERO
	_player.global_position = START
	_player.reset_physics_interpolation()
	for i: int in range(20):
		await physics_frame


## Median world-space speed of the planted foot. A foot that is truly planted
## is motionless in world space, so this is pure sliding.
func _slip(heights: Array[float], positions: Array[Vector3], grounded: Array[bool]) -> float:
	var low: float = heights.min()
	var band: float = low + (heights.max() - low) * PLANTED_BAND
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	var slips: Array[float] = []
	for i: int in range(positions.size() - 1):
		# Airborne frames would look perfectly "planted" while travelling with
		# the body, which is exactly the wrong reading.
		if not grounded[i] or not grounded[i + 1]:
			continue
		if heights[i] > band or heights[i + 1] > band:
			continue
		var delta: Vector3 = positions[i + 1] - positions[i]
		slips.append(Vector2(delta.x, delta.z).length() / step)
	_planted_count = slips.size()
	# The lower quartile, not the median: a real foot rolls from heel to toe
	# through its stance, so even a perfectly matched stride shows movement at
	# the ends of it. Mid-stance is where a foot should be genuinely still, and
	# that is what the lower quartile picks out.
	return _percentile(slips, 0.25)


func _pin_run() -> void:
	_animator.set("parameters/locomotion/blend_position", PlayerAnimator.RUN_SPEED)


## Walks or runs in a straight line, then compares how far the planted foot
## drifts in world space against how far the body travels.
func _gait(label: String, sprint: bool) -> void:
	await _reset()
	Input.action_press("move_up")
	if sprint:
		Input.action_press("sprint")
	for i: int in range(SETTLE_TICKS):
		await physics_frame

	var heights: Array[float] = []
	var positions: Array[Vector3] = []
	var grounded: Array[bool] = []
	var speeds: Array[float] = []

	for i: int in range(SAMPLE_TICKS):
		var planted: Vector3 = _planted_toe()
		heights.append(planted.y)
		positions.append(planted)
		grounded.append(_player.is_on_floor())
		speeds.append(_player.get_planar_speed())
		await physics_frame

	var body: float = _median(speeds)
	var slip: float = _slip(heights, positions, grounded)
	var ratio: float = slip / maxf(body, 0.001)
	print("%-5s body %.2f m/s   planted-foot slip %.2f m/s   (%d%% of body speed)" % [
		label, body, slip, roundi(ratio * 100.0)])
	# A perfectly matched stride still slips a little as weight rolls over the
	# toe; a stride that is simply the wrong length slips far more than this.
	if ratio > 0.25:
		_failures.append("%s: foot slides at %d%% of body speed" % [label, roundi(ratio * 100.0)])
	_release()


## Steps through every state and checks the machine actually goes there, and
## that the skeleton is never left sitting in its bind pose.
func _states() -> void:
	await _expect("idle", "locomotion", 30, func() -> void: pass)
	await _expect("walking", "locomotion", 30, func() -> void: Input.action_press("move_up"))
	await _expect("crouching", "crouch", 30, func() -> void: Input.action_press("crouch"))
	_release()
	await _expect("standing", "locomotion", 30, func() -> void: pass)
	await _expect("jumping", "jump", 6, func() -> void: Input.action_press("jump"))
	_release()
	await _expect("falling", "fall", 25, func() -> void: pass)
	# Let it come back down and settle on its own.
	for i: int in range(90):
		await physics_frame
	var landed: String = _animator.get_state()
	print("after landing: %s" % landed)
	if landed != "locomotion" and landed != "land":
		_failures.append("did not return to locomotion after landing (got '%s')" % landed)


func _expect(label: String, state: String, ticks: int, press: Callable) -> void:
	press.call()
	for i: int in range(ticks):
		await physics_frame
		if _is_bind_pose():
			_failures.append("%s: skeleton flashed its bind pose" % label)
			break
	var actual: String = _animator.get_state()
	print("%-10s -> %s" % [label, actual])
	if actual != state:
		_failures.append("%s: expected state '%s', got '%s'" % [label, state, actual])


## True when almost every bone sits on its rest transform, which is what an
## unconfigured or stalled AnimationTree leaves behind.
func _is_bind_pose() -> bool:
	var matching: int = 0
	for i: int in range(_skeleton.get_bone_count()):
		if _skeleton.get_bone_pose_rotation(i).angle_to(
			_skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		) < 0.009:
			matching += 1
	return matching >= _skeleton.get_bone_count() - 2


## World position of whichever toe is currently lower, i.e. the planted one.
func _planted_toe() -> Vector3:
	var to_world: Transform3D = _skeleton.global_transform
	var left: Vector3 = to_world * _skeleton.get_bone_global_pose(_left).origin
	var right: Vector3 = to_world * _skeleton.get_bone_global_pose(_right).origin
	return left if left.y < right.y else right


func _release() -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(action)


func _median(values: Array[float]) -> float:
	return _percentile(values, 0.5)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var index: int = clampi(roundi(fraction * float(sorted.size() - 1)), 0, sorted.size() - 1)
	return sorted[index]
