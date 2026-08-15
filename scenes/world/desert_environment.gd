class_name DesertEnvironment
extends Node3D
## Drives the day-night cycle: samples `Game.time_of_day` each frame and sets
## the Sun's arc/color/energy, the Moon, the four ProceduralSkyMaterial colors
## and the fog color from a keyframed lighting table (Phase 6.5 piece 2).
##
## Two contracts hold at every hour:
## - 16:00 reproduces the pre-cycle committed golden-hour light *exactly* —
##   the sun arc is calibrated backward from that anchor (CAL_*), and the
##   16:00 keyframe stores those committed values verbatim.
## - `fog_light_color` equals the sky horizon color, so the far dunes melt
##   into the haze at night exactly as they do by day (the Phase 4 horizon
##   contract — the streaming edge must never become visible).
##
## Ambient needs nothing here: the Environment's ambient source is the sky
## background, so darkening the sky darkens the world by itself.
## `tools/verify_cycle.gd` is the executable gate for all of it.

## One keyframe of the lighting day: sky top/horizon, sun color and energy.
class LightKey:
	var hour: float
	var top: Color
	var horizon: Color
	var sun: Color
	var energy: float

	func _init(h: float, t: Color, hz: Color, s: Color, e: float) -> void:
		hour = h
		top = t
		horizon = hz
		sun = s
		energy = e


## The committed pre-cycle light, reproduced exactly at CAL_HOUR: sun pitched
## 40° down at yaw 30°, #FFE9C4 at energy 1.2, under today's sky colors.
const CAL_HOUR: float = 16.0
const CAL_ELEVATION_DEG: float = 40.0
const CAL_YAW_DEG: float = -30.0
const CAL_SUN_COLOR: Color = Color("FFE9C4")
const CAL_SUN_ENERGY: float = 1.2

const DAY_TOP: Color = Color("8FB8C9")
const DAY_HORIZON: Color = Color("FFEFD6")
## The sky material's ground hemisphere at full daylight (today's committed
## value); it dims with the horizon's luminance through the night.
const DAY_GROUND_BOTTOM: Color = Color("C4914E")

## Night sky anchors — `night_darkness` blends the whole night between them.
const MOONLIT_TOP: Color = Color("34455E")
const MOONLIT_HORIZON: Color = Color("4A5E7A")
const DARK_TOP: Color = Color("101828")
const DARK_HORIZON: Color = Color("1F2B44")
const MOONLIT_MOON_ENERGY: float = 0.32
const DARK_MOON_ENERGY: float = 0.06

## The sun sweeps this much yaw between sunrise and sunset.
const SUN_YAW_SPAN_DEG: float = 180.0
const MOON_MAX_ELEVATION_DEG: float = 50.0
const MOON_YAW_RISE_DEG: float = -100.0
const MOON_YAW_SPAN_DEG: float = 160.0
## The moon fades in/out over this many game hours at the night's edges.
const MOON_FADE_HOURS: float = 1.0

## Skip re-applying when time moved less than this (game hours): sky radiance
## regenerates on every material change, and at normal speed 0.002 h is a
## refresh every ~0.12 real seconds — far below a visible color step.
const APPLY_EPSILON: float = 0.002

## 0 = bright moonlit night, 1 = properly dark. Joshua picked 1.0 from the
## ladder (2026-08-15): night should make carried light matter, with a touch
## of dread — see DECISIONS.
@export_range(0.0, 1.0, 0.01) var night_darkness: float = 1.0:
	set(value):
		night_darkness = clampf(value, 0.0, 1.0)
		_rebuild_keys()
		_apply_now()

@onready var _sun: DirectionalLight3D = $Sun
@onready var _moon: DirectionalLight3D = $Moon
@onready var _environment: Environment = ($WorldEnvironment as WorldEnvironment).environment
## The sky is shaders/desert_sky.gdshader since piece 3 (stars needed a
## custom shader); it reproduces ProceduralSkyMaterial's gradient exactly.
@onready var _sky: ShaderMaterial = _environment.sky.sky_material as ShaderMaterial

## The Game autoload, fetched the guarded way so the scene stays standalone-
## safe (F6, --script tools). Without it the cycle holds the 16:00 look.
@onready var _game: Node = get_node_or_null(^"/root/Game")

var _keys: Array[LightKey] = []
var _applied_hour: float = -1.0
## Solved in _ready so that the arc passes through CAL_ELEVATION at CAL_HOUR.
var _max_elevation_deg: float = 0.0
var _sunrise: float = 5.75
var _sunset: float = 18.5


func _ready() -> void:
	if _game != null:
		_sunrise = _game.SUNRISE_HOUR
		_sunset = _game.SUNSET_HOUR
	var cal_u: float = (CAL_HOUR - _sunrise) / (_sunset - _sunrise)
	_max_elevation_deg = CAL_ELEVATION_DEG / sin(PI * cal_u)
	_rebuild_keys()
	_apply_now()


func _physics_process(_delta: float) -> void:
	var hour: float = CAL_HOUR if _game == null else _game.time_of_day
	if absf(hour - _applied_hour) < APPLY_EPSILON:
		return
	apply_time(hour)


