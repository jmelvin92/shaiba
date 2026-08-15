extends SceneTree
## Haze-tuning ladder for Joshua (Phase 6.5 piece 3): same dune vantage at the
## 16:00 golden hour, one shot per fog treatment, from today's exponential
## haze down to none at all.
##
## Two families of rung:
## - exponential (the current kind): fog everywhere, thickening with distance.
##   Density rungs show how much of the frame-wide wash is the density alone.
## - depth ("distance-only"): zero fog until `begin` metres, ramping to a full
##   melt at `end` — the near field stays perfectly crisp by construction and
##   the streaming edge (~350 m) stays hidden because end < 350.
## The "off" rung exists to show the raw pop-in edge the haze is hiding —
## a reference, not a candidate.
##
## Patches are runtime-only; the committed scene is untouched. The picked rung
## gets written into desert_environment.tscn by hand afterwards.
##
## Run windowed:
##   Godot --path . --script res://tools/shoot_haze.gd -- <outdir>

## name -> [mode, a, b, c]:
##   ["exp", density]                       exponential
##   ["depth", begin_m, end_m, curve]       distance-only, fully opaque at end
##   ["off"]                                fog disabled
const RUNGS: Dictionary = {
	"a_current": ["exp", 0.004],
	"b_half": ["exp", 0.002],
	"c_faint": ["exp", 0.001],
	"d_distance": ["depth", 100.0, 330.0, 1.4],
	"e_distance_late": ["depth", 180.0, 350.0, 1.4],
	"f_off_reference": ["off"],
}
const HOUR: float = 16.0

const LOAD_RADIUS: int = 5
const SEARCH_EXTENT: float = 400.0
const SEARCH_STEP: float = 8.0
const SETTLE_FRAMES: int = 20

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
	clock.set_time_of_day(HOUR)

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	manager.load_radius = LOAD_RADIUS
	manager.unload_radius = LOAD_RADIUS + 1
	root.add_child(level)
	await physics_frame

	var environment: Environment = (
		level.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment
	var terrain: TerrainSettings = manager.get_terrain()
	var vantage: Vector2 = _find_vantage(terrain)
	var player: Player = level.find_child("Player", true, false) as Player
	player.global_position = Vector3(
		vantage.x, terrain.get_surface_height(vantage) + 0.1, vantage.y)
	player.reset_physics_interpolation()
	manager.set_tracked(player)
	(level.find_child("CameraRig", true, false) as CameraRig).snap_to_target()
	for i: int in range(360):
		await physics_frame
		if manager.get_pending_count() == 0 and i > 30:
			break

	for rung_name: String in RUNGS:
		_apply_rung(environment, RUNGS[rung_name])
		for _i: int in SETTLE_FRAMES:
			await physics_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		var path: String = _outdir.path_join("haze_%s.png" % rung_name)
		image.save_png(path)
		print("saved ", path)

	# Horizon stress test: a crest with open distance ahead, at maximum zoom —
	# the sightline that reaches furthest. This is where a too-light haze
	# exposes the streaming edge; the hollow shots above can't see that far.
	var crest: Vector2 = _find_crest(terrain)
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	rig._zoom_goal = 34.0
	rig._zoom_current = 34.0
	player.global_position = Vector3(
		crest.x, terrain.get_surface_height(crest) + 0.1, crest.y)
	player.reset_physics_interpolation()
	rig.snap_to_target()
	for i: int in range(360):
		await physics_frame
		if manager.get_pending_count() == 0 and i > 30:
			break
	for rung_name: String in RUNGS:
		_apply_rung(environment, RUNGS[rung_name])
		for _i: int in SETTLE_FRAMES:
			await physics_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		var path: String = _outdir.path_join("horizon_%s.png" % rung_name)
		image.save_png(path)
		print("saved ", path)

	level.free()


func _apply_rung(environment: Environment, spec: Array) -> void:
	var mode: String = String(spec[0])
	environment.fog_enabled = mode != "off"
	if mode == "exp":
		environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		environment.fog_density = float(spec[1])
	elif mode == "depth":
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		# In depth mode density is the opacity reached at depth_end; 1.0
		# guarantees the streaming edge is fully melted by construction.
		environment.fog_density = 1.0
		environment.fog_depth_begin = float(spec[1])
		environment.fog_depth_end = float(spec[2])
		environment.fog_depth_curve = float(spec[3])


## High ground with LOW terrain ahead toward -Z: the longest open sightline.
func _find_crest(terrain: TerrainSettings) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for x: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
		for z: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
			var at: Vector2 = Vector2(x, z)
			var here: float = terrain.get_surface_height(at)
			var ahead_max: float = -INF
			for d: float in range(60, 401, 20):
				ahead_max = maxf(ahead_max, terrain.get_surface_height(at + Vector2(0.0, -d)))
			var score: float = here - ahead_max
			if score > best_score:
				best_score = score
				best = at
	print("crest (%.0f, %.0f): %.1f m above the ground ahead" % [best.x, best.y, best_score])
	return best


## The deepest hollow with dune rises ahead toward -Z (the shoot_daynight
## vantage logic — the horizon band in the upper frame is what haze acts on).
func _find_vantage(terrain: TerrainSettings) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for x: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
		for z: float in range(-SEARCH_EXTENT, SEARCH_EXTENT, SEARCH_STEP):
			var at: Vector2 = Vector2(x, z)
			var here: float = terrain.get_surface_height(at)
			var ahead_max: float = -INF
			for d: float in range(60, 401, 20):
				ahead_max = maxf(ahead_max, terrain.get_surface_height(at + Vector2(0.0, -d)))
			var score: float = ahead_max - here
			if score > best_score:
				best_score = score
				best = at
	print("vantage (%.0f, %.0f): %.1f m of dune ahead" % [best.x, best.y, best_score])
	return best
