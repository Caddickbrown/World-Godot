class_name ForestSystem
extends RefCounted
## The woods are alive. Trees on FOREST and WOODLAND tiles have a size
## (tile.growth, 0 seedling .. 1 grown) that rises with the seasons. People
## who know woodcutting fell grown trees near their camp for timber, leaving
## stumps that sprout again; timber is what turns a camp of tents into a
## hamlet of huts (SettlementSystem). People who know forestry replant what
## they fell and plant groves on bare ground near home. Burnt woods stand as
## snags for a day before they fall; EcologySystem lets the woods around seed
## the ground again.
##
## Everything visible goes through world.mark_flora_dirty, so the flora only
## redraws the tiles that changed.

const GROW_DAYS := 3.0            # seedling to grown, in a growing season
const SEASON_GROWTH := {"spring": 1.8, "summer": 1.2, "autumn": 0.6, "winter": 0.1}
const VISUAL_STEPS := 8           # growth is drawn in this many sizes
const STRIPE_COUNT := 8

const FELL_RADIUS := 9.0          # tiles from the hearth woodcutters will go
const FELL_GROWTH := 0.8          # only grown trees are worth felling
const TIMBER_PER_TREE := 4.0
const WANT_TIMBER := 14.0         # a camp stops felling once it holds this...
const WANT_TIMBER_PER_MEMBER := 0.5
const FIREWOOD_PER_MEMBER := 0.1  # ...and burns this much a night (deadwood alone barely keeps up)
const REACH := 0.9
const RETHINK := 1.0
const REST_AFTER_FELLING := 60.0  # half a day before the same person fells again

const PLANT_REST := 120.0         # a day between plantings, per person
const GROVE_WANT := 14            # planters keep this many wooded tiles round home
const GROVE_MIN := 3.0            # ...planted between these distances of the hearth
const GROVE_MAX := 7.0

var _rest: Dictionary = {}        # agent_id -> seconds before they take on a job
var _job: Dictionary = {}         # agent_id -> {kind, tile: Vector2i}
var _claimed: Dictionary = {}     # Vector2i -> agent_id
var _last_day := -1
var felled := 0
var planted := 0

## Returns this tick's events: [{kind: "felled"|"replanted"|"planted", who: Agent, tile: Vector2i}].
func tick(delta: float, world: World, agents: Array, settlement_system, season: String, day: int) -> Array:
	_grow(delta, world, season)
	var events: Array = []
	if settlement_system == null:
		return events
	if day != _last_day:
		if _last_day >= 0:
			_burn_firewood(settlement_system)
		_last_day = day
	for a in agents:
		if a.is_dead or a.health <= 0.0 or not a.is_adult:
			_drop_job(a.agent_id)
			continue
		var r: float = float(_rest.get(a.agent_id, 0.0)) - delta
		_rest[a.agent_id] = r
		if a.state == Agent.State.SLEEPING or a.at_fire or a.needs["hunger"] < 0.45:
			continue
		var st = settlement_system.get_settlement_for_agent(a.agent_id)
		if st == null:
			_drop_job(a.agent_id)
			continue
		if not _job.has(a.agent_id):
			if r > 0.0:
				continue
			_rest[a.agent_id] = RETHINK
			_find_job(a, st, world)
			if not _job.has(a.agent_id):
				continue
		var evt := _work(a, st, world)
		if not evt.is_empty():
			events.append(evt)
	return events

static func timber_wanted(st) -> float:
	return WANT_TIMBER + WANT_TIMBER_PER_MEMBER * float(st.member_ids.size())

# ── Growth ───────────────────────────────────────────────────────────────────

## Seedlings grow and snags fall: only on the tiles World.growing names.
func _grow(delta: float, world: World, season: String) -> void:
	var rate: float = float(SEASON_GROWTH.get(season, 1.0)) / (GROW_DAYS * TimeSystem.DAY_LENGTH)
	for key: Vector2i in world.growing.keys():
		var tile := world.get_tile(key.x, key.y)
		if tile.is_empty():
			world.growing.erase(key)
			continue
		var burnt: float = float(tile.get("burnt", 0.0))
		if burnt > 0.0:
			burnt -= delta
			tile["burnt"] = maxf(0.0, burnt)
			if burnt <= 0.0:   # the snags fall
				world.mark_tile_dirty(key.x, key.y)
				world.mark_flora_dirty(key.x, key.y)
			else:
				continue
		var g: float = float(tile.get("growth", -1.0))
		if g < 0.0 or g >= 1.0 or bool(tile.get("tree_cut", false)) or not World.has_woods(tile):
			world.growing.erase(key)   # grown, felled (its stump re-marks it) or gone
			continue
		var ng := minf(1.0, g + rate * delta)
		tile["growth"] = ng
		if int(ng * VISUAL_STEPS) != int(g * VISUAL_STEPS):
			world.mark_flora_dirty(key.x, key.y)

