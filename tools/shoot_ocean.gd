extends SceneTree
## Screenshots the ocean at the real gameplay camera (Phase 6.7).
##
## Every frame is shot through the game's own rig — 19 deg pitch, 35 deg lens,
## gameplay zoom — with the player standing in it (shoot_house pattern). Needs
## a visible window; run *without* --headless:
##
##   Godot --path . --script res://tools/shoot_ocean.gd -- <outdir>
##
## Shots: the sea from the homestead courtyard, the beach approach, the
## waterline up close, the player wading at the knee limit, the coastline
## looking along the shore — then the same beach vantage swept through noon,
## golden hour, dusk and night for the glint and the fog contract.

const SETTLE_FRAMES: int = 45

var _outdir: String = ""
var _game: Node = null


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
	var terrain: TerrainSettings = manager.get_terrain()
	_game = root.get_node_or_null(^"/root/Game")
	_set_hour(16.0)

	for _i: int in range(140):
		await physics_frame

	var centre: Vector2 = terrain.get_homestead_center()
	var z: float = centre.y
	var shore_x: float = _shore_x(terrain, z)
	print("homestead %s, waterline x %.1f (%.1f m west)" % [centre, shore_x, centre.x - shore_x])

	# The sea as part of daily life: from the courtyard, looking west.
	await _stand_shot(player, rig, terrain, Vector2(centre.x - 6.0, z), Vector2(-1, 0), "courtyard_west")
	# The beach approach.
	await _stand_shot(player, rig, terrain, Vector2(shore_x + 14.0, z), Vector2(-1, 0), "beach")
	# The waterline up close: foam, swash, wet sand.
	await _stand_shot(player, rig, terrain, Vector2(shore_x + 2.0, z), Vector2(-1, 0), "waterline")
	# Along the shore: the coastline's bays and headlands.
	await _stand_shot(player, rig, terrain, Vector2(shore_x + 3.0, z), Vector2(0, -1), "along_shore")

	# Wading: walk west into the sea on real input until the knee limit holds.
	await _stand_at(player, rig, terrain, Vector2(shore_x + 6.0, z))
	_aim_dir(rig, Vector2(-1, 0))
	player.set_view_yaw(PI / 2.0)
	Input.action_press("move_up")
	for _i: int in range(60 * 10):
		await physics_frame
	Input.action_release("move_up")
	for _i: int in range(30):
		await physics_frame
	print("wading depth at capture: %.2f m" % player.get_water_depth())
	await _capture("wading")

	# Day sweep from the beach vantage: glint, dusk color, and the night sea.
	for entry: Array in [[12.0, "noon"], [16.0, "golden"], [18.2, "dusk"], [22.0, "night"]]:
		_set_hour(entry[0] as float)
		await _stand_shot(
			player, rig, terrain, Vector2(shore_x + 10.0, z), Vector2(-1, 0),
			"sweep_%s" % (entry[1] as String)
		)
	_set_hour(16.0)


func _shore_x(terrain: TerrainSettings, z: float) -> float:
	var lo: float = terrain.get_homestead_center().x - terrain.coast_distance - 40.0
	var hi: float = terrain.get_homestead_center().x - terrain.coast_distance + 40.0
	for _i: int in range(48):
		var mid: float = (lo + hi) * 0.5
		if terrain.get_surface_height(Vector2(mid, z)) >= terrain.get_sea_level():
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


func _set_hour(hour: float) -> void:
	if _game == null:
		return
	_game.time_of_day = hour
	_game.time_paused = true


func _aim_dir(rig: CameraRig, direction: Vector2) -> void:
	rig.set_yaw_degrees(rad_to_deg(atan2(-direction.x, -direction.y)))


func _stand_shot(
	player: Player, rig: CameraRig, terrain: TerrainSettings,
	at: Vector2, look: Vector2, shot_name: String
) -> void:
	await _stand_at(player, rig, terrain, at)
	_aim_dir(rig, look)
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame
	await _capture(shot_name)


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


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)
