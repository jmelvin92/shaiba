class_name SoundBank
extends RefCounted
## The one place that knows how sound files are named (Phase 6.6).
##
## Everything audible in the game asks this class for its streams, by the
## naming convention documented in assets/audio/README.md. Files Joshua has
## sourced are found and wired automatically; files that don't exist yet come
## back null, and every caller treats null as "play nothing" — so the whole
## audio system runs silent-but-correct with an empty assets/audio folder,
## which is also what tools/verify_audio.gd verifies against.
##
## Never instanced — static functions and static caches only. The caches mean
## each file is loaded and each variation set scanned exactly once per run.

const ROOT: String = "res://assets/audio/"
## Numbered variations are scanned _01.._MAX; the README starts sets at _01.
const MAX_TAKES: int = 40

static var _streams: Dictionary = {}
static var _sets: Dictionary = {}


## One exact file under assets/audio/, or null if it isn't there (or isn't
## imported yet). `looped` marks the stream as looping — loops are .ogg by
## convention, but a looped .wav is honoured too.
static func stream(sub_path: String, looped: bool = false) -> AudioStream:
	if _streams.has(sub_path):
		return _streams[sub_path]
	var found: AudioStream = null
	var path: String = ROOT + sub_path
	if ResourceLoader.exists(path, "AudioStream"):
		found = load(path) as AudioStream
	if found != null and looped:
		var ogg: AudioStreamOggVorbis = found as AudioStreamOggVorbis
		if ogg != null:
			ogg.loop = true
		var wav: AudioStreamWAV = found as AudioStreamWAV
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			# loop_end defaults to frame 0, and LOOP_FORWARD with a
			# zero-length loop region plays pure silence — it must be pushed
			# to the last frame by hand. Frames come from the duration, not
			# the byte count: the importer may store compressed data (QOA),
			# where bytes no longer map 1:1 to frames.
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	_streams[sub_path] = found
	return found


## Every numbered take of a one-shot — "<prefix>_01.wav" upward — wrapped in
## an [AudioStreamRandomizer] so repeats never sound mechanical. Null when no
## takes exist yet. `pitch_spread` and `volume_spread_db` are the randomizer's
## per-play variation.
static func take_set(
	prefix: String, pitch_spread: float = 1.08, volume_spread_db: float = 1.5
) -> AudioStreamRandomizer:
	if _sets.has(prefix):
		return _sets[prefix]
	var takes: AudioStreamRandomizer = AudioStreamRandomizer.new()
	var count: int = 0
	for i: int in range(1, MAX_TAKES + 1):
		var take: AudioStream = stream("%s_%02d.wav" % [prefix, i])
		if take == null:
			break
		takes.add_stream(count, take)
		count += 1
	if count == 0:
		_sets[prefix] = null
		return null
	takes.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	takes.random_pitch = pitch_spread
	takes.random_volume_offset_db = volume_spread_db
	_sets[prefix] = takes
	return takes


## How many takes a set found — for the verify harness and the F3 overlay.
static func take_count(prefix: String) -> int:
	var takes: AudioStreamRandomizer = take_set(prefix)
	return 0 if takes == null else takes.streams_count
