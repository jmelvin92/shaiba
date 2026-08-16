class_name SaveSystem
extends Node
## Save/load for the playable level (added 2026-08-15 at Joshua's direction,
## on the 6.6 branch alongside the pause menu that triggers it).
##
## The persistence contract — the part meant to outlive today's content:
## any node that has state worth saving joins the "persistent" group and
## implements three methods:
##
##   get_persistence_key() -> String            a stable ID (see key_for)
##   capture_state() -> Dictionary              JSON-safe values only
##   restore_state(state: Dictionary, context: Dictionary) -> void
##
## The SaveSystem never knows what a door or a lamp is: it walks the group,
## files each node's dictionary under its key, and hands the dictionaries
## back on load. New savable content (a camel, an inventory) implements the
## contract and is saved from then on — no changes here. `context` carries
## level references a restore may legitimately need ("actor": the player —
## the torch stand uses it to put a carried torch back in the hand); it may
## grow keys, and implementers must ignore keys they don't use.
##
## Keys: stability matters more than beauty — a save written today should
## load after scenes are reorganized. Scene-unique props use a short hand
## picked name via their exported override; the default is the node's tree
## path, which is fine for singletons but breaks if the node moves. Old keys
## in a save that no longer match any node are skipped with a warning, never
## an error — saves from older versions must stay loadable.
##
## Footprints are deliberately NOT saved: Phase 5's memory model is "long
## but local" — ephemeral by design, wind refills them.

const SAVE_PATH: String = "user://saves/save_01.json"
const SAVE_VERSION: int = 1
const GROUP: StringName = &"persistent"

var _player: Player = null
var _chunk_manager: ChunkManager = null


## The default persistence key: the node's path below /root — stable as long
## as the scene tree keeps its shape. Nodes pass their exported override
## through so hand-picked keys win.
static func key_for(node: Node, override: String = "") -> String:
	if not override.is_empty():
		return override
	return String(node.get_path()).trim_prefix("/root/")


## Called by the owning level (LevelRoot) — the references restores need.
func setup(player: Player, chunk_manager: ChunkManager) -> void:
	_player = player
	_chunk_manager = chunk_manager


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var states: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var key: String = node.get_persistence_key()
		if states.has(key):
			push_warning(
				"SaveSystem: duplicate persistence key '%s' (%s) — later node wins."
				% [key, node.name]
			)
		states[key] = node.capture_state()
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"states": states,
	}
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SAVE_PATH.get_base_dir())
	)
	var out: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if out == null:
		push_warning("SaveSystem: cannot write %s" % SAVE_PATH)
		return false
	out.store_string(JSON.stringify(payload, "\t"))
	out.close()
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if payload is not Dictionary:
		push_warning("SaveSystem: %s is not a valid save file." % SAVE_PATH)
		return false
	var data: Dictionary = payload as Dictionary
	if int(data.get("version", 0)) > SAVE_VERSION:
		push_warning("SaveSystem: save is from a newer game version; not loading.")
		return false
	var states: Dictionary = data.get("states", {}) as Dictionary
	var context: Dictionary = {"actor": _player}
	var known: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var key: String = node.get_persistence_key()
		known[key] = true
		if states.has(key):
			node.restore_state(states[key] as Dictionary, context)
	for key: String in states.keys():
		if not known.has(key):
			push_warning(
				"SaveSystem: no node answers to saved key '%s'; skipped." % key
			)
	# The player may have been restored far from where they stood: rebuild
	# the chunks around them synchronously (set_tracked's contract) so the
	# ground's collision exists before the next physics tick.
	if _chunk_manager != null and _player != null:
		_chunk_manager.set_tracked(_player)
		_player.reset_physics_interpolation()
	return true
