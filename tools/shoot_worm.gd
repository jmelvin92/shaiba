extends SceneTree
## The Phase 6.8 Part 2 evidence: the titan breaching at the real gameplay
## camera. Stages the worm on deep sand at golden hour, waits for its orbit
## to carry it in front of the camera, triggers a breach and captures the
## rise, the apex (mouth open), the dive and the aftermath.
##
## Needs a visible window; run *without* --headless:
##
##   Godot --path . --script res://tools/shoot_worm.gd -- <outdir>

const SETTLE_FRAMES: int = 45

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

	var level: Node3D = (
		load("res://scenes/world/world.tscn") as PackedScene
	).instantiate() as Node3D
	root.add_child(level)
	await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	var worm: SandWorm = level.find_child("SandWorm", true, false) as SandWorm
	var terrain: TerrainSettings = manager.get_terrain()
	var game: Node = root.get_node_or_null(^"/root/Game")
	if game != null:
		game.time_of_day = 16.0
		game.time_paused = true

	for _i: int in range(140):
		await physics_frame

	# Same deep-sand stage the size ladder used.
	var centre: Vector2 = terrain.get_homestead_center()
	var vantage: Vector2 = centre + Vector2(130.0, -21.0)
	player.global_position = Vector3(
		vantage.x, terrain.get_surface_height(vantage) + 0.2, vantage.y
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	rig.snap_to_target()
	rig.set_yaw_degrees(0.0)  # facing north
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame

	# Deterministic staging: start the worm west of the view, 16 m north of
	# the player, heading east — the breach arc (36 m at a surge) crosses the
	# frame left to right with the apex near centre.
	worm.summon_at(vantage + Vector2(-22.0, -16.0), 0.0, SandWorm.Mode.WANDER)
	for _i: int in range(20):
		await physics_frame
	worm.breach()

	var captured: Dictionary = {"rise": false, "apex": false, "dive": false}
	var guard: int = 0
	while worm.is_breaching() and guard < 60 * 20:
		guard += 1
		await physics_frame
		var progress: float = worm.get_breach_progress()
		if progress > 0.22 and not captured["rise"]:
			captured["rise"] = true
			await _capture("breach_rise")
		elif progress > 0.5 and not captured["apex"]:
			captured["apex"] = true
			await _capture("breach_apex")
		elif progress > 0.78 and not captured["dive"]:
			captured["dive"] = true
			await _capture("breach_dive")
	for _i: int in range(100):
		await physics_frame
	await _capture("breach_after")
	worm.dismiss()


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("worm_%s.png" % shot_name)
	image.save_png(path)
	print("saved %s   (%d fps)" % [
		path, roundi(Performance.get_monitor(Performance.TIME_FPS))
	])
