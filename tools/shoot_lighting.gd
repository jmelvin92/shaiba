extends SceneTree
## Night lighting evidence shots (Phase 6.5 piece 3), at the gameplay camera:
##
##   glow_lamp_lit / glow_lamp_dark — the house from the courtyard at 23:00
##     with the oil lamp lit and snuffed: the lit windows + doorway spill.
##   torch_walk — the player alone on open sand carrying the burning torch.
##   torch_stand — the stand by the door with the torch racked, at dusk.
##
## Run windowed:
##   Godot --path . --script res://tools/shoot_lighting.gd -- <outdir>

const SETTLE_FRAMES: int = 30

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

	var clock: Node = root.get_node_or_null(^"/root/Game")
	if clock == null:
		clock = (load("res://autoload/game.gd") as GDScript).new()
		clock.name = "Game"
		root.add_child(clock)
	clock.time_paused = true

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i: int in 10:
		await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var lamp: OilLamp = level.find_child("OilLamp", true, false) as OilLamp
	var stand: TorchStand = level.find_child("TorchStand", true, false) as TorchStand
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	var terrain: TerrainSettings = manager.get_terrain()
	var home: Vector2 = terrain.get_homestead_center()

	# The courtyard, looking at the house front. The door and windows face
	# south (-Z) and the default camera looks north over the roof, so the rig
	# turns 180°: camera south of the player, front face and player in frame.
	clock.set_time_of_day(23.0)
	rig.set_yaw_degrees(180.0)
	await _seat(player, manager, rig, Vector3(home.x - 2.0, 0.0, home.y - 7.5), terrain)
	lamp.lit = true
	await _shoot("glow_lamp_lit")
	lamp.lit = false
	await _shoot("glow_lamp_dark")
	lamp.lit = true

	# The torch carried into the open dark — plus the piece's perf number,
	# measured right here where both shadowed flames are alive.
	stand._on_interacted(player)
	rig.set_yaw_degrees(0.0)
	await _seat(player, manager, rig, Vector3(home.x + 28.0, 0.0, home.y + 20.0), terrain)
	var frames: int = 300
	var worst_ms: float = 0.0
	var start_usec: int = Time.get_ticks_usec()
	var last_usec: int = start_usec
	for _i: int in frames:
		await process_frame
		var now: int = Time.get_ticks_usec()
		worst_ms = maxf(worst_ms, float(now - last_usec) / 1000.0)
		last_usec = now
	var total_s: float = float(last_usec - start_usec) / 1000000.0
	print("perf with lamp+torch burning: %.0f fps average, worst frame %.2f ms" % [
		float(frames) / total_s, worst_ms])
	await _shoot("torch_walk")

	# Side view of the carried torch, minimum zoom, for judging the grip.
	rig.set_yaw_degrees(90.0)
	rig._zoom_goal = 9.0
	rig._zoom_current = 9.0
	rig.snap_to_target()
	await _shoot("torch_grip_side")
	rig._zoom_goal = 23.0
	rig._zoom_current = 23.0

	# The racked torch at dusk, stand and door in one frame.
	stand._on_interacted(player)
	rig.set_yaw_degrees(180.0)
	await _seat(player, manager, rig, Vector3(home.x - 1.5, 0.0, home.y - 6.0), terrain)
	clock.set_time_of_day(18.0)
	await _shoot("torch_stand")

	level.free()


func _seat(
	player: Player, manager: ChunkManager, rig: CameraRig,
	world_pos: Vector3, terrain: TerrainSettings
) -> void:
	var xz: Vector2 = Vector2(world_pos.x, world_pos.z)
	player.global_position = Vector3(
		xz.x, maxf(terrain.get_surface_height(xz), world_pos.y) + 0.1, xz.y)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	manager.set_tracked(player)
	rig.snap_to_target()
	for i: int in range(240):
		await physics_frame
		if manager.get_pending_count() == 0 and i > 20:
			break


func _shoot(shot_name: String) -> void:
	for _i: int in SETTLE_FRAMES:
		await physics_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)
