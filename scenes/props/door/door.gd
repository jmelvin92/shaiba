class_name Door
extends Node3D
## A hinged door: closed it is a wall, opened it swings clear of its doorway.
##
## Reusable across every building (docs/PLAN.md Phase 6 — independent props):
## the scene wraps assets/models/door.glb (origin on the hinge line, leaf
## growing +X) with an [AnimatableBody3D] so collision turns with the leaf, and
## an [Interactable] so the player's E does the opening. The prop is entirely
## self-driven — a building just instances it in a doorway; the one thing the
## building may want to say is [method set_fadeable], depending on whether the
## wall around the door is fader-managed or cutaway-managed
## (docs/ARCHITECTURE.md, the single-writer rule).
##
## The leaf swings *away from whoever opens it*: opening can therefore never
## shove the player, and the door reads as being pushed rather than operated.
## Closing sweeps the doorway regardless — a player who stands in it may get
## nudged, which is their own doing.

## Announced whenever the door starts opening or closing — for sound, for a
## camel that waits at thresholds, for anything later. Nothing connects it yet.
signal toggled(is_open: bool)

## How far the leaf swings. Past a right angle, so an open door reads as flung
## wide rather than ajar, without reaching so far it hugs walls or awning poles.
@export_range(60.0, 150.0, 1.0) var open_angle_degrees: float = 105.0
## Full-swing travel time. Brisk: the door should never make the player wait.
@export_range(0.1, 2.0, 0.05) var swing_seconds: float = 0.45
@export var start_open: bool = false
## Whether the leaf sits on the occluder layer (5) so [OccluderFader] can
## ghost it, or on the world layer (1) for buildings whose wall around it is
## cutaway-managed. The owning building calls [method set_fadeable] to match
## the door to its wall; standalone, a door is simply fadeable.
@export var fadeable: bool = true

@export var leaf_path: NodePath = ^"Leaf"
@export var body_path: NodePath = ^"Leaf/Body"
@export var interactable_path: NodePath = ^"Interactable"

const LAYER_WORLD: int = 1
const LAYER_FADEABLE: int = 5

var _leaf: Node3D = null
var _interactable: Interactable = null
var _open: bool = false
## Which way the current/last opening swung: +1 toward local -Z, -1 toward +Z.
var _swing_sign: float = 1.0
var _target_degrees: float = 0.0


func _ready() -> void:
	_leaf = get_node_or_null(leaf_path) as Node3D
	if _leaf == null:
		push_warning("Door: no leaf at %s; nothing to swing." % leaf_path)
		set_physics_process(false)
		return
	_interactable = get_node_or_null(interactable_path) as Interactable
	if _interactable != null:
		_interactable.interacted.connect(_on_interacted)
	set_fadeable(fadeable)
	if start_open:
		set_open(true, true)
	else:
		_update_prompt()
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	var degrees: float = rad_to_deg(_leaf.rotation.y)
	var step: float = open_angle_degrees / swing_seconds * delta
	degrees = move_toward(degrees, _target_degrees, step)
	_leaf.rotation.y = deg_to_rad(degrees)
	if is_equal_approx(degrees, _target_degrees):
		# Settled: a standing door costs nothing, per the Phase 5 idle rule.
		set_physics_process(false)


func is_open() -> bool:
	return _open


## Opens or closes without an actor — for level scripts and the verify
## harness. Opening reuses the last swing direction.
func set_open(open: bool, instant: bool = false) -> void:
	_open = open
	_target_degrees = open_angle_degrees * _swing_sign if open else 0.0
	_update_prompt()
	toggled.emit(open)
	if instant and _leaf != null:
		_leaf.rotation.y = deg_to_rad(_target_degrees)
		return
	set_physics_process(true)


## Moves the leaf's collision between the occluder layer and the world layer.
## Called by the owning building; see the class notes.
func set_fadeable(value: bool) -> void:
	fadeable = value
	var body: PhysicsBody3D = get_node_or_null(body_path) as PhysicsBody3D
	if body != null:
		body.collision_layer = LAYER_FADEABLE if value else LAYER_WORLD


## The leaf's meshes — what a cutaway-managed building hands to its
## [InteriorCutaway] alongside its own walls.
func get_visuals() -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	if _leaf != null:
		_collect_visuals(_leaf, found)
	return found


func _on_interacted(actor: Node3D) -> void:
	if not _open and actor != null:
		# Swing away from whoever is opening it. Positive yaw carries the
		# leaf toward local -Z, so the sign of the actor's local Z is the
		# sign of the swing that clears them.
		var actor_z: float = to_local(actor.global_position).z
		if not is_zero_approx(actor_z):
			_swing_sign = signf(actor_z)
	set_open(not _open)


func _update_prompt() -> void:
	if _interactable != null:
		_interactable.prompt = "Close" if _open else "Open"


func _collect_visuals(root: Node, into: Array[GeometryInstance3D]) -> void:
	var visual: GeometryInstance3D = root as GeometryInstance3D
	if visual != null:
		into.append(visual)
	for child: Node in root.get_children():
		_collect_visuals(child, into)
