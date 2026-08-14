extends SceneTree
## Tuning ladder for the footprint look: stamps one synthetic trail (identical
## every rung), then re-screenshots it at each candidate value of print
## darkness and print depth — the display uniforms scale the same texture, so
## rungs differ in exactly one thing. Run without --headless:
##
##   Godot --path . --script res://tools/shoot_print_ladder.gd -- <outdir>

const DARKNESS_RUNGS: Array[float] = [0.30, 0.45, 0.55, 0.70]
const DEPTH_RUNGS: Array[float] = [0.06, 0.12, 0.20]

var _outdir: String = ""


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	await _run()
	quit(0)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <outdir>")
		return
	_outdir = args[0]
	DirAccess.make_dir_recursive_absolute(_outdir)

	var level: Node3D = (
		load("res://scenes/world/world.tscn") as PackedScene
	).instantiate() as Node3D
	root.add_child(level)
	await physics_frame
	var player: Player = level.find_child("Player", true, false) as Player
	var rig: CameraRig = level.find_child("CameraRig", true, false) as CameraRig
	rig.zoom_distance = 14.0
	var sand: SandDeformation = level.find_child("SandDeformation", true, false) as SandDeformation
	sand.wind_drift_per_minute = 0.0
	var material: ShaderMaterial = load(
		"res://resources/terrain/sand_terrain_material.tres"
	) as ShaderMaterial
	for _i: int in range(90):
		await physics_frame

	# A gently curving trail walking toward the camera, so prints appear at
	# several distances in one frame, plus a landing splat beside it.
	var at: Vector2 = Vector2(player.global_position.x, player.global_position.z) + Vector2(0.8, -9.0)
	var heading: float = PI * 0.5  # toward +z, toward the camera
	var left: bool = false
	for i: int in range(40):
		heading += 0.02 * sin(float(i) * 0.35)
		var forward: Vector2 = Vector2(cos(heading), sin(heading))
		var side: Vector2 = Vector2(-forward.y, forward.x)
		at += forward * 0.37
		left = not left
		sand.stamp(
			at + side * (0.14 if left else -0.14), 0.16, 0.85, forward.angle(), 1.8
		)
	sand.stamp(at + Vector2(1.2, -3.0), 0.5, 1.0)
	for _i: int in range(30):
		await physics_frame

	for value: float in DARKNESS_RUNGS:
		material.set_shader_parameter("deform_tint_strength", value)
		await _capture("darkness_%02d" % int(value * 100.0))
	material.set_shader_parameter("deform_tint_strength", sand.tint_strength)

	for value: float in DEPTH_RUNGS:
		material.set_shader_parameter("deform_strength", value)
		await _capture("depth_%02d" % int(value * 100.0))
	material.set_shader_parameter("deform_strength", sand.max_print_depth)


func _capture(shot_name: String) -> void:
	for _i: int in range(10):
		await physics_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)
