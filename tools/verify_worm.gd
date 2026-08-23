extends SceneTree
## The Phase 6.8 Part 1 quality gate as an executable. Drives the real worm
## through the real desert and checks what an eye cannot judge reliably:
##
##   - dormant means dormant: no physics processing, no deformation passes —
##     the worm's presence in world.tscn costs exactly nothing;
##   - the real F7 InputMap binding summons it (injected key event);
##   - raise marks land in the deformation texture's B channel where the worm
##     actually swam, and write NOTHING into the print channels (R, G);
##   - a press stamp likewise writes nothing into the mound channel —
##     the two systems are provably isolated;
##   - the wandering path never violates a guardrail: never into the sea,
##     never onto the homestead pad, never through sand too shallow to hide
##     in (asserted with a curvature tolerance below the steering targets);
##   - the mound settles to zero after passage and the system returns to
##     idle — the zero-cost-when-quiet contract extends to the worm;
##   - pass cost stays inside the Phase 5 budget with the mound churning.
##
## Texture readback needs the real renderer: run *without* --headless and
## keep the window visible (macOS stops drawing occluded windows):
##
##   Godot --path . --script res://tools/verify_worm.gd

## Steering aims for sand >= 0.5 m; the worm turns along arcs, so brief dips
## below the target are legitimate. This is the hard floor a violation of
## which means the guardrails are broken, not merely curving.
const HARD_MIN_SAND: float = 0.30

var _failures: int = 0
var _marks: Array[Dictionary] = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	if _failures == 0:
		print("verify_worm: ALL CHECKS PASSED")
	else:
		print("verify_worm: %d FAILURES" % _failures)
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
	var sand: SandDeformation = level.find_child(
		"SandDeformation", true, false
	) as SandDeformation
	var worm: SandWorm = level.find_child("SandWorm", true, false) as SandWorm
	var terrain: TerrainSettings = (
		level.find_child("ChunkManager", true, false) as ChunkManager
	).get_terrain()
	# Wind drift migrates all content off the exact points these checks probe;
	# verify_prints tests it, everything here runs with drift off.
	sand.wind_drift_per_minute = 0.0
	worm.raised.connect(
		func(at: Vector2, _r: float, _s: float, _a: float, _st: float) -> void:
			_marks.append({"at": at, "time": Time.get_ticks_msec()})
	)
	for _i: int in range(90):
		await physics_frame

	await _check_dormant(sand, worm)
	await _check_summon_via_input(worm)
	await _check_marks_land(sand, worm)
	await _check_body_follows(worm, terrain)
	await _check_breach(worm, terrain)
	await _check_channel_isolation(sand, worm)
	await _check_guardrails(worm, terrain)
	await _check_settle_and_idle(sand, worm)

	print("pass cost: worst %.3f ms over %d passes" % [
		sand.worst_pass_ms, sand.passes_run
	])
	_check(
		sand.worst_pass_ms < 1.0, "pass cost under the Phase 5 budget",
		"worst %.3f ms" % sand.worst_pass_ms
	)


## Reads one channel of the deformation texture at a world position:
## 0 = press (R), 1 = wet (G), 2 = mound (B). -1.0 off-region.
func _channel_at(sand: SandDeformation, world_xz: Vector2, channel: int) -> float:
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
	var pixel: Color = image.get_pixelv(px)
	return [pixel.r, pixel.g, pixel.b][channel]


func _check_dormant(sand: SandDeformation, worm: SandWorm) -> void:
	# Spawn seating leaves a landing splat on the 180 s print clock; flush it
	# the verify_prints way so the zero-cost window measures the worm alone.
	var fade_before: float = sand.fade_seconds
	sand.fade_seconds = 30.0
	Engine.time_scale = 20.0
	var settle_frames: int = 0
	while not sand.is_idle() and settle_frames < 4200:
		settle_frames += 1
		await physics_frame
	Engine.time_scale = 1.0
	sand.fade_seconds = fade_before
	_check(sand.is_idle(), "pre-worm content flushes to idle")
	var passes_before: int = sand.passes_run
	for _i: int in range(120):
		await physics_frame
	_check(not worm.is_active(), "worm starts dormant")
	_check(
		not worm.is_physics_processing(),
		"dormant worm does no physics processing"
	)
	_check(
		sand.passes_run == passes_before,
		"dormant worm schedules no deformation passes",
		"%d passes appeared" % (sand.passes_run - passes_before)
	)


