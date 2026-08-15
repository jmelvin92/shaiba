extends Node
## Global game state singleton (`Game`).
## Keep this deliberately small — see docs/ARCHITECTURE.md before adding
## anything here; new global state usually belongs in a scene instead.

## Fired when the clock crosses the top of an hour — once per hour, in order,
## carrying the hour just begun (0–23). Fires only while time runs forward;
## the debug rewind never emits it.
signal hour_passed(hour: int)

## Fired when the clock enters a new named period (one of PERIOD_* below).
## Discrete reactions (lamps at dusk, future gameplay) connect here; anything
## that moves smoothly with the sun samples `time_of_day` every frame instead.
signal period_changed(period: StringName)

const PERIOD_NIGHT: StringName = &"night"
const PERIOD_DAWN: StringName = &"dawn"
const PERIOD_DAY: StringName = &"day"
const PERIOD_DUSK: StringName = &"dusk"

## Period boundaries, in game hours. Night wraps midnight: [19.5, 5.0).
const DAWN_START_HOUR: float = 5.0
const DAY_START_HOUR: float = 6.5
const DUSK_START_HOUR: float = 17.5
const NIGHT_START_HOUR: float = 19.5

## Where piece 2 will put the sun on the horizon — the mid-points of dawn and
## dusk — and what `is_daytime()` reports against.
const SUNRISE_HOUR: float = 5.75
const SUNSET_HOUR: float = 18.5

## Seed for all deterministic world generation (terrain, prop scatter).
var world_seed: int = 20260813

## One full in-game day, in real minutes. 24.0 ⇒ 1 real minute = 1 game hour
## (Joshua's pick, 2026-08-14 — see DECISIONS.md).
@export_range(1.0, 120.0, 0.5) var day_length_minutes: float = 24.0

## Hour the clock starts at on launch. 16:00 opens every session on the
## signature late-afternoon look.
@export_range(0.0, 23.99) var start_hour: float = 16.0

## How fast the debug scrub keys move time, in game hours per real second.
@export_range(0.5, 12.0, 0.5) var debug_scrub_speed: float = 2.0

## Current time of day in game hours, always in [0, 24).
var time_of_day: float = 16.0

## Completed midnights since launch.
var day_count: int = 0

## The named period `time_of_day` currently falls in.
var period: StringName = PERIOD_DAY

## Freezes the clock (cutscenes, debugging). Tree pause also halts it, since
## this node ticks in _process with the default pause behaviour. The debug
## scrub keys deliberately still work while frozen.
var time_paused: bool = false


func _init() -> void:
	time_of_day = fposmod(start_hour, 24.0)
	period = period_at(time_of_day)


func _process(delta: float) -> void:
	if Input.is_action_pressed(&"debug_time_forward"):
		advance_hours(delta * debug_scrub_speed)
	elif Input.is_action_pressed(&"debug_time_back"):
		rewind_hours(delta * debug_scrub_speed)
	elif not time_paused:
		advance_hours(delta * 24.0 / (day_length_minutes * 60.0))


## Runs the clock forward, emitting hour_passed for every whole hour crossed
## (in order, midnight included) and period_changed on period boundaries.
func advance_hours(hours: float) -> void:
	if hours <= 0.0:
		return
	var target: float = time_of_day + hours
	var next_boundary: float = floorf(time_of_day) + 1.0
	while next_boundary <= target:
		hour_passed.emit(int(next_boundary) % 24)
		next_boundary += 1.0
	day_count += int(floorf(target / 24.0))
	time_of_day = fposmod(target, 24.0)
	_refresh_period()


## Debug-only: runs the clock backward. Updates the period but never emits
## hour_passed — hours don't "pass" in reverse.
func rewind_hours(hours: float) -> void:
	if hours <= 0.0:
		return
	var target: float = time_of_day - hours
	if target < 0.0:
		day_count = maxi(0, day_count + int(floorf(target / 24.0)))
	time_of_day = fposmod(target, 24.0)
	_refresh_period()


## Jumps straight to an hour (tools, tests, piece 2's lighting ladders).
## Updates the period; emits no hour_passed.
func set_time_of_day(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	_refresh_period()


## The named period a given hour falls in.
func period_at(hour: float) -> StringName:
	var h: float = fposmod(hour, 24.0)
	if h < DAWN_START_HOUR or h >= NIGHT_START_HOUR:
		return PERIOD_NIGHT
	if h < DAY_START_HOUR:
		return PERIOD_DAWN
	if h < DUSK_START_HOUR:
		return PERIOD_DAY
	return PERIOD_DUSK


## True between sunrise and sunset (the sun-above-horizon hours).
func is_daytime() -> bool:
	return time_of_day >= SUNRISE_HOUR and time_of_day < SUNSET_HOUR


## Time of day as a 0–1 fraction of the full day (piece 2's sun input).
func normalized_time() -> float:
	return time_of_day / 24.0


## "16:42" — for the debug overlay and any future readout.
func clock_text() -> String:
	return "%02d:%02d" % [int(time_of_day), int(fposmod(time_of_day, 1.0) * 60.0)]


func _refresh_period() -> void:
	var now: StringName = period_at(time_of_day)
	if now != period:
		period = now
		period_changed.emit(now)
