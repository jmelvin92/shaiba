class_name SandDeformation
extends Node3D
## The sand's memory: accumulates stamps into a deformation texture that the
## terrain shader reads for vertex depression + a compacted darkening.
##
## Anything may mark the sand through [method stamp] — the level connects a
## stamper's signal to it (the player's footfalls today, camel feet or dragged
## objects later). This node knows nothing about who stamps; it only follows
## its tracked node to keep the region centred.
##
## The texture covers a [member region_size] square of world space centred on
## the tracked player, held in a ping-pong pair of [SubViewport]s. Each update
## renders the previous accumulation into the other viewport through
## sand_deform_copy.gdshader — shifted when the region recentres, reduced by
## decay — and draws any new stamps additively on top. Recentring moves the
## region by whole texels only, so old prints are copied exactly, never
## resampled: repeated shifts cannot blur or swim them.
##
## Memory is "long but local" (PLAN.md Phase 5): prints persist for
## [member fade_seconds] near the player; walk far enough that they leave the
## region and they are quietly forgotten. Decay doubles as wind refilling the
## prints, and the whole accumulation additionally migrates downwind by
## [member wind_drift_per_minute] — in whole texels, keeping copies exact —
## so old trails smear the way the dunes lie. A future real wind system
## replaces the drift constant, nothing else.
##
## Cost model: nothing renders unless a pass is scheduled. Stamps and
## recentres trigger passes (rate-capped at [member max_update_hz]); while old
## prints are still fading, low-rate decay passes keep them moving; once the
## last print has fully faded the system goes completely idle — stand still
## long enough and the frame cost is zero. [member last_pass_ms],
## [member worst_pass_ms] and [member passes_run] expose the main-thread cost
## for tools/verify_prints.gd.

## Passes per second while only decay is pending (no stamps, no recentre).
const DECAY_HZ: float = 4.0
## Pixel size of the radial stamp brush texture.
const STAMP_TEXTURE_SIZE: int = 64

## One queued mark on the sand.
class Stamp:
	extends RefCounted

	var at: Vector2
	var radius: float
	var strength: float
	var angle: float
	var stretch: float
	## How wet the sand was where this stamp landed, 0 dry to 1 soaked —
	## resolved from the terrain at stamp time, never carried by the signal.
	var wetness: float
	## True for a raise mark (Phase 6.8): sand heaved up into the texture's B
	## channel — the worm's mound — instead of pressed into R.
	var raised: bool = false


@export_group("Region")
## World-space width of the deformation region, metres.
@export_range(32.0, 512.0, 32.0) var region_size: float = 128.0
## Deformation texture resolution. texels per metre = texture_size / region_size.
## A footprint is ~0.3 m across and needs 4+ texels to resolve without
## aliasing — at 128 m regions that demands 2048 (16 texels/m).
@export_range(256, 4096, 256) var texture_size: int = 2048
## How far the player may drift from the region's centre before it recentres.
@export_range(2.0, 32.0, 0.5) var recenter_distance: float = 8.0

@export_group("Prints")
## Depression of a full-strength print in metres of sand — scaled down by the
## local sand depth, so hard ground takes nothing.
@export_range(0.0, 0.5, 0.01) var max_print_depth: float = 0.12
## How strongly a full print darkens the sand toward the compacted tint.
@export_range(0.0, 1.0, 0.05) var tint_strength: float = 0.55
## Metres of local sand at which a print reaches full strength; shallower
## sand takes proportionally fainter prints, bare hard ground none.
@export_range(0.05, 2.0, 0.05) var print_full_depth: float = 0.3
## Seconds for a full-strength print to fade back to untouched sand.
@export_range(30.0, 600.0, 5.0) var fade_seconds: float = 180.0
## Metres the accumulated prints migrate downwind per minute while fading.
@export_range(0.0, 5.0, 0.1) var wind_drift_per_minute: float = 0.5
## How fast wet-sand prints decay relative to dry ones (Phase 6.7: the beach's
## swash band remembers). 0.3 = a soaked print outlives a dry one three-fold;
## the wetness rides the deformation texture's G channel — the per-material
## decay-class slot the Phase 5 biome contract reserved.
@export_range(0.05, 1.0, 0.05) var wet_fade_scale: float = 0.3
## Update-rate cap for stamp/recentre passes.
@export_range(1.0, 30.0, 0.5) var max_update_hz: float = 12.0

