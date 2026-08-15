extends SceneTree
## Phase 6.5 piece 1's quality gate as a runnable script (pattern:
## tools/verify_terrain.gd).
##
## Run headless:
##   Godot --headless --path . --script res://tools/verify_clock.gd
##
## Drives a fresh instance of the Game clock through a full simulated day of
## 60 Hz frames (engine processing disabled, so only the harness ticks it) and
## asserts: the day costs exactly day_length_minutes of summed frame time, the
## midnight wrap increments day_count, hour_passed fires once per hour in
## order across the wrap, period_changed walks day → dusk → night → dawn →
## day, pausing halts time, and the rewind/jump paths keep the period honest
## without ever emitting hour_passed.
##
## Prints FAIL lines and exits non-zero on any failure.

const GameClock := preload("res://autoload/game.gd")

const FRAME_DELTA: float = 1.0 / 60.0

var _failures: PackedStringArray = []
var _hours: Array[int] = []
var _periods: Array[StringName] = []


func _init() -> void:
	process_frame.connect(_start)


func _start() -> void:
	process_frame.disconnect(_start)
	_run()
	print("")
	if _failures.is_empty():
		print("verify_clock: all checks passed")
		quit(0)
	else:
		for line: String in _failures:
			print("FAIL  " + line)
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _make_clock() -> Node:
	var clock: Node = GameClock.new()
	root.add_child(clock)
	clock.set_process(false)
	clock.hour_passed.connect(func(hour: int) -> void: _hours.append(hour))
	clock.period_changed.connect(func(p: StringName) -> void: _periods.append(p))
	_hours.clear()
	_periods.clear()
	return clock


func _run() -> void:
	_launch_state()
	_full_day()
	_exact_boundary()
	_pause()
	_rewind_and_jump()
	_clock_text()
	_scrub_keys()
	_overlay_shows_time()


## Fresh clock: 16:00, day 0, "day" period.
func _launch_state() -> void:
	var clock: Node = _make_clock()
	_check(is_equal_approx(clock.time_of_day, 16.0), "launch time is %.2f, wanted 16.00" % clock.time_of_day)
	_check(clock.day_count == 0, "launch day_count is %d, wanted 0" % clock.day_count)
	_check(clock.period == GameClock.PERIOD_DAY, "launch period is %s, wanted day" % clock.period)
	_check(clock.clock_text() == "16:00", "launch clock_text is %s, wanted 16:00" % clock.clock_text())
	_check(clock.is_daytime(), "16:00 should report daytime")
	clock.free()


## One full simulated day of 60 Hz frames: length, wrap, signal order.
func _full_day() -> void:
	var clock: Node = _make_clock()
	var day_seconds: float = clock.day_length_minutes * 60.0
	var simulated: float = 0.0
	while _hours.size() < 24 and simulated < day_seconds + 60.0:
		clock._process(FRAME_DELTA)
		simulated += FRAME_DELTA
	var real_minutes: float = simulated / 60.0
	_check(absf(real_minutes - clock.day_length_minutes) < 0.1,
		"full day consumed %.3f real minutes of frame time, wanted %.1f" % [real_minutes, clock.day_length_minutes])
	_check(clock.day_count == 1, "after one day day_count is %d, wanted 1" % clock.day_count)
	_check(absf(clock.time_of_day - 16.0) < 0.01,
		"after one day time is %.4f, wanted 16.00" % clock.time_of_day)
	_check(_hours.size() == 24, "hour_passed fired %d times over one day, wanted 24" % _hours.size())
	var expected_hours: Array[int] = []
	for i: int in 24:
		expected_hours.append((17 + i) % 24)
	_check(_hours == expected_hours, "hour_passed order was %s" % str(_hours))
	var expected_periods: Array[StringName] = [
		GameClock.PERIOD_DUSK, GameClock.PERIOD_NIGHT,
		GameClock.PERIOD_DAWN, GameClock.PERIOD_DAY,
	]
	_check(_periods == expected_periods, "period order was %s" % str(_periods))
	clock.free()


## Landing exactly on an hour boundary fires it once — and never twice.
func _exact_boundary() -> void:
	var clock: Node = _make_clock()
	clock.advance_hours(1.0)
	_check(_hours == ([17] as Array[int]), "advancing 16:00→17:00 fired %s, wanted [17]" % str(_hours))
	clock.advance_hours(0.25)
	_check(_hours == ([17] as Array[int]), "17:00→17:15 re-fired the boundary: %s" % str(_hours))
	clock.free()