func _burn_firewood(settlement_system) -> void:
	for st in settlement_system.settlements:
		st.wood_store = maxf(0.0, st.wood_store - FIREWOOD_PER_MEMBER * float(st.member_ids.size()))

# ── Jobs ─────────────────────────────────────────────────────────────────────

func _find_job(a: Agent, st, world: World) -> void:
	if a.fxb("wood_gathering") and st.wood_store < timber_wanted(st):
		var t := _nearest_tile(a, st, world, FELL_RADIUS, 0.0, func(tile: Dictionary) -> bool:
			return World.has_woods(tile) and not bool(tile["tree_cut"]) and float(tile.get("growth", 0.0)) >= FELL_GROWTH)
		if t.x >= 0:
			_take(a, "fell", t)
			return
	if a.fxb("replants") and _woods_round(st, world) < GROVE_WANT:
		var t := _nearest_tile(a, st, world, GROVE_MAX, GROVE_MIN, func(tile: Dictionary) -> bool:
			return int(tile["type"]) == World.TileType.GRASS and float(tile.get("burnt", 0.0)) <= 0.0 \
				and not bool(tile.get("river", false)) and not bool(tile.get("is_shelter", false)))
		if t.x >= 0:
			_take(a, "plant", t)

func _take(a: Agent, kind: String, t: Vector2i) -> void:
	_job[a.agent_id] = {"kind": kind, "tile": t}
	_claimed[t] = a.agent_id

func _drop_job(id: int) -> void:
	if _job.has(id):
		_claimed.erase(_job[id]["tile"])
		_job.erase(id)

func _work(a: Agent, st, world: World) -> Dictionary:
	var job: Dictionary = _job[a.agent_id]
	var t: Vector2i = job["tile"]
	var spot := Vector2(t.x + 0.5, t.y + 0.5)
	if a.pos.distance_to(spot) > REACH:
		a.state = Agent.State.GATHERING
		a.target = spot
		a.chore = "felling a tree" if job["kind"] == "fell" else "planting a tree"
		a.needs_check_timer = maxf(a.needs_check_timer, RETHINK + 0.5)
		return {}
	_drop_job(a.agent_id)
	a.chore = ""
	var tile := world.get_tile(t.x, t.y)
	if job["kind"] == "fell":
		_rest[a.agent_id] = REST_AFTER_FELLING
		if tile.is_empty() or not world.cut_tree(t.x, t.y):
			return {}
		st.wood_store += TIMBER_PER_TREE
		felled += 1
		if a.fxb("replants"):
			world.replant(t.x, t.y)
			return {"kind": "replanted", "who": a, "tile": t}
		return {"kind": "felled", "who": a, "tile": t}
	_rest[a.agent_id] = PLANT_REST
	if tile.is_empty() or int(tile["type"]) != World.TileType.GRASS:
		return {}
	world.set_type(tile, World.TileType.WOODLAND)
	tile["growth"] = World.SAPLING_GROWTH
	world.mark_growing(t.x, t.y)
	tile["planted"] = true
	tile["tree_cut"] = false
	if world.depletion_of(tile) < 0.0:
		world.set_depletion(tile, 0.0)
	world.mark_tile_dirty(t.x, t.y)
	world.mark_flora_dirty(t.x, t.y)
	planted += 1
	return {"kind": "planted", "who": a, "tile": t}

## Nearest tile to the agent, within [min_r, max_r] of the hearth, that passes
## ok and nobody else is already working.
func _nearest_tile(a: Agent, st, world: World, max_r: float, min_r: float, ok: Callable) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var cx := int(st.centre.x)
	var cz := int(st.centre.y)
	var r := int(ceil(max_r))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var hd := Vector2(dx, dz).length()
			if hd > max_r or hd < min_r:
				continue
			var tile := world.get_tile(cx + dx, cz + dz)
			if tile.is_empty():
				continue
			var cell := Vector2i(cx + dx, cz + dz)
			if _claimed.has(cell) or not ok.call(tile):
				continue
			var d := a.pos.distance_squared_to(Vector2(cell.x + 0.5, cell.y + 0.5))
			if d < best_d:
				best_d = d
				best = cell
	return best

func _woods_round(st, world: World) -> int:
	var n := 0
	var cx := int(st.centre.x)
	var cz := int(st.centre.y)
	var r := int(GROVE_MAX)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dz).length() > GROVE_MAX:
				continue
			var tile := world.get_tile(cx + dx, cz + dz)
			if not tile.is_empty() and World.has_woods(tile):
				n += 1
	return n
