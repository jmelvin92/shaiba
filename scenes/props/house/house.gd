class_name House
extends Node3D
## The desert house: an adobe two-storey you can walk into.
##
## The model itself comes from assets/models/house.glb, built by
## tools/build_house.py. Its parts arrive as one MeshInstance3D per wall side
## per storey — deliberately, because [OccluderFader] ghosts a whole mesh at a
## time, and one mesh per side means the wall between camera and player ghosts
## by itself instead of taking the far wall and the floor with it.
##
## This script does the two things the imported model cannot carry: it sorts
## each part onto the right physics layer, and it hands the parts above the
## floor to the [InteriorCutaway] child so walking inside opens the building up.

## Parts the cutaway owns. Everything here sits above at least one floor, so it
## is what has to move out of the way for an occupant. They stay off layer 3,
## which keeps OccluderFader — the only other writer of transparency — away
## from them; see InteriorCutaway's notes on why one writer matters.
const CUTAWAY_PARTS: PackedStringArray = [
	"upper_slab",
	"upper_wall_front", "upper_wall_back", "upper_wall_left", "upper_wall_right",
	"roof",
]

## Parts that never fade and never hide: the ground the player walks on. On the
## world layer alone, so no sight-line can dissolve the floor under their feet
## — the same reasoning that keeps terrain off layer 3.
const FLOOR_PARTS: PackedStringArray = ["ground_floor"]

## Physics layers, per docs/ARCHITECTURE.md: 1 = world, 3 = fadeable occluder.
const LAYER_WORLD: int = 1
const LAYER_FADEABLE: int = 5

## The imported model.
@export var model_path: NodePath = ^"Model"
## Furnishing instances standing inside the building, if any. Each is its own
## asset (its own .glb) rather than geometry baked into the house, so the same
## bed or rug can furnish any building we ever make.
##
## They are handed to the cutaway along with the structure, and its cut plane
## sorts them out by height for free: a rug on the ground floor is below the
## plane and stays, the bed upstairs is above it and goes. Nothing here has to
## know which storey anything is on.
@export var furnishings_path: NodePath = ^"Furnishings"
## The building's [Door] instances. Each door manages itself (swing, collision,
## interaction); the house only needs to know about the ones whose `fadeable`
## export is off, because those adopt the cutaway's management the way the wall
## around them does — see _ready.
@export var doors: Array[NodePath] = [^"FrontDoor", ^"UpperDoor"]
## The cutaway that opens the building up. Optional: a building without one is
## simply never enterable, and everything else here still works.
@export var cutaway_path: NodePath = ^"Cutaway"
## Interior volumes that report an occupant to the cutaway.
@export var interior_areas: Array[NodePath] = [^"Cutaway/Interior"]
## The ground-floor lamp, and the soft "spill" lights just outside the
## ground-floor windows that follow it. Real lamplight does pass through the
## open windows, but a table-height lamp can only throw it *upward* through a
## 1 m sill — physically honest and visually mute from the courtyard. The
## spill lights paint the wall face and the sand under each lit window, which
## is the glow a distant camera actually reads (Joshua asked for more glow,
## 2026-08-15).
@export var lamp_path: NodePath = ^"Furnishings/Ground/OilLamp"
@export var window_spill_path: NodePath = ^"WindowSpill"


func _ready() -> void:
	var model: Node3D = get_node_or_null(model_path) as Node3D
	if model == null:
		push_warning("House: no model at %s; nothing to set up." % model_path)
		return

	var managed: Array[GeometryInstance3D] = []
	for part: Node in model.get_children():
		var visual: GeometryInstance3D = part as GeometryInstance3D
		if visual == null:
			continue
		var cutaway_owned: bool = CUTAWAY_PARTS.has(part.name)
		var fixed: bool = FLOOR_PARTS.has(part.name)
		_set_layer(part, LAYER_WORLD if cutaway_owned or fixed else LAYER_FADEABLE)
		if cutaway_owned:
			managed.append(visual)

	var furnishings: Node3D = get_node_or_null(furnishings_path) as Node3D
	if furnishings != null:
		for piece: Node in furnishings.get_children():
			_collect_visuals(piece, managed)
			_set_layer_deep(piece, LAYER_WORLD)

	# A door follows the wall it is mounted in. The front door sits in a
	# fader-managed ground wall, so it keeps its own occluder layer; the upper
	# door sits in a cutaway-managed wall (its instance sets `fadeable` off),
	# so its leaf is handed to the cutaway here and vanishes with its storey
	# instead of floating in mid-air once the walls around it are gone.
	for path: NodePath in doors:
		var door: Door = get_node_or_null(path) as Door
		if door != null and not door.fadeable:
			managed.append_array(door.get_visuals())

	var lamp: OilLamp = get_node_or_null(lamp_path) as OilLamp
	var spill: Node3D = get_node_or_null(window_spill_path) as Node3D
	if lamp != null and spill != null:
		lamp.lit_changed.connect(func(lit: bool) -> void: spill.visible = lit)
		spill.visible = lamp.lit

	var cutaway: InteriorCutaway = get_node_or_null(cutaway_path) as InteriorCutaway
	if cutaway == null:
		return
	cutaway.setup(managed)
	for path: NodePath in interior_areas:
		var area: Area3D = get_node_or_null(path) as Area3D
		if area == null:
			continue
		area.body_entered.connect(cutaway.occupant_entered)
		area.body_exited.connect(cutaway.occupant_exited)


## The glTF importer hangs a StaticBody3D under each MeshInstance3D, so the
## layer belongs to that child rather than to the part itself.
func _set_layer(part: Node, layer: int) -> void:
	for child: Node in part.get_children():
		var body: StaticBody3D = child as StaticBody3D
		if body != null:
			body.collision_layer = layer


## As above, but for a whole instanced prop, whose meshes sit one level deeper
## inside the scene it was imported as.
func _set_layer_deep(root: Node, layer: int) -> void:
	var body: StaticBody3D = root as StaticBody3D
	if body != null:
		body.collision_layer = layer
	for child: Node in root.get_children():
		_set_layer_deep(child, layer)


func _collect_visuals(root: Node, into: Array[GeometryInstance3D]) -> void:
	var visual: GeometryInstance3D = root as GeometryInstance3D
	if visual != null:
		into.append(visual)
	for child: Node in root.get_children():
		_collect_visuals(child, into)
