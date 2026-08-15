class_name AcousticZone
extends Area3D
## An interior's acoustics in one drop-in node (Phase 6.6).
##
## Give a building one of these, sized to its interior, and it gets both
## halves of "sounding indoors" for free:
##
## 1. Positional sounds inside the volume are rerouted to the Interior bus
##    (subtle reverb) — that's Godot's own Area3D audio-bus override, zero
##    code here.
## 2. While the player is inside, the outdoor ambience bed is muffled: the
##    low-pass on the Ambience bus closes down and the bus is ducked, both
##    eased so walking through the door is a smooth transition, not a cut.
##
## The pattern mirrors [InteriorCutaway]: reusable, nothing per-building to
## configure beyond the shape. The Ambience-bus effect is engine-global state,
## so occupancy is counted across *all* zones (static) and every zone drives
## toward the same shared answer — two nested zones can never fight.

## Cutoff while indoors, Hz. The bus rests at 20500 (inaudibly open).
@export_range(200.0, 4000.0, 50.0) var muffled_cutoff_hz: float = 900.0
## Ambience level while indoors, dB (relative to the bus's outdoor 0).
@export_range(-40.0, 0.0, 0.5) var muffled_volume_db: float = -8.0
## How quickly the muffle closes in and releases.
@export_range(1.0, 30.0, 0.5) var fade_speed: float = 6.0

const OPEN_CUTOFF_HZ: float = 20500.0
const AMBIENCE_BUS: StringName = &"Ambience"
const INTERIOR_BUS: StringName = &"Interior"

## Player-occupancy across every AcousticZone in the level (see class notes).
static var _occupied_zones: int = 0


func _ready() -> void:
	audio_bus_override = true
	audio_bus_name = INTERIOR_BUS
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	var bus: int = AudioServer.get_bus_index(AMBIENCE_BUS)
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0:
		set_physics_process(false)
		return
	var lowpass: AudioEffectLowPassFilter = (
		AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	)
	if lowpass == null:
		set_physics_process(false)
		return
	var inside: bool = _occupied_zones > 0
	var cutoff_goal: float = muffled_cutoff_hz if inside else OPEN_CUTOFF_HZ
	var volume_goal: float = muffled_volume_db if inside else 0.0
	var weight: float = 1.0 - exp(-fade_speed * delta)
	lowpass.cutoff_hz = lerpf(lowpass.cutoff_hz, cutoff_goal, weight)
	AudioServer.set_bus_volume_db(
		bus, lerpf(AudioServer.get_bus_volume_db(bus), volume_goal, weight)
	)
	if (
		absf(lowpass.cutoff_hz - cutoff_goal) < 1.0
		and absf(AudioServer.get_bus_volume_db(bus) - volume_goal) < 0.05
	):
		lowpass.cutoff_hz = cutoff_goal
		AudioServer.set_bus_volume_db(bus, volume_goal)
		set_physics_process(false)


func _on_body_entered(_body: Node3D) -> void:
	_occupied_zones += 1
	set_physics_process(true)


func _on_body_exited(_body: Node3D) -> void:
	_occupied_zones = maxi(_occupied_zones - 1, 0)
	set_physics_process(true)
