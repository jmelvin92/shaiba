extends SceneTree
## Phase 6.5 piece 2's quality gate as a runnable script.
##
## Default mode, headless:
##   Godot --headless --path . --script res://tools/verify_cycle.gd
## asserts: a standalone desert_environment reproduces the committed 16:00
## golden-hour light exactly (autoloads don't run under --script, so this is
## also the no-Game fallback test); a full-day sweep at 0.005 h steps has no
## discontinuity in sun direction, colors or energy; fog color equals the sky
## horizon color at every step (the Phase 4 horizon-melt contract); the sun is
## never lit below the horizon; sun and moon are never both lit; and the
## night_darkness rungs order night luminance and moon energy monotonically.
##
## Perf mode, run windowed:
##   Godot --path . --script res://tools/verify_cycle.gd -- --perf
## streams the real world with a fast clock (full day in ~24 s) so the sky
## re-renders continuously, and prints average fps / worst frame over 600
## frames for comparison against the Phase 6 baseline (119 fps, worst 8.55 ms).

const SWEEP_STEP: float = 0.005
## Per-SWEEP_STEP continuity bounds, far above the real rates (sun direction
## moves ~0.09°/step at its fastest) but far below anything visible as a pop.
const MAX_SUN_STEP_DEG: float = 0.5
const MAX_COLOR_STEP: float = 0.02
const MAX_ENERGY_STEP: float = 0.05
const DARKNESS_RUNGS: Array[float] = [0.0, 0.35, 0.65, 1.0]

## The committed pre-cycle Sun basis (desert_environment.tscn before piece 2).
const CAL_BASIS: Basis = Basis(
	Vector3(0.866025, 0.0, 0.5),
	Vector3(0.321394, 0.766044, -0.55667),
	Vector3(-0.383022, 0.642788, 0.663414))

var _failures: PackedStringArray = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	if OS.get_cmdline_user_args().has("--perf"):
		await _perf()
	else:
		await _run()
	print("")
	if _failures.is_empty():
		print("verify_cycle: all checks passed")
		quit(0)
	else:
		for line: String in _failures:
			print("FAIL  " + line)
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _make_environment() -> DesertEnvironment:
	var env: DesertEnvironment = (
		load("res://scenes/world/desert_environment.tscn") as PackedScene
	).instantiate() as DesertEnvironment
	root.add_child(env)
	return env


func _run() -> void:
	await process_frame
	_golden_hour_reproduction()
	_fog_shape()
	_full_day_sweep()
	_darkness_rungs()


## The haze is distance-only depth fog (Joshua's ladder pick, 2026-08-15) and
## must fully melt terrain before the ~350 m streaming edge at every hour —
## density 1.0 at depth_end < 350 guarantees it by construction, so the shape
## itself is the contract.
func _fog_shape() -> void:
	var env: DesertEnvironment = _make_environment()
	var environment: Environment = _environment_of(env)
	_check(environment.fog_enabled, "fog is disabled")
	_check(environment.fog_mode == Environment.FOG_MODE_DEPTH,
		"fog_mode is %d, wanted depth" % environment.fog_mode)
	_check(is_equal_approx(environment.fog_density, 1.0),
		"depth-fog density %.2f — under 1.0 the streaming edge shows through" % environment.fog_density)
	_check(environment.fog_depth_end <= 350.0,
		"fog_depth_end %.0f m reaches past the streaming edge" % environment.fog_depth_end)
	_check(environment.fog_depth_begin < environment.fog_depth_end,
		"fog_depth_begin %.0f m is not before end %.0f m" % [
			environment.fog_depth_begin, environment.fog_depth_end])
	env.free()


## Standalone (no Game): the scene must hold the committed 16:00 light.
func _golden_hour_reproduction() -> void:
	var env: DesertEnvironment = _make_environment()
	var sun: DirectionalLight3D = env.get_node("Sun") as DirectionalLight3D
	var basis_err: float = 0.0
	for axis: int in 3:
		basis_err = maxf(basis_err, (sun.basis[axis] - CAL_BASIS[axis]).length())
	_check(basis_err < 0.002, "16:00 sun basis is off by %.4f" % basis_err)
	_check(is_equal_approx(sun.light_energy, 1.2), "16:00 sun energy %.3f, wanted 1.2" % sun.light_energy)
	_check(sun.light_color.is_equal_approx(Color("FFE9C4")), "16:00 sun color %s" % sun.light_color)
	var sky: ProceduralSkyMaterial = _sky_of(env)
	var environment: Environment = _environment_of(env)
	_check(sky.sky_top_color.is_equal_approx(Color(0.560784, 0.721569, 0.788235)),
		"16:00 sky top %s" % sky.sky_top_color)
	_check(sky.sky_horizon_color.is_equal_approx(Color(1, 0.937255, 0.839216)),
		"16:00 sky horizon %s" % sky.sky_horizon_color)
	_check(sky.ground_bottom_color.is_equal_approx(Color(0.768627, 0.568627, 0.305882)),
		"16:00 ground bottom %s" % sky.ground_bottom_color)
	_check(environment.fog_light_color.is_equal_approx(Color(1, 0.937255, 0.839216)),
		"16:00 fog color %s" % environment.fog_light_color)
	var moon: DirectionalLight3D = env.get_node("Moon") as DirectionalLight3D
	_check(not moon.visible and moon.light_energy == 0.0, "16:00 moon is lit")
	env.free()


