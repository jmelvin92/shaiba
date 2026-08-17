class_name Ocean
extends Node3D
## The sea surface west of the desert (Phase 6.7).
##
## One large water plane sitting at the terrain's sea level, following the
## player in whole-cell snaps so its vertices stay on a fixed world lattice.
## The waves live entirely in shaders/ocean_water.gdshader and are computed
## from *world* position, so the plane moving under them is invisible — the
## sea is world-anchored however the mesh travels.
##
## The seabed underneath is ordinary streamed terrain; this node draws only
## the surface. It knows nothing about the shoreline: the water shader reads
## the depth buffer to find where land meets sea, and the plane simply hides
## wherever terrain stands above sea level (everywhere east of the coast).
##
## The owning level calls [method set_terrain] and [method set_focus]; on a
## level without a coast (or without terrain at all) the node hides itself and
## costs nothing — the standalone/graybox contract.

## Follow snap, metres. Matches the plane's cell size so a recentre moves the
## mesh by whole cells and the world-space wave pattern never crawls.
@export_range(0.5, 8.0, 0.5) var follow_snap: float = 2.0

@onready var _surface: MeshInstance3D = $Surface

var _terrain: TerrainSettings = null
var _focus: Node3D = null


func _ready() -> void:
	visible = false
	set_physics_process(false)


## Called by the owning level once terrain exists. Hides the sea entirely on
## a coastless world.
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain = terrain
	var coastal: bool = terrain != null and terrain.has_coast()
	visible = coastal
	set_physics_process(coastal and _focus != null)
	if coastal:
		global_position = Vector3(global_position.x, terrain.get_sea_level(), global_position.z)
		reset_physics_interpolation()


## Called by the owning level: whose position the plane follows.
func set_focus(focus: Node3D) -> void:
	_focus = focus
	set_physics_process(_focus != null and _terrain != null and _terrain.has_coast())
	if _focus != null:
		_recenter()
		reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	_recenter()


func _recenter() -> void:
	var target_x: float = floorf(_focus.global_position.x / follow_snap) * follow_snap
	var target_z: float = floorf(_focus.global_position.z / follow_snap) * follow_snap
	if is_equal_approx(target_x, global_position.x) and is_equal_approx(target_z, global_position.z):
		return
	global_position.x = target_x
	global_position.z = target_z
	# A snap is a teleport; without this the interpolator smears the plane
	# across the jump and the world-anchored waves visibly swim for a frame.
	reset_physics_interpolation()
