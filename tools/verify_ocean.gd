extends SceneTree
## Phase 6.7's quality gate as a runnable script (pattern: tools/verify_terrain.gd).
##
## Run headless:
##   Godot --headless --path . --script res://tools/verify_ocean.gd
##
## Analytic checks on the coast field — no scene needed: the shoreline sits
## where Joshua's pick put it (mean coast_distance west of the homestead, ±
## the wander), it is deterministic per seed, a wadeable knee-deep band exists
## along the whole audited shore, the seabed actually reaches its deep depth,
## no dry-land point anywhere inland dips below sea level (the no-flooding
## invariant the water plane relies on), the swash band reads wet and dry in
## the right places, every coast-manufactured slope stays under the 31°
## budget, and the desert far from the coast is bit-identical to a world with
## the coast disabled.
##
## The windowed wading check (the knee-deep stop against the real controller)
## lives in --wade mode, driven the way verify_prints drives the live game.
##
## Prints FAIL lines and exits non-zero on any failure.

const SETTINGS_PATH: String = "res://resources/terrain/desert.tres"
const SLOPE_LIMIT_DEG: float = 31.0
## Shore span, metres of coastline north-south around the homestead's
## latitude, that the transect audits sweep.
const SHORE_SPAN: float = 400.0
## The player's knee-deep wading limit the transect audit checks a usable
## band for (mirrors player.gd's wade_depth_limit default).
const WADE_LIMIT: float = 0.4

var _failures: PackedStringArray = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	print("")
	if _failures.is_empty():
		print("verify_ocean: all checks passed")
		quit(0)
	else:
		for line: String in _failures:
			print("FAIL  " + line)
		quit(1)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_coast_exists()
		_determinism()
		_shoreline_placement()
		_transect_audit()
		_no_inland_flooding()
		_wetness_shape()
		_desert_untouched()
		return
	if args.has("--wade"):
		await _wade()
		return
	if args.has("--wetprints"):
		await _wet_prints()
		return
	if args.has("--perf"):
		await _perf()
		return
	push_error("verify_ocean: unknown mode %s" % " ".join(args))
	_failures.append("unknown mode: " + " ".join(args))


