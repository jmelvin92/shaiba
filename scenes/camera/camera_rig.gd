class_name CameraRig
extends Node3D
## Angled top-down ("diorama") camera rig.
##
## Perspective camera, pitched ~45° down with a narrow FOV — see the fixed
## decision in docs/DECISIONS.md. The rig follows a target position with
## damping and zooms on the scroll wheel between clamps. It deliberately does
## NOT move to avoid geometry: anything blocking the view is faded instead, by
## the OccluderFader child. See docs/DECISIONS.md.
##
## The rig never searches the tree for its target: whoever instances it calls
## [method set_target]. Everything runs in _physics_process so the camera and
## the player it follows update on the same tick; physics interpolation then
## smooths both to the render frame rate together, so there is no relative
## jitter between them.

## Emitted when the viewing yaw changes, so movement input can stay
## camera-relative without the player knowing about this node.
signal yaw_changed(yaw: float)

@export_group("Follow")
## Damping of the follow. Higher = tighter, lower = more lag.
@export_range(1.0, 30.0, 0.5) var follow_speed: float = 8.0
## World-space offset from the target's origin to the point framed by the
## camera. Raised to chest height so the player sits centred, not low.
@export var follow_offset: Vector3 = Vector3(0.0, 1.0, 0.0)

@export_group("Framing")
## Downward pitch in degrees, from horizontal.
@export_range(20.0, 80.0, 0.5) var pitch_degrees: float = 45.0:
	set = set_pitch_degrees
## Rotation of the rig around the world Y axis, degrees.
@export_range(0.0, 360.0, 45.0) var yaw_degrees: float = 0.0:
	set = set_yaw_degrees

@export_group("Zoom")
## Starting distance from the framed point, metres.
@export_range(4.0, 40.0, 0.5) var zoom_distance: float = 23.0
## Closest the player may zoom in.
@export_range(4.0, 40.0, 0.5) var zoom_min: float = 9.0
## Furthest the player may pull back.
@export_range(4.0, 40.0, 0.5) var zoom_max: float = 34.0
## Distance added or removed per scroll notch.
@export_range(0.1, 10.0, 0.1) var zoom_step: float = 1.5
## Damping of the zoom transition.
@export_range(1.0, 30.0, 0.5) var zoom_speed: float = 12.0

@onready var _yaw_pivot: Node3D = $YawPivot
@onready var _pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var _camera: Camera3D = $YawPivot/PitchPivot/Camera3D
@onready var _fader: OccluderFader = $OccluderFader

var _target: Node3D = null
## Where the player has zoomed to, before obstruction is considered.
var _zoom_goal: float = 23.0
## Smoothed follower of [member _zoom_goal]; also the camera's actual distance.
var _zoom_current: float = 23.0


func _ready() -> void:
	_zoom_goal = clampf(zoom_distance, zoom_min, zoom_max)
	_zoom_current = _zoom_goal
	_camera.position.z = _zoom_current
	_apply_pitch()
	_apply_yaw()


## Sets the node this rig follows and snaps to it immediately.
func set_target(target: Node3D) -> void:
	_target = target
	_fader.setup(_camera, target)
	snap_to_target()


## Jumps the rig to its target without any easing — use after teleports.
func snap_to_target() -> void:
	if _target == null:
		return
	global_position = _target.global_position + follow_offset
	if _camera != null:
		_camera.position.z = _zoom_current
	reset_physics_interpolation()


## Current camera distance in metres.
func get_camera_distance() -> float:
	return _zoom_current


func get_yaw() -> float:
	return deg_to_rad(yaw_degrees)


func set_yaw_degrees(value: float) -> void:
	yaw_degrees = value
	_apply_yaw()


func set_pitch_degrees(value: float) -> void:
	pitch_degrees = value
	_apply_pitch()


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var goal: Vector3 = _target.global_position + follow_offset
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * delta))
	_zoom_current = lerpf(_zoom_current, _zoom_goal, 1.0 - exp(-zoom_speed * delta))
	_camera.position.z = _zoom_current


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_zoom_goal = clampf(_zoom_goal - zoom_step, zoom_min, zoom_max)
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom_goal = clampf(_zoom_goal + zoom_step, zoom_min, zoom_max)


func _apply_yaw() -> void:
	if _yaw_pivot != null:
		_yaw_pivot.rotation.y = deg_to_rad(yaw_degrees)
	yaw_changed.emit(deg_to_rad(yaw_degrees))


func _apply_pitch() -> void:
	if _pitch_pivot != null:
		_pitch_pivot.rotation.x = deg_to_rad(-pitch_degrees)
