class_name FootstepAudio
extends Node3D
## The player's movement sounds (Phase 6.6): footsteps whose clip set follows
## the surface underfoot and whose loudness follows the gait, a quiet shuffle
## loop while sneaking, and jump/landing one-shots.
##
## Owned and driven by the Player, exactly like [FootstepStamper]: the player
## calls [method tick] every physics tick and forwards plant/jump/land events
## down into here. This node never reads input and never looks up the tree.
##
## Surface resolution is the extensible half (docs/PLAN.md Phase 6.6): a short
## raycast under the foot asks what it landed on. Terrain answers by sand
## depth — deep drift sounds soft, the packed courtyard firm. Anything else
## answers with the `surface` metadata its collider carries (the house tags
## its floors in house.gd), falling back to "stone". A new material is a new
## take set in assets/audio plus a tag on the floor that should use it —
## no code.
##
## Every stream comes from [SoundBank] and may be null while Joshua is still
## sourcing files; a null set plays nothing but the whole gait/surface logic
## still runs, which is what tools/verify_audio.gd asserts against.

## Something audible happened at a place. Nothing listens yet — this is the
## future stealth/creature hook, emitted whether or not a sound file exists,
## because how much noise you make is gameplay truth, not presentation.
signal noise_made(world_position: Vector3, loudness: float)

@export_group("Gait")
## Planar speed above which a step counts as running, m/s. Sits between the
## walk clip's 1.4 m/s stride and the run's 4.9.
@export_range(0.5, 8.0, 0.1) var run_speed_threshold: float = 3.0
## Loudness of a walking step.
@export_range(-40.0, 6.0, 0.5) var walk_volume_db: float = -7.0
## Loudness of a running step. Same samples as walking, a bit louder —
## Joshua's design: feet keep their voices at any speed.
@export_range(-40.0, 6.0, 0.5) var run_volume_db: float = -3.0
## Loudness of the crouch shuffle loop — sneaking should be genuinely quiet.
@export_range(-60.0, 0.0, 0.5) var shuffle_volume_db: float = -18.0

@export_group("Air")
## Impact speed that turns a landing from soft to hard, m/s. Matches the
## animator's knee-buckle threshold so what you hear agrees with what you see.
@export_range(0.5, 12.0, 0.1) var hard_landing_speed: float = 4.0
@export_range(-40.0, 6.0, 0.5) var jump_volume_db: float = -8.0
@export_range(-40.0, 6.0, 0.5) var land_soft_volume_db: float = -6.0
@export_range(-40.0, 6.0, 0.5) var land_hard_volume_db: float = 0.0

@export_group("Surface")
## Sand shallower than this counts as bare packed ground instead of sand,
## metres. Near zero on purpose (lesson of 2026-08-15): an earlier 0.35
## threshold classified the whole flattened homestead surround as "packed" —
## a surface with no sound files — so the game fell silent exactly where
## Joshua play-tested. Now everything with real sand on it sounds like sand,
## the same rule footprints follow; only print-less hard ground differs.
@export_range(0.0, 1.0, 0.01) var packed_sand_depth: float = 0.05

## Terrain query source, handed down by the Player (which got it from the
## level). Null on levels without terrain, where every ray answer comes from
## collider tags instead.
var _terrain: TerrainSettings = null

var _step_player: AudioStreamPlayer3D = null
var _air_player: AudioStreamPlayer3D = null
var _shuffle_player: AudioStreamPlayer3D = null
## One player per foot (0 = left, 1 = right), so each foot keeps its own
## dedicated sample ("<surface>_left.wav" / "<surface>_right.wav") and a fast
## run cadence can overlap the tail of the previous step.
var _foot_players: Array[AudioStreamPlayer3D] = []

var _planar_speed: float = 0.0
var _crouched: bool = false
var _footed: bool = true
## Latest resolved surface, kept sticky so a ray that misses (mid-step over a
## ledge lip) reuses the last honest answer.
var _surface: String = "sand"
## Whether the sneak shuffle *should* be sounding — tracked separately from
## the player node so the logic stays verifiable with no shuffle file sourced.
var _shuffling: bool = false

## Verify/debug taps (tools/verify_audio.gd) — the last step's resolution.
var last_step_surface: String = ""
var last_step_volume_db: float = 0.0
var steps_played: int = 0


func _ready() -> void:
	_step_player = _make_player()
	_air_player = _make_player()
	_shuffle_player = _make_player()
	_shuffle_player.stream = SoundBank.stream("movement/crouch_shuffle_loop.ogg", true)
	_shuffle_player.volume_db = shuffle_volume_db
	_foot_players = [_make_player(), _make_player()]


