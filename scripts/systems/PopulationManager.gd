class_name PopulationManager
extends RefCounted

## Reproduction, culling and Lotka-Volterra predator/prey dynamics for wild
## animal populations.
##
## This operates purely on an abstract population model — per-species live
## counts fed in each tick, and per-species target deltas computed from them.
## It never reaches into a renderer or animal-simulation instance directly;
## callers read `get_spawn_requests()` / `get_cull_requests()` after tick()
## and apply them to whatever owns the actual animal instances (e.g.
## AnimalSim.animals).
##
## Species are identified by String id: "sheep", "horse" (density-controlled
## against a capacity), and "deer", "rabbit" (prey) / "fox", "wolf"
## (predators) for the Lotka-Volterra pair.
##
## Carrying capacity for sheep is derived from the number of GRASS tiles in
## the world. Horses use a separate fixed capacity. Populations above 2x
## capacity are culled one at a time; below capacity, each evaluation has a
## small chance to spawn one animal.

const SHEEP_PER_GRASS_TILE := 0.05
const HORSE_CAPACITY := 8
const REPRODUCTION_CHANCE := 0.15  # per day, per capacity-controlled species, when below capacity

# The cap below was authored against the JS prototype's 32×32 world; keep
# that as the fixed reference point and scale it by the actual world size
# rather than hardcoding a bigger number for the current 128×128 map.
const REFERENCE_WORLD_SIZE := 32.0
const MAX_SHEEP_CAPACITY := 200

# Lotka-Volterra parameters:
#   dPrey/dt = alpha*prey - beta*prey*predator
#   dPred/dt = delta*prey*predator - gamma*predator
const LV_ALPHA := 0.1   # prey birth rate
const LV_BETA := 0.02   # predation rate
const LV_DELTA := 0.01  # predator birth rate from prey
const LV_GAMMA := 0.05  # predator death rate

const SPECIES_LABELS: Dictionary = {
	"sheep": "Sheep", "horse": "Horses", "deer": "Deer",
	"rabbit": "Rabbits", "fox": "Foxes", "wolf": "Wolves",
}

# ── State ─────────────────────────────────────────────────────────────────────

var _populations: Dictionary = {}     # species (String) → last-known live count (int)
var _ever_positive: Dictionary = {}   # species (String) → true once count > 0 was observed
var extinct: Dictionary = {}          # species (String) → true

var _spawn_requests: Array = []       # queued until get_spawn_requests() drains it
var _cull_requests: Array = []        # queued until get_cull_requests() drains it

var _last_tick_day: int = -1

# Grass-tile positions are a full-world scan; cache them and rebuild at most
# once per in-game day (the world is 128x128 = 16384 tiles, far too much to
# rescan every frame).
var _grass_tiles_cache: Array = []    # Array[Vector2i]
var _grass_cache_day: int = -1

# ── Public API ────────────────────────────────────────────────────────────────

## CAD-213-equivalent: carrying capacity scaled to world size, single place
## to tune the sheep density/cap logic.
## @param grass_tiles - count of GRASS tiles in the world
## @param world_size - current map side length
func get_carrying_capacity(grass_tiles: int, world_size: int = World.WORLD_WIDTH) -> int:
	var base: int = int(float(grass_tiles) * SHEEP_PER_GRASS_TILE)
	var size_scaled_cap: int = int(float(MAX_SHEEP_CAPACITY) * (float(world_size) / REFERENCE_WORLD_SIZE))
	return maxi(4, mini(base, size_scaled_cap))


## Cheap to call every frame — the actual evaluation (grass count refresh,
## capacity control, Lotka-Volterra step) runs at most once per in-game day.
## @param delta - game-seconds elapsed this frame (unused for gating; the
##                day-based cadence below is what keeps this cheap)
## @param world - for grass-tile counting
## @param day - current game day
## @param live_counts - species (String) → current live count (int), as
##                       counted by the caller from its own animal store
## @param history_log - narrative log for extinction/reintroduction events
func tick(_delta: float, world: World, day: int, live_counts: Dictionary, history_log: HistoryLog) -> void:
	if day == _last_tick_day:
		return
	var elapsed_days: float = float(day - _last_tick_day) if _last_tick_day >= 0 else 1.0
	_last_tick_day = day

	_refresh_grass_cache(world, day)
	_sync_populations(live_counts, day, history_log)

	var sheep_capacity: int = get_carrying_capacity(_grass_tiles_cache.size(), world.width)
	_tick_capacity_species("sheep", sheep_capacity)
	_tick_capacity_species("horse", HORSE_CAPACITY)

	_tick_lotka_volterra(elapsed_days)


## Reintroduce two animals of an extinct species at random grass tiles.
## Callers should gate this on the reintroducing agent knowing 'conservation'.
func reintroduce(species: String, day: int = -1, history_log: HistoryLog = null) -> bool:
	if not extinct.has(species):
		return false
	_enqueue_spawn(species, 2)
	extinct.erase(species)
	if history_log != null and day >= 0:
		history_log.add("ecology", "%s have been reintroduced to the wild" % _species_label(species), day)
	return true


