class_name Interactor
extends Area3D
## The player's reach: finds nearby [Interactable]s and fires the closest one
## when the interact key is pressed.
##
## This is the player-side half of the interaction system (the prop-side half
## is [Interactable] — see docs/ARCHITECTURE.md). It is a self-contained child
## of the player scene: player.gd never knows it exists, and props never know
## who used them beyond the actor node handed to them. The overlap query is
## physics-layer 4 only, so this volume can see interaction zones and nothing
## else — walls, terrain and bodies are invisible to it.
##
## There is deliberately no on-screen prompt (Joshua's call, 2026-08-14):
## players know what E does, and the desert stays free of floating UI. The
## Interactable's `prompt` string stays maintained for the verify harness and
## for any future accessibility toggle.

var _target: Interactable = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = Interactable.LAYER_INTERACTION
	monitorable = false


func _physics_process(_delta: float) -> void:
	_target = _closest_interactable()
	if _target == null:
		return
	if Input.is_action_just_pressed("interact"):
		var actor: Node3D = owner as Node3D
		_target.interact(actor if actor != null else self)


## The Interactable currently on offer, if any — read by the verify harness.
func get_target() -> Interactable:
	return _target


func _closest_interactable() -> Interactable:
	var best: Interactable = null
	var best_distance: float = INF
	for area: Area3D in get_overlapping_areas():
		var candidate: Interactable = area as Interactable
		if candidate == null or not candidate.enabled:
			continue
		var distance: float = global_position.distance_squared_to(
			candidate.global_position
		)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best
