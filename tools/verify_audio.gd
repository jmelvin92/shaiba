extends SceneTree
## Phase 6.6 quality gate as an executable (headless):
##
##   Godot --headless --path . --script res://tools/verify_audio.gd
##
## Asserts the audio system's structure and logic with ZERO sound files
## present — silent-safe is part of the gate. What it checks:
##   1. Bus layout: Music/Ambience/SFX/Interior exist, Interior sends to SFX
##      and carries reverb, Ambience carries the muffle low-pass.
##   2. Listener: rides at the player's position, turns with the camera yaw.
##   3. Footsteps: surface resolution answers "packed" on the courtyard pad,
##      "sand" on a deep drift, "stone" on the house ground floor, "wood" on
##      the upper storey; loudness orders run > walk; the sneak shuffle logic
##      arms and disarms; the stamper's plant signal is wired through.
##   4. AcousticZone: stepping inside the house closes the ambience low-pass
##      and ducks the bus; stepping out restores both.
##   5. Ambience: the day/night crossfade weight is anchored right at key
##      hours and monotonic through dusk.
##
## The whole run doubles as the silent-safety assertion: any error or warning
## from a missing sound file fails the gate by definition.

const WORLD_SCENE: String = "res://scenes/world/world.tscn"

var _world: Node3D = null
var _player: Player = null
var _rig: CameraRig = null
var _house: Node3D = null
var _footsteps: FootstepAudio = null
var _terrain: TerrainSettings = null

var _frame: int = 0
var _failures: int = 0
## Frame at which the current wait ends and `_next` runs.
var _resume_at: int = 0
var _step: int = 0
var _deep_sand_xz: Vector2 = Vector2.ZERO


func _initialize() -> void:
	print("verify_audio: loading %s" % WORLD_SCENE)
	var packed: PackedScene = load(WORLD_SCENE)
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	_player = _world.get_node("Player") as Player
	_rig = _world.get_node("CameraRig") as CameraRig
	_house = _world.get_node("Homestead/House") as Node3D
	_footsteps = _player.get_node("FootstepAudio") as FootstepAudio
	var chunks: ChunkManager = _world.get_node("ChunkManager") as ChunkManager
	_terrain = chunks.get_terrain()


func _check(label: String, ok: bool) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


## Teleports the player and reseats them on the local surface.
func _teleport(to: Vector3) -> void:
	_player.global_position = to
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_rig.snap_to_target()


func _teleport_terrain(xz: Vector2) -> void:
	_teleport(Vector3(xz.x, _terrain.get_surface_height(xz) + 0.2, xz.y))


func _ambience_bus() -> int:
	return AudioServer.get_bus_index(&"Ambience")


