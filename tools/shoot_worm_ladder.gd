extends SceneTree
## The Phase 6.8 size ladder: the sand worm at three candidate scales, shot
## at the real gameplay camera so Joshua can pick before the model is rigged.
##
## Each rung stages two shots on deep dune sand at golden hour:
##   - <rung>_mound:  the traveling wake alone — the sight players will
##     actually meet, at that worm's mound size;
##   - <rung>_breach: a placeholder segmented body (palette clay, no rig)
##     arcing out of the sand at the head of its wake — pure scale reference,
##     not the Part 2 breach animation.
## Plus mound_live: the real dormant-until-summoned worm swimming an orbit,
## caught mid-run — the gate's "the mound reads in motion" evidence.
##
## Runtime-only patches (mound height per rung) touch shader parameters, not
## committed values; everything is restored before exit. Needs a visible
## window; run *without* --headless:
##
##   Godot --path . --script res://tools/shoot_worm_ladder.gd -- <outdir>

const SETTLE_FRAMES: int = 45

## The three scales on offer: name, body length m, body diameter m, wake
## mound radius m, stamp spacing m, mound height m (raise-uniform patch).
const RUNGS: Array[Dictionary] = [
	{"name": "a_tremors", "length": 9.0, "dia": 1.3, "radius": 2.0,
		"spacing": 0.8, "height": 0.45},
	{"name": "b_greater", "length": 16.0, "dia": 2.2, "radius": 2.8,
		"spacing": 1.1, "height": 0.65},
	{"name": "c_titan", "length": 26.0, "dia": 3.4, "radius": 3.8,
		"spacing": 1.5, "height": 0.90},
]

var _outdir: String = ""
var _game: Node = null


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
	var manager: ChunkManager = level.find_child("ChunkManager", true, false) as ChunkManager
	var sand: SandDeformation = level.find_child("SandDeformation", true, false) as SandDeformation
	var worm: SandWorm = level.find_child("SandWorm", true, false) as SandWorm
	var terrain: TerrainSettings = manager.get_terrain()
	var material: ShaderMaterial = load(
		"res://resources/terrain/sand_terrain_material.tres"
	) as ShaderMaterial
	_game = root.get_node_or_null(^"/root/Game")
	if _game != null:
		_game.time_of_day = 16.0
		_game.time_paused = true
	sand.wind_drift_per_minute = 0.0

	for _i: int in range(140):
		await physics_frame

	# A stage of deep sand: every rung's full trail must take a full-strength
	# mound, so hunt for a stretch where the sand stays deep end to end.
	var stage: Vector2 = _find_stage(terrain)
	var vantage: Vector2 = stage + Vector2(0.0, 15.0)
	print("stage %s (sand %.2f m), player at %s" % [
		stage, terrain.get_sand_depth(stage), vantage
	])

	for rung: Dictionary in RUNGS:
		var rung_name: String = rung["name"]
		print("rung %s: body %.0f m x %.1f m, mound r %.1f m, height %.2f m" % [
			rung_name, rung["length"], rung["dia"], rung["radius"], rung["height"]
		])
		material.set_shader_parameter("deform_raise", rung["height"] as float)

		# The wake alone: a curved trail sweeping across the view, strength
		# ramped up toward the head so the tail reads as already settling.
		await _stand_at(player, rig, terrain, vantage)
		rig.set_yaw_degrees(0.0)  # look north, at the stage
		_stamp_trail(sand, stage, rung)
		for _i: int in range(8):
			await physics_frame
		await _capture("%s_mound" % rung_name)
		await _flush_mounds(sand)

		# The same wake with a posed placeholder body breaching at its head.
		var body: Node3D = _build_breach_body(terrain, stage, rung)
		level.add_child(body)
		_stamp_trail(sand, stage, rung)
		for _i: int in range(8):
			await physics_frame
		await _capture("%s_breach" % rung_name)
		body.queue_free()
		await _flush_mounds(sand)

	material.set_shader_parameter("deform_raise", sand.mound_height)

	# The real thing in motion: summon the worm and catch its mound mid-orbit.
	await _stand_at(player, rig, terrain, stage)
	rig.set_yaw_degrees(0.0)
	worm.summon(SandWorm.Mode.ORBIT)
	for _i: int in range(60 * 4):
		await physics_frame
	await _capture("mound_live_1")
	for _i: int in range(60 * 2):
		await physics_frame
	await _capture("mound_live_2")
	worm.dismiss()


