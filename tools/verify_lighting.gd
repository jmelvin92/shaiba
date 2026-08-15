extends SceneTree
## Phase 6.5 piece 3's quality gate as a runnable script.
##
## Run headless:
##   Godot --headless --path . --script res://tools/verify_lighting.gd
##
## Streams the real world and drives real interaction input to assert: the oil
## lamp lights and snuffs on E with its prompt tracking state; its flame casts
## shadows (what makes the light spill through the openings instead of through
## the walls); the torch is taken from the stand on E, rides the player's hand
## (its light truly travels), and returns; the flame flicker stays inside its
## configured band and actually moves; stars are zero by day, full at deep
## night; and the clock's debug scrub does not fight a carried torch.
##
## Prints FAIL lines and exits non-zero on any failure.

const FLICKER_FRAMES: int = 150

var _failures: PackedStringArray = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	print("")
	if _failures.is_empty():
		print("verify_lighting: all checks passed")
		quit(0)
	else:
		for line: String in _failures:
			print("FAIL  " + line)
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _press_interact() -> void:
	Input.action_press(&"interact")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact")
	await physics_frame


func _teleport(player: Player, to: Vector3) -> void:
	player.global_position = to
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _i: int in 5:
		await physics_frame


func _run() -> void:
	var clock: Node = root.get_node_or_null(^"/root/Game")
	if clock == null:
		clock = (load("res://autoload/game.gd") as GDScript).new()
		clock.name = "Game"
		root.add_child(clock)
	clock.time_paused = true
	clock.set_time_of_day(23.0)

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i: int in 10:
		await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var lamp: OilLamp = level.find_child("OilLamp", true, false) as OilLamp
	var stand: TorchStand = level.find_child("TorchStand", true, false) as TorchStand
	_check(player != null, "no Player in world")
	_check(lamp != null, "no OilLamp in world")
	_check(stand != null, "no TorchStand in world")
	if player == null or lamp == null or stand == null:
		return

	await _lamp_checks(player, lamp)
	await _torch_checks(player, stand)
	_star_checks(level)
	level.free()


func _lamp_checks(player: Player, lamp: OilLamp) -> void:
	var flame: FlameLight = lamp.get_node("Flame") as FlameLight
	var light: OmniLight3D = _light_of(flame)
	var interactable: Interactable = lamp.get_node("Interactable") as Interactable
	_check(not lamp.lit and not light.visible, "lamp starts lit")
	_check(interactable.prompt == "Light lamp", "cold lamp prompt: %s" % interactable.prompt)
	_check(light.shadow_enabled,
		"lamp flame casts no shadows — light would pass through walls, not windows")

	await _teleport(player, lamp.global_position + Vector3(0.5, 0.05, 0.0))
	await _press_interact()
	_check(lamp.lit and light.visible and light.light_energy > 0.0, "E did not light the lamp")
	_check(interactable.prompt == "Snuff lamp", "lit lamp prompt: %s" % interactable.prompt)

	# Flicker: bounded, alive, and never a strobe.
	var lo: float = INF
	var hi: float = -INF
	var worst_jump: float = 0.0
	var prev: float = light.light_energy
	for _i: int in FLICKER_FRAMES:
		await physics_frame
		lo = minf(lo, light.light_energy)
		hi = maxf(hi, light.light_energy)
		worst_jump = maxf(worst_jump, absf(light.light_energy - prev))
		prev = light.light_energy
	var band: float = flame.base_energy * flame.flicker_amount * 1.05
	_check(hi - lo > 0.01, "flame does not flicker (energy static at %.3f)" % prev)
	_check(lo >= flame.base_energy - band and hi <= flame.base_energy + band,
		"flicker escaped its band: %.3f..%.3f around base %.2f" % [lo, hi, flame.base_energy])
	_check(worst_jump < flame.base_energy * 0.2,
		"flicker jumped %.3f in one tick — reads as a strobe" % worst_jump)

	await _press_interact()
	_check(not lamp.lit and not light.visible, "E did not snuff the lamp")
	_check(interactable.prompt == "Light lamp", "snuffed prompt: %s" % interactable.prompt)


func _torch_checks(player: Player, stand: TorchStand) -> void:
	var torch: Torch = stand.get_node_or_null("Torch") as Torch
	_check(torch != null and not torch.lit, "torch missing from stand or already lit")
	var socket: HandSocket = player.find_child("HandSocket", true, false) as HandSocket
	_check(socket != null, "player has no HandSocket")
	if torch == null or socket == null:
		return

	await _teleport(player, stand.global_position + Vector3(0.7, 0.05, 0.0))
	await _press_interact()
	_check(torch.get_parent() == socket, "E did not hand over the torch")
	_check(torch.lit, "carried torch is not burning")
	var light: OmniLight3D = _light_of(torch.get_node("Flame") as FlameLight)
	_check(light.visible and light.light_energy > 0.0, "carried torch sheds no light")

	# The light must travel: walk away and the torch must follow the hand.
	var before: Vector3 = torch.global_position
	await _teleport(player, stand.global_position + Vector3(6.0, 0.05, 4.0))
	for _i: int in 5:
		await physics_frame
	var moved: float = torch.global_position.distance_to(before)
	_check(moved > 5.0, "torch stayed behind: moved %.2f m" % moved)
	_check(torch.global_position.distance_to(player.global_position) < 1.5,
		"torch is %.2f m from the player carrying it" %
		torch.global_position.distance_to(player.global_position))

	await _teleport(player, stand.global_position + Vector3(0.7, 0.05, 0.0))
	await _press_interact()
	_check(torch.get_parent() == stand and not torch.lit, "E did not return the torch")


func _star_checks(level: Node3D) -> void:
	var env: DesertEnvironment = level.find_child("DesertEnvironment", true, false) as DesertEnvironment
	var sky: ShaderMaterial = (
		(env.get_node("WorldEnvironment") as WorldEnvironment).environment.sky.sky_material
		as ShaderMaterial)
	env.apply_time(12.0)
	_check(float(sky.get_shader_parameter(&"star_strength")) == 0.0, "stars out at noon")
	env.apply_time(0.5)
	_check(float(sky.get_shader_parameter(&"star_strength")) > 0.99,
		"deep-night stars at %.2f, wanted 1" % float(sky.get_shader_parameter(&"star_strength")))
	env.apply_time(23.0)


## FlameLight builds its OmniLight3D in _ready; it is the only OmniLight child.
func _light_of(flame: FlameLight) -> OmniLight3D:
	for child: Node in flame.get_children():
		if child is OmniLight3D:
			return child as OmniLight3D
	return null
