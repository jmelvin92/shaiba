class_name Interactable
extends Area3D
## Something the player can use by pressing the interact key next to it.
##
## This is the prop-side half of the interaction system; the player-side half
## is [Interactor], which watches for these volumes, shows the prompt over the
## nearest one, and calls [method interact] when the key is pressed. A prop
## becomes usable by adding one of these as a child, shaping its volume to
## cover everywhere the prop should be reachable from, and connecting
## [signal interacted] — exactly the shape of the Phase 5 stamper interface:
## one signal, one connect, no coupling.
##
## Interaction volumes live alone on physics layer 4 (docs/ARCHITECTURE.md),
## which nothing else collides with: an Interactable can never block movement,
## fade, or trip the cutaway, and the Interactor's overlap query can never pick
## up a wall. The layer is enforced here rather than trusted to each scene.

## Emitted when an actor uses this. The owning prop connects it and reacts;
## nothing here knows or cares what the prop does with it.
signal interacted(actor: Node3D)

## What the prompt offers, e.g. "Open". The prop may rewrite this as its state
## changes; the Interactor re-reads it every tick.
@export var prompt: String = "Use"
## Where the prompt floats, in this node's local space — over the handle of a
## door, above the lid of a chest.
@export var prompt_anchor: Vector3 = Vector3(0.0, 1.5, 0.0)
## Switched off, this volume neither prompts nor responds — for props that are
## only sometimes usable (a locked door, a lamp with no oil).
@export var enabled: bool = true

## Physics layer 4, as a mask bit.
const LAYER_INTERACTION: int = 8


func _ready() -> void:
	collision_layer = LAYER_INTERACTION
	collision_mask = 0
	monitoring = false


## Called by an [Interactor] on behalf of [param actor] (the player's body).
func interact(actor: Node3D) -> void:
	if enabled:
		interacted.emit(actor)


## World-space point the prompt label hangs at.
func get_prompt_position() -> Vector3:
	return to_global(prompt_anchor)
