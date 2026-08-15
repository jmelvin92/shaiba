extends SceneTree
## Day-night ladder shots for Joshua (Phase 6.5 piece 2): one streamed world,
## two vantages (open dunes, the homestead), photographed through the day and
## at four night_darkness rungs so the night's character is picked from real
## frames, not descriptions.
##
## A clock node named "Game" is injected before the level loads (autoloads
## don't run under --script), frozen, and stepped per shot — the environment
## follows it exactly as it follows the real autoload in the game.
##
## Run windowed (macOS stops drawing occluded windows — keep re-focusing):
##   Godot --path . --script res://tools/shoot_daynight.gd -- <outdir>

## label -> hour. The day sweep runs at DEFAULT_DARKNESS.
const DAY_SWEEP: Dictionary = {
	"0545_sunrise": 5.75,
	"0630_dawn": 6.4,
	"0800_morning": 8.0,
	"1200_noon": 12.0,
	"1600_golden": 16.0,
	"1745_dusk": 17.75,
	"1825_sunset": 18.4,
	"1915_nightfall": 19.25,
}
const NIGHT_HOUR: float = 23.0
const DARKNESS_RUNGS: Array[float] = [0.0, 0.35, 0.65, 1.0]
const DEFAULT_DARKNESS: float = 0.35

const LOAD_RADIUS: int = 5
const SEARCH_EXTENT: float = 400.0
const SEARCH_STEP: float = 8.0
## Frames to let the sky/shadows settle after a time jump before capturing.
const SETTLE_FRAMES: int = 20

var _outdir: String = ""
var _clock: Node = null
var _level: Node3D = null
var _env: DesertEnvironment = null
var _player: Player = null
var _manager: ChunkManager = null


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

	# The Game autoload DOES run under --script (verified 2026-08-15 —
	# shoot_desert_look's older comment predates this); injecting a second
	# node named "Game" gets auto-renamed and the environment keeps
	# listening to the real one. Use the autoload when present.
	_clock = root.get_node_or_null(^"/root/Game")
	if _clock == null:
		_clock = (load("res://autoload/game.gd") as GDScript).new()
		_clock.name = "Game"
		root.add_child(_clock)
	_clock.time_paused = true

	_level = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	_manager = _level.find_child("ChunkManager", true, false) as ChunkManager
	_manager.load_radius = LOAD_RADIUS
	_manager.unload_radius = LOAD_RADIUS + 1
	root.add_child(_level)
	await physics_frame
	_env = _level.find_child("DesertEnvironment", true, false) as DesertEnvironment
	_env.night_darkness = DEFAULT_DARKNESS
	_player = _level.find_child("Player", true, false) as Player

	var terrain: TerrainSettings = _manager.get_terrain()
	var dune_vantage: Vector2 = _find_vantage(terrain)
	var homestead: Vector2 = terrain.get_homestead_center()
	# Stand in the courtyard, camera looking across the house toward -Z.
	var homestead_vantage: Vector2 = homestead + Vector2(0.0, 14.0)

	await _move_to(dune_vantage, terrain)
	for label: String in DAY_SWEEP:
		await _shoot(float(DAY_SWEEP[label]), "day_%s" % label)
	for rung: float in DARKNESS_RUNGS:
		_env.night_darkness = rung
		await _shoot(NIGHT_HOUR, "night_dunes_%03d" % roundi(rung * 100.0))

	await _move_to(homestead_vantage, terrain)
	_env.night_darkness = DEFAULT_DARKNESS
	await _shoot(16.0, "home_1600_golden")
	for rung: float in DARKNESS_RUNGS:
		_env.night_darkness = rung
		await _shoot(NIGHT_HOUR, "night_home_%03d" % roundi(rung * 100.0))

	_level.free()


func _move_to(spot: Vector2, terrain: TerrainSettings) -> void:
	_player.global_position = Vector3(
		spot.x, terrain.get_surface_height(spot) + 0.1, spot.y)
	_player.reset_physics_interpolation()
	_manager.set_tracked(_player)
	(_level.find_child("CameraRig", true, false) as CameraRig).snap_to_target()
	for i: int in range(360):
		await physics_frame
		if _manager.get_pending_count() == 0 and i > 30:
			break


func _shoot(hour: float, shot_name: String) -> void:
	_clock.set_time_of_day(hour)
	for _i: int in SETTLE_FRAMES:
		await physics_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)


## The deepest hollow with dune rises ahead toward -Z (shoot_desert_look's
## vantage logic, single-purpose copy).
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
