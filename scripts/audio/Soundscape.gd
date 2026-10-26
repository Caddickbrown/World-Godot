class_name Soundscape
extends Node3D
## The island's living sound, following what the camera sees and hears. It only
## reads the world (Main's systems), never writes, and draws its dice from its
## own RandomNumberGenerator.
##
## Beds (looped, one player each, levels from SoundMixer.mix): surf, wind,
## rain on leaves / in the open, crickets, the bird chorus.
## Spots (looped, placed in 3D for direction): the two loudest fires, the two
## liveliest groups of people talking, a festival's band.
## Calls (one-shots from a small pool): birdsong, gulls, doves, owls, frogs
## (the ambient frogs' own croaks, and more by fresh water at night), sheep and
## cows near, wolves far off at night, thunder after lightning (late by distance).
## Stingers (UI bus): album moments, discoveries and the like.
##
## Cheap by design: every sound is a pre-rendered loop or one-shot (SoundBank);
## the world is surveyed 5 times a second; a frame only eases a dozen volumes.

const SAMPLE_EVERY := 0.2           # seconds between surveys of the world
const EASE_SECONDS := 1.2           # beds ease to their new level over about this
const ONESHOTS := 8
const STINGER_GAP := {"birth": 6.0, "death": 8.0, "discovery": 2.5, "moment": 1.0, "achievement": 2.0,
	"disaster": 4.0, "weather": 6.0, "festival": 3.0}
## Each bed's level at full (calibrated by ear against the others).
const BED_GAIN := {"surf": 0.85, "wind": 0.5, "rain_soft": 0.7, "rain_leaves": 0.75, "crickets": 0.5, "chorus": 0.6}
const SPOT_GAIN := {"fire": 0.9, "voices": 0.75, "festival": 0.8}
const START_AFTER := 1.0           # real seconds after the world exists before the bank renders
const FESTIVAL_SECONDS := 60.0      # game-seconds a festival plays if no end is heard (half a day)

var main: Node = null
var rng := RandomNumberGenerator.new()
var listener: AudioListener3D

## The last survey, and what the mixer made of it (tests and the debug read these).
var scene: Dictionary = {}
var levels: Dictionary = {}
var heard_fires: Array = []          # [{pos: Vector3, gain}]
var heard_groups: Array = []         # [{pos: Vector3, gain, count}]
var calls_played: Dictionary = {}    # kind -> count, since start
var ear := Vector3.ZERO

var _beds: Dictionary = {}           # name -> AudioStreamPlayer
var _bed_level: Dictionary = {}      # name -> eased 0..1
var _surf_dir := Vector3.ZERO
var _spots: Dictionary = {}          # "fire0", "fire1", "voices0", "voices1", "festival" -> AudioStreamPlayer3D
var _spot_level: Dictionary = {}
var _spot_target: Dictionary = {}
var _oneshots: Array = []
var _ui: Array = []
var _ui_next := 0
var _stinger_last: Dictionary = {}
var _sample_t := 0.0
var _wired := false
var _thunder: Array = []             # [{t: seconds left, pos: Vector3}]
var _frog_last: Dictionary = {}      # frog index -> last croak value seen
var _fire_keys: Dictionary = {}      # "x,z" -> Vector2i (parsed once)
var festivals: Array = []            # [{kind, pos: Vector3, until: game time}]
var _weather_view: Object = null
var _clock := 0.0

func _ready() -> void:
	rng.seed = 0x50DD
	SoundSettings.load_settings()
	listener = AudioListener3D.new()
	add_child(listener)
	for name in SoundMixer.BEDS:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		add_child(p)
		_beds[name] = p
		_bed_level[name] = 0.0
	for name in ["fire0", "fire1", "voices0", "voices1", "festival"]:
		var s := _player3d("Ambience")
		_spots[name] = s
		_spot_level[name] = 0.0
		_spot_target[name] = 0.0
	for i in ONESHOTS:
		_oneshots.append(_player3d("Effects"))
	for i in 3:
		var u := AudioStreamPlayer.new()
		u.bus = "UI"
		add_child(u)
		_ui.append(u)

func _exit_tree() -> void:
	SoundBank.finish()

