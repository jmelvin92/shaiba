class_name TerrainDebugOverlay
extends CanvasLayer
## The F3 streaming readout: player chunk, chunk counts, streaming cost,
## frame time and memory. Hidden by default; the ChunkManager that owns it
## toggles visibility and pushes the chunk numbers down each frame — this
## node never reaches up for them.

@onready var _label: Label = $Label

## The Game autoload, fetched the guarded way so the scene stays standalone-
## safe and the script compiles outside a running project (--check-only).
@onready var _game: Node = get_node_or_null(^"/root/Game")

## Worst process frame seen in the current one-second window, and the window
## it was measured over — "worst 12 ms" is what a hitch looks like on a
## readout, where an instantaneous number would blink past.
var _window_worst_ms: float = 0.0
var _window_started_ms: int = 0
var _shown_worst_ms: float = 0.0


## Called by the owning ChunkManager once per frame while visible.
func update_stats(
	chunk_coord: Vector2i, loaded: int, pending: int,
	apply_ms: float, worst_apply_ms: float
) -> void:
	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_window_worst_ms = maxf(_window_worst_ms, frame_ms)
	var now: int = Time.get_ticks_msec()
	if now - _window_started_ms >= 1000:
		_shown_worst_ms = _window_worst_ms
		_window_worst_ms = 0.0
		_window_started_ms = now

	_label.text = (
		"chunk (%d, %d)   loaded %d   building %d\n" % [chunk_coord.x, chunk_coord.y, loaded, pending]
		+ "apply %.2f ms   worst %.2f ms\n" % [apply_ms, worst_apply_ms]
		+ "frame %.1f ms   worst %.1f ms/s   %d fps\n" % [
			frame_ms, _shown_worst_ms, roundi(Performance.get_monitor(Performance.TIME_FPS))]
		+ "static mem %.0f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	)
	if _game != null:
		_label.text += "\ntime %s   day %d   %s" % [
			_game.clock_text(), _game.day_count, _game.period]
