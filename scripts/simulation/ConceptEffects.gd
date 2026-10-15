class_name ConceptEffects
## The one place an idea's `effects` (data/concepts.json) turn into numbers.
##
## Every effect key is declared in RULES with how several ideas that share it
## combine. Agent.fx() caches the aggregate per person and recomputes it when
## they learn something (knowledge only grows, so its size is the cache key);
## code asks agent.fxf("gather_efficiency") / agent.fxb("unlocks_wading")
## instead of checking for idea ids. tests/suites/40_ideas.gd fails if the data
## names a key that isn't declared here, or a declared key that no script reads.
##
## Kinds:
##   mult  product of the ideas' factors, clamped to [lo, hi] (so twenty
##         "x1.1 gathering" ideas can't add up to a tenfold harvest)
##   sum   sum of the ideas' values, clamped to [lo, hi]
##   flag  true if any known idea sets it
##   list  union of the names the ideas give (settlement buildings)

const RULES := {
	# Body and home
	"max_age_bonus":              ["sum", 0.0, 1.2],    # Agent.life_expectancy
	"warmth_satisfied":           ["flag"],             # Agent: lights fires, no cold-seeking
	"weather_protection":         ["sum", 0.0, 1.2],    # Agent: weather energy drain
	"rest_efficiency":            ["mult", 1.0, 2.4],   # Agent: sleep recovery
	"sleeps_in_trees":            ["flag"],             # Agent: better sleep under a canopy
	"vitality_regen":             ["sum", 0.0, 0.003],  # Agent: health per second
	"herb_healing":               ["flag"],             # Agent: heals on herbs, tends the sick; DiseaseSystem
	"herb_healing_mult":          ["mult", 1.0, 3.0],   # Agent: how much herbs heal
	"reproduction_cooldown_mult": ["mult", 0.6, 1.0],   # Agent._try_reproduce
	# Food
	"gather_efficiency":          ["mult", 1.0, 2.2],   # Agent: food per gather, less wear on the land
	"forest_bonus":               ["flag"],             # Agent: x1.25 in the deep woods
	"grass_bonus":                ["flag"],             # Agent: x1.3 on meadows (fields)
	"field_near_water":           ["flag"],             # Agent: x1.3 on meadows by water (irrigation)
	"hunger_efficiency":          ["mult", 1.0, 2.4],   # Agent: how far food goes
	"carrying_capacity_bonus":    ["mult", 1.0, 2.5],   # Agent: food carried home, pack weight
	"honey_food":                 ["flag"],             # Agent: honey from the woods
	"cooks_food":                 ["flag"],             # Agent: cooks raw food at the hearth
	"safe_foraging":              ["flag"],             # Agent: never eats the wrong mushroom
	"preserves_food":             ["flag"],             # Agent/Inventory and SettlementSystem: slower spoiling
	"store_bonus":                ["mult", 1.0, 2.0],   # SettlementSystem: larder size
	"times_seasons":              ["flag"],             # Agent: puts food by before winter
	"spares_depleted_land":       ["flag"],             # Agent: lets stripped land recover
	"tithe":                      ["sum", 0.0, 0.3],    # Agent: share of each gather carried home
	"can_fish":                   ["flag"],             # Agent: fishing
	# Ideas
	"spread_rate_multiplier":     ["mult", 1.0, 3.2],   # ConceptGraph: as a teacher
	"concept_spread_rate_mult":   ["mult", 1.0, 1.6],   # ConceptGraph: as a listener
	"discovery_bonus":            ["mult", 1.0, 2.2],   # ConceptGraph.check_discovery
	"curiosity_bonus":            ["sum", 0.0, 0.3],    # Agent.curiosity
	"fire_story_bonus":           ["sum", 0.0, 1.0],    # Agent: stories at the hearth carry further
	"cultural_identity":          ["flag"],             # Agent: the camp's own story at the fire
	"map_memory":                 ["flag"],             # Agent: remembers twice the places, roams further
	# Travel (an island: water and mountains are the walls)
	"unlocks_wading":             ["flag"],             # Agent: shallow water, slowly
	"unlocks_water_travel":       ["flag"],             # Agent: boats along the coast
	"unlocks_deep_water_travel":  ["flag"],             # Agent: boats out of sight of land
	"unlocks_ocean_crossing":     ["flag"],             # Agent: anywhere at sea, voyages
	"unlocks_mountain_travel":    ["flag"],             # Agent: climbing
	"unlocks_bridge_building":    ["flag"],             # Agent: rivers don't slow them
	"can_ride_horses":            ["flag"],             # Agent.rides_horses (riding: Animal minds)
	# Society
	"unlocks_tasks":              ["flag"],             # Agent vocations; Main
	"unlocks_burial_ritual":      ["flag"],             # Agent.grieve
	"holds_rituals":              ["flag"],             # Agent: gatherings
	"unlocks_temple_use":         ["flag"],             # Agent: rituals at the temple
	"settlement_morale_bonus":    ["sum", 0.0, 0.6],    # Agent: morale lasts longer
	"plays_music":                ["flag"],             # Agent: plays at the fire
	"fire_morale":                ["flag"],             # Agent: art round the fire lifts spirits
	"trades":                     ["flag"],             # Agent journeys; TradingSystem
	"trade_reach":                ["flag"],             # Agent: trades with far settlements
	"keeps_peace":                ["sum", 0.0, 0.85],   # ConflictSystem: fewer clashes
	"wins_clashes":               ["flag"],             # ConflictSystem: holds ground
	"wood_gathering":             ["flag"],             # ForestSystem: fells trees
	"replants":                   ["flag"],             # ForestSystem: replants
	"enables_reintroduction":     ["flag"],             # IdeaSystem: brings lost animals back
	"unlocks_stone_buildings":    ["flag"],             # IdeaSystem settlement flag
	"builds":                     ["list"],             # IdeaSystem: settlement has_<name> flags
	"reads_tracks":               ["flag"],             # Agent: steers wider round danger
}

