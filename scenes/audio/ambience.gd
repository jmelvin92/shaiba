class_name Ambience
extends Node3D
## The desert's sound bed (Phase 6.6): day and night wind loops crossfaded by
## the game clock, plus occasional wind gusts that sweep past spatially.
##
## Scene-owned by the level, the same shape as DesertEnvironment's lighting:
## it samples `Game.time_of_day` every frame and drives volumes from it —
## dawn and dusk are blends of the two beds, not separate recordings, so the
## crossfade can never disagree with the sky. Standalone (no Game autoload,
## e.g. an F6 run) it holds the 16:00 golden-hour state, like everything else.
##
## Both streams come from [SoundBank] and may be null until sourced; a null
## bed is skipped but the weights still compute, which is what
## tools/verify_audio.gd asserts on.

const GameClock := preload("res://autoload/game.gd")

@export_group("Beds")
## Kills both wind beds outright (Joshua, 2026-08-15 — "mute the wind
## completely"). The loop files and the crossfade logic stay ready; the
## future weather system flips this one export back off.
@export var beds_muted: bool = true
## Full-day loudness of the daytime wind bed, when not muted.
@export_range(-40.0, 6.0, 0.5) var day_volume_db: float = -16.0
## Full-night loudness of the night bed.
@export_range(-40.0, 6.0, 0.5) var night_volume_db: float = -14.0

@export_group("Gusts")
## Loudness of a gust one-shot at its source.
@export_range(-40.0, 6.0, 0.5) var gust_volume_db: float = -4.0
## Shortest and longest quiet stretch between gusts, seconds.
@export_range(2.0, 60.0, 0.5) var gust_interval_min: float = 9.0
@export_range(2.0, 120.0, 0.5) var gust_interval_max: float = 26.0
## How far from the focus a gust spawns, metres.
@export_range(4.0, 40.0, 0.5) var gust_distance: float = 14.0

var _game: Node = null
var _day: AudioStreamPlayer = null
var _night: AudioStreamPlayer = null
var _gust: AudioStreamPlayer3D = null
## Whose surroundings the gusts happen in — the player, handed down by the
## level. Falls back to this node's own position standalone.
var _focus: Node3D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_gust_in: float = 0.0


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	_rng.randomize()
	_day = _make_bed(SoundBank.stream("ambience/wind_day_loop.ogg", true))
	_night = _make_bed(SoundBank.stream("ambience/wind_night_loop.ogg", true))
	_gust = AudioStreamPlayer3D.new()
	_gust.bus = &"Ambience"
	_gust.max_distance = 60.0
	_gust.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_gust)
	_next_gust_in = _rng.randf_range(gust_interval_min, gust_interval_max)


## Called by the level that owns both this node and the player.
func set_focus(focus: Node3D) -> void:
	_focus = focus


func _process(delta: float) -> void:
	var hour: float = 16.0
	if _game != null:
		hour = _game.time_of_day
	var day: float = day_weight(hour)
	_apply_bed(_day, 0.0 if beds_muted else day, day_volume_db)
	_apply_bed(_night, 0.0 if beds_muted else 1.0 - day, night_volume_db)

	_next_gust_in -= delta
	if _next_gust_in <= 0.0:
		_next_gust_in = _rng.randf_range(gust_interval_min, gust_interval_max)
		_play_gust()


## How much of the *day* bed a given hour carries, 0–1; the night bed gets the
## complement. Ramps span dawn and dusk exactly as the clock defines them, so
## sound and sky always turn together. Public and pure for the verify harness.
func day_weight(hour: float) -> float:
	var h: float = fposmod(hour, 24.0)
	if h < GameClock.DAWN_START_HOUR or h >= GameClock.NIGHT_START_HOUR:
		return 0.0
	if h < GameClock.DAY_START_HOUR:
		return (
			(h - GameClock.DAWN_START_HOUR)
			/ (GameClock.DAY_START_HOUR - GameClock.DAWN_START_HOUR)
		)
	if h < GameClock.DUSK_START_HOUR:
		return 1.0
	return (
		(GameClock.NIGHT_START_HOUR - h)
		/ (GameClock.NIGHT_START_HOUR - GameClock.DUSK_START_HOUR)
	)


func _make_bed(stream: AudioStream) -> AudioStreamPlayer:
	if stream == null:
		return null
	var bed: AudioStreamPlayer = AudioStreamPlayer.new()
	bed.stream = stream
	bed.bus = &"Ambience"
	add_child(bed)
	return bed


func _apply_bed(bed: AudioStreamPlayer, weight: float, base_db: float) -> void:
	if bed == null:
		return
	if weight <= 0.001:
		if bed.playing:
			bed.stop()
		return
	if not bed.playing:
		bed.play()
	bed.volume_db = base_db + linear_to_db(weight)


func _play_gust() -> void:
	var takes: AudioStreamRandomizer = SoundBank.take_set("ambience/gust")
	if takes == null or _gust.playing:
		return
	var around: Vector3 = _focus.global_position if _focus != null else global_position
	var angle: float = _rng.randf_range(0.0, TAU)
	_gust.global_position = around + Vector3(
		cos(angle) * gust_distance, 2.0, sin(angle) * gust_distance
	)
	if _gust.stream != takes:
		_gust.stream = takes
	_gust.volume_db = gust_volume_db
	_gust.play()
