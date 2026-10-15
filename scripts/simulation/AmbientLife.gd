class_name AmbientLife
extends RefCounted
## The island's small wild things: whales offshore, fish shoals in the
## shallows and rivers, frogs by fresh water, bird flocks, robins round the
## people, butterflies over meadows, midge swarms at dusk, and wild bees with
## their nests in the woods.
##
## A light simulation of its own, not part of AnimalSim: nothing here is
## hunted, and nothing here changes the people, except two explicit hooks:
##  - fish_catch(): a fisher's yield depends on how near a shoal they are
##    (and a catch thins that shoal for a while);
##  - honey trips: someone who knows honey gathering, out gathering and
##    hungry, may walk to a nearby bees' nest and eat honey (tick()).
## and hive_near(), which ConceptGraph reads for the near_bee_hive condition.
##
## Its dice are its own RandomNumberGenerator, seeded from the world, so it
## never shifts the simulation's global randf(). Positions are world metres
## (x, z = tile * TILE_SIZE); y is the height things are drawn at.

const T := World.TILE_SIZE
const MAX_STEP := 0.25            # game seconds per sub-step (20x stays smooth)

# Caps (the renderer draws at most these).
const WHALES := 3
const SEA_SHOALS := 10
const RIVER_SHOALS := 4
const FISH_MIN := 6
const FISH_MAX := 10
const FLOCKS := 3
const BIRDS_PER_FLOCK := 10
const ROBINS := 8
const BUTTERFLIES := 28
const SWARMS := 8
const HIVES := 4
const BEES_PER_HIVE := 6
const FROGS := 14

# Whales
enum WhaleState { DIVE, SURFACE, BREACH }
const WHALE_SPEED := 1.4           # m/s
const WHALE_DIVE := Vector2(35.0, 70.0)     # seconds under, min..max
const WHALE_SURFACE := Vector2(10.0, 16.0)  # seconds at the surface
const BREACH_RATE := 0.025         # per second while surfaced (about one breach a game day island-wide)
const BREACH_TIME := 4.5
const BREACH_RISE := 5.5           # metres the body's centre clears the sea at the top
const WHALE_DEEP_Y := -3.0
const WHALE_BACK_Y := -0.55        # centre depth with the back just out
const WHALE_MIN_DEPTH := 4.0       # metres of water under them

# Fish
const FISH_REACH := 5.0            # tiles: a fisher this close to a shoal is fishing it
const FISH_NEAR := 1.6             # catch multiplier beside a full shoal
const FISH_NONE := 0.7             # ...and with no shoal in reach
const FISH_REGROW := 30.0          # game seconds per fish back in a thinned shoal
const SHOAL_SPEED := 0.6
const SHOAL_LEASH := 10.0          # metres a shoal drifts from home

# Birds
const BIRD_ALT := 9.0
const BIRD_SPEED := Vector2(3.0, 7.0)
const ROOST_FROM := 19.5           # hour birds head for the trees
const ROOST_UNTIL := 5.5           # ...and leave them

# Bees and honey
const BEE_HOURS := Vector2(7.0, 19.0)
const HIVE_HEIGHT := 1.6           # nest hangs this far above the ground
const HONEY_REGROW := 1.0 / TimeSystem.DAY_LENGTH   # a full nest a day (spring, summer)
const HONEY_RANGE := 12.0          # tiles a hungry gatherer will walk to a nest
const HONEY_CHANCE := 0.3          # per second, for a hungry gatherer in range
const HONEY_TAKE := 0.5            # of a nest per visit
const HONEY_FOOD := 0.8            # hunger per whole nest's honey

# Butterflies, swarms, frogs
const FLY_HOURS := Vector2(8.0, 18.0)
const SWARM_HOURS := Vector2(17.5, 20.5)
const CROAK_HOURS := Vector2(18.0, 23.5)

class Whale:
	var pos := Vector2.ZERO
	var heading := 0.0
	var turn := 1.0
	var state := 0            # WhaleState
	var phase := 0.0          # seconds into this state
	var length := 1.0         # seconds this state lasts
	var y := -3.0
	var pitch := 0.0          # radians, nose up positive
	var roll := 0.0
	var spout := 0.0          # 0..1
	var splash := 0.0         # 1 at a splash, fading
	var splash_pos := Vector2.ZERO

class Shoal:
	var pos := Vector2.ZERO
	var home := Vector2.ZERO
	var vel := Vector2.ZERO
	var stock := 0
	var max_stock := 0
	var regrow := 0.0
	var river := false
	var y := -0.2
	var phase := 0.0

