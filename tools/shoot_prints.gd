extends SceneTree
## Footprint prototype validation: walks the player in a straight line that
## crosses a sand-depth gradient (deep drift → thin skin → near-bare ground),
## then screenshots the trail — once from the walk's end and once teleported
## back to its middle, which also proves prints survive a region recentre.
## Needs a visible window (macOS stops drawing occluded windows); run without
## --headless and keep re-focusing the window:
##
##   Godot --path . --script res://tools/shoot_prints.gd -- <outdir>

const WALK_DISTANCE: float = 42.0
const SEARCH_EXTENT: float = 400.0
const SEARCH_STEP: float = 8.0

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
	var terrain: TerrainSettings = manager.get_terrain()

	# Let the window come forward before anything visual matters.
	for _i: int in range(60):
		await physics_frame

	# Measure which world direction "move_up" walks at the current camera yaw,
	# instead of assuming it.
	var before: Vector3 = player.global_position
	Input.action_press("move_up")
	for _i: int in range(45):
		await physics_frame
	Input.action_release("move_up")
	var walked: Vector3 = player.global_position - before
	var direction: Vector2 = Vector2(walked.x, walked.z).normalized()
	print("move_up walks along ", direction)

	# Find a start whose walk line crosses deep sand early and thin sand late.
	var start: Vector2 = _find_gradient_start(terrain, direction)
	_teleport(player, rig, terrain, start)
	for _i: int in range(30):
		await physics_frame

	# Walk the line. Time is compressed; stamping is distance-clocked, so the
	# trail is unaffected, and the extra decay over ~15 s is negligible.
	Engine.time_scale = 3.0
	var from: Vector3 = player.global_position
	Input.action_press("move_up")
	var guard: int = 0
	while player.global_position.distance_to(from) < WALK_DISTANCE and guard < 5000:
		guard += 1
		await physics_frame
	Input.action_release("move_up")
	Engine.time_scale = 1.0
	for _i: int in range(40):
		await physics_frame

	await _capture("prints_trail_end")

	# Back to the middle of the trail: the region recentres around the
	# teleport, and every print must still be exactly where it was stamped.
	var mid: Vector2 = start + direction * (WALK_DISTANCE * 0.5)
	_teleport(player, rig, terrain, mid)
	for _i: int in range(40):
		await physics_frame
	await _capture("prints_trail_middle")

	print("depth at start %.2f, middle %.2f, end %.2f" % [
		terrain.get_sand_depth(start),
		terrain.get_sand_depth(mid),
		terrain.get_sand_depth(start + direction * WALK_DISTANCE),
	])


func _teleport(
	player: Player, rig: CameraRig, terrain: TerrainSettings, at: Vector2
) -> void:
	player.global_position = Vector3(
		at.x, terrain.get_surface_height(at) + 0.1, at.y
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	rig.snap_to_target()


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)


## Scores candidate starts by how deep the first stretch of the walk is and
## how bare the last stretch is — the gate's deep → faint → gone read.
func _find_gradient_start(terrain: TerrainSettings, direction: Vector2) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var x: float = -SEARCH_EXTENT
	while x < SEARCH_EXTENT:
		var z: float = -SEARCH_EXTENT
		while z < SEARCH_EXTENT:
			var at: Vector2 = Vector2(x, z)
			var early: float = 0.0
			var late: float = INF
			for step: int in range(0, int(WALK_DISTANCE) + 1, 3):
				var depth: float = terrain.get_sand_depth(at + direction * float(step))
				if step <= 15:
					early = maxf(early, depth)
				if step >= int(WALK_DISTANCE) - 15:
					late = minf(late, depth)
			var score: float = minf(early, 2.5) - late * 3.0
			if score > best_score:
				best_score = score
				best = at
			z += SEARCH_STEP
		x += SEARCH_STEP
	print(
		"gradient start %s (early depth %.2f, late depth %.2f)" % [
			best,
			terrain.get_sand_depth(best),
			terrain.get_sand_depth(best + direction * WALK_DISTANCE),
		]
	)
	return best
