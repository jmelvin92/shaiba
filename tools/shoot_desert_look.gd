extends SceneTree
## Desert-look comparison shots for Joshua, three ladders in one run:
##
##   colors  — candidate sand palettes (current cream → Shaybah orange),
##             same vantage, everything else unchanged.
##   ripples — wind-ripple shading strengths on the `shaybah` trio, gameplay
##             zoom plus a close-up at minimum zoom.
##   mega    — mega-dune amplitudes on the `shaybah` trio; each amplitude
##             re-finds its own best vantage because the terrain changes.
##   hero    — one combined "destination" shot (shaybah + crisp + mega 15).
##
## All patches are in-memory only (Godot's resource cache): the committed
## palette/.tres files are untouched; picked values get committed by hand
## afterwards. Autoloads don't run under --script, so the world seeds with 0 —
## the same desert every run, which is exactly what a comparison wants.
##
## Run windowed (macOS stops drawing occluded windows — focus repeatedly):
##   Godot --path . --script res://tools/shoot_desert_look.gd -- <outdir> [ladder ...]

## light / mid / shadow per candidate, sRGB hex.
const TRIOS: Dictionary = {
	"current": ["EFD9A7", "DFB878", "C4914E"],
	"amber": ["F2C177", "E09A4A", "B66B28"],
	"shaybah": ["EFA254", "D97E2E", "A85419"],
	"ember": ["E08A3A", "C4661D", "8F3F10"],
}
## Trio the ripple/mega/hero shots are rendered on.
const SHOW_TRIO: String = "shaybah"
## strength (m), wavelength (m), trough tint per ripple rung.
const RIPPLES: Dictionary = {
	"subtle": [0.04, 2.0, 0.08],
	"crisp": [0.08, 2.4, 0.12],
	"bold": [0.14, 3.0, 0.16],
}
const MEGA_AMPLITUDES: Array[float] = [15.0, 30.0]
const HERO_RIPPLE: String = "crisp"
const HERO_MEGA: float = 15.0

const LOAD_RADIUS: int = 5
const CLOSE_ZOOM: float = 9.0
const SEARCH_EXTENT: float = 400.0
const SEARCH_STEP: float = 8.0
## Mega-dunes are ~650 m features: scan wider, coarser.
const MEGA_SEARCH_EXTENT: float = 700.0
const MEGA_SEARCH_STEP: float = 14.0

var _outdir: String = ""
var _settings: TerrainSettings = load("res://resources/terrain/desert.tres") as TerrainSettings
var _material: ShaderMaterial = load(
	"res://resources/terrain/sand_terrain_material.tres"
) as ShaderMaterial
## Held as members deliberately: every patched resource must stay referenced
## for the whole run. When a level is freed, anything only it referenced drops
## out of the resource cache, and the next load() silently reloads the
## unpatched file from disk — which is exactly how the first ladder run
## produced four byte-identical "different" palettes.
var _palette: Dictionary = {
	"sand_light": load("res://resources/palette/sand_light.tres"),
	"sand_mid": load("res://resources/palette/sand_mid.tres"),
	"sand_shadow": load("res://resources/palette/sand_shadow.tres"),
}


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	quit(0)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <outdir> [colors|ripples|mega|hero ...]")
		return
	_outdir = args[0]
	DirAccess.make_dir_recursive_absolute(_outdir)
	var ladders: Array[String] = ["colors", "ripples", "mega", "hero"]
	if args.size() > 1:
		ladders = []
		for i: int in range(1, args.size()):
			ladders.append(args[i])

	# One fixed vantage for every same-terrain shot, found on the unmodified
	# desert so every ladder that shares terrain shares the exact frame.
	_apply_mega(0.0)
	_settings.setup(0)
	var vantage: Vector2 = _find_vantage(_settings, SEARCH_EXTENT, SEARCH_STEP)

	if ladders.has("colors"):
		_apply_ripples("")
		_apply_mega(0.0)
		for trio_name: String in TRIOS:
			_apply_palette(trio_name)
			await _shoot(vantage, "color_%s" % trio_name, 0.0)

	if ladders.has("ripples"):
		_apply_palette(SHOW_TRIO)
		_apply_mega(0.0)
		for ripple_name: String in RIPPLES:
			_apply_ripples(ripple_name)
			await _shoot(vantage, "ripple_%s" % ripple_name, 0.0)
			await _shoot(vantage, "ripple_%s_close" % ripple_name, CLOSE_ZOOM)

	if ladders.has("mega"):
		_apply_palette(SHOW_TRIO)
		_apply_ripples("")
		for amplitude: float in MEGA_AMPLITUDES:
			_apply_mega(amplitude)
			_settings.setup(0)
			var mega_vantage: Vector2 = _find_vantage(
				_settings, MEGA_SEARCH_EXTENT, MEGA_SEARCH_STEP
			)
			await _shoot(mega_vantage, "mega_%02d" % roundi(amplitude), 0.0)

	if ladders.has("hero"):
		_apply_palette(SHOW_TRIO)
		_apply_ripples(HERO_RIPPLE)
		_apply_mega(HERO_MEGA)
		_settings.setup(0)
		var hero_vantage: Vector2 = _find_vantage(
			_settings, MEGA_SEARCH_EXTENT, MEGA_SEARCH_STEP
		)
		await _shoot(hero_vantage, "hero_combined", 0.0)