class Bird:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var perch := Vector3.ZERO
	var perched := false
	var flap := 0.0

class Flock:
	var goal := Vector2.ZERO
	var goal_timer := 0.0
	var roost := Vector2.ZERO
	var birds: Array = []

class Robin:
	var pos := Vector2.ZERO
	var y := 0.0
	var target := Vector2.ZERO
	var hop_from := Vector2.ZERO
	var hop_t := -1.0         # 0..1 through a hop, -1 standing
	var flying := false
	var wait := 0.0
	var retarget := 0.0
	var facing := 0.0
	var shown := true

class Butterfly:
	var pos := Vector3.ZERO
	var anchor := Vector2.ZERO
	var target := Vector3.ZERO
	var hue := 0
	var shown := false

class Swarm:
	var pos := Vector3.ZERO
	var level := 0.0

class Hive:
	var tile := Vector2i.ZERO
	var pos := Vector2.ZERO
	var y := 0.0
	var honey := 1.0
	var flowers: Array = []   # Vector2 metres

class Bee:
	var hive := 0
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	var linger := 0.0
	var out := false
	var shown := false

class Frog:
	var home := Vector2.ZERO
	var pos := Vector2.ZERO
	var y := 0.0
	var hop_from := Vector2.ZERO
	var hop_to := Vector2.ZERO
	var hop_t := -1.0
	var wait := 0.0
	var facing := 0.0
	var croak := 0.0          # throat puff, 1 at a croak, fading
	var next_croak := 0.0
	var croaking := false
	var shown := true

var whales: Array = []
var shoals: Array = []
var flocks: Array = []
var robins: Array = []
var butterflies: Array = []
var swarms: Array = []
var hives: Array = []
var bees: Array = []
var frogs: Array = []
## {kind: "breach"|"honey"|"chorus", pos: Vector2 tile coords, agent_id?}
var events: Array = []
## agent_id -> {hive, spot (tile coords)}
var honey_trips: Dictionary = {}
## Game seconds this has run (the renderer animates by it, so a pause stands still).
var clock := 0.0
var hour := 12.0
var season := "Spring"
var raining := false

var _world: World
var _rng := RandomNumberGenerator.new()
var _open_tiles: Array = []      # Vector2i: meadow and beach, for flocks
var _chorus_open := false

# ── Setup ────────────────────────────────────────────────────────────────────

func setup(world: World) -> AmbientLife:
	_world = world
	_rng.seed = hash("ambient:%d" % world.seed_val)
	attach()
	var deep: Array = []
	var shallow: Array = []
	var river: Array = []
	var grass: Array = []
	var woods: Array = []
	var fresh_edge: Array = []
	var wet_edge: Array = []
	for z in range(2, world.height - 2):
		for x in range(2, world.width - 2):
			var t := world.get_tile(x, z)
			var ty := int(t["type"])
			match ty:
				World.TileType.DEEP_WATER:
					if _depth_at(Vector2(x + 0.5, z + 0.5) * T) >= WHALE_MIN_DEPTH and _land_within(x, z, 4) == false:
						deep.append(Vector2i(x, z))
				World.TileType.WATER:
					if _land_within(x, z, 3):
						shallow.append(Vector2i(x, z))
				World.TileType.GRASS:
					grass.append(Vector2i(x, z))
					_open_tiles.append(Vector2i(x, z))
				World.TileType.BEACH:
					_open_tiles.append(Vector2i(x, z))
				World.TileType.WOODLAND, World.TileType.FOREST:
					woods.append(Vector2i(x, z))
			if bool(t.get("river", false)) and world.is_walkable(x + 0.5, z + 0.5):
				river.append(Vector2i(x, z))
			if world.is_walkable(x + 0.5, z + 0.5) and not bool(t.get("river", false)):
				if _river_within(x, z, 1):
					fresh_edge.append(Vector2i(x, z))
				elif ty == World.TileType.WOODLAND or ty == World.TileType.FOREST or ty == World.TileType.GRASS:
					if _water_within(x, z, 1):
						wet_edge.append(Vector2i(x, z))
	_spawn_whales(deep)
	_spawn_shoals(shallow, river)
	_spawn_hives(woods)
	_spawn_flocks(woods)
	_spawn_robins(grass)
	_spawn_butterflies(grass)
	_spawn_swarms(fresh_edge + wet_edge, woods)
	_spawn_frogs(fresh_edge if not fresh_edge.is_empty() else wet_edge)
	return self

