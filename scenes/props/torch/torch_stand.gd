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

var _audio: AudioStreamPlayer3D = null


## Stable save-file ID; empty falls back to the node's tree path.
@export var persistence_id: String = "torch_stand"


func _ready() -> void:
	add_to_group(SaveSystem.GROUP)
	_interactable.interacted.connect(_on_interacted)
	_torch.transform = _rest_transform
	_torch.lit = false
	_interactable.prompt = "Take torch"
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.max_distance = 25.0
	add_child(_audio)


func _on_interacted(actor: Node3D) -> void:
	var socket: HandSocket = actor.find_child("HandSocket", true, false) as HandSocket
	if socket == null:
		return
	if _torch.get_parent() == self:
		_give_to(socket)
		_play(SoundBank.stream("fire/torch_take.wav"))
	elif _torch.get_parent() == socket:
		_return_to_stand()
		_play(SoundBank.stream("fire/torch_return.wav"))


func _give_to(socket: HandSocket) -> void:
	_torch.reparent(socket, false)
	_torch.transform = _carry_transform
	_torch.lit = true
	_interactable.prompt = "Return torch"


func _return_to_stand() -> void:
	_torch.reparent(self, false)
	_torch.transform = _rest_transform
	_torch.lit = false
	_interactable.prompt = "Take torch"


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	if _audio.stream != stream:
		_audio.stream = stream
	_audio.play()


## --- Persistence (the SaveSystem contract) ---------------------------------


func get_persistence_key() -> String:
	return SaveSystem.key_for(self, persistence_id)


func capture_state() -> Dictionary:
	return {"taken": _torch.get_parent() != self}


func restore_state(state: Dictionary, context: Dictionary) -> void:
	var taken: bool = bool(state.get("taken", false))
	if taken == (_torch.get_parent() != self):
		return
	if not taken:
		_return_to_stand()
		return
	# "Carried" needs the carrier — the context's actor (the player).
	var actor: Node3D = context.get("actor") as Node3D
	if actor == null:
		return
	var socket: HandSocket = actor.find_child("HandSocket", true, false) as HandSocket
	if socket != null:
		_give_to(socket)