func _player3d(bus: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # we set the level ourselves
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.max_distance = 0.0
	add_child(p)
	return p

## Streams arrive from the bank's thread; start the loops once they do.
func _wire() -> void:
	if _wired or not SoundBank.is_ready():
		return
	_wired = true
	for name in _beds:
		_start_loop(_beds[name], SoundBank.get_stream(name))
	_start_loop(_spots["fire0"], SoundBank.get_stream("fire"))
	_start_loop(_spots["fire1"], SoundBank.get_stream("fire"))
	_start_loop(_spots["voices0"], SoundBank.get_stream("murmur"))
	_start_loop(_spots["voices1"], SoundBank.get_stream("murmur"))
	_start_loop(_spots["festival"], SoundBank.get_stream("festival_tune"))
	(_spots["voices1"] as AudioStreamPlayer3D).pitch_scale = 1.09
	(_spots["fire1"] as AudioStreamPlayer3D).pitch_scale = 0.9

func _start_loop(p: Node, stream: AudioStream) -> void:
	if stream == null:
		return
	p.stream = stream
	p.volume_db = -80.0
	var length := stream.get_length()
	p.play(rng.randf() * length)   # out of step with each other
	p.stream_paused = true

func _process(delta: float) -> void:
	tick(delta)

## One frame (real seconds). Public so tests and tools can drive it.
func tick(delta: float) -> void:
	_clock += delta
	if main == null or main.get("world") == null or main.get("time_system") == null:
		return
	# Render the bank once the island is built and the first frames are out,
	# so it never competes with the boot.
	if _clock > START_AFTER:
		SoundBank.start()
	_wire()
	_watch_lightning()
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_EVERY
		survey()
	_ease(delta)
	_calls(delta)
	_tick_thunder(delta)

# ── Where the ear is, and what is round it ───────────────────────────────────

## Is the wisp walking (Main.ViewMode.WALK)?
func _walking() -> bool:
	return int(main.get("view_mode")) == 1 and main.get("wanderer") != null

## Read the world round the ear: the mixer's scene, and the spots heard.
func survey() -> void:
	var world: World = main.world
	var walk := _walking()
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var focus: Vector3
	var cam_dist: float
	if walk:
		focus = main.wanderer.world_position()
		cam_dist = float(main.wanderer.cam_distance)
		ear = focus + Vector3(0, 1.2, 0)
	else:
		focus = main.observer.target
		cam_dist = float(main.observer.distance)
		# The sky's ear hangs over what you look at, part way up to the camera:
		# near enough to hear a camp, high enough to hear the island.
		ear = focus + Vector3(0, 0.35 * cam_dist, 0)
	var height := ear.y - focus.y if walk else (cam.global_position.y - focus.y if cam else cam_dist * 0.8)
	if listener and listener.is_inside_tree():
		var basis := cam.global_basis if cam else Basis()
		listener.global_transform = Transform3D(basis, ear)
		if not listener.is_current():
			listener.make_current()
	var ft := Vector2(focus.x, focus.z) / World.TILE_SIZE
	var radius_tiles := 10.0 if walk else clampf(cam_dist * 0.25, 10.0, 70.0)
	var land := survey_land(world, ft, radius_tiles)
	_surf_dir = Vector3(land["sea_dir"].x, 0, land["sea_dir"].y)
	var oc: float = main.weather_system.overcast_at(ft.x, ft.y) if main.weather_system else 0.0
	var wet := SoundMixer.rain_from_overcast(oc)
	scene = {
		"hour": float(main.time_system.hour), "season": str(main.time_system.season),
		"walk": walk, "cam_dist": cam_dist, "height": height,
		"sea": land["sea"], "woods": land["woods"], "fresh": land["fresh"],
		"rain": wet.x, "storm": wet.y,
	}
	levels = SoundMixer.mix(scene)
	var hear := SoundMixer.hearing(walk, cam_dist)
	_survey_fires(world, hear)
	_survey_people(hear)
	_survey_festivals(hear)
	_survey_frogs(hear)

## Sea, woods and fresh water round a tile-space point, sampled on rings
## (cheap: about 40 tile reads). sea_dir points to the sea, its length how
## one-sided it is (0 when it is all round, as from high up).
static func survey_land(world: World, at: Vector2, radius_tiles: float) -> Dictionary:
	var sea := 0.0
	var woods := 0.0
	var fresh := 0.0
	var dir := Vector2.ZERO
	var count := 0.0
	var rings := [0.0, 0.35, 0.7, 1.0]
	for ri in rings.size():
		var r: float = rings[ri] * radius_tiles
		var steps := 1 if ri == 0 else 12
		for k in steps:
			var ang := TAU * (float(k) + 0.5 * ri) / steps
			var p := at + Vector2(cos(ang), sin(ang)) * r
			var w := 1.0 / (1.0 + float(ri))     # nearer counts more
			count += w
			var x := int(floor(p.x))
			var z := int(floor(p.y))
			if x < 0 or z < 0 or x >= world.width or z >= world.height:
				sea += w
				dir += Vector2(cos(ang), sin(ang)) * w
				continue
			var t := int(world.layer_type[z * world.width + x]) if world.layer_type.size() > 0 else int(world.get_tile(x, z)["type"])
			if t == World.TileType.WATER or t == World.TileType.DEEP_WATER:
				sea += w
				if ri > 0:
					dir += Vector2(cos(ang), sin(ang)) * w
			elif t == World.TileType.FOREST:
				woods += w
			elif t == World.TileType.WOODLAND:
				woods += w * 0.7
			if ri <= 1 and bool(world.get_tile(x, z).get("river", false)):
				fresh += 2.0 * w
	var d := dir / maxf(count, 0.001)
	return {"sea": sea / count, "woods": woods / count, "fresh": clampf(fresh / count, 0.0, 1.0), "sea_dir": d}

func _gain_at(p: Vector3, hear: Dictionary, scale: float = 1.0) -> float:
	return SoundMixer.falloff(p.distance_to(ear), float(hear["ref"]) * scale, float(hear["radius"]) * scale)

func _ground(world: World, tx: float, tz: float) -> Vector3:
	return Vector3(tx * World.TILE_SIZE, world.surface_y(tx, tz) + 0.5, tz * World.TILE_SIZE)

## Fires: every live one (hearths, campfires, a burning wood), grouped by
## 4-tile cells so a wildfire roars as one; the two loudest get the players.
func _survey_fires(world: World, hear: Dictionary) -> void:
	var cells := {}
	for key in world.natural_fires:
		var t: Vector2i = _fire_keys.get(key, Vector2i(-1, -1))
		if t.x < 0:
			var parts: PackedStringArray = str(key).split(",")
			t = Vector2i(int(parts[0]), int(parts[1]))
			_fire_keys[key] = t
		var c := Vector2i(t.x >> 2, t.y >> 2)
		if not cells.has(c):
			cells[c] = [0, Vector2.ZERO]
		cells[c][0] += 1
		cells[c][1] += Vector2(t) + Vector2(0.5, 0.5)
	if _fire_keys.size() > 512:
		_fire_keys.clear()
	heard_fires.clear()
	for c in cells:
		var n: int = cells[c][0]
		var at: Vector2 = cells[c][1] / n
		var p := _ground(world, at.x, at.y)
		var g := _gain_at(p, hear) * float(hear["detail"]) * minf(1.6, sqrt(float(n)))
		if g > 0.01:
			heard_fires.append({"pos": p, "gain": g, "count": n})
	heard_fires.sort_custom(func(a, b): return a["gain"] > b["gain"])
	for i in 2:
		var name := "fire%d" % i
		if i < heard_fires.size():
			(_spots[name] as Node3D).global_position = heard_fires[i]["pos"]
			_spot_target[name] = minf(1.0, float(heard_fires[i]["gain"]))
		else:
			_spot_target[name] = 0.0

## People talking: awake folk bucketed by 6-tile cells; two or more make a
## murmur, louder when they're socialising, performing or at a rite.
func _survey_people(hear: Dictionary) -> void:
	var world: World = main.world
	var cells := {}
	var r_tiles := float(hear["radius"]) / World.TILE_SIZE
	var et := Vector2(ear.x, ear.z) / World.TILE_SIZE
	for a in main.agents:
		if a.is_dead or a.health <= 0.0 or a.state == Agent.State.SLEEPING:
			continue
		if absf(a.pos.x - et.x) > r_tiles or absf(a.pos.y - et.y) > r_tiles:
			continue
		var c := Vector2i(int(a.pos.x / 6.0), int(a.pos.y / 6.0))
		if not cells.has(c):
			cells[c] = [0.0, Vector2.ZERO, 0]
		var lively := 1.6 if a.state in [Agent.State.SOCIALIZING, Agent.State.PERFORMING, Agent.State.RITUAL] else 1.0
		cells[c][0] += lively
		cells[c][1] += a.pos
		cells[c][2] += 1
	heard_groups.clear()
	for c in cells:
		var n: int = cells[c][2]
		if n < 2:
			continue
		var at: Vector2 = cells[c][1] / n
		var p := _ground(world, at.x, at.y)
		var g := _gain_at(p, hear) * float(hear["detail"]) * minf(1.0, sqrt(float(cells[c][0])) / 2.4)
		if g > 0.01:
			heard_groups.append({"pos": p, "gain": g, "count": n})
	heard_groups.sort_custom(func(a, b): return a["gain"] > b["gain"])
	for i in 2:
		var name := "voices%d" % i
		if i < heard_groups.size():
			(_spots[name] as Node3D).global_position = heard_groups[i]["pos"]
			_spot_target[name] = minf(1.0, float(heard_groups[i]["gain"]))
		else:
			_spot_target[name] = 0.0

func _survey_festivals(hear: Dictionary) -> void:
	var now: float = main.time_system.game_time
	festivals = festivals.filter(func(f): return float(f["until"]) > now)
	var best := 0.0
	for f in festivals:
		var g := _gain_at(f["pos"], hear, 2.5)
		if g > best:
			best = g
			(_spots["festival"] as Node3D).global_position = f["pos"]
	_spot_target["festival"] = best

## The ambient frogs croak on their own clock; voice the ones within earshot.
func _survey_frogs(hear: Dictionary) -> void:
	var life = main.get("ambient_life")
	if life == null:
		return
	var world: World = main.world
	for i in life.frogs.size():
		var f = life.frogs[i]
		var last: float = _frog_last.get(i, 0.0)
		_frog_last[i] = f.croak
		if f.croak > last + 0.3:
			var p := Vector3(f.pos.x, f.y + 0.2, f.pos.y)
			var g := _gain_at(p, hear) * float(hear["detail"])
			if g > 0.03:
				_call_at("frogs", p, g * 0.8, rng.randf_range(0.9, 1.1))

# ── Each frame ───────────────────────────────────────────────────────────────

func _ease(delta: float) -> void:
	var k := 1.0 - exp(-delta / EASE_SECONDS)
	for name in _beds:
		var target := float(levels.get(name, 0.0))
		_bed_level[name] = lerpf(float(_bed_level[name]), target, k)
		var p: AudioStreamPlayer = _beds[name]
		var v := float(_bed_level[name]) * float(BED_GAIN[name])
		_set_level(p, v)
	# A storm's sea is heavier.
	var surf: AudioStreamPlayer = _beds["surf"]
	surf.pitch_scale = 1.0 - 0.06 * float(scene.get("storm", 0.0))
	for name in _spots:
		_spot_level[name] = lerpf(float(_spot_level[name]), float(_spot_target[name]), k * 1.5)
		var kind := "fire" if name.begins_with("fire") else ("voices" if name.begins_with("voices") else "festival")
		var s: AudioStreamPlayer3D = _spots[name]
		s.panning_strength = 1.0 if bool(scene.get("walk", false)) else 0.5
		_set_level(s, float(_spot_level[name]) * float(SPOT_GAIN[kind]))

func _set_level(p: Node, v: float) -> void:
	if p.stream == null:
		return
	p.volume_db = linear_to_db(maxf(v, 0.00001))
	var quiet := v < 0.002
	if p.stream_paused != quiet:
		p.stream_paused = quiet

## Birds, gulls, owls, frogs by the river, sheep and cows, far wolves.
func _calls(delta: float) -> void:
	if levels.is_empty():
		return
	var hear := SoundMixer.hearing(bool(scene.get("walk", false)), float(scene.get("cam_dist", 90.0)))
	var near := float(hear["ref"]) * 1.6
	_maybe("birds", float(levels["bird_rate"]), delta, near, 3.0, 0.7)
	_maybe("coos", float(levels["coo_rate"]), delta, near, 2.0, 0.5)
	_maybe("gulls", float(levels["gull_rate"]), delta, near * 1.5, 6.0, 0.55, _surf_dir)
	_maybe("owls", float(levels["owl_rate"]), delta, near * 1.5, 5.0, 0.5)
	_maybe("frogs", float(levels["frog_rate"]), delta, near, 0.0, 0.45)
	# Herds within earshot: a bleat or a moo now and then.
	var sim = main.get("animal_sim")
	if sim != null and rng.randf() < delta * 4.0:   # look about four times a second
		var sheep := 0
		var cows := 0
		var wolves := 0
		var sp := Vector3.ZERO
		var cp := Vector3.ZERO
		var wp := Vector3.ZERO
		var et := Vector2(ear.x, ear.z) / World.TILE_SIZE
		var r := float(hear["radius"]) / World.TILE_SIZE
		for an in sim.animals:
			if an.health <= 0.0:
				continue
			var d: float = an.pos.distance_to(et)
			if an.animal_type == AnimalSim.AnimalType.WOLF and d < r * 3.0:
				wolves += 1
				wp = Vector3(an.pos.x * World.TILE_SIZE, 2.0, an.pos.y * World.TILE_SIZE)
			elif d < r:
				if an.animal_type == AnimalSim.AnimalType.SHEEP:
					sheep += 1
					sp = Vector3(an.pos.x * World.TILE_SIZE, main.world.surface_y(an.pos.x, an.pos.y) + 0.8, an.pos.y * World.TILE_SIZE)
				elif an.animal_type == AnimalSim.AnimalType.COW:
					cows += 1
					cp = Vector3(an.pos.x * World.TILE_SIZE, main.world.surface_y(an.pos.x, an.pos.y) + 1.0, an.pos.y * World.TILE_SIZE)
		var day := SoundMixer.daylight(float(scene["hour"]))
		var look := 0.25   # the seconds this check stands for (it runs ~4 times a second)
		if sheep > 0 and rng.randf() < minf(0.4, 0.035 * sheep) * (0.3 + 0.7 * day) * look:
			_call_at("sheep", sp, _gain_at(sp, hear) * float(hear["detail"]), rng.randf_range(0.9, 1.12))
		if cows > 0 and rng.randf() < minf(0.3, 0.03 * cows) * (0.3 + 0.7 * day) * look:
			_call_at("cows", cp, _gain_at(cp, hear) * float(hear["detail"]), rng.randf_range(0.92, 1.06))
		if wolves > 0 and rng.randf() < float(levels["wolf_rate"]) * minf(3.0, float(wolves)) * look:
			# Far off: heard from three times as far, never loud.
			_call_at("wolves", wp, minf(0.5, _gain_at(wp, hear, 3.0)), rng.randf_range(0.94, 1.05))

## Roll a per-second rate; place the call somewhere round the ear.
func _maybe(kind: String, rate: float, delta: float, dist: float, up: float, gain: float, toward: Vector3 = Vector3.ZERO) -> void:
	if rate <= 0.0 or rng.randf() >= rate * delta:
		return
	var ang := rng.randf() * TAU
	var off := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.3, 1.0) * dist
	if toward.length() > 0.05:
		off = (toward.normalized() * dist + off * 0.5)
	var p := Vector3(ear.x, 0.0, ear.z) + off
	p.y = main.world.surface_y(p.x / World.TILE_SIZE, p.z / World.TILE_SIZE) + up
	var hear := SoundMixer.hearing(bool(scene.get("walk", false)), float(scene.get("cam_dist", 90.0)))
	var g := _gain_at(p, hear) * float(hear["detail"]) * gain
	_call_at(kind, p, g, rng.randf_range(0.92, 1.08))

