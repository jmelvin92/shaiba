extends SceneTree
## Screenshots the desert at terrain spots chosen from the noise field itself:
## the spawn, the deepest sand, exposed hard ground, and the steepest slope in
## a 1.2 km square. Needs a visible window (macOS stops drawing occluded
## windows — see CLAUDE.md), so run it *without* --headless and focus the
## window right after launch:
##
##   Godot --path . --script res://tools/shoot_terrain.gd -- <outdir> [zoom]

const SEARCH_EXTENT: float = 600.0
const SEARCH_STEP: float = 10.0

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
		push_error("usage: -- <outdir> [zoom]")
		return
	_outdir = args[0]
	DirAccess.make_dir_recursive_absolute(_outdir)

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	if args.size() > 1:
		var rig_node: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
		rig_node.zoom_distance = float(args[1])
	root.add_child(level)
	await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	var terrain: TerrainSettings = manager.get_terrain()

	# A moment for the window to be focused before the first capture.
	for _i: int in range(90):
		await physics_frame

	var spots: Dictionary = _find_spots(terrain)
	for spot_name: String in spots:
		var at: Vector2 = spots[spot_name]
		player.global_position = Vector3(
			at.x, terrain.get_surface_height(at) + 0.1, at.y
		)
		player.reset_physics_interpolation()
		rig.snap_to_target()
		for _i: int in range(45):
			await physics_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		var path: String = _outdir.path_join("terrain_%s.png" % spot_name)
		image.save_png(path)
		print("saved ", path)


## Scans the field for the most characteristic spots of each kind.
func _find_spots(terrain: TerrainSettings) -> Dictionary:
	var deepest: Vector2 = Vector2.ZERO
	var deepest_depth: float = -1.0
	var barest: Vector2 = Vector2.ZERO
	var barest_depth: float = INF
	var steepest: Vector2 = Vector2.ZERO
	var steepest_slope: float = -1.0
	var at: Vector2 = Vector2.ZERO
	for x: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
		for z: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
			at = Vector2(x, z)
			var depth: float = terrain.get_sand_depth(at)
			if depth > deepest_depth:
				deepest_depth = depth
				deepest = at
			if depth < barest_depth:
				barest_depth = depth
				barest = at
			var dx: float = terrain.get_surface_height(at + Vector2(0.5, 0.0)) \
				- terrain.get_surface_height(at - Vector2(0.5, 0.0))
			var dz: float = terrain.get_surface_height(at + Vector2(0.0, 0.5)) \
				- terrain.get_surface_height(at - Vector2(0.0, 0.5))
			var slope: float = dx * dx + dz * dz
			if slope > steepest_slope:
				steepest_slope = slope
				steepest = at
	print(
		"spots: deepest %.1f m at %s, barest %.2f m at %s, steepest at %s"
		% [deepest_depth, deepest, barest_depth, barest, steepest]
	)
	return {
		"spawn": Vector2.ZERO,
		"deep_dune": deepest,
		"hard_ground": barest,
		"steep_slope": steepest,
	}
