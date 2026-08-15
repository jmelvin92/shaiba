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

## What using this does right now, e.g. "Open". Nothing renders it (no
## on-screen prompts — Joshua's call), but the prop keeps it true to its state:
## the verify harness reads it, and a future accessibility toggle could.
@export var prompt: String = "Use"
## Switched off, this volume neither responds nor is offered — for props that
## are only sometimes usable (a locked door, a lamp with no oil).
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
