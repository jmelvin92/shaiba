class_name Torch
extends Node3D
## The carried torch: the model plus a FlameLight at its head. It burns when
## carried and rests cold in its stand — taking it is lighting it (the flint
## is implied). The stand owns the take/return logic; all the torch itself
## knows is whether it is lit.
##
## While lit and moving fast (a sprint with it in hand), the flame flutters —
## an occasional whoosh one-shot on top of the FlameLight's crackle loop.

## Speed above which the flame audibly flutters, m/s. Between the walk (1.8)
## and the run (4.9), so only a real run stirs it.
@export_range(1.0, 10.0, 0.1) var whoosh_speed: float = 3.5
## Shortest gap between two whooshes, seconds.
@export_range(0.1, 3.0, 0.05) var whoosh_gap: float = 0.6

@export var lit: bool = false:
	set(value):
		lit = value
		if _flame != null:
			_flame.lit = value
		set_physics_process(lit and _whoosh != null)

@onready var _flame: FlameLight = $Flame

var _whoosh: AudioStreamPlayer3D = null
var _last_position: Vector3 = Vector3.ZERO
var _whoosh_cooldown: float = 0.0


func _ready() -> void:
	_flame.lit = lit
	var takes: AudioStreamRandomizer = SoundBank.take_set("fire/torch_whoosh")
	if takes != null:
		_whoosh = AudioStreamPlayer3D.new()
		_whoosh.stream = takes
		_whoosh.bus = &"SFX"
		_whoosh.max_distance = 25.0
		_whoosh.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(_whoosh)
	_last_position = global_position
	set_physics_process(lit and _whoosh != null)


func _physics_process(delta: float) -> void:
	var speed: float = (global_position - _last_position).length() / delta
	_last_position = global_position
	_whoosh_cooldown = maxf(_whoosh_cooldown - delta, 0.0)
	# Speeds no player reaches are teleports (being taken from the stand), not
	# motion — skip them or every pickup would open with a spurious whoosh.
	if speed < whoosh_speed or speed > 20.0:
		return
	if _whoosh_cooldown > 0.0 or _whoosh.playing:
		return
	_whoosh_cooldown = whoosh_gap
	_whoosh.play()
