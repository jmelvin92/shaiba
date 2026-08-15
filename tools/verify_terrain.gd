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
## How much height variation the homestead pad may have across it, metres. The
## ripple that survives on thin sand is a few centimetres; this catches the pad
## failing to flatten at all.
const PAD_RELIEF_LIMIT: float = 0.10

var _failures: PackedStringArray = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
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
		_seams()
		_slope_audit()
		_homestead_audit()
		_depth_sanity()
		return
	if args.has("--collision"):
		await _collision_audit()
		return
	if args.has("--walk"):
		await _walk(args)
		return
	if args.has("--sand"):
		await _sand()
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


## Neighbouring chunks must produce bit-identical heights and colours along
## their shared edge — the builder samples global integer grid indices, so any
## difference means a float path diverged and a seam would open.
func _seams() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var n: int = settings.chunk_size + 1
	var origin: TerrainChunk.BuildData = TerrainChunk.build_data(settings, Vector2i.ZERO)
	var east: TerrainChunk.BuildData = TerrainChunk.build_data(settings, Vector2i(1, 0))
	var south: TerrainChunk.BuildData = TerrainChunk.build_data(settings, Vector2i(0, 1))

	var mismatches: int = 0
	for j: int in range(n):
		if origin.shape.map_data[j * n + (n - 1)] != east.shape.map_data[j * n]:
			mismatches += 1
	for i: int in range(n):
		if origin.shape.map_data[(n - 1) * n + i] != south.shape.map_data[i]:
			mismatches += 1
	if mismatches > 0:
		_fail("seams: %d shared-edge height samples differ between neighbours" % mismatches)
	else:
		print("seams: shared edges bit-identical across neighbours")


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


## The homestead pad, audited densely rather than by luck.
##
## The pad is a couple of hundred square metres inside a 16 km² audit area, so
## the random slope audit above may put only a handful of samples on the one
## piece of terrain this project *edits* rather than generates. Its blend band
## is also the only place where a slope is manufactured instead of inherited
## from noise, which makes it the one place a slope failure could be introduced
## by a tuning change. So: sample it deliberately, and check the pad is really
## flat enough to stand a building on.
func _homestead_audit() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var centre: Vector2 = settings.get_homestead_center()
	var outer: float = settings.homestead_radius + settings.homestead_blend
	var epsilon: float = 0.5

	var worst_slope: float = 0.0
	var worst_at: Vector2 = Vector2.ZERO
	var pad_low: float = INF
	var pad_high: float = -INF

	# A polar sweep, finest across the blend band where the slope actually is.
	for ring: int in range(241):
		var radius: float = outer * 1.15 * float(ring) / 240.0
		for spoke: int in range(180):
			var angle: float = TAU * float(spoke) / 180.0
			var at: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
			var height: float = settings.get_surface_height(at)
			if radius <= settings.homestead_radius:
				pad_low = minf(pad_low, height)
				pad_high = maxf(pad_high, height)
			var dx: float = (
				settings.get_surface_height(at + Vector2(epsilon, 0.0))
				- settings.get_surface_height(at - Vector2(epsilon, 0.0))
			) / (2.0 * epsilon)
			var dz: float = (
				settings.get_surface_height(at + Vector2(0.0, epsilon))
				- settings.get_surface_height(at - Vector2(0.0, epsilon))
			) / (2.0 * epsilon)
			var slope: float = rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
			if slope > worst_slope:
				worst_slope = slope
				worst_at = at

	var relief: float = pad_high - pad_low
	print(
		"homestead: centre (%.1f, %.1f), pad relief %.3f m, approach worst %.2f deg"
		% [centre.x, centre.y, relief, worst_slope]
	)
	if worst_slope >= SLOPE_LIMIT_DEG:
		_fail(
			"homestead approach: %.2f deg at (%.0f, %.0f) exceeds the %.0f deg limit"
			% [worst_slope, worst_at.x, worst_at.y, SLOPE_LIMIT_DEG]
		)
	# A building sits on this. A few centimetres of ripple is fine; anything
	# approaching a step is not, because the walls are flat-bottomed.
	if relief > PAD_RELIEF_LIMIT:
		_fail(
			"homestead pad is not flat: %.3f m of relief across it (limit %.2f)"
			% [relief, PAD_RELIEF_LIMIT]
		)
	var depth: float = settings.get_sand_depth(centre)
	if depth > 0.6:
		_fail("homestead pad sand is %.2f m deep; the courtyard should be firm" % depth)