## Sets every light/sky/fog property for [param hour]. Public so tools
## (ladders, verify) can drive the cycle without a clock.
func apply_time(hour: float) -> void:
	var h: float = fposmod(hour, 24.0)
	_applied_hour = h
	var key: LightKey = _blend_keys(h)

	_sky.set_shader_parameter(&"top_color", key.top)
	_sky.set_shader_parameter(&"horizon_color", key.horizon)
	_sky.set_shader_parameter(&"ground_horizon_color", key.horizon)
	var ground_dim: float = clampf(
		key.horizon.get_luminance() / DAY_HORIZON.get_luminance(), 0.05, 1.0)
	_sky.set_shader_parameter(
		&"ground_bottom_color", DAY_GROUND_BOTTOM * Color(ground_dim, ground_dim, ground_dim))
	_sky.set_shader_parameter(&"star_strength", _star_strength(h))
	_environment.fog_light_color = key.horizon

	var day_u: float = (h - _sunrise) / (_sunset - _sunrise)
	_sun.rotation_degrees = Vector3(
		-_max_elevation_deg * sin(PI * clampf(day_u, 0.0, 1.0)),
		CAL_YAW_DEG + (clampf(day_u, 0.0, 1.0) - (CAL_HOUR - _sunrise) / (_sunset - _sunrise))
			* SUN_YAW_SPAN_DEG,
		0.0)
	_sun.light_color = key.sun
	var below_horizon: bool = day_u < 0.0 or day_u > 1.0
	_sun.light_energy = 0.0 if below_horizon else key.energy
	_sun.visible = _sun.light_energy > 0.001

	_apply_moon(h)


## Stars share the moon's night window and fade at its edges, but over twice
## the span, so they linger into late dusk and early dawn the way real ones do.
func _star_strength(h: float) -> float:
	var night_length: float = 24.0 - (_sunset - _sunrise)
	var night_u: float = fposmod(h - _sunset, 24.0) / night_length
	if night_u < 0.0 or night_u > 1.0:
		return 0.0
	return clampf(
		minf(night_u, 1.0 - night_u) * night_length / (MOON_FADE_HOURS * 2.0), 0.0, 1.0)


func _apply_moon(h: float) -> void:
	var night_length: float = 24.0 - (_sunset - _sunrise)
	var night_u: float = fposmod(h - _sunset, 24.0) / night_length
	if night_u < 0.0 or night_u > 1.0:
		_moon.light_energy = 0.0
		_moon.visible = false
		return
	_moon.rotation_degrees = Vector3(
		-MOON_MAX_ELEVATION_DEG * sin(PI * night_u),
		MOON_YAW_RISE_DEG + night_u * MOON_YAW_SPAN_DEG,
		0.0)
	var fade: float = clampf(
		minf(night_u, 1.0 - night_u) * night_length / MOON_FADE_HOURS, 0.0, 1.0)
	_moon.light_energy = lerpf(MOONLIT_MOON_ENERGY, DARK_MOON_ENERGY, night_darkness) * fade
	_moon.visible = _moon.light_energy > 0.001


## Linear blend between the two keyframes bracketing [param h], wrapping
## midnight (the 19:30 → 04:45 stretch is constant night by construction).
func _blend_keys(h: float) -> LightKey:
	var count: int = _keys.size()
	var next_i: int = 0
	while next_i < count and _keys[next_i].hour < h:
		next_i += 1
	var prev: LightKey = _keys[(next_i - 1 + count) % count]
	var next: LightKey = _keys[next_i % count]
	var span: float = fposmod(next.hour - prev.hour, 24.0)
	var t: float = 0.0 if span == 0.0 else fposmod(h - prev.hour, 24.0) / span
	return LightKey.new(
		h,
		prev.top.lerp(next.top, t),
		prev.horizon.lerp(next.horizon, t),
		prev.sun.lerp(next.sun, t),
		lerpf(prev.energy, next.energy, t))


func _rebuild_keys() -> void:
	var night_top: Color = MOONLIT_TOP.lerp(DARK_TOP, night_darkness)
	var night_horizon: Color = MOONLIT_HORIZON.lerp(DARK_HORIZON, night_darkness)
	_keys = [
		LightKey.new(4.75, night_top, night_horizon, Color("FFB36B"), 0.0),
		LightKey.new(5.75, Color("5A7192"), Color("E8A06A"), Color("FFB36B"), 0.0),
		LightKey.new(6.5, Color("7FA6BC"), Color("FFE3BC"), Color("FFDCA8"), 1.05),
		LightKey.new(12.0, DAY_TOP, DAY_HORIZON, Color("FFF3DC"), 1.3),
		LightKey.new(CAL_HOUR, DAY_TOP, DAY_HORIZON, CAL_SUN_COLOR, CAL_SUN_ENERGY),
		LightKey.new(17.5, Color("86A3BE"), Color("FFDCAB"), Color("FFCE96"), 1.1),
		LightKey.new(18.5, Color("5C6E96"), Color("F0975C"), Color("FF9E63"), 0.0),
		LightKey.new(19.5, night_top, night_horizon, Color("FF9E63"), 0.0),
	]


func _apply_now() -> void:
	if not is_node_ready():
		return
	var hour: float = _applied_hour if _applied_hour >= 0.0 else CAL_HOUR
	_applied_hour = -1.0
	apply_time(hour)
