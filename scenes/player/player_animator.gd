class_name PlayerAnimator
extends AnimationTree
## Turns the player's movement state into animation.
##
## The controller calls down into this node once per physics tick with three
## facts about itself — how fast it is moving, whether it is on the ground, and
## whether it is crouching — plus a nudge on the two events it cannot infer
## (a launch and a touchdown). Everything else about clips, blending and state
## lives here, so retuning a gait or swapping a clip never touches player.gd.
##
## See docs/DECISIONS.md for why the blend anchors are where they are.

## Ground speed each locomotion clip covers at 1.0x playback, measured from the
## planted foot by tools/measure_gaits.gd against the real rig.
##
## The blend-space anchors in player_locomotion.tres sit at exactly these
## speeds. Because idle is anchored at 0 m/s, blending it toward walk shortens
## the stride in proportion, so the blended pose's own ground speed always
## equals the blend position — which is why the feet stay planted at every
## speed without correcting the playback rate.
const WALK_SPEED: float = 1.4
const RUN_SPEED: float = 4.9
## Crouched movement holds a pose (the source set has no forward crouch walk),
## so this is simply the speed the controller is tuned to, not a measurement.
const CROUCH_SPEED: float = 1.0

const GROUND: StringName = &"locomotion"
const CROUCHED: StringName = &"crouch"
const JUMP: StringName = &"jump"
const FALL: StringName = &"fall"
const LAND: StringName = &"land"

const REQUIRED: PackedStringArray = [
	"idle", "walk", "run", "crouch_idle", "crouch_walk", "jump", "fall", "land",
]

## Below this landing speed the character just keeps walking. A step off a
## 0.35 m curb arrives at about 3 m/s; a full jump lands at about 5.5 m/s.
@export_range(0.0, 8.0, 0.1) var land_impact_threshold: float = 4.0

var _state: AnimationNodeStateMachinePlayback
## The state we last asked for. [method AnimationNodeStateMachinePlayback.travel]
## only takes effect when the tree next processes, so asking the playback what
## is current would still report the previous state and we would immediately
## override our own request.
var _wanted: StringName = GROUND
## Seconds left of a one-shot (a jump or a landing) that owns the machine until
## it has played out.
var _hold: float = 0.0
var _jump_length: float = 0.0
var _land_length: float = 0.0


func _ready() -> void:
	var player: AnimationPlayer = get_node_or_null(anim_player) as AnimationPlayer
	if player == null:
		push_error("PlayerAnimator: anim_player does not point at an AnimationPlayer.")
		return
	for clip: String in REQUIRED:
		if not player.has_animation(clip):
			push_error("PlayerAnimator: player.glb is missing the '%s' clip." % clip)
			return

	_jump_length = player.get_animation(JUMP).length
	_land_length = player.get_animation(LAND).length

	_state = get("parameters/playback") as AnimationNodeStateMachinePlayback
	# Only start mixing once the machine has somewhere to be, otherwise the
	# first frame renders the bind pose.
	_state.start(GROUND)
	active = true


## Called every physics tick by the controller that owns this node.
func set_locomotion(planar_speed: float, grounded: bool, crouching: bool) -> void:
	if _state == null:
		return

	if crouching:
		set("parameters/%s/blend_position" % CROUCHED, clampf(planar_speed, 0.0, CROUCH_SPEED))
	else:
		set("parameters/%s/blend_position" % GROUND, clampf(planar_speed, 0.0, RUN_SPEED))

	_hold = maxf(_hold - 1.0 / float(Engine.physics_ticks_per_second), 0.0)
	if _hold > 0.0:
		# A jump or a landing is mid-flight; let it finish rather than talking
		# over it every tick.
		return

	if not grounded:
		_travel_to(FALL)
	else:
		_travel_to(CROUCHED if crouching else GROUND)


## Name of the state playing right now, for probes and debug overlays.
func get_state() -> StringName:
	return _state.get_current_node() if _state != null else &""


## The controller launched a jump this tick.
func play_jump() -> void:
	_travel_to(JUMP)
	_hold = _jump_length


## The controller touched down this tick, arriving at [param impact_speed] m/s.
func play_land(impact_speed: float) -> void:
	if impact_speed < land_impact_threshold:
		# Stepping off a curb shouldn't buckle the knees.
		return
	_travel_to(LAND)
	_hold = _land_length


func _travel_to(state: StringName) -> void:
	if _state == null or _wanted == state:
		return
	_wanted = state
	_state.travel(state)
