class_name ChunkManager
extends Node3D
## Streams the desert around a tracked node (the player).
##
## Owns every live [TerrainChunk] as a direct child. Each frame it makes sure
## all chunks within [member load_radius] of the tracked node's chunk exist and
## frees everything beyond [member unload_radius] — the gap between the two
## keeps a chunk from thrashing in and out while the player walks the border.
##
## Chunk builds run on [WorkerThreadPool] threads: the worker produces a
## finished mesh and collision shape (TerrainChunk.build_data is pure), pushes
## it onto a mutex-guarded queue, and this node drains the queue on the main
## thread under a per-frame time budget — so ten chunks finishing at once
## still enter the tree a few at a time and streaming never owns the frame.
##
## A node inside the level scene, not an autoload (docs/ARCHITECTURE.md): the
## level that owns it calls [method set_tracked] once, and hands the terrain to
## whoever else needs it via [method get_terrain].

const CHUNK_SCENE: PackedScene = preload("res://scenes/world/terrain/terrain_chunk.tscn")
## The one material every chunk renders with. The manager owns pushing
## terrain-derived uniforms into it (currently the wind direction the ripple
## shading lies across); per-print uniforms stay SandDeformation's job.
const TERRAIN_MATERIAL: ShaderMaterial = preload("res://resources/terrain/sand_terrain_material.tres")

## The desert's noise fields and tunables — normally resources/terrain/desert.tres.
@export var settings: TerrainSettings
## Chunks kept loaded in every direction from the player's chunk (2 ⇒ 5×5).
@export_range(1, 8) var load_radius: int = 2
## Distance in chunks beyond which a loaded chunk is freed. Must exceed
## load_radius or border chunks load and unload every step.
@export_range(2, 10) var unload_radius: int = 3
## Main-thread time allowed per frame for installing finished chunks, ms.
## At least one chunk is installed per frame regardless, so the queue drains.
@export_range(0.5, 8.0, 0.5) var build_budget_ms: float = 2.0

## Live chunks by chunk coordinate.
var _chunks: Dictionary = {}
## WorkerThreadPool task id by chunk coordinate, for builds in flight.
var _pending: Dictionary = {}
## Finished builds waiting to enter the tree. Guarded by _results_mutex.
var _results: Array = []
var _results_mutex: Mutex = Mutex.new()
var _tracked: Node3D = null
## Streaming diagnostics, read by the debug overlay and verify_terrain: the
## main-thread cost of installing chunks last frame and the worst since reset.
var last_apply_ms: float = 0.0
var worst_apply_ms: float = 0.0

## Optional F3 readout child. Looked up by name so levels without one work.
@onready var _overlay: TerrainDebugOverlay = get_node_or_null(^"DebugOverlay") as TerrainDebugOverlay


func _ready() -> void:
	if settings == null:
		push_warning("ChunkManager: no TerrainSettings assigned; terrain disabled.")
		set_process(false)
		return
	# Fetched through the tree rather than by the `Game` identifier so this
	# script still compiles under `--check-only`, which runs without autoloads.
	var game: Node = get_node_or_null(^"/root/Game")
	if game == null:
		push_warning("ChunkManager: Game autoload missing; seeding terrain with 0.")
		settings.setup(0)
	else:
		settings.setup(game.world_seed)
	settings.load_palette()
	var wind_yaw: float = deg_to_rad(settings.wind_yaw_degrees)
	TERRAIN_MATERIAL.set_shader_parameter(
		"ripple_wind_dir", Vector2(cos(wind_yaw), sin(wind_yaw))
	)


## Called by the owning level. Synchronously builds the chunks around the
## target before returning, so its collision exists before the first physics
## tick — the level can then seat the target on the surface with no falling.
func set_tracked(target: Node3D) -> void:
	_tracked = target
	if settings == null:
		return
	_load_missing(_chunk_coord(target.global_position))


func get_terrain() -> TerrainSettings:
	return settings


## Live chunk count, for the debug overlay and the streaming tests.
func get_loaded_count() -> int:
	return _chunks.size()


## Builds currently running or queued on worker threads.
func get_pending_count() -> int:
	return _pending.size()


## Blocks until every in-flight build has finished. The workers hold a bound
## reference to this node, so it must not be freed while any task still runs.
##
## Those last workers each push a finished [TerrainChunk.BuildData] onto the
## results queue on their way out, and nothing will ever install them — so the
## queue is dropped here too. BuildData is a RefCounted, and leaving a handful
## of them in a member array at teardown is exactly the "ObjectDB instances
## were leaked" warning at exit. It only showed up once the player's spawn
## moved out to the homestead, far enough that chunks are still streaming when
## a short headless run quits.
func _exit_tree() -> void:
	for coord: Vector2i in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[coord] as int)
	_pending.clear()
	_results_mutex.lock()
	_results.clear()
	_results_mutex.unlock()