## Instances the real world scene and rains rays on the loaded chunks.
##
## Two comparisons per hit, answering two different questions:
## - against this script's reimplementation of the mesh's own triangle
##   interpolation: near-zero iff HeightMapShape3D triangulates its cells
##   along the same diagonal the visual mesh uses. This is the check that
##   collision *is* the surface the player sees.
## - against the analytic field: bounded by the field's curvature across one
##   cell — the documented error of sampling TerrainSettings between vertices.
func _collision_audit() -> void:
	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await physics_frame
	await physics_frame

	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	if manager == null:
		_fail("collision: world.tscn has no ChunkManager")
		return
	var settings: TerrainSettings = manager.get_terrain()
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var worst_mesh: float = 0.0
	var worst_field: float = 0.0
	var misses: int = 0
	var roofed: int = 0
	for _i: int in range(2000):
		var at: Vector2 = Vector2(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			Vector3(at.x, 50.0, at.y), Vector3(at.x, -50.0, at.y), 1
		)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			misses += 1
			continue
		# Buildings share the world layer with the terrain, and since Phase 6
		# the homestead stands inside this audit's square. A ray that lands on
		# a roof is not evidence about HeightMapShape3D, so only chunks count.
		if not (hit["collider"] is TerrainChunk):
			roofed += 1
			continue
		var hit_y: float = (hit["position"] as Vector3).y
		worst_mesh = maxf(worst_mesh, absf(hit_y - _mesh_height(settings, at)))
		worst_field = maxf(worst_field, absf(hit_y - settings.get_surface_height(at)))

	print(
		"collision: worst vs mesh %.4f m, worst vs analytic field %.4f m, "
		% [worst_mesh, worst_field]
		+ "%d/2000 rays missed, %d landed on the homestead" % [misses, roofed]
	)
	if misses > 0:
		_fail("collision: %d rays found no ground inside the loaded radius" % misses)
	if worst_mesh > 0.005:
		_fail(
			"collision: %.4f m off the visual mesh — HeightMapShape3D is not "
			% worst_mesh
			+ "triangulating the diagonal the mesh uses"
		)
	if worst_field > 0.08:
		_fail("collision: %.4f m off the analytic field (curvature bound blown)" % worst_field)

	# Synchronous free: queue_free's deletion pass wouldn't run before quit,
	# which shows up as "ObjectDB instances leaked at exit".
	level.free()