func _check_summon_via_input(worm: SandWorm) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_F7
	press.pressed = true
	Input.parse_input_event(press)
	await physics_frame
	await physics_frame
	_check(worm.is_active(), "F7 summons the worm (real InputMap binding)")
	# The rest of the run wants a close worm with fresh marks: orbit tightly.
	worm.dismiss()
	worm.summon(SandWorm.Mode.ORBIT)
	_check(worm.is_active(), "summon(ORBIT) succeeds near the player spawn")


func _check_marks_land(sand: SandDeformation, worm: SandWorm) -> void:
	_marks.clear()
	var waited: int = 0
	while _marks.size() < 8 and waited < 60 * 20:
		waited += 1
		await physics_frame
	_check(_marks.size() >= 8, "swimming emits travel-gated raise marks",
		"%d marks in %d ticks" % [_marks.size(), waited])
	if _marks.size() < 8:
		return
	# Let the queued marks render, then probe a recent one — old enough to be
	# flushed, young enough (< ~2 s) that settle has only nibbled at it.
	for _i: int in range(30):
		await physics_frame
	var probe: Vector2 = _marks[_marks.size() - 3]["at"]
	var mound: float = _channel_at(sand, probe, 2)
	_check(
		mound > 0.25, "raise mark reads back from the mound channel",
		"B = %.3f at %s" % [mound, probe]
	)
	var press: float = _channel_at(sand, probe, 0)
	var wet: float = _channel_at(sand, probe, 1)
	_check(
		press < 0.005 and wet < 0.005,
		"raise mark writes nothing into the print channels",
		"R = %.3f G = %.3f" % [press, wet]
	)
	# Off the worm's path the sand must stay untouched: probe well aside of
	# every recorded mark.
	var aside: Vector2 = probe + Vector2(0.0, 12.0)
	for mark: Dictionary in _marks:
		var at: Vector2 = mark["at"]
		if aside.distance_to(at) < 6.0:
			aside = probe + Vector2(12.0, 0.0)
			break
	var stray: float = _channel_at(sand, aside, 2)
	_check(
		stray < 0.005, "sand off the path stays unmounded",
		"B = %.3f at %s" % [stray, aside]
	)


## World position of a named bone, from the driven skeleton.
func _bone_world(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone: int = skeleton.find_bone(bone_name)
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	)


## Part 2: the rigged body must trail the head along the path — bones spaced
## like the rig contract says, every one of them under the sand while the
## worm swims level.
func _check_body_follows(worm: SandWorm, terrain: TerrainSettings) -> void:
	var skeleton: Skeleton3D = worm.get_skeleton()
	_check(skeleton != null, "the rigged body is found and driven")
	if skeleton == null:
		return
	# Let the orbit put real curvature into the path first.
	for _i: int in range(60 * 3):
		await physics_frame
	var worst_spacing_error: float = 0.0
	var worst_above: float = -INF
	for k: int in range(16):
		var at: Vector3 = _bone_world(skeleton, "spine_%02d" % k)
		if k > 0:
			var previous: Vector3 = _bone_world(skeleton, "spine_%02d" % (k - 1))
			var expected: float = 1.6 if k == 1 else 1.45
			worst_spacing_error = maxf(
				worst_spacing_error,
				absf(at.distance_to(previous) - expected) / expected
			)
		var ground: float = terrain.get_surface_height(Vector2(at.x, at.z))
		worst_above = maxf(worst_above, at.y - ground)
	_check(
		worst_spacing_error < 0.25,
		"spine bones hold the rig's segment spacing along the path",
		"worst error %.0f%%" % (worst_spacing_error * 100.0)
	)
	_check(
		worst_above < 0.5, "the whole body swims under the sand",
		"a bone reached %.2f m above the surface" % worst_above
	)
	_check(
		_bone_world(skeleton, "spine_00").distance_to(worm.global_position) < 0.2,
		"the head bone rides the agent's position"
	)