func _pick(list: Array) -> Variant:
	return list[_rng.randi() % list.size()] if not list.is_empty() else null

func _centre(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * T

func _spawn_whales(deep: Array) -> void:
	for i in WHALES:
		var t = _pick(deep)
		if t == null:
			return
		var w := Whale.new()
		w.pos = _centre(t)
		w.heading = _rng.randf() * TAU
		w.turn = 1.0 if _rng.randf() < 0.5 else -1.0
		w.state = WhaleState.DIVE
		# Staggered, so the three don't all come up together.
		w.length = _rng.randf_range(4.0, WHALE_DIVE.y)
		whales.append(w)

func _spawn_shoals(shallow: Array, river: Array) -> void:
	for i in SEA_SHOALS + RIVER_SHOALS:
		var in_river := i >= SEA_SHOALS
		var t = _pick(river if in_river else shallow)
		if t == null:
			continue
		var s := Shoal.new()
		s.river = in_river
		s.home = _centre(t)
		s.pos = s.home
		s.max_stock = _rng.randi_range(FISH_MIN, FISH_MAX)
		s.stock = s.max_stock
		s.phase = _rng.randf() * TAU
		s.y = _fish_y(s.pos)
		shoals.append(s)

## Wild nests in the woods, spread apart, beside open ground (bees need flowers).
func _spawn_hives(woods: Array) -> void:
	var tries := 0
	while hives.size() < HIVES and tries < 400 and not woods.is_empty():
		tries += 1
		var t: Vector2i = _pick(woods)
		var far := true
		for h in hives:
			if Vector2(h.tile).distance_to(Vector2(t)) < 20.0:
				far = false
		if not far:
			continue
		var flowers: Array = []
		for dz in range(-5, 6):
			for dx in range(-5, 6):
				var n := _world.get_tile(t.x + dx, t.y + dz)
				if not n.is_empty() and int(n["type"]) == World.TileType.GRASS:
					flowers.append(_centre(Vector2i(t.x + dx, t.y + dz)))
		if flowers.size() < 4 and tries < 300:
			continue
		var h := Hive.new()
		h.tile = t
		h.pos = _centre(t) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
		h.y = _ground(h.pos) + HIVE_HEIGHT
		h.flowers = flowers
		hives.append(h)
		for b in BEES_PER_HIVE:
			var bee := Bee.new()
			bee.hive = hives.size() - 1
			bee.pos = Vector3(h.pos.x, h.y, h.pos.y)
			bee.target = bee.pos
			bees.append(bee)

func _spawn_flocks(woods: Array) -> void:
	for f in FLOCKS:
		var t = _pick(_open_tiles)
		if t == null:
			return
		var fl := Flock.new()
		fl.goal = _centre(t)
		fl.goal_timer = _rng.randf_range(5.0, 20.0)
		var r = _nearest_in(woods, t, 30)
		fl.roost = _centre(r) if r != null else fl.goal
		for i in BIRDS_PER_FLOCK:
			var b := Bird.new()
			var off := Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-1, 1), _rng.randf_range(-4, 4))
			b.pos = Vector3(fl.goal.x, _ground(fl.goal) + BIRD_ALT, fl.goal.y) + off
			b.vel = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * BIRD_SPEED.x
			var pa := _rng.randf() * TAU
			var pr := _rng.randf_range(0.5, 3.0)
			var pp := fl.roost + Vector2(cos(pa), sin(pa)) * pr
			b.perch = Vector3(pp.x, _ground(pp) + _rng.randf_range(2.6, 3.6), pp.y)
			b.flap = _rng.randf() * TAU
			fl.birds.append(b)
		flocks.append(fl)

func _spawn_robins(grass: Array) -> void:
	for i in ROBINS:
		var t = _pick(grass)
		if t == null:
			return
		var r := Robin.new()
		r.pos = _centre(t)
		r.target = r.pos
		r.y = _ground(r.pos)
		r.retarget = _rng.randf_range(0.0, 6.0)
		robins.append(r)

func _spawn_butterflies(grass: Array) -> void:
	for i in BUTTERFLIES:
		var t = _pick(grass)
		if t == null:
			return
		var b := Butterfly.new()
		b.anchor = _centre(t)
		b.pos = Vector3(b.anchor.x, _ground(b.anchor) + 0.8, b.anchor.y)
		b.target = b.pos
		b.hue = i
		butterflies.append(b)

