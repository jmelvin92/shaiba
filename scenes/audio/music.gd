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
## The scene runs with PROCESS_MODE_ALWAYS: music keeps playing under the
## pause menu, which also makes the menu's Music slider audible live.

## Loudness of the music. Sits below the wind bed by design — music is the
## deepest layer of the mix. Sliders will later ride the Music bus instead.
@export_range(-60.0, 6.0, 0.5) var music_volume_db: float = -27.0

var _player: AudioStreamPlayer = null


func _ready() -> void:
	var track: AudioStream = SoundBank.stream("music/ambient_01.ogg", true)
	if track == null:
		return
	_player = AudioStreamPlayer.new()
	_player.stream = track
	_player.bus = &"Music"
	_player.volume_db = music_volume_db
	_player.autoplay = true
	add_child(_player)
	_player.play()