## Part 2: a breach (via the real F9 binding) sends the head above the
## surface with the mouth opening, throws sand at both crossings, and ends
## back in clean level swimming.
func _check_breach(worm: SandWorm, terrain: TerrainSettings) -> void:
	var skeleton: Skeleton3D = worm.get_skeleton()
	if skeleton == null:
		return
	var bursts_before: int = worm.bursts_fired
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_F9
	press.pressed = true
	Input.parse_input_event(press)
	await physics_frame
	await physics_frame
	_check(worm.is_breaching(), "F9 starts a breach (real InputMap binding)")
	var peak: float = -INF
	var mouth_peak: float = 0.0
	var guard: int = 0
	while worm.is_breaching() and guard < 60 * 20:
		guard += 1
		await physics_frame
		var head: Vector3 = _bone_world(skeleton, "spine_00")
		peak = maxf(
			peak,
			head.y - terrain.get_surface_height(Vector2(head.x, head.z))
		)
		mouth_peak = maxf(mouth_peak, worm.get_mouth_open())
	_check(not worm.is_breaching(), "the breach ends on its own")
	_check(
		peak > worm.breach_apex * 0.5, "the head clears the surface",
		"peak %.1f m vs apex %.1f m" % [peak, worm.breach_apex]
	)
	_check(
		mouth_peak > 0.5, "the mouth opens at the top of the arc",
		"opened %.2f" % mouth_peak
	)
	_check(
		worm.bursts_fired - bursts_before >= 2,
		"sand bursts at the exit and entry crossings",
		"%d bursts" % (worm.bursts_fired - bursts_before)
	)
	for _i: int in range(60):
		await physics_frame
	var head_after: Vector3 = _bone_world(skeleton, "spine_00")
	var ground_after: float = terrain.get_surface_height(
		Vector2(head_after.x, head_after.z)
	)
	_check(
		head_after.y < ground_after, "the head is back under the sand after"
	)


func _check_channel_isolation(sand: SandDeformation, worm: SandWorm) -> void:
	worm.dismiss()
	# A plain dry press stamp on quiet sand must never touch the mound channel.
	var player: Player = root.find_child("Player", true, false) as Player
	var spot: Vector2 = Vector2(
		player.global_position.x + 3.0, player.global_position.z + 3.0
	)
	sand.stamp(spot, 0.3, 0.9)
	for _i: int in range(20):
		await physics_frame
	var press: float = _channel_at(sand, spot, 0)
	var mound: float = _channel_at(sand, spot, 2)
	_check(press > 0.5, "control press stamp lands", "R = %.3f" % press)
	_check(
		mound < 0.005, "press stamp writes nothing into the mound channel",
		"B = %.3f" % mound
	)


func _check_guardrails(worm: SandWorm, terrain: TerrainSettings) -> void:
	# A long wander, sampled every tick, sped up — the path logic is pure so
	# time scale changes nothing but the wait.
	worm.summon(SandWorm.Mode.WANDER)
	Engine.time_scale = 4.0
	var worst_sand: float = INF
	var worst_water: float = 0.0
	var worst_pad: float = INF
	var pad_limit: float = terrain.homestead_radius + terrain.homestead_blend
	for _i: int in range(60 * 45):
		await physics_frame
		var at: Vector2 = Vector2(worm.global_position.x, worm.global_position.z)
		worst_sand = minf(worst_sand, terrain.get_sand_depth(at))
		worst_water = maxf(worst_water, terrain.get_water_depth(at))
		worst_pad = minf(
			worst_pad, at.distance_to(terrain.get_homestead_center())
		)
	Engine.time_scale = 1.0
	print("guardrails over 45 s wander: sand min %.2f m, water max %.2f m, homestead min %.1f m" % [
		worst_sand, worst_water, worst_pad
	])
	_check(
		worst_sand >= HARD_MIN_SAND, "wander stays in swimmable sand",
		"dipped to %.2f m" % worst_sand
	)
	_check(
		worst_water == 0.0, "wander never enters the sea",
		"water depth %.2f m" % worst_water
	)
	_check(
		worst_pad >= pad_limit, "wander keeps off the homestead pad",
		"came within %.1f m (limit %.1f)" % [worst_pad, pad_limit]
	)


func _check_settle_and_idle(sand: SandDeformation, worm: SandWorm) -> void:
	var last: Vector2 = (
		_marks[_marks.size() - 1]["at"] if not _marks.is_empty() else Vector2.ZERO
	)
	worm.dismiss()
	_check(not worm.is_physics_processing(), "dismissed worm stops processing")
	# Compress the wait the way verify_prints does: everything (the control
	# print included) fades fast, then the system must be flat and idle.
	print("accelerating settle and waiting for idle…")
	sand.fade_seconds = 30.0  # export clamp minimum; compressed by time_scale
	Engine.time_scale = 20.0
	var waited: int = 0
	while not sand.is_idle() and waited < 4200:
		waited += 1
		await physics_frame
	Engine.time_scale = 1.0
	for _i: int in range(10):
		await physics_frame
	_check(sand.is_idle(), "deformation returns to idle after the worm leaves")
	if last != Vector2.ZERO:
		var mound: float = _channel_at(sand, last, 2)
		_check(
			mound < 0.005, "the last mound settles to zero", "B = %.3f" % mound
		)
	var passes_before: int = sand.passes_run
	for _i: int in range(120):
		await physics_frame
	_check(
		sand.passes_run == passes_before,
		"no passes run once the mound has settled",
		"%d passes appeared" % (sand.passes_run - passes_before)
	)