@export_group("Mounds")
## Lift of fully raised sand in metres (Phase 6.8: the worm's traveling
## mound) — scaled down by local sand depth exactly like prints, so hard
## ground heaves nothing.
@export_range(0.0, 1.5, 0.05) var mound_height: float = 0.9
## Seconds for a full mound to slump back to flat sand. Short by design: at
## worm speed this bounds the visible wake to a dozen metres of collapsing
## swell behind the body — longer reads as a built berm wall, not motion.
@export_range(1.0, 60.0, 0.5) var mound_settle_seconds: float = 1.4
## How strongly fully raised sand darkens toward the churned tint.
@export_range(0.0, 1.0, 0.05) var mound_tint_strength: float = 0.45

## Main-thread cost of the last texture pass, ms (scheduling + sprite setup;
## the render itself is GPU-side). Read by verify tooling.
var last_pass_ms: float = 0.0
var worst_pass_ms: float = 0.0
## Total passes rendered since load. Standing still with everything faded,
## this must stop climbing — that is the "zero cost when idle" gate.
var passes_run: int = 0
## Verbose per-pass logging, for verify tooling chasing texture bugs.
var debug_log: bool = false

var _terrain_material: ShaderMaterial = preload(
	"res://resources/terrain/sand_terrain_material.tres"
) as ShaderMaterial
var _copy_shader: Shader = preload("res://shaders/sand_deform_copy.gdshader")

var _viewports: Array[SubViewport] = []
var _copy_materials: Array[ShaderMaterial] = []
var _stamp_roots: Array[Node2D] = []
## Index of the viewport currently holding the accumulated texture.
var _read: int = 0
## World xz of the region's minimum corner, snapped to the texel grid.
var _origin: Vector2 = Vector2.ZERO
var _tracked: Node3D = null
var _pending: Array[Stamp] = []
var _time: float = 0.0
var _last_pass: float = 0.0
var _last_pass_frame: int = -1
## While _time is below this, prints may still be fading and decay passes run.
var _content_until: float = -1.0
## Downwind unit direction in world xz, from the terrain's wind yaw.
var _wind_direction: Vector2 = Vector2.ZERO
## Sub-texel wind displacement carried until it amounts to a whole texel.
var _wind_carry: Vector2 = Vector2.ZERO
var _stamp_texture: GradientTexture2D
## Raise marks use a coreless brush: a print's flat core is what gives a
## footprint its crisp floor, but overlapping flat cores saturate the mound
## channel into a plateau whose edges the 1 m terrain mesh renders as blocky
## terraces. A smooth peak overlaps into a soft-shouldered ridge instead.
var _raise_texture: GradientTexture2D
var _stamp_material: CanvasItemMaterial
## Terrain query source for per-stamp wetness. Null (no coast, isolation
## harnesses) means every stamp is dry — exactly the pre-coast behaviour.
var _terrain: TerrainSettings = null


func _ready() -> void:
	_stamp_texture = _build_stamp_texture()
	_raise_texture = _build_raise_texture()
	_stamp_material = CanvasItemMaterial.new()
	_stamp_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for _i: int in range(2):
		_build_viewport()
	_copy_materials[0].set_shader_parameter("prev_map", _viewports[1].get_texture())
	_copy_materials[1].set_shader_parameter("prev_map", _viewports[0].get_texture())
	for copy: ShaderMaterial in _copy_materials:
		copy.set_shader_parameter("wet_decay_scale", wet_fade_scale)
		# decay_amount is normalised to the print fade time, so the mound's
		# faster settle is expressed as a multiple of it.
		copy.set_shader_parameter(
			"mound_decay_scale", fade_seconds / mound_settle_seconds
		)

	var shadow: Color = (load(
		"res://resources/palette/sand_shadow.tres"
	) as StandardMaterial3D).albedo_color.srgb_to_linear()
	var light: Color = (load(
		"res://resources/palette/sand_light.tres"
	) as StandardMaterial3D).albedo_color.srgb_to_linear()
	_terrain_material.set_shader_parameter(
		"deform_tint",
		Vector3(shadow.r / light.r, shadow.g / light.g, shadow.b / light.b)
	)
	_terrain_material.set_shader_parameter("deform_tint_strength", tint_strength)
	_terrain_material.set_shader_parameter("deform_size", region_size)
	_terrain_material.set_shader_parameter("deform_strength", max_print_depth)
	_terrain_material.set_shader_parameter("deform_raise", mound_height)
	_terrain_material.set_shader_parameter("deform_raise_tint", mound_tint_strength)
	_terrain_material.set_shader_parameter(
		"deformation_map", _viewports[_read].get_texture()
	)


