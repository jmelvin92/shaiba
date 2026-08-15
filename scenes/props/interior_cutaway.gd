class_name InteriorCutaway
extends Node3D
## Opens a building up when the player walks inside it.
##
## The camera never moves to avoid geometry (docs/DECISIONS.md), and at the
## 19° gameplay pitch it looks almost straight at a building's face — so an
## indoor player is behind a wall, under a floor slab and under a roof all at
## once. This node cuts the building at a horizontal plane a little above the
## occupant's head: everything wholly above the plane disappears, and anything
## the plane passes *through* — the walls of the storey they are standing in —
## ghosts back to a readable outline.
##
## Because the plane is derived from the occupant's own height, one node serves
## a building of any number of storeys: walk upstairs and the plane rises with
## you, so the roof goes and the floor you just left becomes solid again. There
## is nothing per-storey to configure.
##
## **It owns [member GeometryInstance3D.transparency] on the parts handed to
## it, and nothing else may write them.** [OccluderFader] writes the same
## property, so the two are separated by physics layer: parts managed here sit
## on the world layer alone (never layer 3), which the fader's mask cannot see.
## Two writers on one property fight every frame and flicker.
##
## The owning building calls [method setup] — this node never searches the tree.

## How far above the occupant's feet the cut plane sits. Above head height, so
## the storey they are in is always crossed by the plane rather than hidden.
@export_range(0.5, 4.0, 0.05) var cut_margin: float = 1.90
## Transparency for a part the plane passes through: the walls around the
## occupant. Not fully gone — a ghosted wall still reads as a room.
@export_range(0.0, 1.0, 0.05) var ghost_transparency: float = 0.82
## Damping of the fade, in and out. Matched to OccluderFader so a building
## whose walls are handled by both settles at one rate.
@export_range(1.0, 30.0, 0.5) var fade_speed: float = 9.0

## Parts whose visibility this node controls, given by the owning building.
var _managed: Array[GeometryInstance3D] = []
## Bodies currently inside. Counted rather than flagged so overlapping volumes,
## or a body that clips out and back, can't leave the building stuck open.
var _occupants: Array[Node3D] = []


## Called by the building that owns this node, with the parts to manage.
func setup(parts: Array[GeometryInstance3D]) -> void:
	_managed = parts


## Connected to every interior [Area3D]'s body signals by the owning building.
func occupant_entered(body: Node3D) -> void:
	if not _occupants.has(body):
		_occupants.append(body)


func occupant_exited(body: Node3D) -> void:
	_occupants.erase(body)


## True while anyone is inside — read by the verification harness.
func is_open() -> bool:
	return not _occupants.is_empty()


## Height of the current cut plane in world space, or NAN when closed.
func get_cut_height() -> float:
	var highest: float = NAN
	for body: Node3D in _occupants:
		if not is_instance_valid(body):
			continue
		var plane: float = body.global_position.y + cut_margin
		if is_nan(highest) or plane > highest:
			highest = plane
	return highest


func _physics_process(delta: float) -> void:
	for i: int in range(_occupants.size() - 1, -1, -1):
		if not is_instance_valid(_occupants[i]):
			_occupants.remove_at(i)
	var cut: float = get_cut_height()
	var weight: float = 1.0 - exp(-fade_speed * delta)

	for visual: GeometryInstance3D in _managed:
		if not is_instance_valid(visual):
			continue
		var goal: float = _goal_for(visual, cut)
		var value: float = lerpf(visual.transparency, goal, weight)
		if goal >= 1.0 and value > 0.985:
			# Fully faded: stop drawing it rather than paying for a
			# transparent pass, and sidestep any alpha-sorting question.
			visual.transparency = 1.0
			visual.visible = false
		else:
			visual.transparency = value
			visual.visible = true


## Where one part stands relative to the cut plane.
func _goal_for(visual: GeometryInstance3D, cut: float) -> float:
	if is_nan(cut):
		return 0.0
	var span: Vector2 = _world_height_span(visual)
	if span.x >= cut:
		return 1.0                      # wholly above the occupant: get out
	if span.y <= cut:
		return 0.0                      # wholly below: floors stay solid
	return ghost_transparency           # the plane crosses it: their storey


## Lowest and highest world-space Y of a part's bounds.
##
## Recomputed rather than cached: a building is placed into the world after its
## own _ready (the level seats it on the terrain), so anything measured at
## _ready would be measured in the wrong place. Thirteen boxes' worth of corner
## transforms per tick does not register.
func _world_height_span(visual: GeometryInstance3D) -> Vector2:
	var bounds: AABB = visual.get_aabb()
	var basis: Transform3D = visual.global_transform
	var lowest: float = INF
	var highest: float = -INF
	for i: int in range(8):
		var corner: Vector3 = basis * bounds.get_endpoint(i)
		lowest = minf(lowest, corner.y)
		highest = maxf(highest, corner.y)
	return Vector2(lowest, highest)
