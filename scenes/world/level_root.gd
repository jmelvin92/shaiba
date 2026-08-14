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


func _ready() -> void:
	var player: Player = get_node_or_null(player_path) as Player
	var camera_rig: CameraRig = get_node_or_null(camera_rig_path) as CameraRig
	if player == null or camera_rig == null:
		push_warning("LevelRoot: missing Player or CameraRig child; skipping wiring.")
		return

	camera_rig.yaw_changed.connect(player.set_view_yaw)
	player.set_view_yaw(camera_rig.get_yaw())
	camera_rig.set_target(player)