## Drives the real player into the real sea in the real world scene: walking
## west wades in and is held gently at the knee limit without jitter, walking
## the surf line stays free, and walking east comes straight back ashore.
func _wade() -> void:
	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await process_frame
	await process_frame

	var player: Player = level.get_node(^"Player") as Player
	var chunks: ChunkManager = level.get_node(^"ChunkManager") as ChunkManager
	var ocean: Ocean = level.get_node(^"Ocean") as Ocean
	var terrain: TerrainSettings = chunks.get_terrain()
	if not terrain.has_coast():
		_fail("wade: the live world has no coast")
		return
	if ocean == null or not ocean.visible:
		_fail("wade: the Ocean node is missing or hidden in a coastal world")
		return
	if absf(ocean.global_position.y - terrain.get_sea_level()) > 0.01:
		_fail(
			"wade: the sea surface sits at %.2f, not sea level %.2f"
			% [ocean.global_position.y, terrain.get_sea_level()]
		)

	# Start on the dry beach at the homestead's latitude, facing out to sea.
	var z: float = terrain.get_homestead_center().y
	var shore_x: float = _waterline_x(terrain, z)
	var start: Vector2 = Vector2(shore_x + 6.0, z)
	player.global_position = Vector3(
		start.x, terrain.get_surface_height(start) + 0.1, start.y
	)
	player.reset_physics_interpolation()
	chunks.set_tracked(player)
	# "up" now points west (-X): straight into the sea.
	player.set_view_yaw(PI / 2.0)

	Engine.time_scale = 6.0
	Input.action_press("move_up")
	var deepest: float = 0.0
	var trail: PackedVector3Array = []
	for frame: int in range(60 * 30):
		await physics_frame
		deepest = maxf(deepest, player.get_water_depth())
		if frame >= 60 * 24:
			trail.append(player.global_position)
	Input.action_release("move_up")

	if deepest < 0.3:
		_fail("wade: 30 s of walking west never reached knee depth (%.2f m)" % deepest)
	if deepest > player.wade_depth_limit + 0.06:
		_fail(
			"wade: carried past the limit — %.2f m against %.2f"
			% [deepest, player.wade_depth_limit]
		)
	# What must hold still at the boundary is the *cross-shore* position — the
	# component pushing out to sea. Sliding along an obliquely-met shoreline is
	# the soft wall working as intended, so tangential drift is free.
	var anchor: Vector2 = Vector2(trail[0].x, trail[0].z)
	var probe: float = 0.75
	var deeper: Vector2 = Vector2(
		terrain.get_water_depth(anchor + Vector2(probe, 0.0))
			- terrain.get_water_depth(anchor - Vector2(probe, 0.0)),
		terrain.get_water_depth(anchor + Vector2(0.0, probe))
			- terrain.get_water_depth(anchor - Vector2(0.0, probe))
	).normalized()
	var cross_drift: float = 0.0
	var tangent_drift: float = 0.0
	for point: Vector3 in trail:
		var offset: Vector2 = Vector2(point.x, point.z) - anchor
		cross_drift = maxf(cross_drift, absf(offset.dot(deeper)))
		tangent_drift = maxf(tangent_drift, absf(offset.dot(Vector2(-deeper.y, deeper.x))))
	print(
		"wade: deepest %.2f m (limit %.2f); at the boundary: cross-shore drift %.2f m, along-shore %.2f m"
		% [deepest, player.wade_depth_limit, cross_drift, tangent_drift]
	)
	if cross_drift > 0.5:
		_fail("wade: player bobs across the wading limit (%.2f m cross-shore drift)" % cross_drift)

	# Along the surf line the sea must not hold you at all.
	var before: Vector3 = player.global_position
	Input.action_press("move_left")
	for _frame: int in range(60 * 6):
		await physics_frame
	Input.action_release("move_left")
	var along: float = before.distance_to(player.global_position)
	print("wade: 6 s along the waterline covered %.1f m" % along)
	if along < 4.0:
		_fail("wade: walking along the waterline only covered %.1f m in 6 s" % along)

	# And it lets you straight back out.
	Input.action_press("move_down")
	for _frame: int in range(60 * 8):
		await physics_frame
	Input.action_release("move_down")
	if player.get_water_depth() > 0.0:
		_fail(
			"wade: could not walk back ashore (still in %.2f m of water)"
			% player.get_water_depth()
		)
	Engine.time_scale = 1.0
	level.queue_free()
	await process_frame


## Windowed (needs a real renderer for the SubViewport readback): a print
## stamped on the wet swash band must outlive one stamped on the dry beach —
## the G-channel decay class doing its job on the real terrain.
func _wet_prints() -> void:
	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await process_frame
	await process_frame

	var player: Player = level.get_node(^"Player") as Player
	var chunks: ChunkManager = level.get_node(^"ChunkManager") as ChunkManager
	var sand: SandDeformation = level.get_node(^"SandDeformation") as SandDeformation
	var terrain: TerrainSettings = chunks.get_terrain()
	var z: float = terrain.get_homestead_center().y
	var shore_x: float = _waterline_x(terrain, z)
	player.global_position = Vector3(
		shore_x + 8.0, terrain.get_surface_height(Vector2(shore_x + 8.0, z)) + 0.1, z
	)
	player.reset_physics_interpolation()
	chunks.set_tracked(player)
	# Fixed-point probes: wind drift must be off (the documented rule).
	sand.wind_drift_per_minute = 0.0
	sand.fade_seconds = 30.0
	for _i: int in range(30):
		await physics_frame

	var wet_at: Vector2 = Vector2(shore_x + 0.3, z + 10.0)
	var dry_at: Vector2 = Vector2(shore_x + 18.0, z - 10.0)
	var wet_w: float = terrain.get_wetness(wet_at)
	var dry_w: float = terrain.get_wetness(dry_at)
	print("wetprints: wetness %.2f at the waterline, %.2f up the beach" % [wet_w, dry_w])
	if wet_w < 0.7:
		_fail("wetprints: the waterline stamp point reads %.2f wet, wanted > 0.7" % wet_w)
	if dry_w > 0.05:
		_fail("wetprints: the dry-beach stamp point reads %.2f wet, wanted ~0" % dry_w)
	# The beach takes a full print: its normalised depth clears the shader's
	# print cap (alpha × tone_full/print_full ≥ 1).
	var cap: float = terrain.get_normalized_depth(dry_at) * (
		terrain.tone_full_depth / sand.print_full_depth
	)
	if cap < 1.0:
		_fail("wetprints: beach print cap %.2f — prints there would be faint" % cap)

	sand.stamp(wet_at, 0.4, 1.0)
	sand.stamp(dry_at, 0.4, 1.0)
	for _i: int in range(10):
		await physics_frame

	Engine.time_scale = 10.0
	for _i: int in range(60 * 20):
		await physics_frame
	Engine.time_scale = 1.0

	var wet_left: float = _value_at(sand, wet_at)
	var dry_left: float = _value_at(sand, dry_at)
	print(
		"wetprints: after 20 s of a 30 s fade — wet print %.2f, dry print %.2f"
		% [wet_left, dry_left]
	)
	if dry_left > 0.55:
		_fail("wetprints: the dry print barely decayed (%.2f)" % dry_left)
	if wet_left < dry_left + 0.25:
		_fail(
			"wetprints: the wet print (%.2f) does not meaningfully outlive the dry one (%.2f)"
			% [wet_left, dry_left]
		)
	level.queue_free()
	await process_frame


