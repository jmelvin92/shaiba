class_name FlameLight
extends Node3D
## A small flame: an OmniLight3D that flickers like fire plus a tiny visible
## flame mesh. One reusable component for the oil lamp, the carried torch and
## any future campfire (Phase 6.5 piece 3).
##
## The flicker is noise-driven, not random: two smooth noise channels move the
## light's energy and position, so shadows dance the way firelight does and
## never strobe. `lit = false` turns the whole node off (light, mesh, cost).
##
## The scene owning a FlameLight gives it a position (the wick, the torch
## head); everything else is exports here.

## Palette-warm flame color: between accent_gold and the dusk sun tones.
const FLAME_COLOR: Color = Color("FFC873")

@export var lit: bool = true:
	set(value):
		lit = value
		_apply_lit()

## Light reach in metres. The lamp keeps the default; the torch may go wider.
@export_range(2.0, 16.0, 0.5) var light_range: float = 7.0
## Steady-state brightness the flicker moves around.
@export_range(0.0, 4.0, 0.05) var base_energy: float = 1.6
## Fraction of base_energy the flicker may add or remove (0.18 = ±18%).
@export_range(0.0, 0.5, 0.01) var flicker_amount: float = 0.18
## How fast the flame dances, in noise-samples per second.
@export_range(0.1, 10.0, 0.1) var flicker_speed: float = 2.6
## How far the light source itself wanders, metres. Small: it is what makes
## the shadows breathe.
@export_range(0.0, 0.1, 0.005) var sway: float = 0.02
## Whether the flame light casts shadows. On for the lamp (walls must block
## its light so windows and the doorway shape it); a carried torch may switch
## it off if profiling ever demands.
@export var shadows: bool = true

var _light: OmniLight3D = null
var _flame: MeshInstance3D = null
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0

	_light = OmniLight3D.new()
	_light.light_color = FLAME_COLOR
	_light.omni_range = light_range
	_light.light_energy = base_energy
	_light.shadow_enabled = shadows
	add_child(_light)

	_flame = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.030
	mesh.height = 0.085
	mesh.radial_segments = 6
	mesh.rings = 3
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = FLAME_COLOR
	material.emission_enabled = true
	material.emission = FLAME_COLOR
	material.emission_energy_multiplier = 1.8
	material.roughness = 1.0
	mesh.material = material
	_flame.mesh = mesh
	_flame.position.y = 0.03
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)

	_apply_lit()


func _physics_process(delta: float) -> void:
	if not lit:
		return
	_time += delta * flicker_speed
	var energy_wobble: float = _noise.get_noise_2d(_time, 0.0)
	var sway_x: float = _noise.get_noise_2d(_time, 37.0)
	var sway_z: float = _noise.get_noise_2d(_time, 71.0)
	_light.light_energy = base_energy * (1.0 + flicker_amount * energy_wobble)
	_light.position = Vector3(sway * sway_x, 0.0, sway * sway_z)
	# The visible flame leans with the sway and breathes a little.
	_flame.position = Vector3(sway * sway_x, 0.03, sway * sway_z)
	_flame.scale = Vector3.ONE * (1.0 + 0.15 * energy_wobble)


func _apply_lit() -> void:
	if _light == null:
		return
	_light.visible = lit
	_flame.visible = lit
	set_physics_process(lit)
