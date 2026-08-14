class_name ChunkManager
extends Node3D
## Streams the desert around a tracked node (the player).
##
## Owns every live [TerrainChunk] as a direct child. Each frame it makes sure
## all chunks within [member load_radius] of the tracked node's chunk exist and
## frees everything beyond [member unload_radius] — the gap between the two
## keeps a chunk from thrashing in and out while the player walks the border.
##
## A node inside the level scene, not an autoload (docs/ARCHITECTURE.md): the
## level that owns it calls [method set_tracked] once, and hands the terrain to
## whoever else needs it via [method get_terrain].

const CHUNK_SCENE: PackedScene = preload("res://scenes/world/terrain/terrain_chunk.tscn")

## The desert's noise fields and tunables — normally resources/terrain/desert.tres.
@export var settings: TerrainSettings
## Chunks kept loaded in every direction from the player's chunk (2 ⇒ 5×5).
@export_range(1, 8) var load_radius: int = 2
## Distance in chunks beyond which a loaded chunk is freed. Must exceed
## load_radius or border chunks load and unload every step.
@export_range(2, 10) var unload_radius: int = 3

## Live chunks by chunk coordinate.
var _chunks: Dictionary = {}
var _tracked: Node3D = null


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
		return
	settings.setup(game.world_seed)


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


func _process(_delta: float) -> void:
	if _tracked == null:
		return
	var center: Vector2i = _chunk_coord(_tracked.global_position)
	_load_missing(center)
	_unload_distant(center)


## World position → chunk coordinate.
func _chunk_coord(world_position: Vector3) -> Vector2i:
	var span: float = float(settings.chunk_size) * settings.cell_size
	return Vector2i(
		int(floorf(world_position.x / span)),
		int(floorf(world_position.z / span))
	)


func _load_missing(center: Vector2i) -> void:
	for dz: int in range(-load_radius, load_radius + 1):
		for dx: int in range(-load_radius, load_radius + 1):
			var coord: Vector2i = center + Vector2i(dx, dz)
			if not _chunks.has(coord):
				_spawn(TerrainChunk.build_data(settings, coord))


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
