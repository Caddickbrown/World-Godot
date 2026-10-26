class_name SoundBank
extends RefCounted
## Every sound the game plays, rendered once (SoundSynth) into AudioStreamWAVs.
## The render takes about a second of CPU, so it runs on a worker thread at boot
## and the soundscape fades layers in as they arrive; the bank is kept for the
## whole run (a new island, a test's second Main, reuse it).
##
## Names: beds ("surf", "wind", "rain_soft", "rain_leaves", "crickets", "fire",
## "murmur", "chorus", "festival_tune"), one-shot lists ("birds", "gulls", "owls",
## "coos", "frogs", "sheep", "cows", "wolves", "thunder_near", "thunder_far") and
## stingers ("st_moment", "st_discovery", "st_birth", "st_death",
## "st_achievement", "st_disaster", "st_weather", "st_festival").

const SEED := 0x5017D
const LOOPS := ["surf", "wind", "rain_soft", "rain_leaves", "crickets", "fire", "murmur", "chorus", "festival_tune"]

static var _streams: Dictionary = {}     # name -> AudioStreamWAV, or Array of them
static var _thread: Thread = null
static var _ready := false
static var build_ms := 0.0               # wall time of the last render (in its thread)
static var seconds_of_audio := 0.0

static func is_ready() -> bool:
	if not _ready and _thread != null and not _thread.is_alive():
		var out: Dictionary = _thread.wait_to_finish()
		_thread = null
		_streams = out
		_ready = true
	return _ready

## Start rendering on a thread (idempotent). Returns at once.
static func start() -> void:
	if _ready or _thread != null:
		return
	_thread = Thread.new()
	_thread.start(_render_all, Thread.PRIORITY_LOW)

## Render now, on this thread (tests, tools). Waits for a running render.
static func build_now() -> void:
	if _ready:
		return
	if _thread != null:
		_streams = _thread.wait_to_finish()
		_thread = null
	else:
		_streams = _render_all()
	_ready = true

## Wait out a render still running (at exit, so the thread is never orphaned).
static func finish() -> void:
	if _thread != null:
		_streams = _thread.wait_to_finish()
		_thread = null
		_ready = true

static func get_stream(name: String) -> AudioStream:
	if not is_ready():
		return null
	var s = _streams.get(name)
	return s as AudioStream

## One of a family of variants (birds, frogs...), picked with the caller's rng.
static func pick(name: String, rng: RandomNumberGenerator) -> AudioStream:
	if not is_ready():
		return null
	var list = _streams.get(name)
	if list is Array and not list.is_empty():
		return list[rng.randi() % list.size()]
	return list as AudioStream

static func names() -> Array:
	return _streams.keys() if is_ready() else []

## The raw mono samples of a stream (tests and tools inspect levels and seams).
static func samples_of(s: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := s.data.size() / 2
	out.resize(n)
	for i in n:
		out[i] = s.data.decode_s16(i * 2) / 32768.0
	return out

static func _render_all() -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out := {}
	var total := 0
	var S := SoundSynth
	var loops := {
		"surf": S.surf(rng), "wind": S.wind(rng), "rain_soft": S.rain(rng, false),
		"rain_leaves": S.rain(rng, true), "crickets": S.crickets(rng), "fire": S.fire(rng),
		"murmur": S.murmur(rng), "chorus": S.chorus(rng), "festival_tune": S.festival_tune(rng),
	}
	for k in loops:
		out[k] = to_wav(loops[k], true)
		total += (loops[k] as PackedFloat32Array).size()
	var shots := {
		"birds": [], "gulls": [], "owls": [], "coos": [], "frogs": [],
		"sheep": [], "cows": [], "wolves": [], "thunder_near": [], "thunder_far": [],
	}
	for kind in ["warble", "tweet", "fluty", "trill"]:
		for v in 2:
			shots["birds"].append(S.bird(rng, kind))
	for v in 2:
		shots["gulls"].append(S.bird(rng, "gull"))
		shots["owls"].append(S.bird(rng, "owl"))
		shots["coos"].append(S.bird(rng, "coo"))
		shots["frogs"].append(S.croak(rng, v == 1))
		shots["frogs"].append(S.croak(rng, false))
		shots["sheep"].append(S.animal(rng, "sheep"))
		shots["cows"].append(S.animal(rng, "cow"))
		shots["wolves"].append(S.animal(rng, "wolf"))
		shots["thunder_near"].append(S.thunder(rng, true))
		shots["thunder_far"].append(S.thunder(rng, false))
	for k in shots:
		var list: Array = []
		for a in shots[k]:
			list.append(to_wav(a, false))
			total += (a as PackedFloat32Array).size()
		out[k] = list
	for kind in ["moment", "discovery", "birth", "death", "achievement", "disaster", "weather", "festival"]:
		var a := S.stinger(rng, kind)
		out["st_" + kind] = to_wav(a, false)
		total += a.size()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	seconds_of_audio = float(total) / SoundSynth.SR
	return out

static func to_wav(a: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(a.size() * 2)
	for i in a.size():
		b.encode_s16(i * 2, int(clampf(a[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SoundSynth.SR
	w.stereo = false
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = a.size()
	return w