func _spawn_swarms(wet: Array, woods: Array) -> void:
	for i in SWARMS:
		var t = _pick(wet if i % 4 != 3 or woods.is_empty() else woods)
		if t == null:
			return
		var s := Swarm.new()
		var p := _centre(t)
		s.pos = Vector3(p.x, _ground(p) + 1.4, p.y)
		swarms.append(s)

func _spawn_frogs(edge: Array) -> void:
	# A few frogs to a pond: pick a handful of spots, put two to four at each.
	while frogs.size() < FROGS and not edge.is_empty():
		var t: Vector2i = _pick(edge)
		var n := mini(_rng.randi_range(2, 4), FROGS - frogs.size())
		for k in n:
			var f := Frog.new()
			f.home = _centre(t) + Vector2(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-1.2, 1.2))
			f.pos = f.home
			f.y = _ground(f.pos)
			f.facing = _rng.randf() * TAU
			f.wait = _rng.randf_range(0.0, 4.0)
			f.next_croak = _rng.randf_range(0.0, 2.0)
			frogs.append(f)

# ── Tick ─────────────────────────────────────────────────────────────────────

## Game delta, the clock's hour and season ("Spring"...), the people (read,
## except for honey trips), and whether it's raining.
func tick(delta: float, p_hour: float, p_season: String, agents: Array = [], p_raining: bool = false) -> void:
	if delta <= 0.0 or _world == null:
		return
	hour = p_hour
	season = p_season
	raining = p_raining
	var left := delta
	while left > 0.0:
		var dt := minf(left, MAX_STEP)
		left -= dt
		clock += dt
		_tick_whales(dt)
		_tick_shoals(dt)
		_tick_flocks(dt)
		_tick_robins(dt, agents)
		_tick_butterflies(dt)
		_tick_swarms(dt)
		_tick_hives(dt)
		_tick_frogs(dt)
	_tick_honey(delta, agents)

func drain_events() -> Array:
	var out := events
	events = []
	return out

func _tick_whales(dt: float) -> void:
	for w: Whale in whales:
		w.phase += dt
		var speed := WHALE_SPEED
		match w.state:
			WhaleState.DIVE:
				# Flukes up as it goes down, then out of sight.
				var t := clampf(w.phase / 3.0, 0.0, 1.0)
				w.y = lerpf(WHALE_BACK_Y, WHALE_DEEP_Y, t * t)
				w.pitch = -0.5 * sin(t * PI) if w.length > 6.0 else 0.0
				w.roll = 0.0
				w.spout = 0.0
				if w.phase >= w.length:
					_whale_state(w, WhaleState.SURFACE, _rng.randf_range(WHALE_SURFACE.x, WHALE_SURFACE.y))
			WhaleState.SURFACE:
				w.y = lerpf(WHALE_DEEP_Y, WHALE_BACK_Y, smoothstep(0.0, 2.0, w.phase))
				w.pitch = 0.04 * sin(w.phase * 0.8)
				# A blow as it comes up, and another before it goes.
				var blow := maxf(_pulse(w.phase, 1.6, 2.4), _pulse(w.phase, w.length - 4.0, 2.0))
				w.spout = blow
				if w.phase > 3.0 and w.phase < w.length - 4.5 and _rng.randf() < BREACH_RATE * dt:
					_whale_state(w, WhaleState.BREACH, BREACH_TIME)
					events.append({"kind": "breach", "pos": w.pos / T})
				elif w.phase >= w.length:
					_whale_state(w, WhaleState.DIVE, _rng.randf_range(WHALE_DIVE.x, WHALE_DIVE.y))
			WhaleState.BREACH:
				var t := clampf(w.phase / BREACH_TIME, 0.0, 1.0)
				w.y = WHALE_BACK_Y + (BREACH_RISE - WHALE_BACK_Y) * sin(t * PI) - maxf(0.0, t - 0.8) * 8.0
				w.pitch = 1.15 * (1.0 - 2.0 * t)
				w.roll = sin(t * PI) * 0.9 * w.turn
				w.spout = 0.0
				speed = WHALE_SPEED * 2.2
				if t > 0.82 and w.splash < 0.5:
					w.splash = 1.0
					w.splash_pos = w.pos
				if w.phase >= w.length:
					_whale_state(w, WhaleState.DIVE, _rng.randf_range(WHALE_DIVE.x, WHALE_DIVE.y))
		w.splash = maxf(0.0, w.splash - dt / 2.5)
		# Swim on, turning away from shallow water ahead.
		var fwd := Vector2(sin(w.heading), cos(w.heading))
		if not _whale_water(w.pos + fwd * 16.0):
			w.heading += 0.6 * w.turn * dt
		else:
			w.heading += _rng.randf_range(-0.08, 0.08) * dt
		var next := w.pos + fwd * speed * dt
		if _whale_water(next):
			w.pos = next
		else:
			w.heading += 1.2 * w.turn * dt