## time_paused freezes _process advancement completely.
func _pause() -> void:
	var clock: Node = _make_clock()
	clock.time_paused = true
	for i: int in 600:
		clock._process(FRAME_DELTA)
	_check(is_equal_approx(clock.time_of_day, 16.0),
		"paused clock moved to %.4f" % clock.time_of_day)
	_check(_hours.is_empty() and _periods.is_empty(), "paused clock emitted signals")
	clock.free()


## Rewind and jump update the period but never emit hour_passed; rewinding
## across midnight decrements day_count and never goes negative.
func _rewind_and_jump() -> void:
	var clock: Node = _make_clock()
	clock.set_time_of_day(18.0)
	_check(clock.period == GameClock.PERIOD_DUSK, "18:00 period is %s, wanted dusk" % clock.period)
	clock.rewind_hours(1.0)
	_check(is_equal_approx(clock.time_of_day, 17.0), "rewind landed at %.2f, wanted 17.00" % clock.time_of_day)
	_check(clock.period == GameClock.PERIOD_DAY, "17:00 period is %s, wanted day" % clock.period)
	_check(_hours.is_empty(), "rewind emitted hour_passed: %s" % str(_hours))
	_check(_periods == ([GameClock.PERIOD_DUSK, GameClock.PERIOD_DAY] as Array[StringName]),
		"rewind period trail was %s" % str(_periods))
	clock.advance_hours(24.0 * 2.0)
	var days_before: int = clock.day_count
	clock.rewind_hours(20.0)
	_check(clock.day_count == days_before - 1,
		"rewind across midnight left day_count %d, wanted %d" % [clock.day_count, days_before - 1])
	clock.set_time_of_day(1.0)
	clock.day_count = 0
	clock.rewind_hours(30.0)
	_check(clock.day_count == 0, "day_count went negative: %d" % clock.day_count)
	_check(is_equal_approx(clock.time_of_day, 19.0),
		"rewind 30 h from 01:00 landed at %.2f, wanted 19.00" % clock.time_of_day)
	clock.free()


## The ]/[ bindings in project.godot really drive the clock, both ways, and
## deliberately override time_paused. Real key events go through Input so the
## InputMap entries themselves are what's tested.
func _scrub_keys() -> void:
	var clock: Node = _make_clock()
	_press_bracket(KEY_BRACKETRIGHT, true)
	clock._process(1.0)
	var expected: float = 16.0 + clock.debug_scrub_speed
	_check(absf(clock.time_of_day - expected) < 0.001,
		"1 s of ] moved time to %.3f, wanted %.3f" % [clock.time_of_day, expected])
	_press_bracket(KEY_BRACKETRIGHT, false)
	_press_bracket(KEY_BRACKETLEFT, true)
	clock.time_paused = true
	clock._process(1.0)
	_check(absf(clock.time_of_day - 16.0) < 0.001,
		"1 s of [ (while paused) moved time to %.3f, wanted 16.000" % clock.time_of_day)
	_press_bracket(KEY_BRACKETLEFT, false)
	clock._process(1.0)
	_check(absf(clock.time_of_day - 16.0) < 0.001,
		"paused clock with keys released moved to %.3f" % clock.time_of_day)
	clock.free()


func _press_bracket(key: Key, down: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## The F3 overlay renders the time line from a clock at /root/Game.
func _overlay_shows_time() -> void:
	var clock: Node = _make_clock()
	clock.set_time_of_day(9.5)
	var overlay: CanvasLayer = (
		load("res://scenes/world/terrain/terrain_debug_overlay.tscn") as PackedScene).instantiate()
	root.add_child(overlay)
	overlay._game = clock
	overlay.update_stats(Vector2i.ZERO, 0, 0, 0.0, 0.0)
	var text: String = overlay._label.text
	_check(text.contains("time 09:30   day 0   day"),
		"overlay text missing the time line: %s" % text.get_slice("\n", text.get_slice_count("\n") - 1))
	overlay.free()
	clock.free()


## clock_text formatting.
func _clock_text() -> void:
	var clock: Node = _make_clock()
	clock.set_time_of_day(9.5)
	_check(clock.clock_text() == "09:30", "09:30 renders as %s" % clock.clock_text())
	clock.set_time_of_day(0.0)
	_check(clock.clock_text() == "00:00", "midnight renders as %s" % clock.clock_text())
	clock.free()