## Drains and returns queued spawn requests:
## [{ "species": String, "count": int, "positions": Array[Vector2] }, ...]
## `positions` are tile-space centres (e.g. 4.5, 9.5) on GRASS tiles, one per
## animal to spawn; a position of (-1, -1) means no grass tile was available.
func get_spawn_requests() -> Array:
	var result := _spawn_requests
	_spawn_requests = []
	return result


## Drains and returns queued cull requests: [{ "species": String, "count": int }, ...]
## The caller picks which live instances of that species to remove.
func get_cull_requests() -> Array:
	var result := _cull_requests
	_cull_requests = []
	return result


func get_population(species: String) -> int:
	return int(_populations.get(species, 0))


func is_extinct(species: String) -> bool:
	return extinct.has(species)


func get_extinct_species() -> Array:
	return extinct.keys()

# ── Lotka-Volterra ────────────────────────────────────────────────────────────

func _tick_lotka_volterra(dt: float) -> void:
	var prey_count: int = int(_populations.get("deer", 0)) + int(_populations.get("rabbit", 0))
	var pred_count: int = int(_populations.get("fox", 0)) + int(_populations.get("wolf", 0))
	if prey_count == 0 and pred_count == 0:
		return

	var d_prey: float = (LV_ALPHA * float(prey_count) - LV_BETA * float(prey_count) * float(pred_count)) * dt
	var d_pred: float = (LV_DELTA * float(prey_count) * float(pred_count) - LV_GAMMA * float(pred_count)) * dt

	# Soft caps that track the current populations rather than a fixed
	# ecological carrying capacity — ported as-is from the JS prototype.
	var prey_capacity: int = maxi(2, prey_count + 20)
	var pred_capacity: int = maxi(1, pred_count + 10)

	var new_prey: int = maxi(1, mini(prey_capacity, int(roundf(float(prey_count) + d_prey))))
	var new_pred: int = maxi(1, mini(pred_capacity, int(roundf(float(pred_count) + d_pred))))

	var prey_delta: int = new_prey - prey_count
	var pred_delta: int = new_pred - pred_count

	# Split the prey/predator delta evenly across their two member species.
	var deer_delta: int = int(ceil(float(prey_delta) / 2.0)) if prey_delta > 0 else int(floor(float(prey_delta) / 2.0))
	var rabbit_delta: int = prey_delta - deer_delta
	_apply_pop_delta("deer", deer_delta)
	_apply_pop_delta("rabbit", rabbit_delta)

	var fox_delta: int = int(ceil(float(pred_delta) / 2.0)) if pred_delta > 0 else int(floor(float(pred_delta) / 2.0))
	var wolf_delta: int = pred_delta - fox_delta
	_apply_pop_delta("fox", fox_delta)
	_apply_pop_delta("wolf", wolf_delta)


## Positive delta enqueues spawns; negative delta enqueues a cull, keeping at
## least one animal of the species alive.
func _apply_pop_delta(species: String, delta: int) -> void:
	if delta > 0:
		_enqueue_spawn(species, delta)
	elif delta < 0:
		var live: int = int(_populations.get(species, 0))
		var to_kill: int = mini(-delta, maxi(0, live - 1))
		_enqueue_cull(species, to_kill)

# ── Capacity-controlled species (sheep, horse) ─────────────────────────────────

func _tick_capacity_species(species: String, capacity: int) -> void:
	var count: int = int(_populations.get(species, 0))
	if count < capacity and randf() < REPRODUCTION_CHANCE:
		_enqueue_spawn(species, 1)
	elif count > capacity * 2:
		_enqueue_cull(species, 1)

# ── Population bookkeeping ──────────────────────────────────────────────────────

func _sync_populations(live_counts: Dictionary, day: int, history_log: HistoryLog) -> void:
	for key in live_counts.keys():
		var species: String = String(key)
		var count: int = int(live_counts[key])
		_populations[species] = count
		if count > 0:
			_ever_positive[species] = true
		elif bool(_ever_positive.get(species, false)) and not extinct.has(species):
			extinct[species] = true
			if history_log != null:
				history_log.add("ecology", "%s have died out" % _species_label(species), day)


func _species_label(species: String) -> String:
	return String(SPECIES_LABELS.get(species, species.capitalize()))

# ── Grass-tile helpers ───────────────────────────────────────────────────────────

func _refresh_grass_cache(world: World, day: int) -> void:
	if _grass_cache_day == day:
		return
	_grass_tiles_cache.clear()
	for z in range(world.height):
		for x in range(world.width):
			if int(world.tiles[z][x].get("type", -1)) == World.TileType.GRASS:
				_grass_tiles_cache.append(Vector2i(x, z))
	_grass_cache_day = day


func _random_grass_position() -> Vector2:
	if _grass_tiles_cache.is_empty():
		return Vector2(-1.0, -1.0)
	var t: Vector2i = _grass_tiles_cache[randi() % _grass_tiles_cache.size()]
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)


func _enqueue_spawn(species: String, count: int) -> void:
	if count <= 0:
		return
	var positions: Array = []
	for _i in range(count):
		positions.append(_random_grass_position())
	_spawn_requests.append({"species": species, "count": count, "positions": positions})


func _enqueue_cull(species: String, count: int) -> void:
	if count <= 0:
		return
	_cull_requests.append({"species": species, "count": count})
