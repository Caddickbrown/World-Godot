class_name SoundSynth
extends RefCounted
## Every sound in the game, made from nothing: noise, sines and a few filters,
## rendered once into mono buffers (SoundBank turns them into looped
## AudioStreamWAVs on a worker thread). No sample files, no third-party audio.
##
## Loops are seamless two ways: noise beds are rendered a little long and the
## tail is crossfaded into the head (`_loopify`); beds made of events (drops,
## chirps, crackles, notes) add each event modulo the loop length (`_add_wrap`),
## so whatever rings past the end comes back in at the start.
##
## Everything takes its own RandomNumberGenerator (never the global one).

const SR := 22050          # mix rate for every buffer (ambience lives below 11 kHz)
const XFADE := 0.75        # seconds of crossfade on noise loops

# ── Helpers ──────────────────────────────────────────────────────────────────

static func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * SR))
	a.fill(0.0)
	return a

## a holds n + xf samples; returns n samples whose end runs into its start.
static func _loopify(a: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var xf := a.size() - n
	var out := a.slice(0, n)
	for i in xf:
		var w := float(i) / float(xf) * PI * 0.5
		out[i] = a[i] * sin(w) + a[n + i] * cos(w)
	return out

## Add src into dst at offset, wrapping round the end (for event loops).
static func _add_wrap(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float = 1.0) -> void:
	var n := dst.size()
	var j := posmod(at, n)
	for i in src.size():
		dst[j] += src[i] * gain
		j += 1
		if j >= n:
			j = 0

## Add src into dst at offset, dropping what runs past the end (one-shots).
static func _add(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float = 1.0) -> void:
	var end := mini(dst.size(), at + src.size())
	for j in range(maxi(at, 0), end):
		dst[j] += src[j - at] * gain

static func _coef(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / SR)

static func rms(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v * v
	return sqrt(s / maxf(1.0, float(a.size())))

static func peak(a: PackedFloat32Array) -> float:
	var p := 0.0
	for v in a:
		p = maxf(p, absf(v))
	return p

## Scale to an RMS, then keep the peak under `ceiling` (beds sit at even levels).
static func _level(a: PackedFloat32Array, target_rms: float, ceiling: float = 0.95) -> PackedFloat32Array:
	var r := rms(a)
	if r <= 0.0:
		return a
	var g := target_rms / r
	var p := peak(a) * g
	if p > ceiling:
		g *= ceiling / p
	for i in a.size():
		a[i] *= g
	return a

## Scale so the peak is `to` (one-shots).
static func _norm(a: PackedFloat32Array, to: float = 0.9) -> PackedFloat32Array:
	var p := peak(a)
	if p <= 0.0:
		return a
	var g := to / p
	for i in a.size():
		a[i] *= g
	return a

## A smooth random curve: one value per `step` seconds, cosine-eased between.
static func _wander(rng: RandomNumberGenerator, n: int, step: float, lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var per := maxi(1, int(step * SR))
	var a := rng.randf_range(lo, hi)
	var b := rng.randf_range(lo, hi)
	for i in n:
		var k := i % per
		if k == 0 and i > 0:
			a = b
			b = rng.randf_range(lo, hi)
		var t := float(k) / float(per)
		out[i] = lerpf(a, b, 0.5 - 0.5 * cos(t * PI))
	return out

static func _fade_ends(a: PackedFloat32Array, attack: float, release: float) -> PackedFloat32Array:
	var na := maxi(1, int(attack * SR))
	var nr := maxi(1, int(release * SR))
	var n := a.size()
	for i in mini(na, n):
		a[i] *= float(i) / na
	for i in mini(nr, n):
		a[n - 1 - i] *= float(i) / nr
	return a

## Feedback-free echo taps (a hillside, a room): cheap space.
static func _echo(a: PackedFloat32Array, taps: Array) -> PackedFloat32Array:
	var src := a.duplicate()
	for t in taps:
		var d := int(float(t[0]) * SR)
		var g := float(t[1])
		for i in range(d, a.size()):
			a[i] += src[i - d] * g
	return a

# ── Beds (loops) ─────────────────────────────────────────────────────────────

## Waves on a shore: a low rumble always, swells that break into a hiss and
## wash back, at uneven intervals.
static func surf(rng: RandomNumberGenerator, seconds: float = 16.0) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var a := _buf(seconds + XFADE)
	var waves: Array = []
	var t := rng.randf_range(0.2, 1.0)
	while t < seconds + XFADE:
		waves.append([t, rng.randf_range(0.6, 1.0)])
		t += rng.randf_range(4.2, 7.4)
	var lp_body := 0.0
	var lp_r1 := 0.0
	var lp_r2 := 0.0
	var lp_h := 0.0
	var c_r := _coef(110.0)
	var c_h := _coef(1800.0)
	var env := 0.0
	var c_body := 0.0
	var fizz_k := 0.0
	for i in a.size():
		if i % 32 == 0:   # the envelope moves slowly: work it out every 32 samples
			var ts := float(i) / SR
			env = 0.0
			for w in waves:
				var u: float = ts - float(w[0])
				if u < -2.2 or u > 9.0:
					continue
				var e := 0.0
				if u < 0.0:
					e = 0.45 * pow((u + 2.2) / 2.2, 2.0)       # the swell
				elif u < 0.12:
					e = lerpf(0.45, 1.0, u / 0.12)              # the break
				else:
					e = exp(-(u - 0.12) / 1.7)                  # the wash
				env = maxf(env, e * float(w[1]))
			c_body = _coef(260.0 + 1400.0 * env)
			fizz_k = pow(env, 1.6) * 0.4
		var x := rng.randf() * 2.0 - 1.0
		lp_body += (x - lp_body) * c_body
		lp_r1 += (x - lp_r1) * c_r
		lp_r2 += (lp_r1 - lp_r2) * c_r
		lp_h += (x - lp_h) * c_h
		a[i] = lp_body * (0.2 + 1.1 * env) + lp_r2 * 1.3 + (x - lp_h) * fizz_k
	return _level(_loopify(a, n), 0.22)

## Wind: noise through a band that wanders, in gusts, with a faint whistle.
static func wind(rng: RandomNumberGenerator, seconds: float = 12.0) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var a := _buf(seconds + XFADE)
	var m := a.size()
	var fc := _wander(rng, m, 1.3, 180.0, 620.0)
	var gust := _wander(rng, m, 0.9, 0.25, 1.0)
	var low := 0.0
	var band := 0.0
	var low2 := 0.0
	var band2 := 0.0
	for i in m:
		var x := rng.randf() * 2.0 - 1.0
		var f := 2.0 * sin(PI * fc[i] / SR)
		var high := x - low - 0.9 * band
		band += f * high
		low += f * band
		# The whistle: a narrow band an octave or so up, only in the gusts.
		var f2 := 2.0 * sin(PI * fc[i] * 2.4 / SR)
		var high2 := x - low2 - 0.12 * band2
		band2 += f2 * high2
		low2 += f2 * band2
		var g := gust[i]
		a[i] = band * g + band2 * 0.012 * g * g * g
	return _level(_loopify(a, n), 0.2)

## Rain: a soft hiss and drops. On leaves (`leaves`) the drops are many,
## brighter and pattering; in the open, fewer and softer.
static func rain(rng: RandomNumberGenerator, leaves: bool, seconds: float = 6.0) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var a := _buf(seconds + XFADE)
	var lp := 0.0
	var lp2 := 0.0
	var c1 := _coef(5200.0 if leaves else 3600.0)
	var c2 := _coef(400.0)
	var hiss := 0.14 if leaves else 0.22
	for i in a.size():
		var x := rng.randf() * 2.0 - 1.0
		lp += (x - lp) * c1
		lp2 += (lp - lp2) * c2
		a[i] = (lp - lp2) * hiss
	a = _loopify(a, n)
	var rate := 150.0 if leaves else 55.0
	var drops := int(rate * seconds)
	for k in drops:
		var at := rng.randi_range(0, n - 1)
		var f := rng.randf_range(1800.0, 5200.0) if leaves else rng.randf_range(1200.0, 3400.0)
		var tau := rng.randf_range(0.003, 0.010)
		var amp := pow(rng.randf(), 2.2) * (0.5 if leaves else 0.35)
		var len := int(tau * 5.0 * SR)
		var d := PackedFloat32Array()
		d.resize(len)
		for i in len:
			var ts := float(i) / SR
			d[i] = sin(TAU * f * ts * (1.0 - ts * 8.0)) * exp(-ts / tau)
		_add_wrap(a, d, at, amp)
		if leaves and rng.randf() < 0.35:
			# A pat on a leaf: a tiny noise burst.
			var pl := int(0.004 * SR)
			var p := PackedFloat32Array()
			p.resize(pl)
			var hp := 0.0
			for i in pl:
				var x := rng.randf() * 2.0 - 1.0
				hp += (x - hp) * 0.5
				p[i] = (x - hp) * (1.0 - float(i) / pl)
			_add_wrap(a, p, at + rng.randi_range(0, 400), amp * 0.8)
	return _level(a, 0.16)

## Crickets on a summer night: a few singers chirping out of step, over a
## faint shimmer of more far away.
static func crickets(rng: RandomNumberGenerator, seconds: float = 8.0) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var a := _buf(seconds + XFADE)
	# The far shimmer: narrow band noise, slowly swelling.
	var low := 0.0
	var band := 0.0
	var f := 2.0 * sin(PI * 4400.0 / SR)
	var sw := _wander(rng, a.size(), 0.8, 0.3, 1.0)
	for i in a.size():
		var x := rng.randf() * 2.0 - 1.0
		var high := x - low - 0.08 * band
		band += f * high
		low += f * band
		a[i] = band * 0.02 * sw[i]
	a = _loopify(a, n)
	for c in 4:
		var carrier := rng.randf_range(4000.0, 5200.0)
		var pulse_rate := rng.randf_range(26.0, 36.0)
		var pulses := rng.randi_range(2, 4)
		var period := rng.randf_range(0.5, 0.95)
		var amp := rng.randf_range(0.35, 1.0)
		var plen := int(SR / pulse_rate * 0.55)
		var pulse := PackedFloat32Array()
		pulse.resize(plen)
		for i in plen:
			var w := sin(PI * float(i) / plen)
			pulse[i] = sin(TAU * carrier * float(i) / SR) * w * w
		var t := rng.randf_range(0.0, period)
		while t < seconds:
			for p in pulses:
				_add_wrap(a, pulse, int((t + p / pulse_rate) * SR), amp * rng.randf_range(0.8, 1.0))
			t += period * rng.randf_range(0.9, 1.12)
			if rng.randf() < 0.08:
				t += period * 2.0    # a pause for breath
	return _level(a, 0.08, 0.7)

## A fire: a soft roar, a hiss, and crackles and pops.
static func fire(rng: RandomNumberGenerator, seconds: float = 6.0) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var a := _buf(seconds + XFADE)
	var flick := _wander(rng, a.size(), 0.35, 0.5, 1.0)
	var lp1 := 0.0
	var lp2 := 0.0
	var hp := 0.0
	var c := _coef(170.0)
	var ch := _coef(2500.0)
	for i in a.size():
		var x := rng.randf() * 2.0 - 1.0
		lp1 += (x - lp1) * c
		lp2 += (lp1 - lp2) * c
		hp += (x - hp) * ch
		a[i] = lp2 * 1.5 * flick[i] + (x - hp) * 0.025 * flick[i]
	a = _loopify(a, n)
	var crackles := int(seconds * 14.0)
	for k in crackles:
		var at := rng.randi_range(0, n - 1)
		var clicks := rng.randi_range(1, 4)
		var amp := pow(rng.randf(), 2.5) * 0.9 + 0.05
		var fc := rng.randf_range(900.0, 4200.0)
		for q in clicks:
			var len := rng.randi_range(20, 90)
			var b := PackedFloat32Array()
			b.resize(len)
			var low := 0.0
			var bnd := 0.0
			var ff := 2.0 * sin(PI * fc / SR)
			for i in len:
				var x := (rng.randf() * 2.0 - 1.0) * (1.0 - float(i) / len)
				var hi := x - low - 0.5 * bnd
				bnd += ff * hi
				low += ff * bnd
				b[i] = bnd
			_add_wrap(a, b, at + q * rng.randi_range(60, 500), amp)
	# Now and then a soft pop of sap.
	for k in int(seconds * 0.7):
		var len := int(0.05 * SR)
		var p := PackedFloat32Array()
		p.resize(len)
		var f := rng.randf_range(140.0, 260.0)
		for i in len:
			var ts := float(i) / SR
			p[i] = sin(TAU * f * ts) * exp(-ts / 0.012)
		_add_wrap(a, p, rng.randi_range(0, n - 1), rng.randf_range(0.2, 0.5))
	return _level(a, 0.14)

# Vowel formants (F1, F2), roughly: a, e, i, o, u, and two in between.
const VOWELS := [[730.0, 1090.0], [530.0, 1840.0], [300.0, 2200.0], [570.0, 840.0],
	[320.0, 900.0], [660.0, 1720.0], [440.0, 1020.0]]

## Voices round a fire, too far off to make out: syllables with the shape of
## talk (vowels, phrases, a rise at the end) and no words, and now and then a
## laugh. Muffled on purpose.
static func murmur(rng: RandomNumberGenerator, seconds: float = 10.0) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var a := _buf(seconds)
	var voices := [rng.randf_range(105.0, 130.0), rng.randf_range(185.0, 225.0),
		rng.randf_range(140.0, 170.0), rng.randf_range(230.0, 270.0)]
	var harm := 6
	for v in voices.size():
		var f0: float = voices[v]
		var t := rng.randf_range(0.0, 1.5)
		var vamp := rng.randf_range(0.6, 1.0)
		while t < seconds:
			# One phrase.
			var syl := rng.randi_range(3, 9)
			var laugh := rng.randf() < 0.12
			if laugh:
				syl = rng.randi_range(4, 6)
			for s in syl:
				var dur := 0.085 if laugh else rng.randf_range(0.1, 0.26)
				var vw: Array = VOWELS[0 if laugh else rng.randi_range(0, VOWELS.size() - 1)]
				var rise := 1.0 + 0.07 * sin(PI * float(s) / maxf(1.0, syl - 1)) + (0.08 if s == syl - 1 and rng.randf() < 0.4 else 0.0)
				var pitch := f0 * rise * (1.45 if laugh else 1.0) * rng.randf_range(0.96, 1.04)
				var glide := rng.randf_range(-0.06, 0.06)
				var w := PackedFloat32Array()
				w.resize(harm)
				var tot := 0.0
				for k in harm:
					var hk := pitch * (k + 1)
					var g := 0.0
					for F in vw:
						var bw: float = 0.18 * float(F) + 60.0
						g += 1.0 / (1.0 + pow((hk - float(F)) / bw, 2.0))
					w[k] = g / (k + 1.0)
					tot += w[k]
				var len := int(dur * SR)
				var start := int(t * SR)
				var ph := rng.randf() * TAU
				for i in len:
					var u := float(i) / len
					var env := pow(sin(PI * u), 0.8)
					ph += TAU * pitch * (1.0 + glide * u) / SR
					var s_ := 0.0
					for k in harm:
						s_ += w[k] * sin(ph * (k + 1))
					var j := start + i
					if j < n:
						a[j] += s_ / tot * env * vamp
					else:
						a[j - n] += s_ / tot * env * vamp
				t += dur + (0.03 if laugh else rng.randf_range(0.015, 0.07))
			t += rng.randf_range(0.5, 2.2)
	# Muffle it (no words, ever) and give it a little room.
	var lp := 0.0
	var lp2 := 0.0
	var c := _coef(1700.0)
	for k in 2:   # twice round so the filter's state wraps too
		for i in n:
			lp += (a[i] - lp) * c
			lp2 += (lp - lp2) * c
			if k == 1:
				a[i] = lp2
	a = _echo(a, [[0.043, 0.22], [0.071, 0.12]])
	return _level(a, 0.15)

## Many birds, some near and most far: the dawn chorus (and the day's bed).
static func chorus(rng: RandomNumberGenerator, seconds: float = 12.0) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var a := _buf(seconds)
	var kinds := ["warble", "tweet", "fluty", "trill"]
	for k in 34:
		var c := bird(rng, kinds[k % kinds.size()])
		_add_wrap(a, c, rng.randi_range(0, n - 1), pow(rng.randf(), 1.5) * 0.8 + 0.08)
	# Far away is duller.
	var lp := 0.0
	var cc := _coef(5200.0)
	for k in 2:
		for i in n:
			lp += (a[i] - lp) * cc
			if k == 1:
				a[i] = lp
	return _level(a, 0.09, 0.8)

## A little band at a festival: a pipe over a frame drum, sixteen beats at
## 120 bpm (eight seconds), in a cheerful pentatonic.
static func festival_tune(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var beat := 0.5
	var seconds := beat * 16.0
	var a := _buf(seconds)
	var scale := [0, 2, 4, 7, 9, 12, 14, 16]
	var root := 523.25
	var deg := 2
	var t := 0.0
	while t < seconds - 0.01:
		var dur := beat * (0.5 if rng.randf() < 0.55 else 1.0)
		deg = clampi(deg + rng.randi_range(-2, 2), 0, scale.size() - 1)
		var f := root * pow(2.0, scale[deg] / 12.0)
		_add_wrap(a, pipe(rng, f, dur * 0.95), int(t * SR), 0.55)
		t += dur
	for b in 16:
		var acc := 1.0 if b % 4 == 0 else (0.6 if b % 2 == 0 else 0.35)
		_add_wrap(a, drum(rng, 95.0 if b % 4 == 0 else 150.0, 0.25), int(b * beat * SR), acc * 0.7)
	return _level(a, 0.14)

# ── Voices of things (one-shots) ─────────────────────────────────────────────

## A breathy pipe note.
static func pipe(rng: RandomNumberGenerator, f: float, dur: float) -> PackedFloat32Array:
	var a := _buf(dur + 0.08)
	var ph := 0.0
	var lp := 0.0
	for i in a.size():
		var ts := float(i) / SR
		var vib := 1.0 + 0.006 * sin(TAU * 5.2 * ts) * minf(1.0, ts * 4.0)
		ph += TAU * f * vib / SR
		var x := rng.randf() * 2.0 - 1.0
		lp += (x - lp) * 0.3
		var env := minf(1.0, ts / 0.03) * (1.0 if ts < dur else exp(-(ts - dur) / 0.025))
		a[i] = (sin(ph) + 0.18 * sin(2.0 * ph) + 0.05 * sin(3.0 * ph) + lp * 0.05) * env
	return a

## A soft frame drum.
static func drum(rng: RandomNumberGenerator, f: float, dur: float) -> PackedFloat32Array:
	var a := _buf(dur)
	var ph := 0.0
	var lp := 0.0
	for i in a.size():
		var ts := float(i) / SR
		ph += TAU * f * (1.0 + 0.6 * exp(-ts / 0.02)) / SR
		var x := rng.randf() * 2.0 - 1.0
		lp += (x - lp) * 0.08
		a[i] = (sin(ph) * exp(-ts / 0.09) + lp * 1.5 * exp(-ts / 0.03))
	return a

## Birdsong. kind: warble (a robin's tumble of notes), tweet (a sparrow's
## repeated chips), fluty (a blackbird's slow whistle), trill (a wren's rattle),
## coo (a dove), gull, owl.
static func bird(rng: RandomNumberGenerator, kind: String) -> PackedFloat32Array:
	var notes: Array = []   # [start, dur, f_from, f_to, amp, harmonic]
	match kind:
		"warble":
			var t := 0.0
			for k in rng.randi_range(6, 12):
				var d := rng.randf_range(0.04, 0.11)
				var f := rng.randf_range(2200.0, 4600.0)
				notes.append([t, d, f, f * rng.randf_range(0.8, 1.25), rng.randf_range(0.5, 1.0), 0.05])
				t += d + rng.randf_range(0.015, 0.06)
		"tweet":
			var f := rng.randf_range(3000.0, 4200.0)
			var t := 0.0
			for k in rng.randi_range(2, 5):
				notes.append([t, 0.06, f, f * 0.78, 1.0, 0.1])
				t += rng.randf_range(0.11, 0.16)
		"fluty":
			var t := 0.0
			for k in rng.randi_range(3, 6):
				var d := rng.randf_range(0.12, 0.26)
				var f := rng.randf_range(1400.0, 2600.0)
				notes.append([t, d, f, f * rng.randf_range(0.85, 1.2), rng.randf_range(0.6, 1.0), 0.2])
				t += d + rng.randf_range(0.04, 0.1)
		"trill":
			var f := rng.randf_range(3600.0, 4800.0)
			var rate := rng.randf_range(18.0, 26.0)
			for k in int(rate * rng.randf_range(0.6, 1.1)):
				notes.append([k / rate, 0.6 / rate, f * 1.05, f * 0.95, 0.7 + 0.3 * sin(k * 0.4), 0.05])
		"coo":
			var f := rng.randf_range(420.0, 520.0)
			notes.append([0.0, 0.28, f * 0.95, f, 0.7, 0.15])
			notes.append([0.36, 0.5, f * 1.05, f * 0.92, 1.0, 0.15])
			notes.append([0.95, 0.3, f, f * 0.9, 0.6, 0.15])
		"gull":
			var t := 0.0
			for k in rng.randi_range(2, 4):
				var d := rng.randf_range(0.22, 0.4)
				notes.append([t, d, rng.randf_range(1150.0, 1350.0), rng.randf_range(650.0, 800.0), 1.0, 0.6])
				t += d + rng.randf_range(0.08, 0.16)
		"owl":
			var f := rng.randf_range(360.0, 420.0)
			notes.append([0.0, 0.45, f, f * 0.96, 0.9, 0.08])
			notes.append([0.95, 0.18, f * 1.02, f, 0.6, 0.08])
			notes.append([1.18, 0.6, f, f * 0.93, 1.0, 0.08])
	var last: Array = notes[-1]
	var a := _buf(float(last[0]) + float(last[1]) + 0.05)
	for nt in notes:
		var start := int(float(nt[0]) * SR)
		var len := int(float(nt[1]) * SR)
		var f0: float = nt[2]
		var f1: float = nt[3]
		var amp: float = nt[4]
		var h: float = nt[5]
		var ph := 0.0
		var fm := rng.randf_range(30.0, 60.0)
		for i in len:
			var u := float(i) / len
			var f := lerpf(f0, f1, u) * (1.0 + 0.02 * sin(TAU * fm * i / SR))
			ph += TAU * f / SR
			var env := sin(PI * u)
			if kind == "owl" or kind == "coo":
				env = pow(env, 0.6)
			var s := sin(ph) + h * sin(2.0 * ph) + h * 0.5 * sin(3.0 * ph)
			var j := start + i
			if j < a.size():
				a[j] += s * env * amp
	return _norm(a, 0.85)

## Frogs. deep: a slow bullfrog "rrrum"; else a two-part ribbit.
static func croak(rng: RandomNumberGenerator, deep: bool) -> PackedFloat32Array:
	var parts: Array = [[0.0, 0.42]] if deep else [[0.0, 0.07], [0.12, 0.11]]
	var a := _buf(0.55 if deep else 0.3)
	var carrier := rng.randf_range(160.0, 210.0) if deep else rng.randf_range(420.0, 560.0)
	var am := rng.randf_range(22.0, 30.0) if deep else rng.randf_range(55.0, 75.0)
	for p in parts:
		var start := int(float(p[0]) * SR)
		var len := int(float(p[1]) * SR)
		for i in len:
			var ts := float(i) / SR
			var u := float(i) / len
			var pulse := pow(0.5 + 0.5 * sin(TAU * am * ts), 3.0)
			var env := sin(PI * u)
			var s := sin(TAU * carrier * ts) + 0.4 * sin(TAU * carrier * 2.0 * ts) + 0.15 * sin(TAU * carrier * 3.1 * ts)
			if start + i < a.size():
				a[start + i] += s * pulse * env
	return _norm(a, 0.8)

## A voiced call: harmonics of a gliding f0 under a moving formant.
## contour: [[t, f0], ...]; formant: [[t, centre Hz], ...]; trem: Hz, depth.
static func _call(rng: RandomNumberGenerator, seconds: float, contour: Array, formant: Array,
		harmonics: int, trem: Vector2, breath: float) -> PackedFloat32Array:
	var a := _buf(seconds)
	var ph := 0.0
	var lp := 0.0
	var f0 := 0.0
	var gains := PackedFloat32Array()
	gains.resize(harmonics)
	for i in a.size():
		var ts := float(i) / SR
		var u := ts / seconds
		if i % 64 == 0:   # pitch and formant at control rate
			f0 = _curve(contour, u)
			var fc := _curve(formant, u)
			for k in harmonics:
				var hk := f0 * (k + 1)
				gains[k] = 1.0 / (1.0 + pow((hk - fc) / (0.6 * fc), 2.0)) / sqrt(k + 1.0)
		ph += TAU * f0 / SR
		var s := 0.0
		for k in harmonics:
			s += gains[k] * sin(ph * (k + 1))
		var x := rng.randf() * 2.0 - 1.0
		lp += (x - lp) * 0.2
		var am := 1.0 - trem.y * (0.5 + 0.5 * sin(TAU * trem.x * ts))
		var env := minf(1.0, u / 0.08) * minf(1.0, (1.0 - u) / 0.25)
		a[i] = (s * am + lp * breath) * env
	return a

static func _curve(pts: Array, u: float) -> float:
	if u <= float(pts[0][0]):
		return float(pts[0][1])
	for k in range(1, pts.size()):
		if u <= float(pts[k][0]):
			var t := (u - float(pts[k - 1][0])) / maxf(0.0001, float(pts[k][0]) - float(pts[k - 1][0]))
			return lerpf(float(pts[k - 1][1]), float(pts[k][1]), 0.5 - 0.5 * cos(t * PI))
	return float(pts[-1][1])

## Farm and wild animals: sheep, cow, wolf (far off, with a hillside echo).
static func animal(rng: RandomNumberGenerator, kind: String) -> PackedFloat32Array:
	match kind:
		"sheep":
			var f := rng.randf_range(260.0, 330.0)
			var a := _call(rng, rng.randf_range(0.7, 1.0), [[0.0, f * 0.92], [0.2, f * 1.03], [1.0, f * 0.9]],
				[[0.0, 500.0], [0.3, 1100.0], [1.0, 800.0]], 10, Vector2(rng.randf_range(20.0, 27.0), 0.55), 0.04)
			return _norm(a, 0.8)
		"cow":
			var f := rng.randf_range(95.0, 120.0)
			var a := _call(rng, rng.randf_range(1.4, 2.0), [[0.0, f], [0.35, f * 1.12], [1.0, f * 0.85]],
				[[0.0, 260.0], [0.4, 750.0], [1.0, 420.0]], 14, Vector2(4.0, 0.08), 0.03)
			return _norm(a, 0.85)
		"wolf":
			var f := rng.randf_range(350.0, 420.0)
			var dur := rng.randf_range(2.6, 3.6)
			var a := _call(rng, dur, [[0.0, f], [0.25, f * 1.6], [0.7, f * 1.5], [1.0, f * 1.15]],
				[[0.0, 800.0], [1.0, 900.0]], 3, Vector2(5.0, 0.12), 0.06)
			var tail := _buf(dur + 1.2)
			_add(tail, a, 0)
			return _norm(_echo(tail, [[0.31, 0.32], [0.58, 0.18], [0.83, 0.1]]), 0.8)
	return _buf(0.1)

## Thunder: near has a crack before the roll; far is only the roll, dull.
static func thunder(rng: RandomNumberGenerator, near: bool) -> PackedFloat32Array:
	var seconds := 6.0 if near else 7.5
	var a := _buf(seconds)
	var bumps: Array = []
	var t := 0.0 if near else rng.randf_range(0.2, 0.5)
	for k in rng.randi_range(4, 7):
		bumps.append([t, rng.randf_range(0.4, 1.0) * exp(-t / 2.5)])
		t += rng.randf_range(0.25, 1.0)
	var lp1 := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var hp := 0.0
	var c := _coef(95.0 if near else 60.0)
	var cc := _coef(260.0)
	var env := 0.0
	for i in a.size():
		var ts := float(i) / SR
		if i % 32 == 0:
			env = 0.0
			for b in bumps:
				var u: float = ts - float(b[0])
				if u > 0.0:
					env += float(b[1]) * minf(1.0, u / (0.08 if near else 0.4)) * exp(-u / 1.3)
		var x := rng.randf() * 2.0 - 1.0
		lp1 += (x - lp1) * c
		lp2 += (lp1 - lp2) * c
		lp3 += (x - lp3) * cc
		var s := lp2 * 9.0 * env + lp3 * 0.6 * env * (0.6 if near else 0.15)
		if near and ts < 0.35:
			hp += (x - hp) * 0.25
			s += (x - hp) * exp(-ts / 0.05) * 0.9 + lp3 * exp(-ts / 0.12) * 1.5
		a[i] = s
	return _norm(_fade_ends(a, 0.002, 1.2), 0.9)

# ── Stingers (the UI's voice) ────────────────────────────────────────────────

## A struck bell or glass: inharmonic partials, each fading at its own pace.
static func bell(f: float, seconds: float, bright: float = 1.0) -> PackedFloat32Array:
	var partials := [[1.0, 1.0, 1.0], [2.0, 0.32, 0.6], [2.76, 0.28 * bright, 0.42], [4.07, 0.12 * bright, 0.25], [5.4, 0.05 * bright, 0.15]]
	var a := _buf(seconds)
	for p in partials:
		var pf: float = f * float(p[0])
		if pf > SR * 0.45:
			continue
		var amp: float = p[1]
		var tau: float = seconds * float(p[2]) * 0.45
		var k := exp(-1.0 / (tau * SR))   # decay per sample
		var w := TAU * pf / SR
		var att := int(0.004 * SR)
		for i in a.size():
			a[i] += sin(w * i) * amp * minf(1.0, float(i) / att)
			amp *= k
			if amp < 0.0005:
				break
	return a

## A kalimba plink: quick, round, a touch of overtone.
static func plink(f: float) -> PackedFloat32Array:
	var a := _buf(0.9)
	for i in a.size():
		var ts := float(i) / SR
		a[i] = (sin(TAU * f * ts) * exp(-ts / 0.28) + 0.25 * sin(TAU * f * 3.0 * ts) * exp(-ts / 0.05)) * minf(1.0, ts / 0.003)
	return a

static func _arp(parts: Array, seconds: float, peak_to: float) -> PackedFloat32Array:
	var a := _buf(seconds)
	for p in parts:
		_add(a, p[1], int(float(p[0]) * SR), float(p[2]))
	return _norm(_fade_ends(a, 0.001, 0.3), peak_to)

## The stingers by name (what AudioSystem's play_* calls).
static func stinger(rng: RandomNumberGenerator, kind: String) -> PackedFloat32Array:
	match kind:
		"moment":       # an album sticker: three glass notes, climbing (C6 E6 G6) and a shimmer
			return _arp([[0.0, bell(1046.5, 2.2), 0.8], [0.13, bell(1318.5, 2.0), 0.7],
				[0.26, bell(1568.0, 2.4), 0.75], [0.3, bell(3136.0, 1.2, 0.3), 0.12]], 2.8, 0.6)
		"discovery":    # an idea: two kalimba notes, a fifth apart
			return _arp([[0.0, plink(880.0), 0.8], [0.12, plink(1318.5), 0.9]], 1.1, 0.55)
		"birth":        # a music box: two high soft notes
			return _arp([[0.0, bell(1568.0, 1.2, 0.5), 0.6], [0.1, bell(2093.0, 1.3, 0.4), 0.5]], 1.5, 0.35)
		"death":        # one low bell, gently
			return _arp([[0.0, bell(220.0, 3.0, 0.3), 1.0]], 3.0, 0.4)
		"achievement":  # a little run of chimes, C5 E5 G5 C6
			return _arp([[0.0, bell(523.25, 1.6), 0.7], [0.11, bell(659.25, 1.6), 0.7],
				[0.22, bell(783.99, 1.6), 0.7], [0.33, bell(1046.5, 2.0), 0.8]], 2.4, 0.55)
		"disaster":     # two soft low drums, far off
			return _arp([[0.0, drum(rng, 62.0, 1.2), 1.0], [0.55, drum(rng, 55.0, 1.4), 0.8]], 2.0, 0.6)
		"weather":      # a breath of air
			var a := _buf(1.4)
			var low := 0.0
			var band := 0.0
			for i in a.size():
				var u := float(i) / a.size()
				var fc := lerpf(300.0, 1300.0, sin(PI * u))
				var f := 2.0 * sin(PI * fc / SR)
				var x := rng.randf() * 2.0 - 1.0
				var high := x - low - 0.6 * band
				band += f * high
				low += f * band
				a[i] = band * sin(PI * u)
			return _norm(a, 0.3)
		"festival":     # a pipe's flourish and a drum
			var a := _buf(1.8)
			var notes := [783.99, 880.0, 1046.5, 1174.66, 1568.0]
			for k in notes.size():
				_add(a, pipe(rng, notes[k], 0.11 if k < 4 else 0.5), int(k * 0.12 * SR), 0.6)
			_add(a, drum(rng, 110.0, 0.3), 0, 0.6)
			_add(a, drum(rng, 110.0, 0.3), int(0.48 * SR), 0.8)
			return _norm(_fade_ends(a, 0.001, 0.3), 0.5)
	return _buf(0.05)
