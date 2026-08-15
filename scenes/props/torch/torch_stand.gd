class_name TorchStand
extends Node3D
## The torch's home: a post by the house door holding one torch. E takes the
## torch into the actor's hand (lighting it); E again, back at the stand,
## returns and snuffs it. The stand owns the whole exchange, so neither the
## player script nor the torch needs to know a hand-off exists — the actor
## only has to carry a [HandSocket] child, which the stand finds on the node
## it is handed.

## Where the torch rests in the ring (mirrors the socket built by
## tools/build_torch.py — change one, change both).
var _rest_transform: Transform3D = Transform3D(
	Basis.IDENTITY.rotated(Vector3.RIGHT, -0.26), Vector3(0.0, 1.12, -0.055))
## How the grip sits in the hand. The rig's hand bone points its +Y down the
## fingers — straight at the ground while the arm hangs — so the torch is
## flipped nearly 180° to burn upward, then canted the other way so the head
## leans *forward* past the shoulder. Tuned against screenshots twice: the
## first attempt lit the player's ankles, the second leaned backward.
var _carry_transform: Transform3D = Transform3D(
	Basis.IDENTITY.rotated(Vector3.RIGHT, PI + 0.40).rotated(Vector3.BACK, 0.45),
	Vector3(0.0, -0.06, 0.10))

@onready var _torch: Torch = $Torch
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	_torch.transform = _rest_transform
	_torch.lit = false
	_interactable.prompt = "Take torch"


func _on_interacted(actor: Node3D) -> void:
	var socket: HandSocket = actor.find_child("HandSocket", true, false) as HandSocket
	if socket == null:
		return
	if _torch.get_parent() == self:
		_torch.reparent(socket, false)
		_torch.transform = _carry_transform
		_torch.lit = true
		_interactable.prompt = "Return torch"
	elif _torch.get_parent() == socket:
		_torch.reparent(self, false)
		_torch.transform = _rest_transform
		_torch.lit = false
		_interactable.prompt = "Take torch"
