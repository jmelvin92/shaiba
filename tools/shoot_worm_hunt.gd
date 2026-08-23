extends SceneTree
## The Phase 6.8 Part 3 evidence: the hunt at the real gameplay camera —
## the mound circling its prey, the telegraph boiling the sand at the
## committed point, the strike erupting onto it, and the bite disappearing
## into the fade. Stages a real hunt (director bypassed; the worm's own
## hunt API) against a stationary player on deep sand at golden hour.
##
## Needs a visible window; run *without* --headless:
##
##   Godot --path . --script res://tools/shoot_worm_hunt.gd -- <outdir>

const SETTLE_FRAMES: int = 45

var _outdir: String = ""
var _bitten: bool = false


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
	var manager: ChunkManager = level.find_child(
		"ChunkManager", true, false
	) as ChunkManager
	var worm: SandWorm = level.find_child("SandWorm", true, false) as SandWorm
	var terrain: TerrainSettings = manager.get_terrain()
	var game: Node = root.get_node_or_null(^"/root/Game")
	if game != null:
		game.time_of_day = 16.0
		game.time_paused = true
	worm.swallowed.connect(func(_prey: Node3D) -> void: _bitten = true)

	for _i: int in range(140):
		await physics_frame

	# The deep-sand stage the Part 2 shoot used, east of the homestead.
	var centre: Vector2 = terrain.get_homestead_center()
	var vantage: Vector2 = centre + Vector2(130.0, -21.0)
	player.global_position = Vector3(
		vantage.x, terrain.get_surface_height(vantage) + 0.2, vantage.y
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	rig.snap_to_target()
	rig.set_yaw_degrees(0.0)
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame

	# A close hunt so the whole loop plays out in frame.
	worm.hunt_spawn_distance = 55.0
	if not worm.hunt(vantage):
		push_error("no swimmable spawn for the staged hunt")
		return

	var captured: Dictionary = {
		"stalk": false, "stalk_close": false,
		"telegraph": false, "strike": false, "bite": false
	}
	var stalk_seen_at: int = -1
	var ticks: int = 0
	while not _bitten and ticks < 60 * 180:
		if ticks % 10 == 0 and worm.is_hunting():
			worm.hear(Vector2(
				player.global_position.x, player.global_position.z
			), 1.0)
		await physics_frame
		ticks += 1
		match worm.get_hunt_state():
			SandWorm.HuntState.STALK:
				if not captured["stalk"]:
					captured["stalk"] = true
					stalk_seen_at = ticks
					await _aim_and_capture(rig, player, worm, "stalk")
				elif (
					not captured["stalk_close"]
					and stalk_seen_at > 0 and ticks - stalk_seen_at > 60 * 6
				):
					captured["stalk_close"] = true
					await _aim_and_capture(rig, player, worm, "stalk_close")
			SandWorm.HuntState.STRIKE:
				if not captured["telegraph"] and not worm.is_breaching():
					captured["telegraph"] = true
					# A few churn stamps first, so the boil is visible.
					for _i: int in range(25):
						await physics_frame
					await _aim_and_capture(rig, player, worm, "telegraph")
					# The escape beat, played for real: step aside so the
					# first strike erupts at the vacated point — that miss
					# is the strike photo. The second strike gets the bite.
					var aside: Vector2 = Vector2(
						worm.global_position.x - player.global_position.x,
						worm.global_position.z - player.global_position.z
					).orthogonal().normalized() * 8.0
					var moved: Vector2 = Vector2(
						player.global_position.x + aside.x,
						player.global_position.z + aside.y
					)
					player.global_position = Vector3(
						moved.x,
						terrain.get_surface_height(moved) + 0.2,
						moved.y
					)
					player.reset_physics_interpolation()
				elif (
					not captured["strike"]
					and worm.is_breaching()
					and worm.get_breach_progress() > 0.12
				):
					captured["strike"] = true
					await _aim_and_capture(rig, player, worm, "strike")
			_:
				pass
	if _bitten:
		# The drag and the fade are underway — catch the darkening frame.
		for _i: int in range(30):
			await physics_frame
		await _capture("bite")
	# Let the death sequence finish cleanly before quitting.
	var guard: int = 0
	while not player.is_control_enabled() and guard < 60 * 20:
		await physics_frame
		guard += 1
	for _i: int in range(30):
		await physics_frame


## Turn the camera toward the worm (the rig orbits the player, so the yaw
## that looks along player→worm is atan2(-dx, -dz)), settle, shoot.
func _aim_and_capture(
	rig: CameraRig, player: Player, worm: SandWorm, shot_name: String
) -> void:
	var dx: float = worm.global_position.x - player.global_position.x
	var dz: float = worm.global_position.z - player.global_position.z
	rig.set_yaw_degrees(rad_to_deg(atan2(-dx, -dz)))
	for _i: int in range(6):
		await physics_frame
	await _capture(shot_name)


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("worm_hunt_%s.png" % shot_name)
	image.save_png(path)
	print("saved %s   (%d fps)" % [
		path, roundi(Performance.get_monitor(Performance.TIME_FPS))
	])
