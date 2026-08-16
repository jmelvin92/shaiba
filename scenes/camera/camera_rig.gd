class_name CameraRig
extends Node3D
## Angled "diorama" camera rig.
##
## Perspective camera with a narrow FOV, pitched 19° down since Joshua's
## Phase 4 pick — low enough that dune backs and a sliver of hazy horizon
## sit in the upper frame — see docs/DECISIONS.md. The rig follows a target position with
## damping and zooms on the scroll wheel between clamps. It deliberately does
## NOT move to avoid geometry: anything blocking the view is faded instead, by
## the OccluderFader child. See docs/DECISIONS.md.
##
## The player orbits it freely around the target with a left-click drag. The
## **pitch stays fixed** while they do — this is a turntable, not free-look, so
## the diorama framing the whole art direction rests on cannot be lost, and
## there is no angle from which the camera can end up under the sand.
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
## Downward pitch in degrees, from horizontal. Below ~15° dunes would hide
## the player constantly (terrain never fades); above ~26° the narrow lens
## shows no background at all.
@export_range(10.0, 80.0, 0.5) var pitch_degrees: float = 19.0:
	set = set_pitch_degrees
## Rotation of the rig around the world Y axis, degrees. Free — the player
## orbits it with a left-click drag (see the Orbit group), so this is a
## continuous value rather than the 45 deg detents originally planned.
@export_range(0.0, 360.0, 1.0) var yaw_degrees: float = 0.0:
	set = set_yaw_degrees

@export_group("Orbit")
## Degrees of yaw per pixel of horizontal drag. 0.25 puts a half-turn in about
## 720 px — roughly one comfortable sweep of the hand across a trackpad.
@export_range(0.02, 1.0, 0.01) var orbit_sensitivity: float = 0.25
## Drag right turns the view right by default, the way a mouse-look camera
## does. Flip this if it reads backwards — some players expect a drag to grab
## the world and spin it the other way, and it is purely a matter of taste.
@export var invert_orbit: bool = false

@export_group("Terrain")
## Minimum height the camera keeps above the sand, metres. At a 19° pitch the
## camera rides low enough that a tall dune behind the player could otherwise
## swallow it. This is a vertical clamp from the terrain's analytic height —
## not the "camera dodges geometry" behaviour docs/DECISIONS.md rejects: the
## framing never pulls in, it only lifts.
@export_range(0.0, 5.0, 0.1) var terrain_clearance: float = 1.2
## Damping of the lift as it engages and releases.
@export_range(1.0, 30.0, 0.5) var lift_speed: float = 8.0

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
## The game's ears (Phase 6.6). Kept at the *player's* position, not the
## camera's — the camera hangs 23 m back, and ears there would make everything
## sound distant — but turned with the camera's yaw so left/right panning
## matches the screen. `top_level` in the scene so the rig's own follow and
## lift never drag it around; this script places it absolutely each tick.
@onready var _listener: AudioListener3D = $Listener

var _target: Node3D = null
## Where the player has zoomed to, before obstruction is considered.
var _zoom_goal: float = 23.0
## Smoothed follower of [member _zoom_goal]; also the camera's actual distance.
var _zoom_current: float = 23.0
## Terrain query source for the clearance clamp; null on levels without one.
var _terrain: TerrainSettings = null
## The follow position before any terrain lift, tracked separately so the
## lift can never feed back into the follow damping.
var _follow_position: Vector3 = Vector3.ZERO
## Smoothed extra height currently applied to clear the sand.
var _lift: float = 0.0
## True while the player is holding the orbit button and dragging.
var _orbiting: bool = false
## Where the cursor was grabbed, so it can be put back on release.
var _grab_position: Vector2 = Vector2.ZERO
## Drag collected since the last physics tick, degrees. Mouse motion arrives at
## the render rate; banking it and applying it once per tick keeps the rig on
## the same 60 Hz beat as the player it follows, which is what stops the two
## from jittering relative to each other (docs/DECISIONS.md).
var _pending_yaw: float = 0.0


func _ready() -> void:
	add_to_group(SaveSystem.GROUP)
	_zoom_goal = clampf(zoom_distance, zoom_min, zoom_max)
	_zoom_current = _zoom_goal
	_camera.position.z = _zoom_current
	_apply_pitch()
	_apply_yaw()
	_listener.make_current()


## Sets the node this rig follows and snaps to it immediately.
func set_target(target: Node3D) -> void:
	_target = target
	_fader.setup(_camera, target)
	snap_to_target()