func _process(_delta: float) -> void:
	if _tracked == null:
		return
	var center: Vector2i = _chunk_coord(_tracked.global_position)
	_collect_finished_tasks()
	_apply_results(center)
	_request_missing(center)
	_unload_distant(center)
	if _overlay != null and _overlay.visible:
		_overlay.update_stats(
			center, _chunks.size(), _pending.size(), last_apply_ms, worst_apply_ms
		)


func _unhandled_input(event: InputEvent) -> void:
	if _overlay != null and event.is_action_pressed("debug_overlay"):
		_overlay.visible = not _overlay.visible


## World position → chunk coordinate.
func _chunk_coord(world_position: Vector3) -> Vector2i:
	var span: float = float(settings.chunk_size) * settings.cell_size
	return Vector2i(
		int(floorf(world_position.x / span)),
		int(floorf(world_position.z / span))
	)


## Synchronous fill, used only at spawn where the ground must exist *now*.
func _load_missing(center: Vector2i) -> void:
	for dz: int in range(-load_radius, load_radius + 1):
		for dx: int in range(-load_radius, load_radius + 1):
			var coord: Vector2i = center + Vector2i(dx, dz)
			if not _chunks.has(coord):
				_spawn(TerrainChunk.build_data(settings, coord))


## Releases the pool's handle for every build whose worker has finished. The
## results themselves arrive through the queue; this is only task bookkeeping.
func _collect_finished_tasks() -> void:
	for coord: Vector2i in _pending.keys():
		var task_id: int = _pending[coord]
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			_pending.erase(coord)


## Installs finished builds until the frame budget is spent (always at least
## one). Builds whose chunk has meanwhile left the unload radius are dropped —
## tasks cannot be cancelled mid-run, so this is where stale work dies.
func _apply_results(center: Vector2i) -> void:
	var started: int = Time.get_ticks_usec()
	var deadline: int = started + int(build_budget_ms * 1000.0)
	_apply_results_inner(center, deadline)
	last_apply_ms = float(Time.get_ticks_usec() - started) / 1000.0
	worst_apply_ms = maxf(worst_apply_ms, last_apply_ms)


func _apply_results_inner(center: Vector2i, deadline: int) -> void:
	while true:
		_results_mutex.lock()
		var data: TerrainChunk.BuildData = null
		if not _results.is_empty():
			data = _results.pop_back()
		_results_mutex.unlock()
		if data == null:
			return
		var offset: Vector2i = data.coord - center
		var wanted: bool = maxi(absi(offset.x), absi(offset.y)) <= unload_radius
		if wanted and not _chunks.has(data.coord):
			_spawn(data)
		if Time.get_ticks_usec() >= deadline:
			return


## Queues builds for every missing chunk in range, nearest first so the ground
## under the player's feet always wins over the horizon.
func _request_missing(center: Vector2i) -> void:
	var missing: Array[Vector2i] = []
	for dz: int in range(-load_radius, load_radius + 1):
		for dx: int in range(-load_radius, load_radius + 1):
			var coord: Vector2i = center + Vector2i(dx, dz)
			if not _chunks.has(coord) and not _pending.has(coord):
				missing.append(coord)
	if missing.is_empty():
		return
	missing.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - center).length_squared() < (b - center).length_squared()
	)
	for coord: Vector2i in missing:
		_pending[coord] = WorkerThreadPool.add_task(
			_build_task.bind(coord), false, "TerrainChunk %s" % coord
		)


## Runs on a WorkerThreadPool thread. Touches nothing but the read-only
## settings and the mutex-guarded results queue.
func _build_task(coord: Vector2i) -> void:
	var data: TerrainChunk.BuildData = TerrainChunk.build_data(settings, coord)
	_results_mutex.lock()
	_results.append(data)
	_results_mutex.unlock()


func _unload_distant(center: Vector2i) -> void:
	for coord: Vector2i in _chunks.keys():
		var offset: Vector2i = (coord as Vector2i) - center
		if maxi(absi(offset.x), absi(offset.y)) > unload_radius:
			(_chunks[coord] as TerrainChunk).queue_free()
			_chunks.erase(coord)


func _spawn(data: TerrainChunk.BuildData) -> void:
	var chunk: TerrainChunk = CHUNK_SCENE.instantiate() as TerrainChunk
	var span: float = float(settings.chunk_size) * settings.cell_size
	chunk.position = Vector3(data.coord.x * span, 0.0, data.coord.y * span)
	add_child(chunk)
	chunk.apply(data)
	# Runtime-added nodes otherwise interpolate in from the origin for a frame.
	chunk.reset_physics_interpolation()
	_chunks[data.coord] = chunk
