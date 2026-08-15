extends SceneTree
## Screenshots a prop .glb in the real desert, at the real gameplay camera.
##
##   Godot --path . --script res://tools/shoot_prop.gd -- \
##       <outdir> <glb[,glb...]> [name] [count] [spread]
##
## Several comma-separated paths shoot as one mixed scatter, which is the only
## honest way to judge a *set* — a rock reads differently beside its siblings
## than it does alone.
##
## Blender's Workbench previews (the `--render` flag on the build scripts) are
## for proportion and silhouette against a grey card. They cannot answer the
## question ART_DIRECTION's checklist actually asks — does this thing sit in
## *our* sand, under *our* warm sun, at 19 deg and 23 m — so every asset gets
## shot here before it is called done.
##
## Needs a visible window: macOS stops drawing occluded ones and the capture
## would hang on frame_post_draw (CLAUDE.md), so run it *without* --headless.
##
## Nothing here is placed permanently — the instances live only for the shot.
## Where props really go in the world is map work, not asset work.

const SETTLE_FRAMES: int = 40

var _outdir: String = ""
var _props: Array[PackedScene] = []
var _label: String = "prop"
var _planted: int = 0
## How many to scatter, and over what radius. Small scatter props need a field;
## a landmark needs a handful.
var _count: int = 4
var _spread: float = 7.0


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	quit(0)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <outdir> <res://path.glb[,...]> [name]")
		return
	_outdir = args[0]
	for path: String in args[1].split(",", false):
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			push_error("could not load %s" % path)
			return
		_props.append(packed)
	_label = args[2] if args.size() > 2 else args[1].get_file().get_basename()
	if args.size() > 3:
		_count = int(args[3])
	if args.size() > 4:
		_spread = float(args[4])
	DirAccess.make_dir_recursive_absolute(_outdir)

	var level: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await physics_frame

	var player: Player = level.find_child("Player", true, false) as Player
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	var house: House = level.find_child("House", true, false) as House
	var terrain: TerrainSettings = manager.get_terrain()

	# Long settle: the window has to reach the foreground before the first
	# capture, and the chunks under these positions have to finish building.
	for _i: int in range(120):
		await physics_frame

	var home: Vector3 = house.global_position

	# A grove out on open sand, well clear of the homestead pad, so the palm is
	# judged against dunes rather than against the one flat spot in the world.
	var grove_at: Vector2 = Vector2(home.x + 46.0, home.z - 30.0)
	# Deterministic scatter: a handful of big props reads as a grove, and a
	# field of small ones is the only way to judge scatter texture at all.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260814
	for i: int in range(_count):
		var angle: float = rng.randf() * TAU
		var reach: float = _spread * sqrt(rng.randf())
		_plant(
			level, terrain,
			grove_at + Vector2(cos(angle), sin(angle)) * reach,
			rng.randf() * 360.0,
			rng.randf_range(0.78, 1.25),
		)

	# And a pair by the house, which is the cohesion check: one style, one
	# palette, the new asset next to the one we already approved.
	var side: Vector3 = house.global_transform.basis.x
	var front: Vector3 = -house.global_transform.basis.z
	var by_house: Array[Vector2] = [
		Vector2(home.x, home.z) + Vector2(side.x, side.z) * 7.5 + Vector2(front.x, front.z) * 3.0,
		Vector2(home.x, home.z) + Vector2(side.x, side.z) * 9.4 + Vector2(front.x, front.z) * -2.4,
	]
	_plant(level, terrain, by_house[0], 205.0, 1.0)
	_plant(level, terrain, by_house[1], 33.0, 0.9)
	for _i: int in range(30):
		await physics_frame

	# Standing among them, looking into the grove.
	var among: Vector2 = grove_at + Vector2(-7.0, -9.5)
	await _shoot(player, rig, terrain, among, grove_at, "grove")

	# Close up beside one, with the player in frame for scale.
	var beside: Vector2 = grove_at + Vector2(-4.0, -4.2)
	await _shoot(player, rig, terrain, beside, grove_at, "scale")

	# Far enough back that the whole tree is in frame against the dunes.
	var far: Vector2 = grove_at + Vector2(-16.0, -19.0)
	await _shoot(player, rig, terrain, far, grove_at, "silhouette")

	# The cohesion shot: palms and house together.
	var at_house: Vector2 = Vector2(home.x, home.z) + Vector2(front.x, front.z) * 17.0 \
		+ Vector2(side.x, side.z) * 7.0
	await _shoot(player, rig, terrain, at_house, Vector2(home.x, home.z), "homestead")


func _plant(
	level: Node3D, terrain: TerrainSettings, at: Vector2, yaw: float, scale: float
) -> void:
	# Cycle the set so a scatter mixes every variant rather than repeating one.
	var node: Node3D = _props[_planted % _props.size()].instantiate() as Node3D
	_planted += 1
	level.add_child(node)
	node.global_position = Vector3(at.x, terrain.get_surface_height(at), at.y)
	node.rotation.y = deg_to_rad(yaw)
	node.scale = Vector3.ONE * scale


func _shoot(
	player: Player, rig: CameraRig, terrain: TerrainSettings,
	from: Vector2, look_at: Vector2, shot: String
) -> void:
	rig.set_yaw_degrees(rad_to_deg(atan2(-(look_at.x - from.x), -(look_at.y - from.y))))
	player.global_position = Vector3(from.x, terrain.get_surface_height(from) + 0.2, from.y)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	rig.snap_to_target()
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s_%s.png" % [_label, shot])
	image.save_png(path)
	print("saved ", path)