## Effect keys that are in the data but deliberately not their own mechanic.
## (Empty: every key the data uses is consumed. Kept so a future drop is explicit.)
const DROPPED := {}

static var _defs: Dictionary = {}   # concept id -> effects dict

static func defs() -> Dictionary:
	if _defs.is_empty():
		var f := FileAccess.open("res://data/concepts.json", FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if data is Array:
				for c in data:
					_defs[str(c["id"])] = c.get("effects", {})
	return _defs

## The neutral aggregate (no ideas known).
static func neutral() -> Dictionary:
	var out := {}
	for k in RULES:
		match str(RULES[k][0]):
			"mult": out[k] = 1.0
			"sum": out[k] = 0.0
			"flag": out[k] = false
			"list": out[k] = {}
	return out

## Aggregate effects of every idea in `knowledge` (id -> true).
static func aggregate(knowledge: Dictionary) -> Dictionary:
	var d := defs()
	var out := neutral()
	for id in knowledge:
		var eff: Dictionary = d.get(str(id), {})
		for k in eff:
			if not RULES.has(k):
				continue
			var v = eff[k]
			match str(RULES[k][0]):
				"mult": out[k] = float(out[k]) * float(v)
				"sum": out[k] = float(out[k]) + float(v)
				"flag": out[k] = bool(out[k]) or bool(v)
				"list":
					for name in (v if v is Array else [v]):
						out[k][str(name)] = true
	for k in RULES:
		var r: Array = RULES[k]
		if str(r[0]) == "mult" or str(r[0]) == "sum":
			out[k] = clampf(float(out[k]), float(r[1]), float(r[2]))
	return out

## The aggregate of a settlement's knowledge pool, cached on the settlement
## (the pool only grows, so its size is the cache key).
static func settlement_fx(st) -> Dictionary:
	if st == null:
		return neutral()
	var pool: Dictionary = st.knowledge_pool
	if int(st.get_meta("fx_n", -1)) != pool.size():
		st.set_meta("fx_n", pool.size())
		st.set_meta("fx", aggregate(pool))
	return st.get_meta("fx")

# ── Settlement flags (for the buildings) ─────────────────────────────────────

## What a settlement has, from what its living members know, as
## {"has_temple": true, "has_barn": true, ...}. IdeaSystem refreshes it every
## couple of seconds; without one (tests) it is worked out from the camp's
## knowledge pool. Names come from the "builds" effect in concepts.json, plus
## has_boats / has_bridge / has_stone_buildings from the travel and building
## unlocks. A flag goes away when the last member who knew the idea dies.
static func settlement_flags(st) -> Dictionary:
	if st == null:
		return {}
	if st.has_meta("idea_flags"):
		return st.get_meta("idea_flags")
	return flags_from(settlement_fx(st))

static func flags_from(fx: Dictionary) -> Dictionary:
	var out := {}
	for name in (fx.get("builds", {}) as Dictionary):
		out["has_" + str(name)] = true
	if bool(fx.get("unlocks_water_travel", false)): out["has_boats"] = true
	if bool(fx.get("unlocks_bridge_building", false)): out["has_bridge"] = true
	if bool(fx.get("unlocks_stone_buildings", false)): out["has_stone_buildings"] = true
	return out

# ── The sea ──────────────────────────────────────────────────────────────────

## Tiles from the nearest land (0 on land), capped at 255; cached on the world.
## Boats hug the coast (COAST_REACH) until navigation takes them further.
const COAST_REACH := 3
const OPEN_SEA_REACH := 10

static func land_distance(world: World, x: int, z: int) -> int:
	if world == null:
		return 0
	if not world.has_meta("land_dist"):
		world.set_meta("land_dist", _build_land_distance(world))
	if x < 0 or z < 0 or x >= world.width or z >= world.height:
		return 255
	var arr: PackedByteArray = world.get_meta("land_dist")
	return arr[z * world.width + x]

static func _build_land_distance(world: World) -> PackedByteArray:
	var w := world.width
	var h := world.height
	var arr := PackedByteArray()
	arr.resize(w * h)
	arr.fill(255)
	var queue: Array = []
	for z in h:
		for x in w:
			var t := int(world.tiles[z][x]["type"])
			if t != World.TileType.WATER and t != World.TileType.DEEP_WATER:
				arr[z * w + x] = 0
				queue.append(Vector2i(x, z))
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = arr[c.y * w + c.x]
		if d >= 254:
			continue
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if arr[n.y * w + n.x] > d + 1:
				arr[n.y * w + n.x] = d + 1
				queue.append(n)
	return arr