## Streams a fresh world with whatever is currently patched, seats the player
## at [param vantage], captures one frame. zoom 0 keeps the gameplay default.
func _shoot(vantage: Vector2, shot_name: String, zoom: float) -> void:
	var level: Node3D = (
		load("res://scenes/world/world.tscn") as PackedScene
	).instantiate() as Node3D
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	manager.load_radius = LOAD_RADIUS
	manager.unload_radius = LOAD_RADIUS + 1
	if zoom > 0.0:
		# zoom_distance is only read by CameraRig._ready, so it must be set
		# before the scene enters the tree.
		(level.find_child("CameraRig", true, false) as CameraRig).zoom_distance = zoom
	root.add_child(level)
	await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var terrain: TerrainSettings = manager.get_terrain()
	player.global_position = Vector3(
		vantage.x, terrain.get_surface_height(vantage) + 0.1, vantage.y
	)
	player.reset_physics_interpolation()
	manager.set_tracked(player)
	rig.snap_to_target()

	for i: int in range(360):
		await physics_frame
		if manager.get_pending_count() == 0 and i > 60:
			break
	for _i: int in range(30):
		await physics_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)

	level.free()
	for _i: int in range(5):
		await physics_frame


## Patches the three sand palette materials in the resource cache; the chunk
## builder bakes vertex colors from these, and SandDeformation derives its
## print tint from them, so one patch recolors everything.
func _apply_palette(trio_name: String) -> void:
	var trio: Array = TRIOS[trio_name]
	var slots: Array[String] = ["sand_light", "sand_mid", "sand_shadow"]
	for i: int in range(3):
		(_palette[slots[i]] as StandardMaterial3D).albedo_color = Color(String(trio[i]))


## Sets the ripple-shading uniforms; empty name switches ripples off.
func _apply_ripples(ripple_name: String) -> void:
	if ripple_name.is_empty():
		_material.set_shader_parameter("ripple_strength", 0.0)
		return
	var spec: Array = RIPPLES[ripple_name]
	_material.set_shader_parameter("ripple_strength", float(spec[0]))
	_material.set_shader_parameter("ripple_wavelength", float(spec[1]))
	_material.set_shader_parameter("ripple_trough_tint", float(spec[2]))


func _apply_mega(amplitude: float) -> void:
	_settings.mega_amplitude = amplitude


## The deepest hollow with notably higher ground ahead toward -Z (where the
## camera looks) — shoot_pitch.gd's vantage logic, parameterised so the mega
## ladder can scan wider and look further: a mega-dune's rise is spread over
## hundreds of metres, so judging it 220 m out misses the crest entirely.
func _find_vantage(terrain: TerrainSettings, extent: float, step: float) -> Vector2:
	var lookahead: float = minf(extent, 400.0)
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for x: float in range(-extent, extent, step):
		for z: float in range(-extent, extent, step):
			var at: Vector2 = Vector2(x, z)
			var here: float = terrain.get_surface_height(at)
			var ahead_max: float = -INF
			for d: float in range(60, int(lookahead) + 1, 20):
				ahead_max = maxf(
					ahead_max, terrain.get_surface_height(at + Vector2(0.0, -d))
				)
			var score: float = ahead_max - here
			if score > best_score:
				best_score = score
				best = at
	print("vantage (%.0f, %.0f): %.1f m of dune rises ahead" % [best.x, best.y, best_score])
	return best