## Windowed: frame cost with the full ocean vista on screen — player on the
## beach, camera west over the water, 600 frames measured (the verify_cycle
## --perf pattern). The gate asks for 60 fps+; the baseline elsewhere is ~120.
func _perf() -> void:
	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await process_frame
	await process_frame
	var player: Player = level.get_node(^"Player") as Player
	var chunks: ChunkManager = level.get_node(^"ChunkManager") as ChunkManager
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var terrain: TerrainSettings = chunks.get_terrain()
	var z: float = terrain.get_homestead_center().y
	var shore_x: float = _waterline_x(terrain, z)
	player.global_position = Vector3(
		shore_x + 10.0, terrain.get_surface_height(Vector2(shore_x + 10.0, z)) + 0.1, z
	)
	player.reset_physics_interpolation()
	chunks.set_tracked(player)
	rig.set_yaw_degrees(90.0)
	rig.snap_to_target()
	for _i: int in range(240):
		await process_frame

	var worst_ms: float = 0.0
	var total_us: int = 0
	var last: int = Time.get_ticks_usec()
	for _i: int in range(600):
		await process_frame
		var now: int = Time.get_ticks_usec()
		var frame_us: int = now - last
		last = now
		total_us += frame_us
		worst_ms = maxf(worst_ms, float(frame_us) / 1000.0)
	var fps: float = 600.0 / (float(total_us) / 1_000_000.0)
	print("perf: %.0f fps average over 600 frames, worst frame %.2f ms" % [fps, worst_ms])
	if fps < 60.0:
		_fail("perf: %.0f fps with the ocean on screen — under the 60 fps gate" % fps)
	level.queue_free()
	await process_frame


## Reads the deformation R value at a world position (verify_prints pattern).
func _value_at(sand: SandDeformation, world_xz: Vector2) -> float:
	var state: Dictionary = sand.get_debug_state()
	var origin: Vector2 = state["origin"]
	var image: Image = (state["texture"] as ViewportTexture).get_image()
	var uv: Vector2 = (world_xz - origin) / sand.region_size
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return -1.0
	var px: Vector2i = Vector2i(
		clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1),
		clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1)
	)
	return image.get_pixelv(px).r


func _fail(message: String) -> void:
	_failures.append(message)


func _world_seed() -> int:
	var game: Node = root.get_node_or_null(^"/root/Game")
	if game != null:
		return game.world_seed
	return 20260813


func _fresh_settings(seed_value: int, coast: bool = true) -> TerrainSettings:
	var settings: TerrainSettings = (load(SETTINGS_PATH) as TerrainSettings).duplicate(true)
	if not coast:
		settings.coast_distance = 0.0
	settings.setup(seed_value)
	return settings


## The waterline x at a given z, found by bisecting the surface across sea
## level between well-inland and well-out-to-sea brackets.
func _waterline_x(settings: TerrainSettings, z: float) -> float:
	var centre: Vector2 = settings.get_homestead_center()
	var lo: float = centre.x - settings.coast_distance - settings.coast_wiggle - 30.0
	var hi: float = centre.x - settings.coast_distance + settings.coast_wiggle + 30.0
	for _i: int in range(48):
		var mid: float = (lo + hi) * 0.5
		if settings.get_surface_height(Vector2(mid, z)) >= settings.sea_level:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