## A point whose surrounding ±18 m east-west stays deep enough that even the
## titan rung's trail takes full-strength mounds.
func _find_stage(terrain: TerrainSettings) -> Vector2:
	var centre: Vector2 = terrain.get_homestead_center()
	var best: Vector2 = centre + Vector2(60.0, 0.0)
	var best_depth: float = 0.0
	for x: float in range(50, 220, 10):
		for z: float in range(-90, 91, 10):
			var at: Vector2 = centre + Vector2(x, z)
			var worst: float = INF
			for dx: float in [-18.0, -9.0, 0.0, 9.0, 18.0]:
				worst = minf(worst, terrain.get_sand_depth(at + Vector2(dx, 0.0)))
			if worst > best_depth:
				best_depth = worst
				best = at
			if best_depth >= 1.2:
				return best
	print("stage depth settled for %.2f m" % best_depth)
	return best


## A wake trail ending at the stage centre, curved like a real approach.
func _stamp_trail(sand: SandDeformation, head: Vector2, rung: Dictionary) -> void:
	var spacing: float = rung["spacing"]
	var radius: float = rung["radius"]
	var count: int = 18
	for i: int in range(count):
		var back: float = float(count - 1 - i) * spacing
		# Diagonal to the 16:00 sun so the ridge catches raking light, with a
		# gentle S-curve; stamped twice — the soft saturation compresses the
		# sum, and a single staged batch reads fainter than the live worm's
		# continuously refreshed head.
		var at: Vector2 = head + Vector2(-back * 0.82, back * 0.5 + sin(back * 0.25) * 1.8)
		var angle: float = atan2(0.5, 0.82)
		var strength: float = lerpf(0.5, 1.0, float(i) / float(count - 1))
		sand.raise(at, radius, strength, angle, 1.5)
		sand.raise(at, radius, strength, angle, 1.5)


## Let staged mounds settle to nothing between rungs, fast.
func _flush_mounds(sand: SandDeformation) -> void:
	Engine.time_scale = 10.0
	var guard: int = 0
	while not sand.is_idle() and guard < 1200:
		guard += 1
		await physics_frame
	Engine.time_scale = 1.0
	for _i: int in range(10):
		await physics_frame


## A segmented placeholder body arcing out of the sand: cylinders along a
## parabola, a cone for the head — palette clay, shadows on, zero rigging.
func _build_breach_body(
	terrain: TerrainSettings, head: Vector2, rung: Dictionary
) -> Node3D:
	var body: Node3D = Node3D.new()
	var clay: StandardMaterial3D = load(
		"res://resources/palette/clay.tres"
	) as StandardMaterial3D
	var length: float = rung["length"]
	var dia: float = rung["dia"]
	var chord: float = length * 0.55
	var peak: float = dia * 0.9 + length * 0.05
	var surface: float = terrain.get_surface_height(head)
	# The arc runs along +X (the trail's travel direction), cresting between
	# a buried entry and exit; the head cone caps the leading end.
	var segments: int = 9
	var points: Array[Vector3] = []
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		var lift: float = peak * (1.0 - pow(2.0 * t - 1.0, 2.0)) - dia * 0.8
		points.append(Vector3(
			head.x - chord + t * chord, surface + lift, head.y
		))
	for i: int in range(segments):
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = dia * 0.5
		mesh.bottom_radius = dia * 0.5
		mesh.height = from.distance_to(to) * 1.15
		var seg: MeshInstance3D = MeshInstance3D.new()
		seg.mesh = mesh
		seg.material_override = clay
		body.add_child(seg)
		seg.global_transform = Transform3D(
			Basis(Quaternion(Vector3.UP, (to - from).normalized())),
			(from + to) * 0.5
		)
	var nose: CylinderMesh = CylinderMesh.new()
	nose.bottom_radius = dia * 0.5
	nose.top_radius = dia * 0.08
	nose.height = dia * 0.9
	var head_seg: MeshInstance3D = MeshInstance3D.new()
	head_seg.mesh = nose
	head_seg.material_override = clay
	body.add_child(head_seg)
	var head_dir: Vector3 = (points[segments] - points[segments - 1]).normalized()
	head_seg.global_transform = Transform3D(
		Basis(Quaternion(Vector3.UP, head_dir)),
		points[segments] + head_dir * (dia * 0.45)
	)
	return body


func _stand_at(
	player: Player, rig: CameraRig, terrain: TerrainSettings, at: Vector2
) -> void:
	player.global_position = Vector3(
		at.x, terrain.get_surface_height(at) + 0.2, at.y
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	rig.snap_to_target()
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = _outdir.path_join("%s.png" % shot_name)
	image.save_png(path)
	print("saved ", path)