func _whale_state(w: Whale, s: int, length: float) -> void:
	w.state = s
	w.phase = 0.0
	w.length = length

static func _pulse(t: float, start: float, length: float) -> float:
	if t < start or t > start + length:
		return 0.0
	return sin((t - start) / length * PI)

func _whale_water(p: Vector2) -> bool:
	var tx := p.x / T
	var tz := p.y / T
	if tx < 2.0 or tz < 2.0 or tx > _world.width - 2.0 or tz > _world.height - 2.0:
		return false
	var t := _world.get_tile_f(tx, tz)
	return not t.is_empty() and int(t["type"]) == World.TileType.DEEP_WATER and _depth_at(p) >= WHALE_MIN_DEPTH * 0.75

func _tick_shoals(dt: float) -> void:
	for s: Shoal in shoals:
		if s.stock < s.max_stock:
			s.regrow += dt
			if s.regrow >= FISH_REGROW:
				s.regrow = 0.0
				s.stock += 1
		s.vel += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.6 * dt
		var home := s.home - s.pos
		if home.length() > SHOAL_LEASH:
			s.vel += home.normalized() * 0.5 * dt
		s.vel = s.vel.limit_length(SHOAL_SPEED * (0.6 if s.river else 1.0))
		var next := s.pos + s.vel * dt
		if _fish_water(next, s.river):
			s.pos = next
		else:
			s.vel = (s.home - s.pos).normalized() * 0.2
		s.y = lerpf(s.y, _fish_y(s.pos), minf(1.0, dt * 2.0))

func _fish_water(p: Vector2, river: bool) -> bool:
	var t := _world.get_tile_f(p.x / T, p.y / T)
	if t.is_empty():
		return false
	if river:
		return bool(t.get("river", false)) or int(t["type"]) == World.TileType.WATER
	return int(t["type"]) == World.TileType.WATER

## Fish swim a hand under the surface (the sea is at y = 0); in a river that
## runs above sea level, just over its bed.
func _fish_y(p: Vector2) -> float:
	var bed := _bed(p)
	if bed < 0.0:
		return maxf(bed * 0.5, -0.22)
	return bed + 0.05

func _tick_flocks(dt: float) -> void:
	var roosting := is_roost_time()
	for fl: Flock in flocks:
		fl.goal_timer -= dt
		if fl.goal_timer <= 0.0 and not _open_tiles.is_empty():
			fl.goal_timer = _rng.randf_range(15.0, 30.0)
			# Somewhere open not too far from here, so they drift over the island.
			for i in 8:
				var t: Vector2i = _pick(_open_tiles)
				var p := _centre(t)
				if p.distance_to(fl.goal) < 70.0:
					fl.goal = p
					break
		var mean_vel := Vector3.ZERO
		for b: Bird in fl.birds:
			mean_vel += b.vel
		mean_vel /= maxf(1.0, fl.birds.size())
		var goal3 := Vector3(fl.goal.x, _ground(fl.goal) + BIRD_ALT, fl.goal.y)
		for b: Bird in fl.birds:
			b.flap += dt * (14.0 if not b.perched else 0.0)
			if roosting:
				var to := b.perch - b.pos
				if b.perched or to.length() < 0.6:
					b.perched = true
					b.pos = b.perch
					b.vel = Vector3.ZERO
					continue
				b.vel = b.vel.lerp(to.normalized() * minf(BIRD_SPEED.y, maxf(1.0, to.length())), minf(1.0, dt * 2.0))
				b.pos += b.vel * dt
				continue
			b.perched = false
			var acc := Vector3.ZERO
			var to_goal := goal3 - b.pos
			acc += to_goal * 0.08
			# Wheel round the goal rather than settle on it.
			acc += Vector3(-to_goal.z, 0, to_goal.x).normalized() * 1.2
			acc += (mean_vel - b.vel) * 0.5
			for o: Bird in fl.birds:
				if o == b:
					continue
				var away := b.pos - o.pos
				var d := away.length()
				if d < 1.6 and d > 0.001:
					acc += away / d * (1.6 - d) * 4.0
			var floor_y := _ground(Vector2(b.pos.x, b.pos.z)) + 4.0
			if b.pos.y < floor_y:
				acc.y += (floor_y - b.pos.y) * 2.0
			b.vel += acc * dt
			var sp := b.vel.length()
			if sp > BIRD_SPEED.y:
				b.vel = b.vel / sp * BIRD_SPEED.y
			elif sp < BIRD_SPEED.x:
				b.vel = (b.vel / maxf(sp, 0.001)) * BIRD_SPEED.x
			b.vel.y = clampf(b.vel.y, -2.0, 2.0)
			b.pos += b.vel * dt