func _coast_exists() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	if not settings.has_coast():
		_fail("coast: has_coast() is false with coast_distance %.1f" % settings.coast_distance)
	if settings.get_sea_level() > -3.1:
		_fail(
			"coast: sea_level %.2f is above the deepest possible desert hollow (-3.1)"
			% settings.get_sea_level()
		)
	var off: TerrainSettings = _fresh_settings(_world_seed(), false)
	if off.has_coast():
		_fail("coast: has_coast() is true with the coast disabled")
	if off.get_water_depth(Vector2(-10000.0, 0.0)) != 0.0:
		_fail("coast: disabled coast still reports water depth")


func _determinism() -> void:
	var seed_value: int = _world_seed()
	var a: TerrainSettings = _fresh_settings(seed_value)
	var b: TerrainSettings = _fresh_settings(seed_value)
	var centre: Vector2 = a.get_homestead_center()
	var mismatches: int = 0
	for i: int in range(64):
		var z: float = centre.y + (float(i) / 63.0 - 0.5) * SHORE_SPAN
		var at: Vector2 = Vector2(centre.x - a.coast_distance - 40.0, z)
		if a.get_surface_height(at) != b.get_surface_height(at):
			mismatches += 1
		if a.get_shore_distance(at) != b.get_shore_distance(at):
			mismatches += 1
	if mismatches > 0:
		_fail("determinism: %d coast samples differ between same-seed runs" % mismatches)
	var other: TerrainSettings = _fresh_settings(seed_value + 1)
	var same: int = 0
	for i: int in range(16):
		var z: float = float(i) * 25.0
		if is_equal_approx(
			a.get_shore_distance(Vector2(0.0, z)), other.get_shore_distance(Vector2(0.0, z))
		):
			same += 1
	if same == 16:
		_fail("determinism: a different seed produced an identical shoreline")


func _shoreline_placement() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var centre: Vector2 = settings.get_homestead_center()
	var worst_err: float = 0.0
	for i: int in range(33):
		var z: float = centre.y + (float(i) / 32.0 - 0.5) * SHORE_SPAN
		var x: float = _waterline_x(settings, z)
		# The waterline must sit at coast_distance ± the wander from the
		# homestead's x, and the analytic shore distance must agree with the
		# bisected crossing to within the wave of drift patchiness.
		var err: float = absf(settings.get_shore_distance(Vector2(x, z)))
		worst_err = maxf(worst_err, err)
		var from_home: float = centre.x - x
		var slack: float = settings.coast_wiggle + 4.0
		if from_home < settings.coast_distance - slack or from_home > settings.coast_distance + slack:
			_fail(
				"shoreline: waterline at z %.0f sits %.1f m from the homestead (wanted %.0f ± %.0f)"
				% [z, from_home, settings.coast_distance, slack]
			)
	print("shoreline: analytic-vs-bisected worst error %.2f m" % worst_err)
	if worst_err > 3.0:
		_fail("shoreline: get_shore_distance disagrees with the surface by %.2f m" % worst_err)


## Walks straight west-east transects across the coast: slopes stay under the
## budget, water depth grows monotonically enough to reach the deep, and a
## usable knee-deep wading band exists on every one.
func _transect_audit() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var centre: Vector2 = settings.get_homestead_center()
	var worst_slope: float = 0.0
	var worst_at: Vector2 = Vector2.ZERO
	var narrowest_wade: float = INF
	var deep_reached: float = INF
	for i: int in range(17):
		var z: float = centre.y + (float(i) / 16.0 - 0.5) * SHORE_SPAN
		var shore_x: float = _waterline_x(settings, z)
		var wade_band: float = 0.0
		var wade_found: bool = false
		# From 220 m inland to the deep water, at half-metre steps.
		var x: float = shore_x + 220.0
		var prev: float = settings.get_surface_height(Vector2(x, z))
		while x > shore_x - settings.seabed_deep_distance - 60.0:
			x -= 0.5
			var h: float = settings.get_surface_height(Vector2(x, z))
			var slope: float = rad_to_deg(atan(absf(h - prev) / 0.5))
			if slope > worst_slope:
				worst_slope = slope
				worst_at = Vector2(x, z)
			prev = h
			var depth: float = maxf(settings.sea_level - h, 0.0)
			if depth > 0.0 and depth <= WADE_LIMIT:
				wade_band += 0.5
			if depth > WADE_LIMIT:
				wade_found = true
		narrowest_wade = minf(narrowest_wade, wade_band)
		if not wade_found:
			_fail("transect z %.0f: water never exceeds the wade limit" % z)
		deep_reached = minf(
			deep_reached,
			settings.get_water_depth(
				Vector2(shore_x - settings.seabed_deep_distance - 40.0, z)
			)
		)
	print(
		"transects: worst slope %.2f deg at (%.0f, %.0f); narrowest wade band %.1f m; deep water >= %.1f m"
		% [worst_slope, worst_at.x, worst_at.y, narrowest_wade, deep_reached]
	)
	if worst_slope >= SLOPE_LIMIT_DEG:
		_fail(
			"transects: slope %.2f deg at (%.0f, %.0f) exceeds the %.0f deg budget"
			% [worst_slope, worst_at.x, worst_at.y, SLOPE_LIMIT_DEG]
		)
	if narrowest_wade < 1.5:
		_fail("transects: narrowest knee-deep wading band is only %.1f m" % narrowest_wade)
	if deep_reached < settings.seabed_deep_depth * 0.6:
		_fail(
			"transects: water %.1f m at the deep distance — seabed never reaches its depth"
			% deep_reached
		)


