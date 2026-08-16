extends SceneTree
## Save/load gate as an executable (2026-08-15, Phase 6.6 branch):
##
##   Godot --headless --path . --script res://tools/verify_save.gd
##
## Against the real world scene: mutates everything savable (clock, player,
## camera, doors, lamp, carried torch), saves, mutates everything *again*,
## loads, and asserts the first state came back. Also asserts the save file's
## shape (version + stable keys), that a save carrying an unknown key from
## some future version loads with a warning rather than an error, and that
## loading with no file is a clean refusal. The real save file is
## snapshotted and restored, so the gate never eats a real save.

const WORLD_SCENE: String = "res://scenes/world/world.tscn"

var _failures: int = 0
var _saved_bytes: PackedByteArray = PackedByteArray()
var _had_save: bool = false


func _initialize() -> void:
	_had_save = FileAccess.file_exists(SaveSystem.SAVE_PATH)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SaveSystem.SAVE_PATH)
	var world: Node3D = (load(WORLD_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	_run(world)


func _run(world: Node3D) -> void:
	await process_frame
	await process_frame

	var save_system: SaveSystem = world.get_node("SaveSystem") as SaveSystem
	var game: Node = root.get_node("/root/Game")
	var player: Player = world.get_node("Player") as Player
	var rig: CameraRig = world.get_node("CameraRig") as CameraRig
	var door: Door = world.get_node("Homestead/House/FrontDoor") as Door
	var lamp: OilLamp = world.get_node(
		"Homestead/House/Furnishings/Ground/OilLamp"
	) as OilLamp
	var stand: TorchStand = world.get_node("Homestead/TorchStand") as TorchStand
	var torch: Node3D = stand.get_node("Torch") as Node3D
	var terrain: TerrainSettings = (
		world.get_node("ChunkManager") as ChunkManager
	).get_terrain()

	print("preconditions:")
	_check("save system present in world", save_system != null)
	_check("all savable actors found", door != null and lamp != null and stand != null)

	print("no-file behaviour:")
	if save_system.has_save():
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(SaveSystem.SAVE_PATH)
		)
	_check("load with no save file refuses cleanly", not save_system.load_game())

	print("save:")
	game.set_time_of_day(2.25)
	game.day_count = 3
	var here: Vector3 = player.global_position + Vector3(12.0, 0.0, 7.0)
	here.y = terrain.get_surface_height(Vector2(here.x, here.z)) + 0.1
	player.global_position = here
	player.rotation.y = 1.2
	rig.set_yaw_degrees(123.0)
	rig.zoom_distance = 15.0
	door.set_open(true, true)
	lamp.lit = true
	(stand.get_node("Interactable") as Interactable).interacted.emit(player)
	_check("mutation took: torch is carried", torch.get_parent() != stand)
	_check("save_game succeeds", save_system.save_game())

	print("file shape:")
	var payload: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(SaveSystem.SAVE_PATH)
	)
	var data: Dictionary = payload as Dictionary
	_check("file is JSON with version %d" % SaveSystem.SAVE_VERSION,
		data != null and int(data.get("version", -1)) == SaveSystem.SAVE_VERSION)
	var states: Dictionary = data.get("states", {}) as Dictionary
	for key: String in [
		"game_clock", "player", "camera",
		"house_front_door", "house_upper_door", "house_oil_lamp", "torch_stand",
	]:
		_check("stable key '%s' saved" % key, states.has(key))

	print("load restores over a different present:")
	game.set_time_of_day(9.0)
	game.day_count = 0
	player.global_position += Vector3(-6.0, 0.0, 4.0)
	player.rotation.y = 0.0
	rig.set_yaw_degrees(10.0)
	rig.zoom_distance = 30.0
	door.set_open(false, true)
	lamp.lit = false
	(stand.get_node("Interactable") as Interactable).interacted.emit(player)
	_check("second mutation took: torch back on stand", torch.get_parent() == stand)

	_check("load_game succeeds", save_system.load_game())
	_check("clock restored (02:15, day 3)",
		absf(float(game.time_of_day) - 2.25) < 0.01 and int(game.day_count) == 3)
	_check("period follows the restored clock", game.period == &"night")
	_check("player position restored",
		player.global_position.distance_to(here) < 0.01)
	_check("player yaw restored", absf(player.rotation.y - 1.2) < 0.001)
	_check("camera restored (yaw 123, zoom 15)",
		absf(rig.yaw_degrees - 123.0) < 0.001
			and absf(rig.zoom_distance - 15.0) < 0.001)
	_check("front door restored open", door.is_open())
	_check("lamp restored lit", lamp.lit)
	_check("torch restored into the hand", torch.get_parent() != stand)

	print("forward compatibility:")
	states["some_future_prop"] = {"anything": 1}
	var out: FileAccess = FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	out.store_string(JSON.stringify(data))
	out.close()
	_check(
		"a save carrying an unknown key still loads (warns, never errors)",
		save_system.load_game()
	)

	_restore_snapshot()
	if _failures == 0:
		print("verify_save: ALL PASS")
	else:
		print("verify_save: %d FAILURE(S)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(what: String, ok: bool) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _restore_snapshot() -> void:
	if _had_save:
		var out: FileAccess = FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
		out.store_buffer(_saved_bytes)
		out.close()
	elif FileAccess.file_exists(SaveSystem.SAVE_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(SaveSystem.SAVE_PATH)
		)
