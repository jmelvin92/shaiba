class_name OccluderFader
extends Node
## Fades anything standing between the camera and the character.
##
## The alternative — pulling the camera in until it can see past the obstacle —
## wrecks the framing at this camera angle (see docs/DECISIONS.md), so the
## camera holds its distance and the wall gets out of the way instead.
##
## Only bodies on [member occluder_mask] are ever faded, so terrain can sit on
## the world layer alone and never dissolve under the player's feet. Fading
## uses [member GeometryInstance3D.transparency], which needs no changes to the
## palette materials — it is a per-instance multiplier, not a material edit.

## Physics layers whose bodies are allowed to fade. Layer 3 = "occluder".
@export_flags_3d_physics var occluder_mask: int = 4
## How see-through an occluder becomes. 1.0 would hide it entirely; leaving a
## little means you can still read the shape you are walking behind.
@export_range(0.0, 1.0, 0.05) var fade_to: float = 0.78
## Damping of the fade, in and out.
@export_range(1.0, 30.0, 0.5) var fade_speed: float = 9.0
## Heights above the target's feet to sight along, so a wall that hides only
## the head or only the legs still counts as blocking.
@export var sample_heights: PackedFloat32Array = PackedFloat32Array([0.4, 1.0, 1.6])
## Ceiling on how many bodies deep a single sight-line is traced.
@export_range(1, 12, 1) var max_layers: int = 6

var _camera: Camera3D = null
var _target: Node3D = null
## GeometryInstance3D -> the transparency currently applied to it.
var _fading: Dictionary = {}


## Told what to look from and at by the camera rig that owns this node.
func setup(camera: Camera3D, target: Node3D) -> void:
	_camera = camera
	_target = target


func _physics_process(delta: float) -> void:
	var blocking: Dictionary = {}
	if _camera != null and _target != null and is_instance_valid(_target):
		blocking = _find_occluders()
	_apply_fades(blocking, delta)


## Every fadeable body the character is hiding behind this tick, found by
## walking each sight-line hit by hit rather than stopping at the first.
func _find_occluders() -> Dictionary:
	var found: Dictionary = {}
	var space: PhysicsDirectSpaceState3D = _camera.get_world_3d().direct_space_state
	var eye: Vector3 = _camera.global_position
	var feet: Vector3 = _target.global_position

	for height: float in sample_heights:
		var exclude: Array[RID] = []
		for i: int in range(max_layers):
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				eye, feet + Vector3.UP * height
			)
			query.collision_mask = occluder_mask
			query.exclude = exclude
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				break
			exclude.append(hit["rid"])
			for visual: GeometryInstance3D in _visuals_of(hit["collider"]):
				found[visual] = true
	return found


## Walks each tracked object toward the transparency it should have, and stops
## tracking it once it is fully opaque again.
func _apply_fades(blocking: Dictionary, delta: float) -> void:
	for node: Variant in blocking:
		if not _fading.has(node):
			_fading[node] = 0.0

	var weight: float = 1.0 - exp(-fade_speed * delta)
	var finished: Array = []
	for node: Variant in _fading:
		var visual: GeometryInstance3D = node as GeometryInstance3D
		if not is_instance_valid(visual):
			finished.append(node)
			continue
		var goal: float = fade_to if blocking.has(node) else 0.0
		var value: float = lerpf(float(_fading[node]), goal, weight)
		if goal == 0.0 and value < 0.01:
			visual.transparency = 0.0
			finished.append(node)
		else:
			visual.transparency = value
			_fading[node] = value

	for node: Variant in finished:
		_fading.erase(node)


## The meshes to fade for a body the ray hit. A CSG shape is its own geometry;
## an imported prop keeps its collider and its mesh in the same little subtree,
## either way round, so check the body, then below it, then alongside it — and
## then the parent itself, which is where Godot's glTF importer puts the mesh
## when a model uses the `-col` name suffix (the StaticBody3D hangs *under* the
## MeshInstance3D, so the mesh is the parent, not one of the parent's children).
func _visuals_of(collider: Object) -> Array[GeometryInstance3D]:
	var body: Node = collider as Node
	if body == null:
		return []
	if body is GeometryInstance3D:
		return [body as GeometryInstance3D]

	var found: Array[GeometryInstance3D] = []
	_collect_visuals(body, found)
	if not found.is_empty():
		return found

	var parent: Node = body.get_parent()
	if parent == null:
		return found
	if parent is GeometryInstance3D:
		return [parent as GeometryInstance3D]
	_collect_visuals(parent, found)
	return found


func _collect_visuals(root: Node, into: Array[GeometryInstance3D]) -> void:
	for child: Node in root.get_children():
		if child is GeometryInstance3D:
			into.append(child as GeometryInstance3D)
		else:
			_collect_visuals(child, into)
