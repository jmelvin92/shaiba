extends SceneTree
## Prints the node tree of a scene, plus animation and skeleton details.
##
## A throwaway inspection aid for asset work:
##   Godot --headless --path . --script res://tools/dump_scene.gd -- res://path.glb
## Defaults to the player model when no path is given.


func _init() -> void:
	var path: String = "res://assets/models/player.glb"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("could not load %s" % path)
		quit(1)
		return

	var root: Node = packed.instantiate()
	_describe(root, 0)
	root.free()
	quit()


func _describe(node: Node, depth: int) -> void:
	var indent: String = "  ".repeat(depth)
	print("%s%s : %s" % [indent, node.name, node.get_class()])

	if node is Node3D:
		var xform: Transform3D = (node as Node3D).transform
		if not xform.is_equal_approx(Transform3D.IDENTITY):
			print("%s    transform origin=%v scale=%v" % [
				indent, xform.origin, xform.basis.get_scale()])

	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			print("%s    aabb=%v surfaces=%d" % [indent, mesh.get_aabb().size, mesh.get_surface_count()])

	if node is Skeleton3D:
		var skeleton: Skeleton3D = node as Skeleton3D
		print("%s    bones=%d" % [indent, skeleton.get_bone_count()])
		var names: PackedStringArray = []
		for i: int in range(skeleton.get_bone_count()):
			names.append(skeleton.get_bone_name(i))
		print("%s    %s" % [indent, ", ".join(names)])

	if node is AnimationPlayer:
		var player: AnimationPlayer = node as AnimationPlayer
		for clip: StringName in player.get_animation_list():
			var anim: Animation = player.get_animation(clip)
			print("%s    %-12s %5.2fs loop=%d tracks=%d" % [
				indent, clip, anim.length, anim.loop_mode, anim.get_track_count()])

	for child: Node in node.get_children():
		_describe(child, depth + 1)