func is_roost_time() -> bool:
	return hour >= ROOST_FROM or hour < ROOST_UNTIL

func _tick_robins(dt: float, agents: Array) -> void:
	var night := hour >= 20.5 or hour < 5.5
	for r: Robin in robins:
		r.shown = not night
		if night:
			continue
		r.retarget -= dt
		if r.retarget <= 0.0:
			r.retarget = _rng.randf_range(8.0, 20.0)
			var near := _someone(agents)
			var base := (near.pos * T) if near != null else r.pos
			for i in 6:
				var p := base + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(2.0, 5.0)
				if _world.is_walkable(p.x / T, p.y / T):
					r.target = p
					break
		var to := r.target - r.pos
		var dist := to.length()
		if r.hop_t < 0.0:
			if r.wait > 0.0:
				r.wait -= dt
			elif dist > 0.25:
				r.hop_from = r.pos
				r.flying = dist > 10.0
				r.hop_t = 0.0
				r.facing = atan2(to.x, to.y)
		if r.hop_t >= 0.0:
			var span := minf(dist, 12.0 if r.flying else 0.35)
			var dur := span / 6.0 if r.flying else 0.3
			r.hop_t += dt / maxf(dur, 0.05)
			var dir := to.normalized() if dist > 0.001 else Vector2.ZERO
			r.pos += dir * minf(dist, span * dt / maxf(dur, 0.05))
			var arc := sin(clampf(r.hop_t, 0.0, 1.0) * PI) * (2.0 if r.flying else 0.09)
			r.y = _ground(r.pos) + arc
			if r.hop_t >= 1.0:
				r.hop_t = -1.0
				r.y = _ground(r.pos)
				if _rng.randf() < 0.25:
					r.wait = _rng.randf_range(0.5, 2.5)

## A living person, picked by the robin's own dice; null when there's no one.
func _someone(agents: Array) -> Agent:
	if agents.is_empty():
		return null
	for i in 4:
		var a: Agent = agents[_rng.randi() % agents.size()]
		if not a.is_dead and a.health > 0.0:
			return a
	return null

func butterflies_out() -> bool:
	return (season == "Spring" or season == "Summer" or season == "Autumn") and not raining \
		and hour >= FLY_HOURS.x and hour < FLY_HOURS.y

func _tick_butterflies(dt: float) -> void:
	var out := butterflies_out()
	for b: Butterfly in butterflies:
		# Autumn keeps a third of them; winter none.
		b.shown = out and (season != "Autumn" or b.hue % 3 == 0)
		if not b.shown:
			continue
		var to := b.target - b.pos
		if to.length() < 0.3:
			var p := b.anchor + Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5))
			b.target = Vector3(p.x, _ground(p) + _rng.randf_range(0.4, 1.6), p.y)
		else:
			var jig := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.8
			b.pos += (to.normalized() * 1.1 + jig) * dt
			b.pos.y = maxf(b.pos.y, _ground(Vector2(b.pos.x, b.pos.z)) + 0.25)

func swarms_out() -> bool:
	return season != "Winter" and not raining and hour >= SWARM_HOURS.x and hour < SWARM_HOURS.y

func _tick_swarms(dt: float) -> void:
	var goal := 1.0 if swarms_out() else 0.0
	for s: Swarm in swarms:
		s.level = move_toward(s.level, goal, dt * 0.25)

func bees_out() -> bool:
	return season != "Winter" and not raining and hour >= BEE_HOURS.x and hour < BEE_HOURS.y

