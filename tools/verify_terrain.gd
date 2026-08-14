extends SceneTree
## Phase 4's quality gate as a runnable script (pattern: tools/verify_player.gd).
##
## Run headless:
##   Godot --headless --path . --script res://tools/verify_terrain.gd [-- <mode>]
##
## With no mode: field-level checks that need no scene — determinism (same seed
## twice gives bit-identical terrain, a different seed gives different terrain,
## plus a canonical world hash printable across runs), the slope audit (the
## walkable-sand guarantee: analytic slope must stay below the player's 32°
## floor_max_angle everywhere), and depth sanity (deep and shallow sand both
## actually occur).
##
## Prints FAIL lines and exits non-zero on any failure.

const SETTINGS_PATH: String = "res://resources/terrain/desert.tres"
## The slope audit fails at this angle — 1° under the player's floor_max_angle,
## so collision triangles (secants, always shallower than the analytic worst
## case) can never present a wall-like face to _try_step_up.
const SLOPE_LIMIT_DEG: float = 31.0
## Half-width of the audited square around the origin, metres.
const AUDIT_EXTENT: float = 2000.0

var _failures: PackedStringArray = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	_run()
	print("")
	if _failures.is_empty():
		print("verify_terrain: all checks passed")
		quit(0)
	else:
		for line: String in _failures:
			print("FAIL  " + line)
		quit(1)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_determinism()
		_slope_audit()
		_depth_sanity()
		return
	push_error("verify_terrain: unknown mode %s" % " ".join(args))
	_failures.append("unknown mode: " + " ".join(args))


func _fail(message: String) -> void:
	_failures.append(message)


func _world_seed() -> int:
	var game: Node = root.get_node_or_null(^"/root/Game")
	if game != null:
		return game.world_seed
	return 20260813


## A fresh, independent TerrainSettings (own noise instances), seeded.
func _fresh_settings(seed_value: int) -> TerrainSettings:
	var settings: TerrainSettings = (load(SETTINGS_PATH) as TerrainSettings).duplicate(true)
	settings.setup(seed_value)
	return settings


## Heights over a fixed grid, as the byte stream the world hash is taken over.
func _sample_block(settings: TerrainSettings) -> PackedFloat32Array:
	var samples: PackedFloat32Array = []
	for j: int in range(96):
		for i: int in range(96):
			var at: Vector2 = Vector2((i - 48) * 21.5, (j - 48) * 21.5)
			samples.append(settings.get_surface_height(at))
			samples.append(settings.get_sand_depth(at))
	return samples


func _determinism() -> void:
	var seed_value: int = _world_seed()
	var first: PackedFloat32Array = _sample_block(_fresh_settings(seed_value))
	var second: PackedFloat32Array = _sample_block(_fresh_settings(seed_value))
	if first != second:
		_fail("determinism: same seed produced different terrain")
	var other: PackedFloat32Array = _sample_block(_fresh_settings(seed_value + 1))
	if first == other:
		_fail("determinism: different seed produced identical terrain")

	var hasher: HashingContext = HashingContext.new()
	hasher.start(HashingContext.HASH_MD5)
	hasher.update(first.to_byte_array())
	print("world hash (seed %d): %s" % [seed_value, hasher.finish().hex_encode()])


func _slope_audit() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var epsilon: float = 0.5
	var worst: float = 0.0
	var worst_at: Vector2 = Vector2.ZERO
	for _i: int in range(120000):
		var at: Vector2 = Vector2(
			rng.randf_range(-AUDIT_EXTENT, AUDIT_EXTENT),
			rng.randf_range(-AUDIT_EXTENT, AUDIT_EXTENT)
		)
		var dx: float = (
			settings.get_surface_height(at + Vector2(epsilon, 0.0))
			- settings.get_surface_height(at - Vector2(epsilon, 0.0))
		) / (2.0 * epsilon)
		var dz: float = (
			settings.get_surface_height(at + Vector2(0.0, epsilon))
			- settings.get_surface_height(at - Vector2(0.0, epsilon))
		) / (2.0 * epsilon)
		var slope: float = rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
		if slope > worst:
			worst = slope
			worst_at = at
	print("slope audit: worst %.2f deg at (%.0f, %.0f)" % [worst, worst_at.x, worst_at.y])
	if worst >= SLOPE_LIMIT_DEG:
		_fail(
			"slope audit: %.2f deg at (%.0f, %.0f) exceeds the %.0f deg limit"
			% [worst, worst_at.x, worst_at.y, SLOPE_LIMIT_DEG]
		)


func _depth_sanity() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2
	var count: int = 50000
	var min_depth: float = INF
	var max_depth: float = 0.0
	var min_height: float = INF
	var max_height: float = -INF
	var hard: int = 0
	var deep: int = 0
	for _i: int in range(count):
		var at: Vector2 = Vector2(
			rng.randf_range(-AUDIT_EXTENT, AUDIT_EXTENT),
			rng.randf_range(-AUDIT_EXTENT, AUDIT_EXTENT)
		)
		var depth: float = settings.get_sand_depth(at)
		min_depth = minf(min_depth, depth)
		max_depth = maxf(max_depth, depth)
		var height: float = settings.get_surface_height(at)
		min_height = minf(min_height, height)
		max_height = maxf(max_height, height)
		if depth < 0.05:
			hard += 1
		if depth > 1.0:
			deep += 1
	print(
		"depth: %.2f-%.2f m (height %.2f-%.2f), hard ground %.1f%%, deep sand %.1f%%"
		% [
			min_depth, max_depth, min_height, max_height,
			100.0 * hard / count, 100.0 * deep / count,
		]
	)
	if min_depth < 0.0:
		_fail("depth sanity: negative sand depth %.3f" % min_depth)
	if max_depth < 1.0:
		_fail("depth sanity: no deep sand anywhere sampled (max %.2f m)" % max_depth)
	if hard == 0:
		_fail("depth sanity: no shallow/hard ground anywhere sampled")
	if deep == 0:
		_fail("depth sanity: no notably deep sand anywhere sampled")