## Called by a level that has terrain, so the camera can stay out of the sand.
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain = terrain


## Jumps the rig to its target without any easing — use after teleports.
func snap_to_target() -> void:
	if _target == null:
		return
	_follow_position = _target.global_position + follow_offset
	global_position = _follow_position
	if _camera != null:
		_camera.position.z = _zoom_current
	_lift = _needed_lift()
	global_position.y += _lift
	_update_listener()
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
	if _pending_yaw != 0.0:
		# Applied whole, with no damping: a drag that lags behind the hand
		# feels rubbery rather than smooth. Physics interpolation is what
		# carries the rotation to the render rate.
		set_yaw_degrees(fposmod(yaw_degrees + _pending_yaw, 360.0))
		_pending_yaw = 0.0
	if _target == null:
		return
	var goal: Vector3 = _target.global_position + follow_offset
	_follow_position = _follow_position.lerp(goal, 1.0 - exp(-follow_speed * delta))
	global_position = _follow_position
	_zoom_current = lerpf(_zoom_current, _zoom_goal, 1.0 - exp(-zoom_speed * delta))
	_camera.position.z = _zoom_current
	_lift = lerpf(_lift, _needed_lift(), 1.0 - exp(-lift_speed * delta))
	global_position.y += _lift
	_update_listener()


## Places the ears on the followed target, facing the camera's way. See the
## note on [member _listener].
func _update_listener() -> void:
	if _target == null:
		return
	_listener.global_position = _target.global_position + follow_offset
	_listener.global_rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)


## How far the camera must rise right now to keep its clearance over the sand.
## Evaluated from the terrain's analytic height at the camera's own footprint,
## with the rig sitting at the unlifted follow position.
func _needed_lift() -> float:
	if _terrain == null or _camera == null:
		return 0.0
	var cam: Vector3 = _camera.global_position
	var floor_y: float = _terrain.get_surface_height(Vector2(cam.x, cam.z))
	return maxf(floor_y + terrain_clearance - cam.y, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_orbit"):
		_begin_orbit()
	elif event.is_action_released("camera_orbit"):
		_end_orbit()
	elif _orbiting and event is InputEventMouseMotion:
		var drag: float = (event as InputEventMouseMotion).relative.x * orbit_sensitivity
		# Negated so that dragging right turns the view right: increasing yaw
		# swings the camera anticlockwise seen from above, which reads as left.
		_pending_yaw += drag if invert_orbit else -drag
	# allow_echo, so holding a bound key (+/-) keeps stepping the way repeated
	# scroll notches do; wheel events never echo, so they are unaffected.
	elif event.is_action_pressed("camera_zoom_in", true):
		_zoom_goal = clampf(_zoom_goal - zoom_step, zoom_min, zoom_max)
	elif event.is_action_pressed("camera_zoom_out", true):
		_zoom_goal = clampf(_zoom_goal + zoom_step, zoom_min, zoom_max)


## Grabs the mouse for the duration of a drag.
##
## Capturing rather than merely hiding it means a long spin never runs out of
## desk or off the edge of the window, and the cursor is warped back to where
## it was grabbed on release, so the pointer does not appear to teleport.
func _begin_orbit() -> void:
	if _orbiting:
		return
	_orbiting = true
	_grab_position = get_viewport().get_mouse_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_orbit() -> void:
	if not _orbiting:
		return
	_orbiting = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(_grab_position)


## Losing focus mid-drag would otherwise leave the mouse captured with no way
## to release it, since the button-up lands in another window.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_orbit()


func _apply_yaw() -> void:
	if _yaw_pivot != null:
		_yaw_pivot.rotation.y = deg_to_rad(yaw_degrees)
	yaw_changed.emit(deg_to_rad(yaw_degrees))


func _apply_pitch() -> void:
	if _pitch_pivot != null:
		_pitch_pivot.rotation.x = deg_to_rad(-pitch_degrees)


## --- Persistence (the SaveSystem contract) ---------------------------------


func get_persistence_key() -> String:
	return "camera"


func capture_state() -> Dictionary:
	return {"yaw_degrees": yaw_degrees, "zoom_distance": zoom_distance}


func restore_state(state: Dictionary, _context: Dictionary) -> void:
	set_yaw_degrees(float(state.get("yaw_degrees", yaw_degrees)))
	zoom_distance = clampf(
		float(state.get("zoom_distance", zoom_distance)), zoom_min, zoom_max
	)
	_zoom_goal = zoom_distance
	_zoom_current = zoom_distance
	_camera.position.z = _zoom_current
	snap_to_target()