## Fine-step full-day sweep: continuity + the standing contracts.
func _full_day_sweep() -> void:
	var env: DesertEnvironment = _make_environment()
	var sun: DirectionalLight3D = env.get_node("Sun") as DirectionalLight3D
	var moon: DirectionalLight3D = env.get_node("Moon") as DirectionalLight3D
	var sky: ProceduralSkyMaterial = _sky_of(env)
	var environment: Environment = _environment_of(env)

	var prev_dir: Vector3 = Vector3.ZERO
	var prev_energy: float = -1.0
	var prev_horizon: Color = Color.BLACK
	var prev_top: Color = Color.BLACK
	var worst_sun_step: float = 0.0
	var worst_color_step: float = 0.0
	var worst_energy_step: float = 0.0
	var steps: int = int(24.0 / SWEEP_STEP)
	for i: int in steps + 1:
		var h: float = fposmod(float(i) * SWEEP_STEP, 24.0)
		env.apply_time(h)
		if not environment.fog_light_color.is_equal_approx(sky.sky_horizon_color):
			_check(false, "fog color detached from sky horizon at %.3f h" % h)
			break
		var elevation: float = -sun.rotation_degrees.x
		if sun.light_energy > 0.0:
			_check(elevation > -0.01, "sun lit at elevation %.2f° (%.3f h)" % [elevation, h])
		if sun.light_energy > 0.01 and moon.light_energy > 0.01:
			_check(false, "sun and moon both lit at %.3f h" % h)
			break
		var dir: Vector3 = -sun.basis.z
		if i > 0 and sun.visible:
			if prev_dir != Vector3.ZERO:
				worst_sun_step = maxf(worst_sun_step, rad_to_deg(prev_dir.angle_to(dir)))
			worst_energy_step = maxf(worst_energy_step, absf(sun.light_energy - prev_energy))
		if i > 0:
			worst_color_step = maxf(worst_color_step, _color_step(prev_horizon, sky.sky_horizon_color))
			worst_color_step = maxf(worst_color_step, _color_step(prev_top, sky.sky_top_color))
		prev_dir = dir if sun.visible else Vector3.ZERO
		prev_energy = sun.light_energy
		prev_horizon = sky.sky_horizon_color
		prev_top = sky.sky_top_color
	_check(worst_sun_step < MAX_SUN_STEP_DEG,
		"sun direction jumped %.3f° in one step (bound %.1f°)" % [worst_sun_step, MAX_SUN_STEP_DEG])
	_check(worst_color_step < MAX_COLOR_STEP,
		"sky color jumped %.4f in one step (bound %.2f)" % [worst_color_step, MAX_COLOR_STEP])
	_check(worst_energy_step < MAX_ENERGY_STEP,
		"sun energy jumped %.4f in one step (bound %.2f)" % [worst_energy_step, MAX_ENERGY_STEP])
	print("sweep: worst sun step %.3f°, color step %.4f, energy step %.4f" % [
		worst_sun_step, worst_color_step, worst_energy_step])
	env.free()


## Deeper night_darkness must mean darker night sky and dimmer moon.
func _darkness_rungs() -> void:
	var env: DesertEnvironment = _make_environment()
	var sky: ProceduralSkyMaterial = _sky_of(env)
	var moon: DirectionalLight3D = env.get_node("Moon") as DirectionalLight3D
	var prev_lum: float = INF
	var prev_moon: float = INF
	for rung: float in DARKNESS_RUNGS:
		env.night_darkness = rung
		env.apply_time(23.0)
		var lum: float = sky.sky_horizon_color.get_luminance()
		_check(lum < prev_lum, "night luminance not monotonic at darkness %.2f" % rung)
		_check(moon.light_energy < prev_moon, "moon energy not monotonic at darkness %.2f" % rung)
		prev_lum = lum
		prev_moon = moon.light_energy
	env.free()


func _color_step(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func _sky_of(env: DesertEnvironment) -> ProceduralSkyMaterial:
	return _environment_of(env).sky.sky_material as ProceduralSkyMaterial


func _environment_of(env: DesertEnvironment) -> Environment:
	return (env.get_node("WorldEnvironment") as WorldEnvironment).environment


## Windowed: the real world streaming while a fast clock sweeps the whole day.
func _perf() -> void:
	# Use the real autoload when it's there (it does run under --script);
	# a second node named "Game" would be auto-renamed and ignored.
	var clock: Node = root.get_node_or_null(^"/root/Game")
	if clock == null:
		clock = (load("res://autoload/game.gd") as GDScript).new()
		clock.name = "Game"
		root.add_child(clock)
	clock.day_length_minutes = 0.4
	var level: Node3D = (
		load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for i: int in 240:
		await physics_frame
	var frames: int = 600
	var worst_ms: float = 0.0
	var start_usec: int = Time.get_ticks_usec()
	var last_usec: int = start_usec
	for i: int in frames:
		await process_frame
		var now: int = Time.get_ticks_usec()
		worst_ms = maxf(worst_ms, float(now - last_usec) / 1000.0)
		last_usec = now
	var total_s: float = float(last_usec - start_usec) / 1000000.0
	print("perf: %.0f fps average, worst frame %.2f ms over %d frames (full day each 24 s)" % [
		float(frames) / total_s, worst_ms, frames])
	level.free()
