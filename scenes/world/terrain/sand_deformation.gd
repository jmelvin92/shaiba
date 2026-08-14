class_name SandDeformation
extends Node3D
## The sand's memory: accumulates footprint stamps into a deformation texture
## that the terrain shader reads for vertex depression + a compacted tint.
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
## prints.
##
## Cost model: nothing renders unless a pass is scheduled. Stamps and
## recentres trigger passes (rate-capped at [member max_update_hz]); while old
## prints are still fading, low-rate decay passes keep them moving; once the
## last print has fully faded the system goes completely idle — stand still
## long enough and the frame cost is zero.

## Passes per second while only decay is pending (no stamps, no recentre).
const DECAY_HZ: float = 4.0
## Pixel size of the radial stamp brush texture.
const STAMP_TEXTURE_SIZE: int = 64

@export_group("Region")
## World-space width of the deformation region, metres.
@export_range(32.0, 512.0, 32.0) var region_size: float = 128.0
## Deformation texture resolution. texels per metre = texture_size / region_size.
@export_range(256, 4096, 256) var texture_size: int = 1024
## How far the player may drift from the region's centre before it recentres.
@export_range(2.0, 32.0, 0.5) var recenter_distance: float = 8.0

@export_group("Prints")
## Depression of a full-strength print in metres of sand — scaled down by the
## local normalised sand depth (vertex COLOR.a), so hard ground takes nothing.
@export_range(0.0, 0.5, 0.01) var max_print_depth: float = 0.12
## How strongly a full print darkens the sand toward the compacted tint.
@export_range(0.0, 1.0, 0.05) var tint_strength: float = 0.55
## Metres of local sand at which a print reaches full strength; shallower
## sand takes proportionally fainter prints, bare hard ground none.
@export_range(0.05, 2.0, 0.05) var print_full_depth: float = 0.3
## Seconds for a full-strength print to fade back to untouched sand.
@export_range(30.0, 600.0, 5.0) var fade_seconds: float = 180.0
## Update-rate cap for stamp/recentre passes.
@export_range(1.0, 30.0, 0.5) var max_update_hz: float = 12.0

@export_group("Prototype stamping")
## Distance between successive footfalls at a walk (one stamp every half of it).
@export_range(0.2, 2.0, 0.05) var stride_length: float = 0.75
## Radius of one footprint stamp, metres.
@export_range(0.05, 1.0, 0.01) var foot_radius: float = 0.22
## Sideways offset of each foot from the path centreline, metres.
@export_range(0.0, 0.5, 0.01) var foot_offset: float = 0.14
## Strength of a normal footstep (1 = presses the surface the full cap).
@export_range(0.0, 1.0, 0.05) var stamp_strength: float = 0.85
## Base radius of the stamp left by landing from a jump or fall.
@export_range(0.0, 2.0, 0.05) var landing_radius: float = 0.45

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
var _tracked: CharacterBody3D = null
## Queued stamps as (world x, world z, radius m, strength 0..1).
var _pending: Array[Vector4] = []
var _time: float = 0.0
var _last_pass: float = 0.0
var _last_pass_frame: int = -1
## While _time is below this, prints may still be fading and decay passes run.
var _content_until: float = -1.0
var _distance_to_step: float = 0.0
var _left_foot: bool = false
var _stamp_texture: GradientTexture2D
var _stamp_material: CanvasItemMaterial


func _ready() -> void:
	_stamp_texture = _build_stamp_texture()
	_stamp_material = CanvasItemMaterial.new()
	_stamp_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for _i: int in range(2):
		_build_viewport()
	_copy_materials[0].set_shader_parameter("prev_map", _viewports[1].get_texture())
	_copy_materials[1].set_shader_parameter("prev_map", _viewports[0].get_texture())

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
	_terrain_material.set_shader_parameter(
		"deformation_map", _viewports[_read].get_texture()
	)


## The shared terrain material outlives this node (it is a saved resource), so
## leave it inert for whoever renders with it next — this is what keeps the
## graybox and any deformation-free level untouched.
func _exit_tree() -> void:
	_terrain_material.set_shader_parameter("deform_strength", 0.0)


## Called by the owning level: rescales the vertex-alpha depth cap from the
## colour ramp's normalisation to this rig's [member print_full_depth].
func set_terrain(terrain: TerrainSettings) -> void:
	_terrain_material.set_shader_parameter(
		"deform_cap_scale", terrain.tone_full_depth / print_full_depth
	)


