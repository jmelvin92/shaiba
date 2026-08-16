class_name OilLamp
extends Node3D
## The oil lamp, grown from a decorative furnishing into a real light source
## (Phase 6.5 piece 3): E lights it, E snuffs it. Dark until someone lights it
## — Joshua's call; the lamp is the interior's only light at night, and its
## shadow-casting flame is what makes the windows and doorway glow from
## outside.

signal lit_changed(lit: bool)

## Lamps start cold. An export so a future scene could pre-light one.
@export var lit: bool = false:
	set(value):
		lit = value
		if is_node_ready():
			_apply()

@onready var _flame: FlameLight = $Flame
@onready var _interactable: Interactable = $Interactable

var _audio: AudioStreamPlayer3D = null


## Stable save-file ID; empty falls back to the node's tree path.
@export var persistence_id: String = ""


func _ready() -> void:
	add_to_group(SaveSystem.GROUP)
	_interactable.interacted.connect(_on_interacted)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.max_distance = 20.0
	add_child(_audio)
	_apply()


func _on_interacted(_actor: Node3D) -> void:
	lit = not lit
	lit_changed.emit(lit)
	var stream: AudioStream = SoundBank.stream(
		"fire/lamp_light.wav" if lit else "fire/lamp_snuff.wav"
	)
	if stream != null:
		if _audio.stream != stream:
			_audio.stream = stream
		_audio.play()


func _apply() -> void:
	_flame.lit = lit
	_interactable.prompt = "Snuff lamp" if lit else "Light lamp"


## --- Persistence (the SaveSystem contract) ---------------------------------


func get_persistence_key() -> String:
	return SaveSystem.key_for(self, persistence_id)


func capture_state() -> Dictionary:
	return {"lit": lit}


func restore_state(state: Dictionary, _context: Dictionary) -> void:
	var value: bool = bool(state.get("lit", false))
	if value == lit:
		return
	# The setter relights the flame; lit_changed still fires so listeners
	# (the house's window spill lights) follow. Sound stays with the
	# interaction — a restore is silent.
	lit = value
	lit_changed.emit(lit)
