class_name LevelRoot
extends Node3D
## Root behaviour shared by every playable level scene (world, graybox).
##
## Its only job is the wiring the two feature scenes deliberately don't do
## themselves: the camera rig is told what to follow, and the player is told
## which way the camera is facing. Both are direct children, so this only ever
## calls *down* — see docs/ARCHITECTURE.md.

## Direct child that the camera should follow.
@export var player_path: NodePath = ^"Player"
## Direct child holding the gameplay camera.
@export var camera_rig_path: NodePath = ^"CameraRig"
## Direct child streaming the terrain, if this level has one. Levels without
## terrain (the graybox) leave the node out and everything below is skipped —
## the player's sand hooks then stay inert.
@export var chunk_manager_path: NodePath = ^"ChunkManager"
## Direct child accumulating footprint deformation, if this level has one.
## Levels without it (the graybox) leave the node out; the terrain shader's
## deformation uniforms then stay at their inert defaults.
@export var sand_deformation_path: NodePath = ^"SandDeformation"
## Direct child holding the homestead buildings, if this level has one. It is
## moved to the seeded site the terrain levelled for it; a level without one
## skips this entirely.
@export var homestead_path: NodePath = ^"Homestead"
## Marker inside the homestead saying where the player arrives. Without it the
## player keeps whatever spawn the scene gave them.
@export var homestead_spawn_path: NodePath = ^"PlayerSpawn"


func _ready() -> void:
	var player: Player = get_node_or_null(player_path) as Player
	var camera_rig: CameraRig = get_node_or_null(camera_rig_path) as CameraRig
	if player == null or camera_rig == null:
		push_warning("LevelRoot: missing Player or CameraRig child; skipping wiring.")
		return

	camera_rig.yaw_changed.connect(player.set_view_yaw)
	player.set_view_yaw(camera_rig.get_yaw())
	camera_rig.set_target(player)

	var chunk_manager: ChunkManager = get_node_or_null(chunk_manager_path) as ChunkManager
	if chunk_manager == null:
		return

	# set_tracked builds the spawn chunks before returning, so the ground's
	# collision exists before the first physics tick; only then is the player
	# seated on the actual surface (which may sit metres above y = 0).
	chunk_manager.set_tracked(player)
	var terrain: TerrainSettings = chunk_manager.get_terrain()
	if terrain == null:
		return
	player.set_terrain(terrain)
	camera_rig.set_terrain(terrain)

	# The homestead goes onto the pad the terrain levelled for it, and the
	# player starts in its courtyard — so the game opens looking at the one
	# built thing in the desert rather than at empty sand.
	_place_homestead(terrain, player)

	var spawn_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	player.global_position.y = terrain.get_surface_height(spawn_xz) + 0.1
	player.reset_physics_interpolation()
	camera_rig.snap_to_target()

	var sand: SandDeformation = get_node_or_null(sand_deformation_path) as SandDeformation
	if sand != null:
		sand.set_terrain(terrain)
		sand.set_tracked(player)
		player.stamped.connect(sand.stamp)


## Moves the homestead onto its levelled pad and the player into its courtyard.
##
## The site is chosen by the terrain rather than fixed in the scene, because
## the terrain is what has to be flat there — the two would drift apart if the
## scene held its own copy of the position.
func _place_homestead(terrain: TerrainSettings, player: Player) -> void:
	var homestead: Node3D = get_node_or_null(homestead_path) as Node3D
	if homestead == null:
		return
	var centre: Vector2 = terrain.get_homestead_center()
	homestead.global_position = Vector3(
		centre.x, terrain.get_surface_height(centre), centre.y
	)
	homestead.reset_physics_interpolation()

	var spawn: Marker3D = homestead.get_node_or_null(homestead_spawn_path) as Marker3D
	if spawn == null:
		return
	# Only the XZ is taken; the caller drops the player onto the surface next,
	# so a marker sitting at the homestead's own height can't leave them buried.
	player.global_position.x = spawn.global_position.x
	player.global_position.z = spawn.global_position.z
