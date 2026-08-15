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


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	_apply()


func _on_interacted(_actor: Node3D) -> void:
	lit = not lit
	lit_changed.emit(lit)


func _apply() -> void:
	_flame.lit = lit
	_interactable.prompt = "Snuff lamp" if lit else "Light lamp"
