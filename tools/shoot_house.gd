extends SceneTree
## Screenshots the homestead at the real gameplay camera.
##
## Every frame here is shot through the game's own rig — its 19 deg pitch, 35
## deg lens and zoom distance — with the player standing in it, so what comes
## out is what Joshua would see standing there rather than a flattering
## art-department angle. Needs a visible window (macOS stops drawing occluded
## ones — see CLAUDE.md), so run it *without* --headless:
##
##   Godot --path . --script res://tools/shoot_house.gd -- <outdir>
##
## The camera yaw is aimed per shot so the house is always beyond the player,
## and the interior shots walk in through the doorway on real movement input —
## which is also the proof that the doorway is wide enough to walk through.

const SETTLE_FRAMES: int = 40

var _outdir: String = ""


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	quit(0)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <outdir>")
		return
	_outdir = args[0]
	DirAccess.make_dir_recursive_absolute(_outdir)

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	var house: House = level.find_child("House", true, false) as House
	var cutaway: InteriorCutaway = house.get_node(^"Cutaway") as InteriorCutaway
	var terrain: TerrainSettings = manager.get_terrain()

	# Long settle: the window has to reach the foreground before the first
	# capture, and the chunks under the homestead have to finish building.
	for _i: int in range(120):
		await physics_frame

	var house_at: Vector3 = house.global_position
	var front: Vector3 = -house.global_transform.basis.z   # the door's normal
	var side: Vector3 = house.global_transform.basis.x     # toward the stair
	print("homestead centre %s, house %s, player %s" % [
		terrain.get_homestead_center(), house_at, player.global_position
	])

	var spots: Dictionary = {
		"approach": front * 16.0,
		"door": front * 8.5 - side * 1.2,
		"stair": side * 12.0 + front * 6.0,
		"back": front * -14.0 + side * 4.0,
	}
	for shot: String in spots:
		var at: Vector3 = house_at + (spots[shot] as Vector3)
		_aim(rig, at, house_at)
		await _stand_at(player, rig, terrain, Vector2(at.x, at.z))
		await _capture("house_%s" % shot)

	# Walk in through the front door. The rig is aimed straight down the door's
	# own axis rather than at the middle of the house: movement is
	# camera-relative, so aiming at the centre would walk the player diagonally
	# off the doorway and into the wall beside it.
	var outside: Vector3 = house_at + front * 9.0 - side * 1.2
	_aim(rig, outside, outside - front * 10.0)
	await _stand_at(player, rig, terrain, Vector2(outside.x, outside.z))
	await _hold_action("move_up", 260)
	var inside_local: Vector3 = house.to_local(player.global_position)
	print("inside: open=%s cut=%.2f local=%.2v" % [
		cutaway.is_open(), cutaway.get_cut_height(), inside_local
	])
	await _capture("house_inside_ground")

	# Then back out, which is the check that the building closes up again.
	await _hold_action("move_down", 240)
	print("outside again: open=%s" % cutaway.is_open())
	await _capture("house_left_again")


## Points the rig so that [param target] lies beyond the player from the
## camera. The rig's forward at yaw a is (-sin a, 0, -cos a), so the yaw that
## looks from [param from] toward [param target] falls straight out of atan2.
func _aim(rig: CameraRig, from: Vector3, target: Vector3) -> void:
	var to_target: Vector3 = target - from
	rig.set_yaw_degrees(rad_to_deg(atan2(-to_target.x, -to_target.z)))


func _stand_at(
	player: Player, rig: CameraRig, terrain: TerrainSettings, at: Vector2
) -> void:
	player.global_position = Vector3(
		at.x, terrain.get_surface_height(at) + 0.2, at.y
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	rig.snap_to_target()
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame


## Holds a real input action, so the animator, the footstep stamper and the
## cutaway's volumes all see ordinary walking rather than a teleport.
func _hold_action(action: String, ticks: int) -> void:
	Input.action_press(action)
	for _i: int in range(ticks):
		await physics_frame
	Input.action_release(action)
	for _i: int in range(24):
		await physics_frame


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)