## Play a one-shot of `kind` at p, at level g (0..1).
func _call_at(kind: String, p: Vector3, g: float, pitch: float = 1.0) -> void:
	calls_played[kind] = int(calls_played.get(kind, 0)) + 1
	if g < 0.01:
		return
	var stream := SoundBank.pick(kind, rng)
	if stream == null:
		return
	var player: AudioStreamPlayer3D = null
	for o in _oneshots:
		if not o.playing:
			player = o
			break
	if player == null:
		return   # busy enough already; let this one go
	player.stream = stream
	player.global_position = p
	player.pitch_scale = pitch
	player.panning_strength = 1.0 if bool(scene.get("walk", false)) else 0.6
	player.volume_db = linear_to_db(clampf(g, 0.0, 1.0))
	player.play()

# ── Thunder ──────────────────────────────────────────────────────────────────

func _watch_lightning() -> void:
	var sky = main.get("sky")
	var wv = sky.get("weather_view") if sky != null else null
	if wv == _weather_view or wv == null:
		return
	_weather_view = wv
	if wv.has_signal("struck") and not wv.is_connected("struck", on_lightning):
		wv.connect("struck", on_lightning)

## A bolt at `ground` (metres): the thunder follows, late by distance.
func on_lightning(ground: Vector3) -> void:
	var d := Vector2(ground.x - ear.x, ground.z - ear.z).length()
	_thunder.append({"t": SoundMixer.thunder_delay(d), "pos": ground + Vector3(0, 20, 0), "d": d})