## The shared terrain material outlives this node (it is a saved resource), so
## leave it inert for whoever renders with it next — this is what keeps the
## graybox and any deformation-free level untouched.
func _exit_tree() -> void:
	_terrain_material.set_shader_parameter("deform_strength", 0.0)
	_terrain_material.set_shader_parameter("deform_raise", 0.0)


## Called by the owning level: rescales the vertex-alpha depth cap from the
## colour ramp's normalisation to this rig's [member print_full_depth], reads
## the wind direction the drift leans with, and keeps the terrain for
## resolving how wet the sand is under each stamp.
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain = terrain
	_terrain_material.set_shader_parameter(
		"deform_cap_scale", terrain.tone_full_depth / print_full_depth
	)
	var yaw: float = deg_to_rad(terrain.wind_yaw_degrees)
	_wind_direction = Vector2(cos(yaw), sin(yaw))


## Called by the owning level: whose position the region follows.
func set_tracked(target: Node3D) -> void:
	_tracked = target
	_origin = _snapped_origin()
	_terrain_material.set_shader_parameter("deform_origin", _origin)


## Mark the sand. Anything may call this (usually via a stamper signal the
## level connected): position/radius in world metres, strength 0–1, angle in
## radians, stretch elongating the mark along its angle.
func stamp(
	world_xz: Vector2,
	radius: float,
	strength: float,
	angle: float = 0.0,
	stretch: float = 1.0
) -> void:
	var entry: Stamp = Stamp.new()
	entry.at = world_xz
	entry.radius = radius
	entry.strength = strength
	entry.angle = angle
	entry.stretch = stretch
	entry.wetness = 0.0 if _terrain == null else _terrain.get_wetness(world_xz)
	_pending.append(entry)


## Heave the sand up instead of pressing it down (Phase 6.8): the worm's
## traveling mound. Same contract as [method stamp] — anything may call it,
## usually via a raiser signal the level connected — but the mark rides the
## texture's B channel with its own fast settle, so prints are untouched.
func raise(
	world_xz: Vector2,
	radius: float,
	strength: float,
	angle: float = 0.0,
	stretch: float = 1.0
) -> void:
	var entry: Stamp = Stamp.new()
	entry.at = world_xz
	entry.radius = radius
	entry.strength = strength
	entry.angle = angle
	entry.stretch = stretch
	entry.raised = true
	_pending.append(entry)


## True when nothing is queued and every print has fully faded — the state in
## which this system costs exactly nothing per frame.
func is_idle() -> bool:
	return _pending.is_empty() and _time >= _content_until


## Current region origin and the accumulated texture, for verify tooling.
func get_debug_state() -> Dictionary:
	return {
		"origin": _origin,
		"texture": _viewports[_read].get_texture(),
	}


func _physics_process(delta: float) -> void:
	_time += delta
	if _tracked == null:
		return
	var since_pass: float = _time - _last_pass
	if not _pending.is_empty() or _needs_recenter():
		if since_pass >= 1.0 / max_update_hz:
			_run_pass()
	elif _time < _content_until and since_pass >= 1.0 / DECAY_HZ:
		_run_pass()


func _needs_recenter() -> bool:
	if _tracked == null:
		return false
	var center: Vector2 = _origin + Vector2(region_size, region_size) * 0.5
	var at: Vector2 = Vector2(_tracked.global_position.x, _tracked.global_position.z)
	return center.distance_to(at) > recenter_distance