## Called by the owning Player every physics tick with the state the sounds
## follow. Runs the shuffle loop; per-step one-shots arrive by
## [method on_foot_planted].
func tick(_delta: float, planar_speed: float, crouched: bool, footed: bool) -> void:
	_planar_speed = planar_speed
	_crouched = crouched
	_footed = footed
	var wants_shuffle: bool = crouched and footed and planar_speed > 0.3
	if wants_shuffle == _shuffling:
		return
	_shuffling = wants_shuffle
	if _shuffle_player.stream == null:
		return
	if _shuffling:
		_shuffle_player.play()
	else:
		_shuffle_player.stop()


## Called (via the Player's wiring) on the FootstepStamper's plant edge.
## `foot` is 0 = left, 1 = right, straight from the print system — the same
## event that stamps that foot's print fires that foot's sound.
func on_foot_planted(foot: int, world_xz: Vector2) -> void:
	if _crouched:
		return
	var running: bool = _planar_speed > run_speed_threshold
	_surface = resolve_surface(world_xz)
	last_step_surface = _surface
	last_step_volume_db = run_volume_db if running else walk_volume_db
	steps_played += 1
	var at: Vector3 = Vector3(world_xz.x, global_position.y, world_xz.y)
	noise_made.emit(at, 1.0 if running else 0.5)

	# Preferred mode (Joshua's design, 2026-08-15): each foot owns one fixed
	# sample per surface, so the step pattern is as deterministic as the
	# prints it rides on. Running keeps the identical samples, just louder.
	var own: AudioStream = SoundBank.stream(
		"footsteps/%s_%s.wav" % [_surface, "left" if foot == 0 else "right"]
	)
	if own != null:
		var player: AudioStreamPlayer3D = _foot_players[foot]
		player.stream = own
		player.volume_db = last_step_volume_db
		player.global_position = at
		player.play()
		return

	# Fallback for surfaces without per-foot samples: the numbered take set,
	# with walk takes reused at run loudness when no run set exists.
	var takes: AudioStreamRandomizer = SoundBank.take_set(
		"footsteps/%s_%s" % [_surface, "run" if running else "walk"]
	)
	if takes == null and running:
		takes = SoundBank.take_set("footsteps/%s_walk" % _surface)
	_play(_step_player, takes, last_step_volume_db, at)


## Called by the owning Player the moment a jump launches.
func on_jumped() -> void:
	_play(
		_air_player, SoundBank.take_set("movement/jump"), jump_volume_db, global_position
	)
	noise_made.emit(global_position, 0.6)


## Called by the owning Player on touchdown.
func on_landed(impact_speed: float) -> void:
	var hard: bool = impact_speed >= hard_landing_speed
	var takes: AudioStreamRandomizer = SoundBank.take_set(
		"movement/land_hard" if hard else "movement/land_soft"
	)
	_play(
		_air_player,
		takes,
		land_hard_volume_db if hard else land_soft_volume_db,
		global_position
	)
	noise_made.emit(global_position, 1.0 if hard else 0.6)


## Handed down by the Player alongside its own terrain reference.
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain = terrain


## What the ground at [param world_xz] sounds like: "sand", "packed", or a
## collider's `surface` tag ("stone", "wood", …). Public for the verify
## harness, which probes known spots.
func resolve_surface(world_xz: Vector2) -> String:
	var from: Vector3 = Vector3(world_xz.x, global_position.y + 0.6, world_xz.y)
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * 2.5, 1
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return _surface
	var collider: Object = hit["collider"]
	if collider is TerrainChunk:
		var depth: float = 1.0
		if _terrain != null:
			depth = _terrain.get_sand_depth(world_xz)
		return "packed" if depth < packed_sand_depth else "sand"
	if collider.has_meta("surface"):
		return String(collider.get_meta("surface"))
	return "stone"


## True while the sneak shuffle should be sounding (whether or not its file
## has been sourced) — for the verify harness.
func is_shuffling() -> bool:
	return _shuffling


func _make_player() -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.bus = &"SFX"
	player.max_distance = 40.0
	add_child(player)
	return player


func _play(
	player: AudioStreamPlayer3D, takes: AudioStreamRandomizer, volume_db: float, at: Vector3
) -> void:
	if takes == null:
		return
	if player.stream != takes:
		player.stream = takes
	player.volume_db = volume_db
	player.global_position = at
	player.play()
