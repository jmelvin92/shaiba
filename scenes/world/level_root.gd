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
## Direct child playing the ambient sound bed, if this level has one. Told to
## centre its gusts on the player; a level without one skips it.
@export var ambience_path: NodePath = ^"Ambience"
## Direct child drawing the sea surface, if this level has one. Handed the
## terrain (for sea level and the coast switch) and the player to follow; a
## level without one — or a coastless world — skips it entirely.
@export var ocean_path: NodePath = ^"Ocean"
## Direct child housing the sand worm, if this level has one (Phase 6.8).
## Levels without it skip the wiring; the worm itself stays dormant until
## summoned, so its presence costs nothing.
@export var sand_worm_path: NodePath = ^"SandWorm"
## Direct child deciding when the worm hunts (Phase 6.8 Part 3). Optional —
## without it the worm only ever answers the debug keys.
@export var worm_director_path: NodePath = ^"WormDirector"
## Direct child fading the screen to black, used by the swallow sequence.
@export var screen_fade_path: NodePath = ^"ScreenFade"
## How long the swallow drags the player under before the reload, seconds.
@export_range(0.3, 3.0, 0.05) var swallow_seconds: float = 1.2
## Direct child owning save/load, if this level has one (the graybox doesn't).
@export var save_system_path: NodePath = ^"SaveSystem"
## Direct child holding the pause menu, whose save/load requests the level
## answers by calling down into the SaveSystem.
@export var pause_menu_path: NodePath = ^"PauseMenu"

var _save_system: SaveSystem = null
var _pause_menu: PauseMenu = null
## Held for the swallow sequence — set only when the level has all of the
## pieces (worm, terrain, fade), so the handler can trust them.
var _player: Player = null
var _camera_rig: CameraRig = null
var _terrain: TerrainSettings = null
var _worm: SandWorm = null
## True from the bite to the fade-back-in; re-entry is impossible while set.
var _swallowing: bool = false


func _ready() -> void:
	var player: Player = get_node_or_null(player_path) as Player
	var camera_rig: CameraRig = get_node_or_null(camera_rig_path) as CameraRig
	if player == null or camera_rig == null:
		push_warning("LevelRoot: missing Player or CameraRig child; skipping wiring.")
		return

	camera_rig.yaw_changed.connect(player.set_view_yaw)
	player.set_view_yaw(camera_rig.get_yaw())
	camera_rig.set_target(player)

	var ambience: Ambience = get_node_or_null(ambience_path) as Ambience
	if ambience != null:
		ambience.set_focus(player)

	_save_system = get_node_or_null(save_system_path) as SaveSystem
	_pause_menu = get_node_or_null(pause_menu_path) as PauseMenu
	if _save_system != null:
		_save_system.setup(
			player, get_node_or_null(chunk_manager_path) as ChunkManager
		)
		if _pause_menu != null:
			_pause_menu.save_requested.connect(_on_save_requested)
			_pause_menu.load_requested.connect(_on_load_requested)
			_pause_menu.set_can_load(_save_system.has_save())

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

	var ocean: Ocean = get_node_or_null(ocean_path) as Ocean
	if ocean != null:
		ocean.set_terrain(terrain)
		ocean.set_focus(player)
	if ambience != null:
		ambience.set_terrain(terrain)

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

	# The worm reports its wake exactly like the player's feet report steps:
	# one signal, one connect — the Phase 5 stamper contract, raise flavour.
	var worm: SandWorm = get_node_or_null(sand_worm_path) as SandWorm
	if worm != null:
		worm.set_terrain(terrain)
		worm.set_focus(player)
		if sand != null:
			worm.raised.connect(sand.raise)
		var overlay: TerrainDebugOverlay = chunk_manager.get_debug_overlay()
		if overlay != null:
			overlay.set_worm(worm)

		# Part 3: the director hears what the world hears (the player's feet
		# today; any future noisemaker is the same signal and connect), and
		# the bite comes back up as one signal the level answers with the
		# death sequence.
		var director: WormDirector = (
			get_node_or_null(worm_director_path) as WormDirector
		)
		if director != null:
			director.setup(worm, terrain, player)
			player.noise_made.connect(director.hear_noise)
			if overlay != null:
				overlay.set_worm_director(director)
		_player = player
		_camera_rig = camera_rig
		_terrain = terrain
		_worm = worm
		worm.swallowed.connect(_on_swallowed)


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


## The kill (Phase 6.8 Part 3, Joshua's design): being caught is a cinematic
## swallow — control cut, dragged under with the diving head, fade to black,
## reload the last save (or re-seat at the spawn when none exists), fade back
## in. No health bar; the escape beat happened before the bite ever landed.
func _on_swallowed(_prey: Node3D) -> void:
	if _swallowing or _player == null:
		return
	_swallowing = true
	_player.set_control_enabled(false)
	var fade: ScreenFade = get_node_or_null(screen_fade_path) as ScreenFade
	if fade != null:
		# Fire-and-forget: the fade darkens while the drag plays out below.
		fade.fade_out(swallow_seconds * 0.9)

	# Dragged under: the body rides the mouth as the head dives. Direct
	# position writes are safe — control-cut players skip their physics.
	var dragged: float = 0.0
	while dragged < swallow_seconds:
		var delta: float = get_physics_process_delta_time()
		dragged += delta
		if _worm != null and _worm.is_active():
			_player.global_position = _player.global_position.lerp(
				_worm.global_position, 1.0 - exp(-8.0 * delta)
			)
		await get_tree().physics_frame

	if _worm != null:
		_worm.dismiss()
	if _save_system != null and _save_system.has_save():
		_save_system.load_game()
	else:
		_respawn_at_start()
	_player.set_control_enabled(true)
	if _camera_rig != null:
		_camera_rig.snap_to_target()
	if fade != null:
		await fade.fade_in(0.8)
	_swallowing = false


## No save to return to: back to the courtyard, the way a fresh run starts.
func _respawn_at_start() -> void:
	if _terrain == null:
		return
	_place_homestead(_terrain, _player)
	var at: Vector2 = Vector2(_player.global_position.x, _player.global_position.z)
	_player.global_position.y = _terrain.get_surface_height(at) + 0.1
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _on_save_requested() -> void:
	var ok: bool = _save_system.save_game()
	_pause_menu.report_save(ok)
	_pause_menu.set_can_load(_save_system.has_save())


func _on_load_requested() -> void:
	_pause_menu.report_load(_save_system.load_game())