func _tick_thunder(delta: float) -> void:
	for i in range(_thunder.size() - 1, -1, -1):
		var th: Dictionary = _thunder[i]
		th["t"] = float(th["t"]) - delta
		if th["t"] <= 0.0:
			_thunder.remove_at(i)
			var d: float = th["d"]
			_call_at("thunder_near" if d < 70.0 else "thunder_far", th["pos"], SoundMixer.thunder_gain(d), rng.randf_range(0.9, 1.05))

func thunder_pending() -> int:
	return _thunder.size()

# ── Stingers and festivals ───────────────────────────────────────────────────

## A short tune for something that happened (moment, discovery, birth...).
## Repeats close together are let go, so a busy day stays calm.
func stinger(kind: String, gain: float = 1.0) -> bool:
	var gap: float = STINGER_GAP.get(kind, 2.0)
	if _clock - float(_stinger_last.get(kind, -1000.0)) < gap:
		return false
	_stinger_last[kind] = _clock
	var stream := SoundBank.get_stream("st_" + kind)
	if stream == null:
		return false
	var p: AudioStreamPlayer = _ui[_ui_next]
	_ui_next = (_ui_next + 1) % _ui.size()
	p.stream = stream
	p.volume_db = linear_to_db(clampf(gain, 0.001, 1.0))
	p.play()
	return true

