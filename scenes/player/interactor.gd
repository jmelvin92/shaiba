class_name Interactor
extends Area3D
## The player's reach: finds nearby [Interactable]s, offers the closest one
## with a floating key prompt, and fires it when the interact key is pressed.
##
## This is the player-side half of the interaction system (the prop-side half
## is [Interactable] — see docs/ARCHITECTURE.md). It is a self-contained child
## of the player scene: player.gd never knows it exists, and props never know
## who used them beyond the actor node handed to them. The overlap query is
## physics-layer 4 only, so this volume can see interaction zones and nothing
## else — walls, terrain and bodies are invisible to it.
##
## The prompt is a single [Label3D] this node owns and repositions over
## whichever Interactable is currently closest, so any number of usable props
## can stand together without a cloud of competing labels.

## How the prompt reads, e.g. "E — Open". %s slots: key name, then the
## Interactable's own prompt text.
@export var prompt_format: String = "%s — %s"
## Prompt lettering, from the palette: plaster on night_blue.
@export var prompt_color: Color = Color("F2E7CF")
@export var prompt_outline_color: Color = Color("34455E")
@export_range(8, 96, 1) var prompt_font_size: int = 30

var _label: Label3D = null
var _target: Interactable = null
var _key_name: String = "E"


func _ready() -> void:
	collision_layer = 0
	collision_mask = Interactable.LAYER_INTERACTION
	monitorable = false
	_key_name = _interact_key_name()
	_label = Label3D.new()
	_label.top_level = true
	_label.visible = false
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.pixel_size = 0.0009
	_label.font_size = prompt_font_size
	_label.outline_size = int(prompt_font_size * 0.4)
	_label.modulate = prompt_color
	_label.outline_modulate = prompt_outline_color
	# The label teleports between props rather than travelling; interpolating
	# those jumps would smear it across the screen.
	_label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_label)


func _physics_process(_delta: float) -> void:
	_target = _closest_interactable()
	if _target == null:
		_label.visible = false
		return
	_label.text = prompt_format % [_key_name, _target.prompt]
	_label.global_position = _target.get_prompt_position()
	_label.visible = true
	if Input.is_action_just_pressed("interact"):
		var actor: Node3D = owner as Node3D
		_target.interact(actor if actor != null else self)


## The Interactable currently on offer, if any — read by the verify harness.
func get_target() -> Interactable:
	return _target


func _closest_interactable() -> Interactable:
	var best: Interactable = null
	var best_distance: float = INF
	for area: Area3D in get_overlapping_areas():
		var candidate: Interactable = area as Interactable
		if candidate == null or not candidate.enabled:
			continue
		var distance: float = global_position.distance_squared_to(
			candidate.global_position
		)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## The key bound to `interact`, for the prompt. Falls back to "E" when the
## binding or the display server can't say (headless runs, notably).
func _interact_key_name() -> String:
	for event: InputEvent in InputMap.action_get_events(&"interact"):
		var key: InputEventKey = event as InputEventKey
		if key == null:
			continue
		var keycode: Key = key.keycode
		if keycode == KEY_NONE and key.physical_keycode != KEY_NONE \
				and DisplayServer.get_name() != "headless":
			keycode = DisplayServer.keyboard_get_keycode_from_physical(
				key.physical_keycode
			)
		if keycode != KEY_NONE:
			return OS.get_keycode_string(keycode)
	return "E"
