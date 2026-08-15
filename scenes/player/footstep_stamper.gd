class_name FootstepStamper
extends Node
## Turns the character's actual gait into sand stamps: a print the moment a
## toe bone plants, a wide drag stamp while wading deep sand, a splat on
## landing. Owned and driven by the Player (which calls [method tick] every
## physics tick — call down); reports stamps by signal only, so it knows
## nothing about the terrain or the deformation system that listens.
##
## Plant detection: a swinging foot travels roughly twice the body's speed,
## a planted one nearly stops (Phase 3 measured ~14% of body speed of stance
## roll). A foot "plants" when its horizontal speed drops below
## [member plant_fraction] of the body's and stamps once on that edge;
## it must exceed [member unplant_fraction] again before it can replant.

## A mark for the sand: position and radius in world metres, strength 0–1,
## angle in radians, stretch elongating the mark along its angle.
signal stamped(
	world_xz: Vector2, radius: float, strength: float, angle: float, stretch: float
)

## A foot hit the ground (Phase 6.6). Emitted at the same plant edge as the
## footprint stamp, so footstep *sound* and footprint can never drift apart —
## but as its own signal, because drag stamps and landing splats are sand
## marks, not footfalls.
signal foot_planted(world_xz: Vector2)

@export_group("Footprints")
## Across-the-foot half-width of a print, metres.
@export_range(0.05, 0.5, 0.01) var foot_radius: float = 0.16
## Elongation of a print along the direction of travel.
@export_range(1.0, 3.0, 0.05) var foot_stretch: float = 1.8
## Strength of a normal footprint.
@export_range(0.0, 1.0, 0.05) var foot_strength: float = 0.85
## A foot plants when its speed falls below this fraction of body speed…
@export_range(0.1, 0.9, 0.05) var plant_fraction: float = 0.5
## …and must exceed this fraction again before it can plant again.
@export_range(0.2, 1.5, 0.05) var unplant_fraction: float = 0.85
## …and must also have TRAVELLED this far since its own last plant, metres.
## The speed thresholds alone chatter at low body speeds (turning in place, a
## slow indoor shuffle): a hovering foot re-plants in the same spot several
## times a second. Prints hid that — a stamp on top of itself is invisible —
## but Phase 6.6 made every plant audible, and a double step is very not.
## Same-foot plants sit ~1.3 m apart at a normal walk, so 0.25 m only ever
## rejects plants that didn't come from a real stride.
@export_range(0.0, 1.0, 0.05) var min_step_distance: float = 0.25

@export_group("Deep-sand drag")
## Wading factor (0–1, from the player's sand depth) where dragging begins.
@export_range(0.0, 1.0, 0.05) var drag_wade_min: float = 0.35
## Distance between drag stamps, metres.
@export_range(0.1, 1.0, 0.05) var drag_spacing: float = 0.35
## Radius of a drag stamp, metres.
@export_range(0.05, 1.0, 0.01) var drag_radius: float = 0.34
## Strength of a drag stamp at full wade.
@export_range(0.0, 1.0, 0.05) var drag_strength: float = 0.3

@export_group("Landing")
## Base radius of the splat left by landing from a jump or fall, metres.
@export_range(0.0, 2.0, 0.05) var landing_radius: float = 0.45

var _skeleton: Skeleton3D = null
var _bones: Array[int] = []
var _previous: Array[Vector2] = []
var _planted: Array[bool] = [true, true]
## Where each foot last made a counted plant, for the travel gate. Starts far
## away so the first real plant always counts.
var _last_plant: Array[Vector2] = [Vector2(1e9, 1e9), Vector2(1e9, 1e9)]
var _drag_travelled: float = 0.0


## Called by the owning Player once its model is in the tree.
func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_bones = [skeleton.find_bone("LeftToeBase"), skeleton.find_bone("RightToeBase")]
	_previous = [_toe_xz(0), _toe_xz(1)]


## Called by the owning Player every physics tick.
func tick(delta: float, velocity: Vector3, footed: bool, wade: float) -> void:
	if _skeleton == null:
		return
	var planar: Vector2 = Vector2(velocity.x, velocity.z)
	var body_speed: float = planar.length()

	if not footed or body_speed < 0.3:
		# Airborne or (nearly) still: no gait to read. Counting both feet as
		# planted means stopping never fires a late stamp, and the first real
		# stamp after moving again comes from a genuine swing-then-plant.
		_planted = [true, true]
		_previous = [_toe_xz(0), _toe_xz(1)]
		return

	var travel_angle: float = planar.angle()
	for foot: int in range(2):
		var at: Vector2 = _toe_xz(foot)
		var foot_speed: float = (at - _previous[foot]).length() / delta
		_previous[foot] = at
		if _planted[foot]:
			if foot_speed > unplant_fraction * body_speed:
				_planted[foot] = false
		elif foot_speed < plant_fraction * body_speed:
			_planted[foot] = true
			if at.distance_to(_last_plant[foot]) >= min_step_distance:
				_last_plant[foot] = at
				stamped.emit(at, foot_radius, foot_strength, travel_angle, foot_stretch)
				foot_planted.emit(at)

	if wade >= drag_wade_min:
		_drag_travelled += body_speed * delta
		if _drag_travelled >= drag_spacing:
			_drag_travelled -= drag_spacing
			var body_at: Vector2 = _body_xz()
			stamped.emit(body_at, drag_radius, drag_strength * wade, travel_angle, 1.4)
	else:
		_drag_travelled = 0.0


## Called by the owning Player when it lands from a jump or fall.
func notify_landed(impact_speed: float) -> void:
	if _skeleton == null:
		return
	var radius: float = landing_radius * clampf(0.5 + impact_speed * 0.12, 0.7, 1.4)
	stamped.emit(_body_xz(), radius, 1.0, 0.0, 1.0)


func _toe_xz(foot: int) -> Vector2:
	var world: Vector3 = (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_bones[foot]).origin
	)
	return Vector2(world.x, world.z)


func _body_xz() -> Vector2:
	var world: Vector3 = _skeleton.global_transform.origin
	return Vector2(world.x, world.z)
