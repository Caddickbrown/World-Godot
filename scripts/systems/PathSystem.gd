class_name PathSystem
extends RefCounted
## Worn earth: where people walk, the ground remembers. Every SAMPLE_SECONDS
## of game time each person on the move adds a footfall to the tile under
## them (World.trade_traffic, Vector2i tile -> count); a trader on a journey between
## settlements counts TRADER_WEIGHT times. Once a day every count fades by
## DAILY_KEEP, so a way nobody walks any more greens over in a few days.
## PathRenderer draws the counts as worn paths.
##
## This writes only World.trade_traffic, which no simulation code reads: the
## paths are a picture of where people went, never a reason to go there.

const SAMPLE_SECONDS := 1.0        # game seconds between footfall samples
const TRADER_WEIGHT := 3.0
const DAILY_KEEP := 0.55           # fraction of a tile's wear left after a day
const MAX_WEAR := 60.0             # a tile can't get more worn than this
const MOVED_MIN := 0.3             # tiles walked since the last sample to count
const HOME_CLEAR := 3.0            # tiles: inside this of a hearth the camp's own trampled ground shows instead

var revision := 0                  # bumped whenever the wear changes enough to redraw
var _timer := 0.0
var _last_pos: Dictionary = {}     # agent_id -> Vector2
var _last_day := -1
var _fresh := 0.0                  # footfalls since the last revision bump

func tick(delta: float, agents: Array, world: World, settlements: Array, day: int) -> void:
	if world == null:
		return
	if _last_day < 0:
		_last_day = day
	if day != _last_day:
		_last_day = day
		_fade(world)
	_timer += delta
	if _timer < SAMPLE_SECONDS:
		return
	_timer = fmod(_timer, SAMPLE_SECONDS)
	var hearths: Array = []
	for s in settlements:
		hearths.append(s.centre)
	var seen: Dictionary = {}
	for entry in agents:
		var a := entry as Agent
		if a == null or a.is_dead or a.health <= 0.0:
			continue
		seen[a.agent_id] = true
		var last: Vector2 = _last_pos.get(a.agent_id, a.pos)
		_last_pos[a.agent_id] = a.pos
		if a.state == Agent.State.SLEEPING or a.pos.distance_to(last) < MOVED_MIN:
			continue
		var by_hearth := false
		for h in hearths:
			if a.pos.distance_squared_to(h) < HOME_CLEAR * HOME_CLEAR:
				by_hearth = true
				break
		if by_hearth:
			continue
		var w := TRADER_WEIGHT if not a.trader_state.is_empty() else 1.0
		# A step can cross a tile boundary between samples: wear the tile we
		# passed through too, so a line is continuous rather than dotted.
		var mid := (a.pos + last) * 0.5
		step_on(world, a.pos, w)
		if Vector2i(mid.floor()) != Vector2i(a.pos.floor()):
			step_on(world, mid, w * 0.5)
	for id in _last_pos.keys():
		if not seen.has(id):
			_last_pos.erase(id)

## One footfall (weight w) on the tile under tile-space point p.
func step_on(world: World, p: Vector2, w: float = 1.0) -> void:
	var x := int(floor(p.x))
	var z := int(floor(p.y))
	if x < 0 or z < 0 or x >= world.width or z >= world.height:
		return
	var key := Vector2i(x, z)
	var before := float(world.trade_traffic.get(key, 0.0))
	world.trade_traffic[key] = minf(MAX_WEAR, before + w)
	_fresh += w
	if _fresh >= 40.0:
		_fresh = 0.0
		revision += 1

func _fade(world: World) -> void:
	var gone: Array = []
	for key in world.trade_traffic:
		var v := float(world.trade_traffic[key]) * DAILY_KEEP
		if v < 0.5:
			gone.append(key)
		else:
			world.trade_traffic[key] = v
	for key in gone:
		world.trade_traffic.erase(key)
	revision += 1

## How worn a tile is, 0 (untouched) .. 1 (a beaten path).
static func wear_of(world: World, x: int, z: int) -> float:
	return clampf((float(world.trade_traffic.get(Vector2i(x, z), 0.0)) - PathRenderer.WEAR_START) / (PathRenderer.WEAR_FULL - PathRenderer.WEAR_START), 0.0, 1.0)