## A festival began at `pos` (tile coords as Vector2, or metres as Vector3):
## a flourish, then a band, a bonfire's crackle and lively voices there until
## it ends (or FESTIVAL_SECONDS of game time).
func add_festival(kind: String, pos, seconds: float = FESTIVAL_SECONDS) -> void:
	if main == null or main.get("world") == null:
		return
	var p: Vector3
	if pos is Vector3:
		p = pos
	elif pos is Vector2:
		p = _ground(main.world, pos.x, pos.y)
	else:
		p = main.observer.target if main.get("observer") else Vector3.ZERO
	festivals.append({"kind": kind, "pos": p, "until": float(main.time_system.game_time) + seconds})
	var hear := SoundMixer.hearing(_walking(), float(scene.get("cam_dist", 90.0)))
	stinger("festival", clampf(_gain_at(p, hear, 2.5) * 2.0, 0.25, 1.0))

func end_festival(pos = null) -> void:
	if pos == null:
		festivals.clear()
		return
	var p: Vector3 = pos if pos is Vector3 else _ground(main.world, pos.x, pos.y)
	festivals = festivals.filter(func(f): return (f["pos"] as Vector3).distance_to(p) > 8.0)

# ── Mute ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_N:
		return
	var off := SoundSettings.toggle_mute()
	if main and main.has_method("_push_notification"):
		main._push_notification("Sound off (N)" if off else "Sound on")
	get_viewport().set_input_as_handled()