## Walks the player 2 km in a straight line through streaming terrain and
## watches what the gate cares about: per-frame wall time (worst frame, count
## over 4 ms), the loaded-chunk count (must plateau — proof that unloading
## works), memory drift, and the largest one-tick grounded rise of the player
## (a step-up false-triggering on a chunk seam would spike it).
##
## Headless, physics runs on the wall clock, so 2 km at run speed is ~7 min;
## `Engine.time_scale` is raised to compress that. Frame-time numbers under
## time_scale measure the same per-frame streaming work, just denser — the
## windowed run without time_scale is the honest fps gate. Progress goes to
## user://walk_progress.txt because piped print is block-buffered (CLAUDE.md).
func _walk(args: PackedStringArray) -> void:
	var realtime: bool = args.has("--realtime")
	if not realtime:
		Engine.time_scale = 4.0

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await physics_frame
	await physics_frame
	var player: Player = level.find_child("Player", true, false) as Player
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager

	# Let the spawn build, the first frames, and (windowed) the window-focus
	# transition all settle before measuring.
	for _i: int in range(300):
		await physics_frame

	var progress_path: String = "user://walk_progress.txt"
	var start_z: float = player.global_position.z
	var start_memory: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var worst_frame_ms: float = 0.0
	var over_budget: int = 0
	var dropped: int = 0
	var drops: PackedStringArray = []
	var frames: int = 0
	var max_loaded: int = 0
	var end_loaded: int = 0
	var max_rise: float = 0.0
	var last_y: float = player.global_position.y
	var was_grounded: bool = true
	var last_usec: int = Time.get_ticks_usec()

	Input.action_press("move_up")
	Input.action_press("sprint")
	var wall_start: int = Time.get_ticks_usec()
	while absf(player.global_position.z - start_z) < 2000.0:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var frame_ms: float = float(now - last_usec) / 1000.0
		last_usec = now
		frames += 1
		if frame_ms > worst_frame_ms:
			worst_frame_ms = frame_ms
		if frame_ms > 4.0:
			over_budget += 1
		if frame_ms > 16.8:
			dropped += 1
			# Attribution: was streaming actually doing anything this frame?
			if drops.size() < 40:
				drops.append(
					"t %.1f s: frame %.1f ms, apply %.2f ms, pending %d"
					% [float(Time.get_ticks_usec() - wall_start) / 1e6,
						frame_ms, manager.last_apply_ms, manager.get_pending_count()]
				)

		var grounded: bool = player.is_on_floor()
		var y: float = player.global_position.y
		if grounded and was_grounded:
			max_rise = maxf(max_rise, y - last_y)
		last_y = y
		was_grounded = grounded

		end_loaded = manager.get_loaded_count()
		max_loaded = maxi(max_loaded, end_loaded)

		if frames % 600 == 0:
			var log_file: FileAccess = FileAccess.open(progress_path, FileAccess.WRITE)
			log_file.store_line(
				"z %.0f m, %d frames, worst %.2f ms, loaded %d"
				% [absf(player.global_position.z - start_z), frames, worst_frame_ms, end_loaded]
			)
			log_file.close()
		if Time.get_ticks_usec() - wall_start > 25 * 60 * 1000 * 1000:
			_fail("walk: aborted after 25 min wall time without covering 2 km")
			break
	Input.action_release("move_up")
	Input.action_release("sprint")
	Engine.time_scale = 1.0

	var memory_delta_mb: float = (
		Performance.get_monitor(Performance.MEMORY_STATIC) - start_memory
	) / 1048576.0
	var full_grid: int = (2 * manager.load_radius + 1) * (2 * manager.load_radius + 1)
	var max_grid: int = (2 * manager.unload_radius + 1) * (2 * manager.unload_radius + 1)
	print(
		"walk: %d frames over %.0f m; whole frame worst %.2f ms, %d > 4 ms (%.2f%%), "
		% [frames, absf(player.global_position.z - start_z), worst_frame_ms, over_budget,
			100.0 * over_budget / maxf(frames, 1.0)]
		+ "%d dropped (> 16.8 ms); streaming apply worst %.2f ms; "
		% [dropped, manager.worst_apply_ms]
		+ "loaded now %d (max %d), memory %+.1f MB, max grounded rise %.3f m/tick"
		% [end_loaded, max_loaded, memory_delta_mb, max_rise]
	)
	for line: String in drops:
		print("  drop " + line)
	if realtime and dropped > frames / 1000:
		_fail("walk: %d frames dropped below 60 fps over the run" % dropped)
	if manager.worst_apply_ms > 4.0:
		_fail(
			"walk: installing chunks took %.2f ms in one frame (budget is 4 ms)"
			% manager.worst_apply_ms
		)
	if end_loaded > max_grid:
		_fail("walk: %d chunks still loaded at the end — unloading is not working" % end_loaded)
	if end_loaded < full_grid:
		_fail("walk: only %d chunks loaded at the end (full grid is %d)" % [end_loaded, full_grid])
	if max_loaded > max_grid + 8:
		_fail("walk: loaded count peaked at %d — far past the unload ring %d" % [max_loaded, max_grid])
	if memory_delta_mb > 500.0:
		_fail("walk: static memory grew %.0f MB over one walk" % memory_delta_mb)
	if max_rise > 0.30:
		_fail(
			"walk: player rose %.3f m in one grounded tick — step-up fired on terrain"
			% max_rise
		)

	# Synchronous free: queue_free's deletion pass wouldn't run before quit,
	# which shows up as "ObjectDB instances leaked at exit".
	level.free()


