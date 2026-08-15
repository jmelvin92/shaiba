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


func _ready() -> void:
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
