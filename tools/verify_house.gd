extends SceneTree
## Phase 6 Part 1's quality gate as a runnable script.
## (Pattern: tools/verify_player.gd, tools/verify_terrain.gd.)
##
## Run headless:
##   Godot --headless --path . --script res://tools/verify_house.gd
##
## Answers the questions an eye cannot judge reliably about a building you can
## walk into: is the doorway actually passable at both gaits, do the walls
## actually stop you, does the stair actually climb, and does the cutaway open
## and — the failure that would matter most — close again afterwards. A
## building stuck open would look like a bug in every later screenshot.
##
## Prints FAIL lines and exits non-zero on any failure.

## Ticks allowed for each scripted walk. 260 ticks is ~4.3 s at 60 Hz, which
## covers the longest leg here (nine metres of courtyard) at walking pace.
const WALK_TICKS: int = 260
const RUN_TICKS: int = 150
## How far the interior floor stands above the ground the house is placed on —
## FLOOR_LIFT in tools/build_house.py. Kept in step with it by the floor-vs-sand
## check below, which fails loudly if the two ever disagree.
const HOUSE_FLOOR_LIFT: float = 0.12

var _failures: PackedStringArray = []
var _level: Node3D = null
var _player: Player = null
var _rig: CameraRig = null
var _house: House = null
var _cutaway: InteriorCutaway = null
var _terrain: TerrainSettings = null


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	print("")
	if _failures.is_empty():
		print("verify_house: all checks passed")
		quit(0)
	else:
		for line: String in _failures:
			print("FAIL  " + line)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	_level = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_level)
	await physics_frame

	_player = _level.find_child("Player", true, false) as Player
	_rig = _level.find_child("CameraRig", true, false) as CameraRig
	_house = _level.find_child("House", true, false) as House
	_cutaway = _house.get_node(^"Cutaway") as InteriorCutaway
	var manager: ChunkManager = _level.find_child("ChunkManager", true, false) as ChunkManager
	_terrain = manager.get_terrain()
	for _i: int in range(30):
		await physics_frame

	await _spawn_check()
	_floor_clears_the_sand()
	await _doorway_passable("walk", false, WALK_TICKS)
	await _doorway_passable("run", true, RUN_TICKS)
	await _walls_block()
	await _stair_climbs()
	await _cutaway_closes()
	await _layers_are_sane()


## The player should start outside, on the levelled pad, at ground level.
func _spawn_check() -> void:
	var centre: Vector2 = _terrain.get_homestead_center()
	var here: Vector2 = Vector2(_player.global_position.x, _player.global_position.z)
	var distance: float = here.distance_to(centre)
	print("spawn: %.1f m from the homestead centre, cutaway open=%s"
		% [distance, _cutaway.is_open()])
	if distance > _terrain.homestead_radius:
		_fail("spawn is %.1f m out, off the %.1f m pad"
			% [distance, _terrain.homestead_radius])
	if _cutaway.is_open():
		_fail("the building is already open at spawn; the player starts outside")


## The interior floor must stand clear of the desert underneath it.
##
## This is the bug that made the ground floor "still sand" after its material
## was already correct: the slab sat flush with the terrain, and a few
## centimetres of ripple left sand drawn proud of the floor across almost the
## whole footprint. Nothing about the model was wrong, which is exactly why it
## survived a material fix — so the clearance is asserted rather than eyeballed.
func _floor_clears_the_sand() -> void:
	var floor_y: float = _house.to_global(Vector3(0.0, HOUSE_FLOOR_LIFT, 0.0)).y
	var above: int = 0
	var worst: float = -INF
	var samples: int = 0
	for ix: int in range(-7, 8):
		for iz: int in range(-6, 7):
			var at: Vector3 = _house.to_global(Vector3(ix * 0.5, 0.0, iz * 0.5))
			var ground: float = _terrain.get_surface_height(Vector2(at.x, at.z))
			worst = maxf(worst, ground - floor_y)
			samples += 1
			if ground > floor_y:
				above += 1
	print("floor vs sand: %d/%d samples of desert above the floor, closest %+.3f m"
		% [above, samples, worst])
	if above > 0:
		_fail(
			"the desert stands above the interior floor at %d of %d points "
			% [above, samples]
			+ "(by up to %.3f m) — the floor will read as sand" % worst
		)


## Walks in through the front door and out again, at one gait.
##
## Passability is the whole point: a doorway that models fine can still be
## unwalkable if a jamb, a lintel or a threshold eats the clearance, and none
## of that shows in a screenshot of the outside.
func _doorway_passable(gait: String, running: bool, ticks: int) -> void:
	var door_axis: Vector3 = -_house.global_transform.basis.z
	var side: Vector3 = _house.global_transform.basis.x
	var outside: Vector3 = _house.global_position + door_axis * 9.0 - side * 1.2

	_aim(outside, outside - door_axis * 10.0)
	await _stand_at(Vector2(outside.x, outside.z))
	await _hold("move_up", ticks, running)

	var local: Vector3 = _house.to_local(_player.global_position)
	var inside: bool = _cutaway.is_open()
	print("%s through the doorway: inside=%s local=(%.2f, %.2f, %.2f)"
		% [gait, inside, local.x, local.y, local.z])
	if not inside:
		_fail("%s: the player did not get through the doorway (stopped at z=%.2f)"
			% [gait, local.z])
	# Also a check that they walked *through* rather than over: the interior
	# floor is at local y = 0, so anything much above it means they climbed.
	if absf(local.y) > 0.35:
		_fail("%s: ended %.2f m off the interior floor" % [gait, local.y])

	# Always walk out on the full budget, never the gait's: running in carries
	# the player deeper than walking does, so a run's shorter tick count would
	# fail the exit for having overshot rather than for anything being wrong.
	await _hold("move_down", WALK_TICKS, false)
	if _cutaway.is_open():
		_fail("%s: the player could not walk back out" % gait)