## Verifies the deep-sand movement hooks against the real desert: walking
## speed at a deep spot and a shallow spot must each match what the depth
## there predicts, and standing in deep sand must visibly sink the mesh.
## (That the hooks stay inert off-terrain is verify_player's default suite —
## it measures full walking speed on the terrain-less graybox.)
func _sand() -> void:
	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await physics_frame
	await physics_frame
	var player: Player = level.find_child("Player", true, false) as Player
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	var terrain: TerrainSettings = manager.get_terrain()

	# Flattest markedly-deep and markedly-shallow spots near the spawn, so the
	# speed reading is not fighting a dune face.
	var deep_spot: Vector2 = _flattest_where(terrain, func(depth: float) -> bool:
		return depth > 0.8)
	var shallow_spot: Vector2 = _flattest_where(terrain, func(depth: float) -> bool:
		return depth < 0.25)

	for spot: Vector2 in [deep_spot, shallow_spot]:
		var label: String = "deep" if spot == deep_spot else "shallow"
		_teleport(player, manager, terrain, spot)
		for _i: int in range(30):
			await physics_frame

		Input.action_press("move_up")
		var speeds: Array[float] = []
		var factors: Array[float] = []
		for i: int in range(150):
			await physics_frame
			if i >= 90:
				speeds.append(player.get_planar_speed())
				factors.append(
					clampf(
						terrain.get_sand_depth(
							Vector2(player.global_position.x, player.global_position.z)
						) / player.deep_sand_depth,
						0.0, 1.0
					)
				)
		Input.action_release("move_up")
		speeds.sort()
		factors.sort()
		var actual: float = speeds[speeds.size() / 2]
		var factor: float = factors[factors.size() / 2]
		var expected: float = player.walk_speed * lerpf(1.0, player.deep_sand_speed_scale, factor)
		print(
			"sand %s: depth factor %.2f, expected %.2f m/s, measured %.2f m/s"
			% [label, factor, expected, actual]
		)
		if absf(actual - expected) > expected * 0.1:
			_fail(
				"sand %s: walking at %.2f m/s where depth predicts %.2f m/s"
				% [label, actual, expected]
			)

	# Standing still in deep sand: the mesh should settle visibly below the
	# collider.
	_teleport(player, manager, terrain, deep_spot)
	for _i: int in range(90):
		await physics_frame
	var visual: Node3D = player.get_node(^"Visual") as Node3D
	var sink: float = visual.position.y
	var wanted: float = -minf(
		terrain.get_sand_depth(Vector2(player.global_position.x, player.global_position.z))
		* player.sand_sink_ratio,
		player.sand_sink_max
	)
	print("sand sink: visual offset %.3f m (target %.3f m)" % [sink, wanted])
	if absf(sink - wanted) > 0.02:
		_fail("sand sink: mesh sits at %.3f m, expected %.3f m" % [sink, wanted])

	# Synchronous free: queue_free's deletion pass wouldn't run before quit,
	# which shows up as "ObjectDB instances leaked at exit".
	level.free()


## Scans a ring around the spawn for positions whose depth satisfies
## [param wanted] and returns the one with the least local slope.
func _flattest_where(terrain: TerrainSettings, wanted: Callable) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_slope: float = INF
	for x: int in range(-240, 241, 8):
		for z: int in range(-240, 241, 8):
			var at: Vector2 = Vector2(x, z)
			if not wanted.call(terrain.get_sand_depth(at)):
				continue
			var dx: float = terrain.get_surface_height(at + Vector2(1.0, 0.0)) \
				- terrain.get_surface_height(at - Vector2(1.0, 0.0))
			var dz: float = terrain.get_surface_height(at + Vector2(0.0, 1.0)) \
				- terrain.get_surface_height(at - Vector2(0.0, 1.0))
			var slope: float = dx * dx + dz * dz
			if slope < best_slope:
				best_slope = slope
				best = at
	return best


## Moves the player somewhere possibly unloaded: the manager synchronously
## fills the chunks around the new spot before the player can fall through.
func _teleport(
	player: Player, manager: ChunkManager, terrain: TerrainSettings, at: Vector2
) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(at.x, terrain.get_surface_height(at) + 0.1, at.y)
	player.reset_physics_interpolation()
	manager.set_tracked(player)


## The visual mesh's own piecewise-linear height at [param at]: bilinear cell
## lookup with the cell split along the (x+1, z) → (x, z+1) diagonal, exactly
## as terrain_chunk.gd builds it.
func _mesh_height(settings: TerrainSettings, at: Vector2) -> float:
	var cell: float = settings.cell_size
	var gx: float = at.x / cell
	var gz: float = at.y / cell
	var ix: float = floorf(gx)
	var iz: float = floorf(gz)
	var u: float = gx - ix
	var v: float = gz - iz
	var h00: float = settings.get_surface_height(Vector2(ix * cell, iz * cell))
	var h10: float = settings.get_surface_height(Vector2((ix + 1.0) * cell, iz * cell))
	var h01: float = settings.get_surface_height(Vector2(ix * cell, (iz + 1.0) * cell))
	var h11: float = settings.get_surface_height(Vector2((ix + 1.0) * cell, (iz + 1.0) * cell))
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


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
