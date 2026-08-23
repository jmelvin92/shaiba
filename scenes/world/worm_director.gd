class_name WormDirector
extends Node
## The sand worm's encounter director (Phase 6.8 Part 3): decides when the
## desert's giant exists at all. Joshua's call — noise wakes it. The player's
## own sounds (footsteps, landings; any future noisemaker that emits
## `noise_made(position, loudness)`) charge a hidden attraction meter that
## drains during quiet play; when it crests, the worm enters the world far
## away and comes hunting. Rarity emerges from behaviour, never a timer: a
## quiet, watchful player might never meet it.
##
## Two physical rules live here rather than in the worm:
##   - noise only carries through sand deep enough to swim in — steps on
##     packed earth, the homestead pad or thin skins are silent to the worm,
##     which is the same physics that makes that ground safe to stand on;
##   - after a hunt ends (departure, dismissal or a kill) a calm-down window
##     keeps the next encounter distant, so hunts never chain.
##
## The director is a plain world-scene node: LevelRoot connects the player's
## `noise_made` to [method hear_noise] and calls [method setup]. It owns no
## worm behaviour — it wakes the worm ([method SandWorm.hunt]) and forwards
## fresh noise to it ([method SandWorm.hear]); the hunt itself is the worm's.

## Accumulated loudness at which the worm wakes. Walking takes several
## times longer than running; crouching never wakes it (crouched feet make
## no noise at all).
##
## PLAYTEST VALUE (2026-08-23, Joshua's ask): 60 ≈ 25 s of sustained
## running — easy to trigger while the hunt is being tuned. The shipping
## rarity ("incredibly rare") wants this back up around 300+ once the feel
## locks; the encounter should be something a quiet player may never see.
@export_range(20.0, 2000.0, 5.0) var attraction_threshold: float = 60.0
## Meter units added per unit of noise loudness.
@export_range(0.1, 10.0, 0.1) var noise_gain: float = 1.0
## Meter units drained per second of quiet — patience erases attention.
@export_range(0.0, 10.0, 0.05) var attraction_decay: float = 0.6
## Sand shallower than this at the noise's position does not carry it to
## the worm. Matched to the worm's own swimmable minimum by default: ground
## it cannot swim through is also ground it cannot listen through.
@export_range(0.05, 2.0, 0.05) var min_carry_depth: float = 0.5
## Quiet window after a hunt ends before the meter may build again, seconds.
## PLAYTEST VALUE (2026-08-23): 45 so encounters can chain while tuning;
## shipping rarity wants minutes here (the plan's original 240).
@export_range(0.0, 1800.0, 5.0) var calm_seconds: float = 45.0

var _worm: SandWorm = null
var _terrain: TerrainSettings = null
var _focus: Node3D = null
var _attraction: float = 0.0
var _calm_left: float = 0.0


## Called by the owning level once the worm and terrain exist. Without them
## the director is inert — the standalone-scene contract.
func setup(worm: SandWorm, terrain: TerrainSettings, focus: Node3D) -> void:
	_worm = worm
	_terrain = terrain
	_focus = focus
	if not worm.hunt_ended.is_connected(_on_hunt_ended):
		worm.hunt_ended.connect(_on_hunt_ended)


## A noise happened in the world — the player's feet today, any connected
## noisemaker tomorrow (thrown rocks, radios: same signal, same connect).
func hear_noise(world_position: Vector3, loudness: float) -> void:
	if _worm == null or _terrain == null:
		return
	var at: Vector2 = Vector2(world_position.x, world_position.z)
	if _terrain.get_sand_depth(at) < min_carry_depth:
		return
	if _worm.is_hunting():
		_worm.hear(at, loudness)
		return
	if _worm.is_active():
		# A debug-summoned worm is a demo, not a hunter; leave it alone and
		# keep the meter still so F7 sessions don't queue up an ambush.
		return
	if _calm_left > 0.0:
		return
	_attraction += loudness * noise_gain
	if _attraction >= attraction_threshold:
		if _worm.hunt(at):
			_attraction = 0.0


func get_attraction() -> float:
	return _attraction


func get_calm_left() -> float:
	return _calm_left


## For verify tooling: clears any calm window so checks need not wait it out.
func clear_calm() -> void:
	_calm_left = 0.0


## One line for the F3 overlay; pulled, never pushed.
func get_debug_text() -> String:
	if _calm_left > 0.0:
		return "director calm %ds" % int(ceilf(_calm_left))
	return "director attraction %d%%" % int(
		100.0 * _attraction / maxf(attraction_threshold, 0.001)
	)


func _process(delta: float) -> void:
	_attraction = maxf(_attraction - attraction_decay * delta, 0.0)
	_calm_left = maxf(_calm_left - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	# F10: skip the accumulation and start a hunt at the player, for
	# playtesting the encounter without minutes of running first.
	if event.is_action_pressed("debug_worm_hunt"):
		if _worm == null or _focus == null or _worm.is_active():
			return
		_calm_left = 0.0
		_attraction = 0.0
		_worm.hunt(Vector2(_focus.global_position.x, _focus.global_position.z))


func _on_hunt_ended() -> void:
	_attraction = 0.0
	_calm_left = calm_seconds