func _tick_hives(dt: float) -> void:
	var regrow: float = {"Spring": 1.0, "Summer": 1.0, "Autumn": 0.5}.get(season, 0.0)
	for h: Hive in hives:
		h.honey = minf(1.0, h.honey + HONEY_REGROW * regrow * dt)
	var out := bees_out()
	for b: Bee in bees:
		var h: Hive = hives[b.hive]
		var home := Vector3(h.pos.x, h.y, h.pos.y)
		if not out:
			# Home for the night (or the rain); gone in once there.
			b.out = false
			if b.shown:
				var to_home := home - b.pos
				if to_home.length() < 0.3:
					b.shown = false
				else:
					b.pos += to_home.normalized() * minf(to_home.length(), 2.5 * dt)
			continue
		b.shown = true
		if b.linger > 0.0:
			b.linger -= dt
			b.pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * 0.3 * dt
			continue
		var to := b.target - b.pos
		if to.length() < 0.25:
			b.out = not b.out
			if b.out and not h.flowers.is_empty():
				var f: Vector2 = h.flowers[_rng.randi() % h.flowers.size()]
				f += Vector2(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.8, 0.8))
				# Bees work the flowers near home: at most about 8 m out.
				f = h.pos + (f - h.pos).limit_length(8.0)
				b.target = Vector3(f.x, _ground(f) + 0.3, f.y)
				b.linger = 0.0
			else:
				b.target = home
				b.out = false
				b.linger = _rng.randf_range(0.5, 2.0) if b.pos.distance_to(home) > 1.0 else _rng.randf_range(0.2, 1.0)
		else:
			b.pos += to.normalized() * minf(to.length(), 2.5 * dt) + Vector3(0, sin(clock * 9.0 + b.hive) * 0.4 * dt, 0)

func croak_time() -> bool:
	return season != "Winter" and hour >= CROAK_HOURS.x and hour < CROAK_HOURS.y

func _tick_frogs(dt: float) -> void:
	var asleep := season == "Winter"
	var croaking := croak_time()
	var chorus_starts := croaking and not _chorus_open
	_chorus_open = croaking
	var told := 0
	for f: Frog in frogs:
		f.shown = not asleep
		if asleep:
			continue
		f.croak = maxf(0.0, f.croak - dt * 2.5)
		f.croaking = croaking
		if croaking:
			f.next_croak -= dt
			if f.next_croak <= 0.0:
				f.next_croak = _rng.randf_range(1.2, 3.0)
				f.croak = 1.0
			if chorus_starts and told < 4 and frogs.find(f) % 3 == 0:
				told += 1
				events.append({"kind": "chorus", "pos": f.pos / T})
		if f.hop_t >= 0.0:
			f.hop_t += dt / 0.4
			var t := minf(f.hop_t, 1.0)
			f.pos = f.hop_from.lerp(f.hop_to, t)
			f.y = _ground(f.pos) + sin(t * PI) * 0.22
			if f.hop_t >= 1.0:
				f.hop_t = -1.0
				f.y = _ground(f.pos)
			continue
		f.wait -= dt
		if f.wait <= 0.0:
			f.wait = _rng.randf_range(2.0, 7.0) * (2.0 if croaking else 1.0)
			var to := f.home + Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
			if _world.is_walkable(to.x / T, to.y / T):
				f.hop_from = f.pos
				f.hop_to = f.pos + (to - f.pos).limit_length(0.7)
				f.hop_t = 0.0
				f.facing = atan2(f.hop_to.x - f.pos.x, f.hop_to.y - f.pos.y)

## Honey trips: a hungry gatherer who knows honey gathering may turn aside to
## a nearby nest. Arriving beside it they eat honey (hunger up, nest down).
func _tick_honey(delta: float, agents: Array) -> void:
	if hives.is_empty():
		return
	for a: Agent in agents:
		if a.is_dead or a.health <= 0.0:
			honey_trips.erase(a.agent_id)
			continue
		var trip: Dictionary = honey_trips.get(a.agent_id, {})
		if not trip.is_empty():
			var h: Hive = hives[int(trip["hive"])]
			var spot: Vector2 = trip["spot"]
			if a.pos.distance_to(spot) < 0.7:
				var take := minf(HONEY_TAKE, h.honey)
				h.honey -= take
				var food := take * HONEY_FOOD * (1.25 if a.knowledge.has("beekeeping") else 1.0)
				a.needs["hunger"] = minf(1.0, float(a.needs["hunger"]) + food)
				a.say("Honey!", 3.0)
				honey_trips.erase(a.agent_id)
				events.append({"kind": "honey", "pos": a.pos, "agent_id": a.agent_id, "food": food})
			elif a.state != Agent.State.GATHERING or a.target.distance_to(spot) > 0.05:
				honey_trips.erase(a.agent_id)   # they've something else in mind now
			continue
		if not a.knowledge.has("honey_gathering") or a.state != Agent.State.GATHERING:
			continue
		if float(a.needs["hunger"]) > 0.6:
			continue
		var best := -1
		var best_d := HONEY_RANGE
		for i in hives.size():
			var h: Hive = hives[i]
			if h.honey < 0.3:
				continue
			var d := a.pos.distance_to(h.pos / T)
			if d < best_d:
				best_d = d
				best = i
		if best < 0 or _rng.randf() >= HONEY_CHANCE * delta:
			continue
		var hv: Hive = hives[best]
		var at := hv.pos / T
		var spot := at + (a.pos - at).normalized() * 0.4 if a.pos.distance_to(at) > 0.01 else at
		if not _world.is_walkable(spot.x, spot.y):
			spot = at
		a.target = spot
		honey_trips[a.agent_id] = {"hive": best, "spot": spot}

