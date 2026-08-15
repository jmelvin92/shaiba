class_name Torch
extends Node3D
## The carried torch: the model plus a FlameLight at its head. It burns when
## carried and rests cold in its stand — taking it is lighting it (the flint
## is implied). The stand owns the take/return logic; all the torch itself
## knows is whether it is lit.

@export var lit: bool = false:
	set(value):
		lit = value
		if _flame != null:
			_flame.lit = value

@onready var _flame: FlameLight = $Flame


func _ready() -> void:
	_flame.lit = lit
