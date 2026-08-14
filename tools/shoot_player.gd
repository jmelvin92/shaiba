extends SceneTree
## Captures the character in each pose at the real gameplay camera angle.
##
##   Godot --path . --script res://tools/shoot_player.gd -- <output-directory>
##
## Must run with a window (not --headless), and macOS stops drawing an occluded
## window, so keep the game frontmost while this runs — see CLAUDE.md.

const LEVEL: String = "res://scenes/world/world.tscn"
const START: Vector3 = Vector3(0.0, 0.5, 12.0)
const SETTLE: int = 100

var _out: String = "user://"
var _player: Player


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]

	var level: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await physics_frame
	_player = level.find_child("Player", true, false) as Player

	# Let the camera rig glide into place before the first shot.
	await _pose("idle", [], 60)

	await _pose("idle", [], SETTLE)
	await _pose("walk", ["move_up"], SETTLE)
	await _pose("run", ["move_up", "sprint"], SETTLE)
	await _pose("crouch", ["crouch"], SETTLE)
	await _pose("jump", ["move_up", "jump"], 14)

	print("shots written to %s" % _out)
	quit()


func _pose(name: String, actions: Array, ticks: int) -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(action)
	if name == "idle":
		_player.velocity = Vector3.ZERO
		_player.global_position = START
		_player.reset_physics_interpolation()
	for action: String in actions:
		Input.action_press(action)

	for i: int in range(ticks):
		await physics_frame

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/player_%s.png" % [_out, name])
	print("captured %s" % name)
