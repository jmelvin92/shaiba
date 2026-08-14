extends SceneTree
## Measures how fast each locomotion clip "wants" the character to travel.
##
##   Godot --headless --path . --script res://tools/measure_gaits.gd
##
## While a foot is planted it is still on the ground, so relative to the body it
## slides backwards at exactly the speed the body moves forwards. Sampling that
## backward speed gives each clip its natural ground speed, which is what the
## blend-space anchors in player_animator.gd are set to. Anchoring there is what
## keeps the feet from skating: at those speeds the animation plays at 1.0x.

const MODEL: String = "res://assets/models/player.glb"
const CLIPS: PackedStringArray = ["walk", "run", "crouch_walk", "idle"]
const SAMPLES: int = 240
## A foot counts as planted while it sits in the lowest slice of its own travel.
const PLANTED_BAND: float = 0.3


func _init() -> void:
	# Wait for the first processed frame: nothing is inside the tree yet while
	# the SceneTree itself is still being constructed, and an AnimationPlayer
	# that is not in the tree will not pose its skeleton.
	process_frame.connect(_run)


func _run() -> void:
	process_frame.disconnect(_run)
	var scene: Node3D = (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(scene)

	var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton: Skeleton3D = scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var left: int = skeleton.find_bone("LeftToeBase")
	var right: int = skeleton.find_bone("RightToeBase")
	var hips: int = skeleton.find_bone("Hips")

	print("clip          length   natural speed   planted samples")
	for clip: String in CLIPS:
		if not player.has_animation(clip):
			continue
		_measure(player, skeleton, clip, left, right, hips)

	scene.queue_free()
	quit()


func _measure(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip: String,
	left: int,
	right: int,
	hips: int
) -> void:
	var anim: Animation = player.get_animation(clip)
	var length: float = anim.length
	# The rig was authored in centimetres, so the Armature carries a 0.01 scale.
	# Accumulate local transforms rather than asking for the global one: nothing
	# is inside the tree yet at this point.
	var scale: float = 1.0
	var walker: Node3D = skeleton
	while walker != null:
		scale *= walker.transform.basis.get_scale().x
		walker = walker.get_parent() as Node3D

	var heights: Array[float] = []
	var offsets: Array[float] = []
	player.play(clip)

	for i: int in range(SAMPLES + 1):
		player.seek(length * float(i) / float(SAMPLES), true)
		var lp: Vector3 = skeleton.get_bone_global_pose(left).origin * scale
		var rp: Vector3 = skeleton.get_bone_global_pose(right).origin * scale
		var hp: Vector3 = skeleton.get_bone_global_pose(hips).origin * scale
		var planted: Vector3 = lp if lp.y < rp.y else rp
		heights.append(planted.y)
		# Distance along the character's facing, measured from the hips so the
		# body's own bob and sway don't count as travel.
		offsets.append(planted.z - hp.z)

	var low: float = heights.min()
	var band: float = low + (heights.max() - low) * PLANTED_BAND

	var speeds: Array[float] = []
	var step: float = length / float(SAMPLES)
	for i: int in range(SAMPLES):
		if heights[i] > band or heights[i + 1] > band:
			continue
		speeds.append(absf(offsets[i + 1] - offsets[i]) / step)

	if speeds.is_empty():
		print("%-12s %6.2fs   (never planted)" % [clip, length])
		return

	speeds.sort()
	var median: float = speeds[speeds.size() / 2]
	print("%-12s %6.2fs   %6.2f m/s        %d/%d" % [
		clip, length, median, speeds.size(), SAMPLES])