## One ping-pong update: carry the accumulation into the write viewport
## (shifted + decayed + wind-drifted), draw pending stamps on top, point the
## terrain at it.
func _run_pass() -> void:
	# The read viewport must actually have rendered since the last pass, or
	# this would copy from a stale texture and drop that pass's stamps —
	# possible when physics ticks outpace drawn frames (high Engine.time_scale).
	if Engine.get_frames_drawn() == _last_pass_frame:
		return
	var started: int = Time.get_ticks_usec()
	_last_pass_frame = Engine.get_frames_drawn()
	var write: int = 1 - _read
	var elapsed: float = _time - _last_pass
	var new_origin: Vector2 = _snapped_origin() if _needs_recenter() else _origin

	# Wind migration accumulates until it amounts to whole texels, then rides
	# along as an extra content shift — still an exact texel-for-texel copy.
	var texel: float = region_size / float(texture_size)
	_wind_carry += _wind_direction * (wind_drift_per_minute / 60.0) * elapsed
	var wind_step: Vector2 = Vector2(
		floorf(_wind_carry.x / texel), floorf(_wind_carry.y / texel)
	) * texel
	_wind_carry -= wind_step

	var copy: ShaderMaterial = _copy_materials[write]
	var uv_shift: Vector2 = (new_origin - _origin - wind_step) / region_size
	if debug_log:
		print("[sand] pass %d: shift %s decay %.4f pending %d" % [
			passes_run, uv_shift, elapsed / fade_seconds, _pending.size(),
		])
	copy.set_shader_parameter("uv_shift", uv_shift)
	copy.set_shader_parameter("decay_amount", elapsed / fade_seconds)

	var stamps: Node2D = _stamp_roots[write]
	for child: Node in stamps.get_children():
		child.free()
	var px_per_m: float = float(texture_size) / region_size
	for entry: Stamp in _pending:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = _raise_texture if entry.raised else _stamp_texture
		sprite.material = _stamp_material
		sprite.position = (entry.at - new_origin) * px_per_m
		sprite.rotation = entry.angle
		var base: float = entry.radius * 2.0 * px_per_m / float(STAMP_TEXTURE_SIZE)
		sprite.scale = Vector2(base * entry.stretch, base)
		# R carries the press, G carries press × wetness — so G/R *is* the
		# wetness, which the copy shader reads as the decay class. A raise
		# mark writes B alone: the mound channel, untouched by print math.
		sprite.modulate = (
			Color(0.0, 0.0, entry.strength, 1.0) if entry.raised
			else Color(entry.strength, entry.strength * entry.wetness, 0.0, 1.0)
		)
		stamps.add_child(sprite)
	for entry: Stamp in _pending:
		# Mound-only content settles in seconds; keep decay passes running no
		# longer than the longest-lived mark actually pending.
		_content_until = maxf(
			_content_until,
			_time + (mound_settle_seconds if entry.raised else fade_seconds)
		)
	_pending.clear()

	_viewports[write].render_target_update_mode = SubViewport.UPDATE_ONCE
	_terrain_material.set_shader_parameter(
		"deformation_map", _viewports[write].get_texture()
	)
	_terrain_material.set_shader_parameter("deform_origin", new_origin)
	_origin = new_origin
	_read = write
	_last_pass = _time
	passes_run += 1
	last_pass_ms = float(Time.get_ticks_usec() - started) / 1000.0
	worst_pass_ms = maxf(worst_pass_ms, last_pass_ms)


## Region origin that centres the player, snapped to whole texels so recentre
## shifts copy texel-for-texel (see the class comment on blur).
func _snapped_origin() -> Vector2:
	var texel: float = region_size / float(texture_size)
	var target: Vector2 = Vector2(
		_tracked.global_position.x, _tracked.global_position.z
	) - Vector2(region_size, region_size) * 0.5
	return Vector2(floorf(target.x / texel), floorf(target.y / texel)) * texel


func _build_viewport() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(texture_size, texture_size)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	var copy: ColorRect = ColorRect.new()
	copy.position = Vector2.ZERO
	copy.size = Vector2(float(texture_size), float(texture_size))
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _copy_shader
	copy.material = material
	viewport.add_child(copy)

	var stamps: Node2D = Node2D.new()
	viewport.add_child(stamps)

	_viewports.append(viewport)
	_copy_materials.append(material)
	_stamp_roots.append(stamps)


func _build_stamp_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.35, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = STAMP_TEXTURE_SIZE
	texture.height = STAMP_TEXTURE_SIZE
	return texture


## The mound brush: same radial fill, but falling from the very centre — see
## [member _raise_texture] for why raises must not have a flat core.
func _build_raise_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = STAMP_TEXTURE_SIZE
	texture.height = STAMP_TEXTURE_SIZE
	return texture