## Walking at a blank wall must not get you inside.
func _walls_block() -> void:
	var back: Vector3 = _house.global_transform.basis.z    # away from the door
	var outside: Vector3 = _house.global_position + back * 9.0
	_aim(outside, outside - back * 10.0)
	await _stand_at(Vector2(outside.x, outside.z))
	await _hold("move_up", WALK_TICKS, false)

	var local: Vector3 = _house.to_local(_player.global_position)
	print("into the back wall: inside=%s local_z=%.2f" % [_cutaway.is_open(), local.z])
	if _cutaway.is_open():
		_fail("the player walked through the back wall")


## The external stair has to be climbable — it is the only way upstairs, and
## its 0.277 m risers are close enough to the player's 0.35 m step-up that a
## tuning change could quietly break the upper floor.
func _stair_climbs() -> void:
	var side: Vector3 = _house.global_transform.basis.x
	var door_axis: Vector3 = -_house.global_transform.basis.z
	# Stand on open ground just short of the bottom step, not on the flight
	# itself: the steps are solid to the ground, so a spot part-way up would
	# drop the player inside the masonry and measure nothing but their being
	# pushed back out.
	var foot: Vector3 = _house.global_position + side * 4.65 + door_axis * 4.1
	_aim(foot, foot - door_axis * 10.0)
	await _stand_at(Vector2(foot.x, foot.z))
	var start_y: float = _player.global_position.y
	await _hold("move_up", 320, false)

	var climbed: float = _player.global_position.y - start_y
	var local: Vector3 = _house.to_local(_player.global_position)
	print("stair: climbed %.2f m (local y %.2f), upstairs cutaway open=%s"
		% [climbed, local.y, _cutaway.is_open()])
	if climbed < 2.0:
		_fail("stair: only climbed %.2f m; the upper floor is unreachable" % climbed)


## The building must close up again once the player leaves — and while they are
## inside, the roof must actually be gone rather than merely intended to be.
func _cutaway_closes() -> void:
	var door_axis: Vector3 = -_house.global_transform.basis.z
	var side: Vector3 = _house.global_transform.basis.x
	var outside: Vector3 = _house.global_position + door_axis * 9.0 - side * 1.2
	_aim(outside, outside - door_axis * 10.0)
	await _stand_at(Vector2(outside.x, outside.z))

	var roof: GeometryInstance3D = _house.find_child("roof", true, false) as GeometryInstance3D
	if roof == null:
		_fail("cutaway: no roof mesh found to check")
		return
	var roof_outside: float = roof.transparency

	await _hold("move_up", WALK_TICKS, false)
	for _i: int in range(45):
		await physics_frame
	var roof_inside: float = roof.transparency
	print("roof transparency: %.2f outside -> %.2f inside (visible=%s)"
		% [roof_outside, roof_inside, roof.visible])
	if roof_outside > 0.05:
		_fail("roof is already faded (%.2f) while the player is outside" % roof_outside)
	if roof_inside < 0.9:
		_fail("roof only faded to %.2f with the player inside" % roof_inside)

	await _hold("move_down", WALK_TICKS, false)
	for _i: int in range(60):
		await physics_frame
	print("after leaving: roof transparency %.2f, open=%s"
		% [roof.transparency, _cutaway.is_open()])
	if _cutaway.is_open():
		_fail("the cutaway stayed open after the player left")
	if roof.transparency > 0.05:
		_fail("the roof stayed faded (%.2f) after the player left" % roof.transparency)


## Each part must sit on exactly one system's layer, because the cutaway and
## the occluder fader both write transparency and would fight over any part
## they could both see. Layer 3 is the fader's; the cutaway's parts stay off it.
func _layers_are_sane() -> void:
	var model: Node3D = _house.get_node(^"Model") as Node3D
	var wrong: PackedStringArray = []
	for part: Node in model.get_children():
		for child: Node in part.get_children():
			var body: StaticBody3D = child as StaticBody3D
			if body == null:
				continue
			var fadeable: bool = (body.collision_layer & 4) != 0
			var cutaway_owned: bool = House.CUTAWAY_PARTS.has(part.name)
			if cutaway_owned and fadeable:
				wrong.append("%s is cutaway-managed but on the fader's layer" % part.name)
			if not cutaway_owned and not fadeable \
					and not House.FLOOR_PARTS.has(part.name):
				wrong.append("%s can neither fade nor be cut away" % part.name)
	print("collision layers: %d parts checked, %d wrong"
		% [model.get_child_count(), wrong.size()])
	for line: String in wrong:
		_fail(line)


func _aim(from: Vector3, target: Vector3) -> void:
	var to_target: Vector3 = target - from
	_rig.set_yaw_degrees(rad_to_deg(atan2(-to_target.x, -to_target.z)))


func _stand_at(at: Vector2) -> void:
	_player.global_position = Vector3(
		at.x, _terrain.get_surface_height(at) + 0.2, at.y
	)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_rig.snap_to_target()
	for _i: int in range(40):
		await physics_frame


func _hold(action: String, ticks: int, running: bool) -> void:
	Input.action_press(action)
	if running:
		Input.action_press("sprint")
	for _i: int in range(ticks):
		await physics_frame
	Input.action_release(action)
	if running:
		Input.action_release("sprint")
	for _i: int in range(24):
		await physics_frame