func _lowpass() -> AudioEffectLowPassFilter:
	return AudioServer.get_bus_effect(_ambience_bus(), 0) as AudioEffectLowPassFilter


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < _resume_at:
		return false
	match _step:
		0:
			# Give the level a second to spawn, seat and settle.
			_wait(60)
		1:
			_check_buses()
			_check_listener_position()
			_rig.set_yaw_degrees(90.0)
			_wait(5)
		2:
			_check_listener_yaw()
			_check_footstep_logic()
			_check_courtyard_surface()
			_check_house_surfaces()
			_find_deep_sand()
			_wait(5)
		3:
			_teleport_terrain(_deep_sand_xz)
			_wait(150)
		4:
			_check_deep_sand_surface()
			# Into the house for the acoustic zone.
			_teleport(_house.to_global(Vector3(-0.5, 0.4, -2.0)))
			_wait(120)
		5:
			_check_zone_inside()
			_teleport(_house.to_global(Vector3(0.0, 0.3, -8.0)))
			_wait(120)
		6:
			_check_zone_outside()
			_check_ambience_weights()
			print("verify_audio: %s" % ("ALL PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
			quit(0 if _failures == 0 else 1)
	_step += 1
	return false


func _wait(frames: int) -> void:
	_resume_at = _frame + frames


func _check_buses() -> void:
	print("buses:")
	_check("5 buses loaded from default_bus_layout.tres", AudioServer.bus_count == 5)
	for wanted: StringName in [&"Music", &"Ambience", &"SFX", &"Interior"]:
		_check("bus '%s' exists" % wanted, AudioServer.get_bus_index(wanted) >= 0)
	var interior: int = AudioServer.get_bus_index(&"Interior")
	_check(
		"Interior sends to SFX", AudioServer.get_bus_send(interior) == &"SFX"
	)
	_check(
		"Interior carries reverb",
		AudioServer.get_bus_effect(interior, 0) is AudioEffectReverb
	)
	var lowpass: AudioEffectLowPassFilter = _lowpass()
	_check("Ambience carries the muffle low-pass", lowpass != null)
	_check(
		"low-pass rests open", lowpass != null and lowpass.cutoff_hz > 20000.0
	)


func _check_listener_position() -> void:
	print("listener:")
	var listener: AudioListener3D = _rig.get_node("Listener") as AudioListener3D
	_check("listener exists on the rig", listener != null)
	if listener == null:
		return
	var expected: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
	var off: float = listener.global_position.distance_to(expected)
	_check("listener rides the player (off by %.2f m)" % off, off < 0.6)


func _check_listener_yaw() -> void:
	var listener: AudioListener3D = _rig.get_node("Listener") as AudioListener3D
	if listener == null:
		return
	var yaw: float = fposmod(listener.global_rotation.y, TAU)
	_check(
		"listener turned with the camera (yaw %.1f deg)" % rad_to_deg(yaw),
		absf(yaw - deg_to_rad(90.0)) < 0.05
	)


func _check_footstep_logic() -> void:
	print("footsteps:")
	var here: Vector2 = Vector2(_player.global_position.x, _player.global_position.z)
	_footsteps.tick(0.016, 2.0, false, true)
	_footsteps.on_foot_planted(here)
	var walk_db: float = _footsteps.last_step_volume_db
	_footsteps.tick(0.016, 4.5, false, true)
	_footsteps.on_foot_planted(here)
	var run_db: float = _footsteps.last_step_volume_db
	_check(
		"run steps louder than walk steps (%.1f > %.1f dB)" % [run_db, walk_db],
		run_db > walk_db
	)
	_footsteps.tick(0.016, 1.0, true, true)
	_check("sneak shuffle arms while crouch-moving", _footsteps.is_shuffling())
	var shuffled_steps: int = _footsteps.steps_played
	_footsteps.on_foot_planted(here)
	_check(
		"crouched plants make no step sound", _footsteps.steps_played == shuffled_steps
	)
	_footsteps.tick(0.016, 0.0, true, true)
	_check("shuffle disarms at rest", not _footsteps.is_shuffling())
	_footsteps.tick(0.016, 0.0, false, true)
	var stamper: FootstepStamper = _player.get_node("FootstepStamper") as FootstepStamper
	_check(
		"stamper plant signal wired to footstep audio",
		stamper.foot_planted.get_connections().size() >= 1
	)


func _check_courtyard_surface() -> void:
	var here: Vector2 = Vector2(_player.global_position.x, _player.global_position.z)
	var depth: float = _terrain.get_sand_depth(here)
	var surface: String = _footsteps.resolve_surface(here)
	_check(
		"courtyard resolves 'packed' (depth %.2f m, got '%s')" % [depth, surface],
		surface == "packed"
	)


func _check_house_surfaces() -> void:
	var ground: Vector3 = _house.to_global(Vector3(-0.5, 0.4, -2.0))
	var upper: Vector3 = _house.to_global(Vector3(0.5, 3.45, -1.5))
	var was: Vector3 = _player.global_position
	_teleport(ground)
	var ground_surface: String = _footsteps.resolve_surface(Vector2(ground.x, ground.z))
	_teleport(upper)
	var upper_surface: String = _footsteps.resolve_surface(Vector2(upper.x, upper.z))
	_teleport(was)
	_check(
		"house ground floor resolves 'stone' (got '%s')" % ground_surface,
		ground_surface == "stone"
	)
	_check(
		"upper storey resolves 'wood' (got '%s')" % upper_surface,
		upper_surface == "wood"
	)


func _find_deep_sand() -> void:
	var centre: Vector2 = Vector2(_player.global_position.x, _player.global_position.z)
	var best: Vector2 = centre
	var best_depth: float = -1.0
	for ring: int in range(4, 30):
		for spoke: int in range(12):
			var angle: float = TAU * float(spoke) / 12.0
			var at: Vector2 = centre + Vector2(cos(angle), sin(angle)) * float(ring) * 5.0
			var depth: float = _terrain.get_sand_depth(at)
			if depth > best_depth:
				best_depth = depth
				best = at
		if best_depth > 0.6:
			break
	print("deep sand probe: depth %.2f m at %s" % [best_depth, best])
	_check("found a genuinely deep drift to test on", best_depth > 0.3)
	_deep_sand_xz = best


func _check_deep_sand_surface() -> void:
	var surface: String = _footsteps.resolve_surface(_deep_sand_xz)
	_check("deep drift resolves 'sand' (got '%s')" % surface, surface == "sand")


func _check_zone_inside() -> void:
	print("acoustic zone:")
	var lowpass: AudioEffectLowPassFilter = _lowpass()
	if lowpass == null:
		_check("low-pass reachable", false)
		return
	_check(
		"indoors closes the ambience low-pass (%.0f Hz)" % lowpass.cutoff_hz,
		lowpass.cutoff_hz < 2000.0
	)
	_check(
		"indoors ducks the ambience bus (%.1f dB)"
		% AudioServer.get_bus_volume_db(_ambience_bus()),
		AudioServer.get_bus_volume_db(_ambience_bus()) < -4.0
	)


func _check_zone_outside() -> void:
	var lowpass: AudioEffectLowPassFilter = _lowpass()
	if lowpass == null:
		return
	_check(
		"outdoors reopens the low-pass (%.0f Hz)" % lowpass.cutoff_hz,
		lowpass.cutoff_hz > 19000.0
	)
	_check(
		"outdoors restores the ambience bus (%.1f dB)"
		% AudioServer.get_bus_volume_db(_ambience_bus()),
		AudioServer.get_bus_volume_db(_ambience_bus()) > -0.5
	)


func _check_ambience_weights() -> void:
	print("ambience crossfade:")
	var ambience: Ambience = _world.get_node("Ambience") as Ambience
	_check("ambience node present in world", ambience != null)
	if ambience == null:
		return
	_check("noon is pure day", is_equal_approx(ambience.day_weight(12.0), 1.0))
	_check("midnight is pure night", is_zero_approx(ambience.day_weight(0.0)))
	_check("16:00 golden hour is pure day", is_equal_approx(ambience.day_weight(16.0), 1.0))
	var previous: float = 1.1
	var monotonic: bool = true
	var hour: float = 17.5
	while hour <= 19.5:
		var weight: float = ambience.day_weight(hour)
		if weight > previous + 0.0001:
			monotonic = false
		previous = weight
		hour += 0.05
	_check("dusk fade is monotonic day-to-night", monotonic)
	_check(
		"mid-dusk is a genuine blend",
		ambience.day_weight(18.5) > 0.1 and ambience.day_weight(18.5) < 0.9
	)
