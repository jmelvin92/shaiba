extends SceneTree
## Camera-pitch comparison shots for Joshua: same dune vantage, several
## pitches, so a "more horizontal" camera can be judged like the Phase 2
## 52/45/40 comparison. Streams a larger chunk radius than the game currently
## uses and roughs in a warm distance haze, because both belong to any flatter
## camera (see DECISIONS.md "no far-field" — its math only holds at 45°).
##
## Run windowed (focus the window right after launch):
##   Godot --path . --script res://tools/shoot_pitch.gd -- <outdir> [pitch ...]

const DEFAULT_PITCHES: Array[float] = [45.0, 38.0, 32.0, 26.0]
## Chunk radius for the comparison — a flatter camera sees a few hundred
## metres, so stream well past the current 5x5.
const LOAD_RADIUS: int = 5
const SEARCH_EXTENT: float = 400.0
const SEARCH_STEP: float = 8.0


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	quit(0)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <outdir> [pitch ...]")
		return
	var outdir: String = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var pitches: Array[float] = DEFAULT_PITCHES
	if args.size() > 1:
		pitches = []
		for i: int in range(1, args.size()):
			pitches.append(float(args[i]))

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	manager.load_radius = LOAD_RADIUS
	manager.unload_radius = LOAD_RADIUS + 1
	_add_haze(level)
	root.add_child(level)
	await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var terrain: TerrainSettings = manager.get_terrain()

	# A hollow with tall dunes ahead (-Z is where the camera looks), so the
	# flatter pitches actually show dune backs and sky.
	var vantage: Vector2 = _find_vantage(terrain)
	player.global_position = Vector3(
		vantage.x, terrain.get_surface_height(vantage) + 0.1, vantage.y
	)
	player.reset_physics_interpolation()
	manager.set_tracked(player)
	rig.snap_to_target()

	# Give the streaming time to fill the enlarged radius, and the window time
	# to be focused.
	for _i: int in range(240):
		await physics_frame
		if manager.get_pending_count() == 0 and _i > 90:
			break

	for pitch: float in pitches:
		rig.pitch_degrees = pitch
		for _i: int in range(30):
			await physics_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		var path: String = outdir.path_join("pitch_%02d.png" % roundi(pitch))
		image.save_png(path)
		print("saved ", path)
	level.free()


## Warm exponential haze so distant dunes melt toward the sky's horizon tone
## instead of ending at the loaded edge. Roughed in for comparison only — the
## kept values become part of desert_environment.tscn once a pitch is chosen.
func _add_haze(level: Node3D) -> void:
	var world_environment: WorldEnvironment = level.find_child(
		"WorldEnvironment", true, false
	) as WorldEnvironment
	var environment: Environment = world_environment.environment
	environment.fog_enabled = true
	environment.fog_light_color = Color("ffefd6")
	environment.fog_density = 0.004
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.5


## The deepest hollow that has notably higher ground 60–220 m ahead of it.
func _find_vantage(terrain: TerrainSettings) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for x: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
		for z: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
			var at: Vector2 = Vector2(x, z)
			var here: float = terrain.get_surface_height(at)
			var ahead_max: float = -INF
			for d: float in range(60, 221, 20):
				ahead_max = maxf(
					ahead_max, terrain.get_surface_height(at + Vector2(0.0, -d))
				)
			var score: float = ahead_max - here
			if score > best_score:
				best_score = score
				best = at
	print("vantage (%.0f, %.0f): %.1f m of dune rises ahead" % [best.x, best.y, best_score])
	return best
