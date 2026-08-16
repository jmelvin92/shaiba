extends SceneTree
## Screenshot evidence for the pause menu (windowed):
##
##   Godot --path . --script res://tools/shoot_pause.gd
##
## Opens the world, presses Esc (real injected key event), captures the root
## page, opens Settings, captures the audio page. Writes docs/references/
## ingame_pause_root.png and ingame_pause_settings.png. Needs the window
## frontmost — run the usual osascript focus dance alongside (CLAUDE.md).

const OUT_DIR: String = "res://docs/references/"

var _menu: PauseMenu = null


func _initialize() -> void:
	var world: Node3D = (
		load("res://scenes/world/world.tscn") as PackedScene
	).instantiate() as Node3D
	root.add_child(world)
	_run(world)


func _run(world: Node3D) -> void:
	for i: int in 30:
		await process_frame
	_menu = world.get_node("PauseMenu") as PauseMenu

	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	for i: int in 10:
		await process_frame
	await _shoot("ingame_pause_root.png")

	(_menu.get_node("%SettingsButton") as Button).pressed.emit()
	for i: int in 10:
		await process_frame
	await _shoot("ingame_pause_settings.png")

	quit(0)


func _shoot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT_DIR + file_name)
	image.save_png(path)
	print("saved %s" % path)
