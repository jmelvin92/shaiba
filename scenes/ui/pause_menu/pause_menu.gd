class_name PauseMenu
extends CanvasLayer
## The Esc pause menu (Phase 6.6 detour, 2026-08-15).
##
## Owns the two user-facing volume controls: the sliders write the `Music`
## and `Sound` bus volumes and persist them to user://settings.cfg, which is
## applied back every launch from _ready. `Sound` is the parent bus Ambience
## and SFX both send into — the AcousticZone's indoor ducking writes the
## *Ambience* bus, so the slider and the zone never fight over one value.
##
## The node runs with PROCESS_MODE_ALWAYS: it is the one thing that keeps
## working while the tree is paused. Music also keeps playing under the menu
## (its own scene opts in), so the Music slider is audible live; everything
## else falls silent with the pause, which is the point of pausing.

## The menu never saves or loads itself — it announces, and the level (which
## owns the SaveSystem) answers back through report_save / report_load /
## set_can_load. Keeps the UI ignorant of save-file mechanics.
signal save_requested
signal load_requested

const SETTINGS_PATH: String = "user://settings.cfg"
const MUSIC_BUS: StringName = &"Music"
const SOUND_BUS: StringName = &"Sound"

## UI feedback levels — quiet by default, like everything else in the mix.
@export_range(-30.0, 0.0, 0.5) var hover_volume_db: float = -16.0
@export_range(-30.0, 0.0, 0.5) var click_volume_db: float = -10.0

@onready var _root_page: VBoxContainer = %RootPage
@onready var _settings_page: VBoxContainer = %SettingsPage
@onready var _resume_button: Button = %ResumeButton
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _settings_button: Button = %SettingsButton
@onready var _back_button: Button = %BackButton
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sound_slider: HSlider = %SoundSlider
@onready var _music_value: Label = %MusicValue
@onready var _sound_value: Label = %SoundValue
@onready var _hover_sound: AudioStreamPlayer = %HoverSound
@onready var _click_sound: AudioStreamPlayer = %ClickSound


func _ready() -> void:
	visible = false
	_hover_sound.stream = SoundBank.take_set("ui/hover", 1.02, 0.0)
	_click_sound.stream = SoundBank.take_set("ui/click", 1.02, 0.0)
	_hover_sound.volume_db = hover_volume_db
	_click_sound.volume_db = click_volume_db

	_resume_button.pressed.connect(_on_resume_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	for button: Button in [
		_resume_button, _save_button, _load_button, _settings_button, _back_button
	]:
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.focus_entered.connect(_on_button_hover.bind(button))
		button.pressed.connect(_play_click)
	for slider: HSlider in [_music_slider, _sound_slider]:
		slider.mouse_entered.connect(_play_hover)
		slider.focus_entered.connect(_play_hover)
		slider.drag_started.connect(_play_click)
		slider.drag_ended.connect(_on_slider_drag_ended)
	_music_slider.value_changed.connect(_on_music_changed)
	_sound_slider.value_changed.connect(_on_sound_changed)

	_load_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		_open()
	elif _settings_page.visible:
		_show_root_page()
	else:
		_close()


func _open() -> void:
	get_tree().paused = true
	visible = true
	_show_root_page()


func _close() -> void:
	_save_settings()
	visible = false
	get_tree().paused = false


func _show_root_page() -> void:
	_settings_page.visible = false
	_root_page.visible = true
	_resume_button.grab_focus()


func _on_resume_pressed() -> void:
	_close()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_load_pressed() -> void:
	load_requested.emit()


## Called by the level: whether a save file exists for Load to act on.
func set_can_load(can_load: bool) -> void:
	_load_button.disabled = not can_load


## Called by the level after a requested save; flashes the outcome in place.
func report_save(ok: bool) -> void:
	_flash_button(_save_button, "Saved" if ok else "Save failed", "Save Game")


## Called by the level after a requested load. Success resumes play — the
## loaded world is the point, not the menu.
func report_load(ok: bool) -> void:
	if ok:
		_close()
	else:
		_flash_button(_load_button, "No save found", "Load Game")


func _flash_button(button: Button, flash_text: String, rest_text: String) -> void:
	button.text = flash_text
	# create_timer defaults to process_always, so it ticks under the pause.
	await get_tree().create_timer(1.1).timeout
	button.text = rest_text


func _on_settings_pressed() -> void:
	_root_page.visible = false
	_settings_page.visible = true
	_music_slider.grab_focus()


func _on_back_pressed() -> void:
	_save_settings()
	_show_root_page()


func _on_music_changed(value: float) -> void:
	_music_value.text = "%d%%" % int(value)
	_apply_bus_volume(MUSIC_BUS, value)


func _on_sound_changed(value: float) -> void:
	_sound_value.text = "%d%%" % int(value)
	_apply_bus_volume(SOUND_BUS, value)


func _on_slider_drag_ended(changed: bool) -> void:
	if changed:
		_save_settings()


func _apply_bus_volume(bus: StringName, percent: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	# 100% = the bus's authored 0 dB; 0% clamps to -80 dB (silence) because
	# linear_to_db(0) is -inf.
	AudioServer.set_bus_volume_db(
		index, maxf(linear_to_db(percent / 100.0), -80.0)
	)


func _on_button_hover(button: Button) -> void:
	if not button.disabled:
		_play_hover()


func _play_hover() -> void:
	_hover_sound.play()


func _play_click() -> void:
	_click_sound.play()


func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)  # A missing file just keeps the defaults.
	_music_slider.value = clampf(
		float(config.get_value("audio", "music_percent", 100.0)), 0.0, 100.0
	)
	_sound_slider.value = clampf(
		float(config.get_value("audio", "sound_percent", 100.0)), 0.0, 100.0
	)
	# Setting .value emitted value_changed, so labels and buses are current.


func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "music_percent", _music_slider.value)
	config.set_value("audio", "sound_percent", _sound_slider.value)
	config.save(SETTINGS_PATH)
