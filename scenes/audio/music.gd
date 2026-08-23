class_name MusicBed
extends Node
## The game's ambient music (Phase 6.6, added at Joshua's direction
## 2026-08-15): quiet instrumental beds under everything, quieter even than
## the wind.
##
## Tracks are data, like every sound: numbered files in assets/audio/music/
## (`ambient_01.ogg`, `ambient_02.ogg`, …). For now the first track simply
## loops — Joshua wants to feel out the vibe with one song. The intended end
## state (his words: "one of many ambient songs that will trigger randomly")
## is a rotation: random track, a silent gap, another track. Build that here
## when a second track lands; nothing else in the game will need to change.
##
## Phase 6.8 Part 3 added the threat score (Joshua's design, 2026-08-23):
## while the worm hunts, the ambient bed PAUSES (it resumes where it left
## off), a wake growl announces the threat once, and the hunt drums loop in
## the ambient's place. LevelRoot wires the worm's hunt_started/hunt_ended
## to [method set_hunt_active] — this node never reaches for the worm. All
## of it is silent-safe per 6.6: missing files mean that piece stays quiet.
##
## The scene runs with PROCESS_MODE_ALWAYS: music keeps playing under the
## pause menu, which also makes the menu's Music slider audible live.

## Loudness of the music. Sits below the wind bed by design — music is the
## deepest layer of the mix. Sliders will later ride the Music bus instead.
@export_range(-60.0, 6.0, 0.5) var music_volume_db: float = -27.0

## Loudness of the hunt drums — deliberately above the ambient bed: the
## threat score is meant to be felt, not buried under the wind.
@export_range(-60.0, 6.0, 0.5) var hunt_volume_db: float = -16.0

## Loudness of the wake growl that announces the hunt.
@export_range(-60.0, 6.0, 0.5) var alert_volume_db: float = -8.0

var _player: AudioStreamPlayer = null
var _hunt_player: AudioStreamPlayer = null
var _alert_player: AudioStreamPlayer = null
var _hunt_active: bool = false


func _ready() -> void:
	var track: AudioStream = SoundBank.stream("music/ambient_01.ogg", true)
	if track != null:
		_player = AudioStreamPlayer.new()
		_player.stream = track
		_player.bus = &"Music"
		_player.volume_db = music_volume_db
		_player.autoplay = true
		add_child(_player)
		_player.play()

	var drums: AudioStream = SoundBank.stream("music/worm_hunt_loop.wav", true)
	if drums != null:
		_hunt_player = AudioStreamPlayer.new()
		_hunt_player.stream = drums
		_hunt_player.bus = &"Music"
		_hunt_player.volume_db = hunt_volume_db
		add_child(_hunt_player)

	# The growl is a creature vocal, not music — it rides the SFX bus so the
	# Sound slider owns it, but it lives here because it is part of the
	# score's one gesture: ambient out, growl, drums in.
	var growl: AudioStream = SoundBank.stream("creatures/worm_wake_01.wav")
	if growl != null:
		_alert_player = AudioStreamPlayer.new()
		_alert_player.stream = growl
		_alert_player.bus = &"SFX"
		_alert_player.volume_db = alert_volume_db
		add_child(_alert_player)


## The threat score, on or off. Idempotent — repeated calls with the same
## state do nothing, so signal wiring never double-fires the growl.
func set_hunt_active(active: bool) -> void:
	if active == _hunt_active:
		return
	_hunt_active = active
	if _player != null:
		_player.stream_paused = active
	if active:
		if _alert_player != null:
			_alert_player.play()
		if _hunt_player != null:
			_hunt_player.play()
	elif _hunt_player != null:
		_hunt_player.stop()


func is_hunt_active() -> bool:
	return _hunt_active