# ── Hooks the simulation calls ───────────────────────────────────────────────

## Make this the wild life the world's hooks find (setup does it). The world
## points back weakly, so there's no cycle (World and its helpers must not
## hold each other: LESSONS.md).
func attach() -> void:
	_world.set_meta("ambient_life", weakref(self))

## The AmbientLife living on this world, or null (tests, tools without one).
static func of(world: World) -> AmbientLife:
	if world == null or not world.has_meta("ambient_life"):
		return null
	var ref: WeakRef = world.get_meta("ambient_life")
	return ref.get_ref() as AmbientLife

## Agent fishing: the yield multiplier at a tile-space point, and the catch
## thins that shoal. 1.0 when nothing models fish (so old behaviour holds).
static func fish_catch(world: World, tile_pos: Vector2) -> float:
	var life := of(world)
	return life.catch_at(tile_pos) if life else 1.0

func catch_at(tile_pos: Vector2) -> float:
	var s := nearest_shoal(tile_pos)
	if s == null:
		return FISH_NONE
	var d := s.pos.distance_to(tile_pos * T) / T
	var full := float(s.stock) / float(maxi(1, s.max_stock))
	if s.stock > 0:
		s.stock -= 1
	return lerpf(FISH_NONE, FISH_NEAR, full * (1.0 - clampf(d / FISH_REACH, 0.0, 1.0) * 0.5))

## The shoal within FISH_REACH tiles of a tile-space point, or null.
func nearest_shoal(tile_pos: Vector2) -> Shoal:
	var best: Shoal = null
	var best_d := FISH_REACH * T
	for s: Shoal in shoals:
		var d := s.pos.distance_to(tile_pos * T)
		if d <= best_d:
			best_d = d
			best = s
	return best

## ConceptGraph's near_bee_hive: 1 if a nest is within r tiles of the tile,
## 0 if not, -1 if this world has no nests modelled.
static func hive_near(world: World, tile: Dictionary, r: float) -> int:
	var life := of(world)
	if life == null or tile.is_empty():
		return -1
	var p := Vector2(float(tile["x"]) + 0.5, float(tile["z"]) + 0.5)
	for h: Hive in life.hives:
		if p.distance_to(h.pos / T) <= r:
			return 1
	return 0

# ── Ground helpers ───────────────────────────────────────────────────────────

func _ground(p: Vector2) -> float:
	return _world.surface_y(p.x / T, p.y / T)

## The real ground height (below 0 under the sea), metres.
func _bed(p: Vector2) -> float:
	if _world.heightfield != null:
		return _world.heightfield.height_at(p.x, p.y)
	var t := _world.get_tile_f(p.x / T, p.y / T)
	if t.is_empty():
		return -5.0
	var ty := int(t["type"])
	if ty == World.TileType.DEEP_WATER:
		return -8.0
	if ty == World.TileType.WATER:
		return -1.0
	return float(t["elevation"]) * World.HEIGHT_SCALE

func _depth_at(p: Vector2) -> float:
	return -_bed(p)

func _land_within(x: int, z: int, r: int) -> bool:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := _world.get_tile(x + dx, z + dz)
			if not t.is_empty() and int(t["type"]) != World.TileType.WATER and int(t["type"]) != World.TileType.DEEP_WATER:
				return true
	return false

func _river_within(x: int, z: int, r: int) -> bool:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := _world.get_tile(x + dx, z + dz)
			if not t.is_empty() and bool(t.get("river", false)):
				return true
	return false

func _water_within(x: int, z: int, r: int) -> bool:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := _world.get_tile(x + dx, z + dz)
			if not t.is_empty() and int(t["type"]) == World.TileType.WATER:
				return true
	return false

func _nearest_in(list: Array, from: Vector2i, max_d: float) -> Variant:
	var best = null
	var best_d := max_d
	for t: Vector2i in list:
		var d := Vector2(t).distance_to(Vector2(from))
		if d < best_d:
			best_d = d
			best = t
	return best
