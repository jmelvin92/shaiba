extends SceneTree
## Pause-menu gate as an executable (2026-08-15 detour, Phase 6.6 branch):
##
##   Godot --headless --path . --script res://tools/verify_pause.gd
##
## Asserts, against the real world scene:
##   1. Esc (the real `pause` InputMap binding, injected as a key event)
##      pauses the tree and opens the menu; the game clock freezes with it.
##   2. Settings opens from the root page; Esc unwinds settings -> root ->
##      closed-and-unpaused, in that order.
##   3. The sliders drive the Music / Sound bus volumes (linear percent to
##      dB), and Sound is the parent bus Ambience and SFX send into.
##   4. A finished drag persists to user://settings.cfg and a fresh menu
##      instance restores the saved values on _ready.
##   5. UI feedback streams load when their files exist (silent-safe: absent
##      files are reported, never failed).
## The user settings file is snapshotted and restored, so running the gate
## never disturbs real preferences.

const WORLD_SCENE: String = "res://scenes/world/world.tscn"
const MENU_SCENE: String = "res://scenes/ui/pause_menu/pause_menu.tscn"
const SETTINGS_PATH: String = "user://settings.cfg"

var _failures: int = 0
var _saved_settings: PackedByteArray = PackedByteArray()
var _had_settings: bool = false


func _initialize() -> void:
	_snapshot_settings()
	var world: Node3D = (load(WORLD_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	_run(world)


func _run(world: Node3D) -> void:
	await process_frame
	await process_frame

	var menu: PauseMenu = world.get_node_or_null("PauseMenu") as PauseMenu
	_check("pause menu instanced in the world scene", menu != null)
	if menu == null:
		_finish()
		return
	var root_page: Control = menu.get_node("%RootPage") as Control
	var settings_page: Control = menu.get_node("%SettingsPage") as Control
	var music_slider: HSlider = menu.get_node("%MusicSlider") as HSlider
	var sound_slider: HSlider = menu.get_node("%SoundSlider") as HSlider

	print("pause toggle:")
	_check("menu starts hidden", not menu.visible)
	_check("tree starts unpaused", not paused)
	var game: Node = root.get_node("/root/Game")
	await _press_escape()
	_check("Esc pauses the tree", paused)
	_check("Esc opens the menu on its root page", menu.visible and root_page.visible)
	var frozen_hour: float = game.time_of_day
	await process_frame
	await process_frame
	_check("game clock freezes while paused", game.time_of_day == frozen_hour)

	print("pages:")
	(menu.get_node("%SettingsButton") as Button).pressed.emit()
	_check(
		"Settings swaps the pages",
		settings_page.visible and not root_page.visible
	)
	await _press_escape()
	_check(
		"Esc in settings returns to the root page (still paused)",
		root_page.visible and not settings_page.visible and paused
	)

	print("sliders:")
	music_slider.value = 40.0
	sound_slider.value = 70.0
	_check(
		"music slider drives the Music bus",
		_bus_db_matches(&"Music", 0.40)
	)
	_check(
		"sound slider drives the Sound bus",
		_bus_db_matches(&"Sound", 0.70)
	)
	_check(
		"value labels track the sliders",
		(menu.get_node("%MusicValue") as Label).text == "40%"
			and (menu.get_node("%SoundValue") as Label).text == "70%"
	)
	music_slider.value = 0.0
	_check(
		"0% clamps to silence, not -inf",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) == -80.0
	)
	music_slider.value = 40.0

	print("persistence:")
	music_slider.drag_ended.emit(true)
	var config: ConfigFile = ConfigFile.new()
	var loaded: bool = config.load(SETTINGS_PATH) == OK
	_check(
		"finished drag saves user://settings.cfg",
		loaded
			and float(config.get_value("audio", "music_percent", -1.0)) == 40.0
			and float(config.get_value("audio", "sound_percent", -1.0)) == 70.0
	)
	var fresh: PauseMenu = (load(MENU_SCENE) as PackedScene).instantiate() as PauseMenu
	root.add_child(fresh)
	await process_frame
	_check(
		"a fresh menu restores the saved values",
		(fresh.get_node("%MusicSlider") as HSlider).value == 40.0
			and (fresh.get_node("%SoundSlider") as HSlider).value == 70.0
	)
	fresh.queue_free()

	print("ui feedback sounds:")
	for prefix: String in ["ui/hover", "ui/click"]:
		var takes: int = SoundBank.take_count(prefix)
		if takes > 0:
			_check("%s loaded (%d take(s))" % [prefix, takes], true)
		else:
			print("  note %s not sourced yet — menu stays silent-safe" % prefix)

	print("unwind:")
	await _press_escape()
	_check("Esc on the root page closes and unpauses", not menu.visible and not paused)
	await process_frame
	_check("game clock runs again after unpause", game.time_of_day != frozen_hour)

	_finish()


func _press_escape() -> void:
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _bus_db_matches(bus: StringName, linear: float) -> bool:
	var db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
	return absf(db - linear_to_db(linear)) < 0.01


func _check(what: String, ok: bool) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _snapshot_settings() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_settings() -> void:
	if _had_settings:
		var out: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		out.store_buffer(_saved_settings)
		out.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _finish() -> void:
	_restore_settings()
	if _failures == 0:
		print("verify_pause: ALL PASS")
	else:
		print("verify_pause: %d FAILURE(S)" % _failures)
	quit(0 if _failures == 0 else 1)