## Called by the owning level (see LevelRoot): who leaves prints in the sand.
func set_tracked(target: CharacterBody3D) -> void:
	_tracked = target
	if target.has_signal("landed"):
		target.connect("landed", _on_landed)
	_origin = _snapped_origin()
	_terrain_material.set_shader_parameter("deform_origin", _origin)


func _physics_process(delta: float) -> void:
	_time += delta
	if _tracked == null:
		return
	_clock_footsteps(delta)

	var since_pass: float = _time - _last_pass
	if not _pending.is_empty() or _needs_recenter():
		if since_pass >= 1.0 / max_update_hz:
			_run_pass()
	elif _time < _content_until and since_pass >= 1.0 / DECAY_HZ:
		_run_pass()


## Prototype stamping: footfalls clocked by distance travelled, alternating
## feet either side of the path. The real thing (later this phase) times
## stamps to the walk/run animation's toe bones instead.
func _clock_footsteps(delta: float) -> void:
	var planar: Vector2 = Vector2(_tracked.velocity.x, _tracked.velocity.z)
	var speed: float = planar.length()
	if not _tracked.is_on_floor() or speed < 0.3:
		return
	_distance_to_step -= speed * delta
	if _distance_to_step > 0.0:
		return
	_distance_to_step += stride_length * 0.5

	var forward: Vector2 = planar / speed
	var side: Vector2 = Vector2(-forward.y, forward.x)
	var sign_offset: float = foot_offset if _left_foot else -foot_offset
	_left_foot = not _left_foot
	var at: Vector2 = Vector2(
		_tracked.global_position.x, _tracked.global_position.z
	) + side * sign_offset
	_pending.append(Vector4(at.x, at.y, foot_radius, stamp_strength))


func _on_landed(impact_speed: float) -> void:
	var at: Vector2 = Vector2(_tracked.global_position.x, _tracked.global_position.z)
	var radius: float = landing_radius * clampf(0.5 + impact_speed * 0.12, 0.7, 1.4)
	_pending.append(Vector4(at.x, at.y, radius, 1.0))


func _needs_recenter() -> bool:
	if _tracked == null:
		return false
	var center: Vector2 = _origin + Vector2(region_size, region_size) * 0.5
	var at: Vector2 = Vector2(_tracked.global_position.x, _tracked.global_position.z)
	return center.distance_to(at) > recenter_distance


## One ping-pong update: carry the accumulation into the write viewport
## (shifted + decayed), draw pending stamps on top, point the terrain at it.
func _run_pass() -> void:
	# The read viewport must actually have rendered since the last pass, or
	# this would copy from a stale texture and drop that pass's stamps —
	# possible when physics ticks outpace drawn frames (high Engine.time_scale).
	if Engine.get_frames_drawn() == _last_pass_frame:
		return
	_last_pass_frame = Engine.get_frames_drawn()
	var write: int = 1 - _read
	var new_origin: Vector2 = _snapped_origin() if _needs_recenter() else _origin

	var copy: ShaderMaterial = _copy_materials[write]
	copy.set_shader_parameter("uv_shift", (new_origin - _origin) / region_size)
	copy.set_shader_parameter("decay_amount", (_time - _last_pass) / fade_seconds)

	var stamps: Node2D = _stamp_roots[write]
	for child: Node in stamps.get_children():
		child.free()
	var px_per_m: float = float(texture_size) / region_size
	for stamp: Vector4 in _pending:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = _stamp_texture
		sprite.material = _stamp_material
		sprite.position = (Vector2(stamp.x, stamp.y) - new_origin) * px_per_m
		sprite.scale = Vector2.ONE * (
			stamp.z * 2.0 * px_per_m / float(STAMP_TEXTURE_SIZE)
		)
		sprite.modulate = Color(stamp.w, stamp.w, stamp.w, 1.0)
		stamps.add_child(sprite)
	if not _pending.is_empty():
		_content_until = _time + fade_seconds
	_pending.clear()

	_viewports[write].render_target_update_mode = SubViewport.UPDATE_ONCE
	_terrain_material.set_shader_parameter(
		"deformation_map", _viewports[write].get_texture()
	)
	_terrain_material.set_shader_parameter("deform_origin", new_origin)
	_origin = new_origin
	_read = write
	_last_pass = _time


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
