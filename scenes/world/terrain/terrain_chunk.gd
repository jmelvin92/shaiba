class_name TerrainChunk
extends StaticBody3D
## One 64 m square of desert: terrain mesh + heightfield collision.
##
## The expensive half of a chunk's life happens off the main thread:
## [method build_data] is a pure static function — no tree access, no shared
## state beyond read-only [TerrainSettings] — that a WorkerThreadPool task can
## run to produce a finished mesh and collision shape. The cheap half,
## [method apply], runs on the main thread when the chunk enters the tree.
##
## Collision is a [HeightMapShape3D] built from the same samples as the mesh,
## and the mesh's cells are split along the same diagonal the physics engine
## uses ((x+1, z) → (x, z+1)), so collision and visuals are the same surface.
## tools/verify_terrain.gd --collision audits exactly that.

## Everything a worker thread produces for one chunk. The mesh travels as raw
## arrays, not an ArrayMesh: creating rendering resources off the main thread
## works on the real renderer but corrupts RIDs under the headless dummy
## renderer, and the main-thread add_surface_from_arrays for one chunk is
## well under a millisecond anyway. The collision shape has no such problem —
## the physics server takes it happily from a worker.
class BuildData:
	extends RefCounted

	var coord: Vector2i
	var arrays: Array
	var shape: HeightMapShape3D
	## Where the collision shape sits in chunk-local space: HeightMapShape3D is
	## centred on its owner, while the mesh spans [0, size] from the chunk origin.
	var collision_offset: Vector3


@onready var _mesh_instance: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $Collision


## Builds one chunk's mesh and collision from the noise fields. Safe to call
## from any thread once [param settings] has been seeded.
static func build_data(settings: TerrainSettings, coord: Vector2i) -> BuildData:
	var cells: int = settings.chunk_size
	var n: int = cells + 1
	var cell: float = settings.cell_size

	var heights: PackedFloat32Array = []
	heights.resize(n * n)
	var vertices: PackedVector3Array = []
	vertices.resize(n * n)
	var colors: PackedColorArray = []
	colors.resize(n * n)

	# Read off the settings resource, never load()ed here: build_data runs on
	# worker threads, and a thread-side load() misses runtime palette changes
	# (ChunkManager fills these from the palette .tres on the main thread).
	var shadow: Color = settings.sand_shadow_color
	var mid: Color = settings.sand_mid_color
	var light: Color = settings.sand_light_color

	for j: int in range(n):
		# World coordinates derive from *global integer* grid indices, so the
		# vertices a chunk shares with its neighbour are bit-identical and the
		# seam cannot open. Never accumulate floats from the chunk origin.
		var gz: int = coord.y * cells + j
		var wz: float = float(gz) * cell
		for i: int in range(n):
			var gx: int = coord.x * cells + i
			var wx: float = float(gx) * cell
			var at: Vector2 = Vector2(wx, wz)

			var height: float = settings.get_surface_height(at)
			var index: int = j * n + i
			heights[index] = height
			vertices[index] = Vector3(float(i) * cell, height, float(j) * cell)

			# Dither is sampled at roughly a sixth of the ripple frequency so it
			# reads as broad patches of lighter and darker sand, not per-vertex
			# speckle that averages away at the gameplay camera.
			var depth_norm: float = settings.get_normalized_depth(at)
			var tone: float = depth_norm + settings.tone_dither * settings.ripple_noise.get_noise_2d(
				wx * 0.35 + 511.0, wz * 0.35 - 511.0
			)
			tone = clampf(tone, 0.0, 1.0)
			var rgb: Color
			if tone < 0.5:
				rgb = shadow.lerp(mid, tone * 2.0)
			else:
				rgb = mid.lerp(light, tone * 2.0 - 1.0)
			# The blend happens in sRGB (that is what the palette values are),
			# then converts, because vertex COLOR reaches the shader raw where a
			# StandardMaterial3D albedo would be converted by the engine.
			var color: Color = rgb.srgb_to_linear()
			# Alpha carries normalised sand depth — Phase 5's per-fragment cap
			# on footprint depth. Deliberately the un-dithered value.
			color.a = depth_norm
			colors[index] = color

	var indices: PackedInt32Array = []
	indices.resize(cells * cells * 6)
	var cursor: int = 0
	for j: int in range(cells):
		for i: int in range(cells):
			var v00: int = j * n + i
			var v10: int = v00 + 1
			var v01: int = v00 + n
			var v11: int = v01 + 1
			# Both triangles share the (x+1, z) → (x, z+1) diagonal, matching
			# HeightMapShape3D's own triangulation.
			indices[cursor] = v00
			indices[cursor + 1] = v10
			indices[cursor + 2] = v01
			indices[cursor + 3] = v10
			indices[cursor + 4] = v11
			indices[cursor + 5] = v01
			cursor += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights

	var data: BuildData = BuildData.new()
	data.coord = coord
	data.arrays = arrays
	data.shape = shape
	# The heightmap's samples are centred on the shape's origin; the mesh spans
	# [0, cells × cell] from the chunk origin. Half the span reconciles them.
	var half: float = float(cells) * cell * 0.5
	data.collision_offset = Vector3(half, 0.0, half)
	return data


## Installs a finished build on this chunk. Main thread only — this is where
## the ArrayMesh resource actually gets created (see BuildData).
func apply(data: BuildData) -> void:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.arrays)
	_mesh_instance.mesh = mesh
	_collision.shape = data.shape
	_collision.position = data.collision_offset


