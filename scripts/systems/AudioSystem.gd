class_name AudioSystem
extends Node

const SAMPLE_RATE: float = 44100.0
const POOL_SIZE: int = 4

var _players: Array = []
var _pool_index: int = 0


func _ready() -> void:
	for i: int in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


# ---------------------------------------------------------------------------
# Public sound triggers
# ---------------------------------------------------------------------------

func play_discovery() -> void:
	# Ascending arpeggio: C5 → E5 → G5, each 80ms, sine, amp 0.3, fade out last
	var freqs: Array = [523.25, 659.25, 783.99]
	var all_samples: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(freqs.size()):
		var freq: float = float(freqs[i])
		var amp: float = 0.3
		var fade_out: bool = (i == freqs.size() - 1)
		var note: PackedFloat32Array = _make_sine_opt(freq, 0.08, amp, fade_out)
		all_samples.append_array(note)
	_play_samples(all_samples)


func play_birth() -> void:
	# C5 + E5 + G5 chord simultaneously, 200ms, sine, amp 0.2
	var num_samples: int = int(SAMPLE_RATE * 0.2)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(num_samples)
	var freqs: Array = [523.25, 659.25, 783.99]
	for i: int in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var s: float = 0.0
		for freq in freqs:
			s += sin(TAU * float(freq) * t)
		samples[i] = s * (0.2 / float(freqs.size()))
	_play_samples(samples)


func play_death() -> void:
	# Frequency sweep 440Hz → 180Hz over 400ms, sawtooth (approx), amp 0.25
	var sweep: PackedFloat32Array = _make_sweep_sawtooth(440.0, 180.0, 0.4, 0.25)
	_play_samples(sweep)


func play_weather_change() -> void:
	# Sine sweep 80Hz → 1200Hz over 300ms, amp 0.2
	var sweep: PackedFloat32Array = _make_sweep(80.0, 1200.0, 0.3, 0.2)
	_play_samples(sweep)


func play_disaster() -> void:
	# Low rumble: 60Hz sine, 500ms, amp 0.3, fade out
	var samples: PackedFloat32Array = _make_sine_opt(60.0, 0.5, 0.3, true)
	_play_samples(samples)


func play_achievement() -> void:
	# Fanfare: C5 → G5 → C6, 100ms each, amp 0.35
	var freqs: Array = [523.25, 783.99, 1046.50]
	var all_samples: PackedFloat32Array = PackedFloat32Array()
	for freq in freqs:
		var note: PackedFloat32Array = _make_sine(float(freq), 0.1, 0.35)
		all_samples.append_array(note)
	_play_samples(all_samples)


# ---------------------------------------------------------------------------
# Sample generators
# ---------------------------------------------------------------------------

func _make_sine(freq: float, duration_sec: float, amplitude: float) -> PackedFloat32Array:
	return _make_sine_opt(freq, duration_sec, amplitude, false)


func _make_sine_opt(freq: float, duration_sec: float, amplitude: float, fade_out: bool) -> PackedFloat32Array:
	var num_samples: int = int(SAMPLE_RATE * duration_sec)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(num_samples)
	for i: int in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = 1.0
		if fade_out:
			env = 1.0 - (float(i) / float(num_samples))
		samples[i] = sin(TAU * freq * t) * amplitude * env
	return samples


func _make_sweep(freq_start: float, freq_end: float, duration_sec: float, amplitude: float) -> PackedFloat32Array:
	var num_samples: int = int(SAMPLE_RATE * duration_sec)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(num_samples)
	var phase: float = 0.0
	for i: int in range(num_samples):
		var progress: float = float(i) / float(num_samples)
		var freq: float = freq_start + (freq_end - freq_start) * progress
		samples[i] = sin(phase) * amplitude
		phase += TAU * freq / SAMPLE_RATE
	return samples


func _make_sweep_sawtooth(freq_start: float, freq_end: float, duration_sec: float, amplitude: float) -> PackedFloat32Array:
	var num_samples: int = int(SAMPLE_RATE * duration_sec)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(num_samples)
	var phase: float = 0.0
	for i: int in range(num_samples):
		var progress: float = float(i) / float(num_samples)
		var freq: float = freq_start + (freq_end - freq_start) * progress
		# Sawtooth: phase / PI - 1.0 maps [0, 2π] → [-1, 1]
		var saw: float = (phase / PI) - 1.0
		samples[i] = saw * amplitude
		phase += TAU * freq / SAMPLE_RATE
		if phase >= TAU:
			phase -= TAU
	return samples


# ---------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------

func _play_samples(samples: PackedFloat32Array) -> void:
	var player: AudioStreamPlayer = _players[_pool_index] as AudioStreamPlayer
	_pool_index = (_pool_index + 1) % POOL_SIZE

	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.1

	player.stream = generator
	player.play()

	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return

	for i: int in range(samples.size()):
		var s: float = samples[i]
		playback.push_frame(Vector2(s, s))