## No dry land below sea level anywhere inland: the water plane covers the
## whole map at sea_level, so any inland dip under it would flood.
func _no_inland_flooding() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 617
	var flooded: int = 0
	var lowest: float = INF
	for _i: int in range(60000):
		var at: Vector2 = Vector2(
			rng.randf_range(-2000.0, 2000.0), rng.randf_range(-2000.0, 2000.0)
		)
		if settings.get_shore_distance(at) < 2.0:
			continue
		var h: float = settings.get_surface_height(at)
		lowest = minf(lowest, h)
		if h < settings.sea_level:
			flooded += 1
	print("flooding: lowest inland surface %.2f m vs sea level %.2f" % [lowest, settings.sea_level])
	if flooded > 0:
		_fail("flooding: %d inland samples sit below sea level" % flooded)


func _wetness_shape() -> void:
	var settings: TerrainSettings = _fresh_settings(_world_seed())
	var centre: Vector2 = settings.get_homestead_center()
	if settings.get_wetness(centre) != 0.0:
		_fail("wetness: the homestead reads wet")
	var z: float = centre.y
	var shore_x: float = _waterline_x(settings, z)
	var under: float = settings.get_wetness(Vector2(shore_x - 10.0, z))
	if under < 0.999:
		_fail("wetness: underwater sand reads %.2f, wanted 1.0" % under)
	var at_line: float = settings.get_wetness(Vector2(shore_x + 0.2, z))
	var mid_band: float = settings.get_wetness(Vector2(shore_x + 4.0, z))
	if at_line <= mid_band:
		_fail(
			"wetness: swash band does not dry inland (%.2f at the line, %.2f 4 m up)"
			% [at_line, mid_band]
		)


## The desert away from the coast is bit-identical to a coastless world — the
## proof that Phase 6.7 added a biome without touching the one Joshua approved.
func _desert_untouched() -> void:
	var seed_value: int = _world_seed()
	var with_coast: TerrainSettings = _fresh_settings(seed_value)
	var without: TerrainSettings = _fresh_settings(seed_value, false)
	var centre: Vector2 = with_coast.get_homestead_center()
	if centre != without.get_homestead_center():
		_fail("desert: the coast moved the homestead site")
	# Everything from the homestead eastward (and the whole desert north/south
	# of it at those longitudes) must match exactly; the audit starts at the
	# pad centre, which is itself comfortably east of the coast's reach only
	# for sand — base/tone reach ends at beach_width, so start the strict
	# audit just east of the ceiling's provable no-op line.
	var free_x: float = centre.x - with_coast.coast_distance + 240.0
	var mismatches: int = 0
	for j: int in range(48):
		for i: int in range(48):
			var at: Vector2 = Vector2(
				free_x + float(i) * 9.0, centre.y - 216.0 + float(j) * 9.0
			)
			if with_coast.get_surface_height(at) != without.get_surface_height(at):
				mismatches += 1
			if with_coast.get_sand_depth(at) != without.get_sand_depth(at):
				mismatches += 1
			if with_coast.get_normalized_depth(at) != without.get_normalized_depth(at):
				mismatches += 1
	if mismatches > 0:
		_fail(
			"desert: %d samples east of the coast's reach differ from a coastless world"
			% mismatches
		)
