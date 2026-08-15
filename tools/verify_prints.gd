extends SceneTree
## The Phase 5 quality gate as an executable. Drives the real player across
## the real desert and checks what an eye cannot judge reliably:
##
##   - every footfall stamp lands in the deformation texture where the toe
##     bone actually was, and nothing marks the sand off the trail;
##   - stamp cadence matches the gait (a plausible print count per metre);
##   - a jump's landing leaves its splat;
##   - prints survive the region recentring as the player walks on;
##   - decay really empties the texture and the system then goes idle —
##     passes stop, which is the "zero cost standing still" gate;
##   - the main-thread cost of a pass stays far under the 1 ms budget.
##
## Texture readback needs the real renderer: run *without* --headless and let
## the window stay visible (macOS stops drawing occluded windows):
##
##   Godot --path . --script res://tools/verify_prints.gd

var _failures: int = 0
var _stamps: Array[Dictionary] = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	if _failures == 0:
		print("verify_prints: ALL CHECKS PASSED")
	else:
		print("verify_prints: %d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _run() -> void:
	var level: Node3D = (
		load("res://scenes/world/world.tscn") as PackedScene
	).instantiate() as Node3D
	root.add_child(level)
	await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var sand: SandDeformation = level.find_child("SandDeformation", true, false) as SandDeformation
	# Wind drift deliberately migrates all prints downwind over time, which
	# would slowly move them off the exact points these checks probe. Test it
	# separately (_check_wind_drift); everything else runs with drift off.
	sand.wind_drift_per_minute = 0.0
	player.stamped.connect(
		func(at: Vector2, radius: float, strength: float, _angle: float, _stretch: float) -> void:
			_stamps.append({"at": at, "radius": radius, "strength": strength})
	)
	for _i: int in range(60):
		await physics_frame

	await _walk_and_check_alignment(player, sand)
	await _check_landing(player)
	await _check_recentre(player, sand)
	await _check_wind_drift(sand)
	await _check_decay_and_idle(sand)

	print("pass cost: worst %.3f ms over %d passes" % [sand.worst_pass_ms, sand.passes_run])
	_check(
		sand.worst_pass_ms < 1.0, "pass cost under budget",
		"worst %.3f ms" % sand.worst_pass_ms
	)


## Reads the deformation value at a world position, or -1.0 off-region.
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


func _walk_and_check_alignment(player: Player, sand: SandDeformation) -> void:
	print("walking 20 m and checking stamp alignment…")
	var from: Vector3 = player.global_position
	Input.action_press("move_up")
	var guard: int = 0
	while player.global_position.distance_to(from) < 20.0 and guard < 3000:
		guard += 1
		await physics_frame
	Input.action_release("move_up")
	for _i: int in range(30):
		await physics_frame

	var walked: Vector3 = player.global_position - from
	var direction: Vector2 = Vector2(walked.x, walked.z).normalized()
	# Footfalls only: drag stamps are deliberately faint (strength scales with
	# wade depth) and testing their readability would test the wrong thing.
	var foot_stamps: Array[Dictionary] = _stamps.filter(
		func(s: Dictionary) -> bool:
			return s["strength"] > 0.5 and s["strength"] < 1.0
	)
	_check(
		foot_stamps.size() >= 20 and foot_stamps.size() <= 120,
		"stamp cadence plausible for 20 m",
		"%d stamps" % foot_stamps.size()
	)

	var hits: int = 0
	for s: Dictionary in foot_stamps:
		if _value_at(sand, s["at"] as Vector2) > 0.1:
			hits += 1
	_check(
		foot_stamps.size() > 0 and hits >= foot_stamps.size() * 9 / 10,
		"prints landed where the feet were",
		"%d/%d readable" % [hits, foot_stamps.size()]
	)

	var side: Vector2 = Vector2(-direction.y, direction.x)
	var off_trail: Vector2 = Vector2(from.x, from.z) + direction * 10.0 + side * 4.0
	var clean: float = _value_at(sand, off_trail)
	_check(clean <= 0.02, "sand off the trail is unmarked", "value %.3f" % clean)


func _check_landing(player: Player) -> void:
	print("jumping…")
	var before: int = _stamps.size()
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for _i: int in range(90):
		await physics_frame
	var landed: bool = false
	for i: int in range(before, _stamps.size()):
		if _stamps[i]["strength"] >= 1.0:
			landed = true
	_check(landed, "landing left its splat")


func _check_recentre(player: Player, sand: SandDeformation) -> void:
	print("walking on to force recentres…")
	var probe: Vector2 = Vector2.ZERO
	for s: Dictionary in _stamps:
		if s["strength"] < 1.0:
			probe = s["at"] as Vector2
	var before: float = _value_at(sand, probe)
	var from: Vector3 = player.global_position
	Input.action_press("move_up")
	var guard: int = 0
	while player.global_position.distance_to(from) < 25.0 and guard < 3000:
		guard += 1
		await physics_frame
	Input.action_release("move_up")
	for _i: int in range(30):
		await physics_frame
	var after: float = _value_at(sand, probe)
	_check(
		before > 0.1 and after > before - 0.15,
		"prints survive region recentring",
		"before %.3f after %.3f" % [before, after]
	)


## Wind drift must move a mark downwind — in whole texels, so the mark's
## peak strength must survive the trip essentially undimmed.
func _check_wind_drift(sand: SandDeformation) -> void:
	print("checking wind drift…")
	var start: Vector2 = Vector2(sand._tracked.global_position.x, sand._tracked.global_position.z)
	sand.wind_drift_per_minute = 60.0  # 1 m/s, so a short wait shows real travel
	sand.stamp(start, 0.5, 1.0)
	for _i: int in range(150):
		await physics_frame
	sand.wind_drift_per_minute = 0.0

	var wind: Vector2 = sand._wind_direction
	var best: Vector2 = start
	var best_value: float = 0.0
	var probe_step: float = 0.125
	for i: int in range(0, int(4.0 / probe_step)):
		var at: Vector2 = start + wind * (float(i) * probe_step)
		var value: float = _value_at(sand, at)
		if value > best_value:
			best_value = value
			best = at
	var travelled: float = start.distance_to(best)
	_check(
		best_value > 0.7 and travelled > 1.0 and travelled < 4.0,
		"prints migrate downwind at the drift rate",
		"peak %.2f moved %.2f m" % [best_value, travelled]
	)


func _check_decay_and_idle(sand: SandDeformation) -> void:
	print("accelerating decay and waiting for idle…")
	sand.fade_seconds = 30.0  # export clamp minimum; compressed by time_scale
	Engine.time_scale = 20.0
	var guard: int = 0
	while not sand.is_idle() and guard < 4200:
		guard += 1
		await physics_frame
	Engine.time_scale = 1.0
	_check(sand.is_idle(), "system reaches idle after prints fade")

	var state: Dictionary = sand.get_debug_state()
	var image: Image = (state["texture"] as ViewportTexture).get_image()
	var peak: float = 0.0
	for y: int in range(0, image.get_height(), 8):
		for x: int in range(0, image.get_width(), 8):
			peak = maxf(peak, image.get_pixel(x, y).r)
	_check(peak <= 0.02, "texture fully refilled by decay", "peak %.3f" % peak)

	var passes_before: int = sand.passes_run
	for _i: int in range(120):
		await physics_frame
	_check(
		sand.passes_run == passes_before,
		"no passes while idle (zero standing cost)",
		"%d extra" % (sand.passes_run - passes_before)
	)
