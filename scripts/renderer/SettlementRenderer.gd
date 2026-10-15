class_name SettlementRenderer
extends Node3D
## Where people live, drawn from SettlementSystem: a ring of dwellings round a
## hearth, one more for every few members. Camps are hide tents, hamlets round
## huts with thatch, towns timber houses. Every live fire in the world
## (World.natural_fires) gets a flame and, after dusk, real firelight.
##
## What a settlement's people know shows in what stands there (BUILDINGS):
## each building appears once any idea in its list is in the settlement's
## Settlement.knowledge_pool (and, for some, the place is big enough). Keyed on
## idea ids only, so it holds whatever those ideas come to do in the sim.
## docs/features/places.md has the table. Buildings are drawn, never built:
## the simulation does not know they are there.

const TILE_SIZE := World.TILE_SIZE
const PEOPLE_PER_DWELLING := 3
const MAX_DWELLINGS := 12
const MAX_FIRE_LIGHTS := 16

## kind -> ideas (any one), minimum tier, what it's called.
const BUILDINGS := {
	"shrine":     {"ideas": ["animism", "ritual"], "tier": 0, "name": "Shrine"},
	"temple":     {"ideas": ["temple"], "tier": 0, "name": "Temple"},
	"church":     {"ideas": ["church"], "tier": 1, "name": "Church"},
	"granary":    {"ideas": ["agriculture", "barn"], "tier": 0, "name": "Barn"},
	"fields":     {"ideas": ["agriculture"], "tier": 0, "name": "Field"},
	"workshop":   {"ideas": ["woodworking", "pottery", "metal_tools", "metallurgy"], "tier": 0, "name": "Workshop"},
	"well":       {"ideas": ["irrigation"], "tier": 0, "name": "Well"},
	"coop":       {"ideas": ["coop", "animal_domestication", "domestication"], "tier": 0, "name": "Hen coop"},
	"pen":        {"ideas": ["herding", "animal_breeding"], "tier": 0, "name": "Sheep pen"},
	"tree_house": {"ideas": ["tree_house"], "tier": 0, "name": "Tree house"},
	"walls":      {"ideas": ["masonry", "architecture"], "tier": 2, "name": "Walls"},   # towns only
	"docks":      {"ideas": ["boat_building", "sailing", "seafaring"], "tier": 0, "name": "Jetty"},
}
## Order the civic ring is filled in (the rest have places of their own).
const CIVIC := ["temple", "church", "granary", "workshop", "well", "coop", "pen"]
const CIVIC_RING := 14.0      # metres from the hearth
const CIVIC_SLOTS := 12
const WALL_RING := 18.5
const FIELD_RING := 25.0
const SHRINE_AT := Vector2(1.5, 1.5)   # tiles from the hearth: SettlementSystem's temple_pos, where rituals gather
const TIER_WORDS := ["camp", "hamlet", "town"]

var world: World
var darkness := 0.0               # 0 day .. 1 night, set by Main
var _built: Dictionary = {}       # settlement id -> {node, sig}
var _fires: Dictionary = {}       # "x,z" -> {node, light}
var _mats: Dictionary = {}
var _kit_mat: StandardMaterial3D
## settlement id -> Array of sites {kind, name, pos: Vector2 (world metres), radius, day, settlement}
var sites: Dictionary = {}
var _raised: Dictionary = {}      # "id:kind" -> day it first stood

func clear() -> void:
	for ch in get_children():
		ch.queue_free()
	_built.clear()
	_fires.clear()
	sites.clear()

func restyle() -> void:
	clear()
	_mats.clear()
	_kit_mat = null

## Which buildings a settlement's knowledge (and size) puts up, in a fixed order.
static func buildings_for(s) -> Array:
	var out: Array = []
	for kind in BUILDINGS:
		var b: Dictionary = BUILDINGS[kind]
		if int(s.tier) < int(b["tier"]):
			continue
		var ok := false
		for id in b["ideas"]:
			if s.knowledge_pool.has(id):
				ok = true
				break
		if kind == "shrine" and s.has_temple:
			ok = true
		if ok:
			out.append(kind)
	return out

## How full the larder is, 0..1 (SettlementSystem caps it per member).
static func larder_fill(s) -> float:
	var cap := float(s.member_ids.size()) * SettlementSystem.STORE_PER_MEMBER
	return clampf(float(s.food_store) / cap, 0.0, 1.0) if cap > 0.0 else 0.0

## settlements: SettlementSystem.get_settlements(); fires: World.natural_fires keys.
func sync(settlements: Array, fires: Dictionary) -> void:
	var live: Dictionary = {}
	var season := world.get_season() if world else "summer"
	for s in settlements:
		live[s.id] = true
		var count := clampi(int(ceil(float(s.member_ids.size()) / PEOPLE_PER_DWELLING)), 2, MAX_DWELLINGS)
		var kinds := buildings_for(s)
		var sig := "%d|%d|%.1f,%.1f|%s|%d|%s" % [int(s.tier), count, s.centre.x, s.centre.y, ",".join(kinds),
			int(larder_fill(s) * 4.99), season]
		var e: Dictionary = _built.get(s.id, {})
		if e.is_empty() or str(e["sig"]) != sig:
			if not e.is_empty():
				(e["node"] as Node).queue_free()
			for k in kinds:
				var key := "%d:%s" % [s.id, k]
				if not _raised.has(key):
					_raised[key] = world.day if world else 1
			_built[s.id] = {"node": _build_settlement(s, count, kinds, season), "sig": sig}
	for id in _built.keys():
		if not live.has(id):
			(_built[id]["node"] as Node).queue_free()
			_built.erase(id)
			sites.erase(id)
	_sync_fires(fires)

func _build_settlement(s, count: int, kinds: Array, season: String) -> Node3D:
	var root := Node3D.new()
	var c := Vector3(s.centre.x * TILE_SIZE, 0, s.centre.y * TILE_SIZE)
	root.position = c
	add_child(root)
	var list: Array = []
	sites[s.id] = list
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.id) * 7919 + 13
	var shrine_local := Vector3(SHRINE_AT.x * TILE_SIZE, 0, SHRINE_AT.y * TILE_SIZE)
	if s.has_temple:
		shrine_local = Vector3((s.temple_pos.x - s.centre.x) * TILE_SIZE, 0, (s.temple_pos.y - s.centre.y) * TILE_SIZE)
	var has_shrine := kinds.has("shrine")
	var dwell_name: String = ["Hide tent", "Round hut", "Timber house"][clampi(int(s.tier), 0, 2)]
	for i in count:
		# Rings: six round the hearth, then a wider ring.
		var ring := 0 if i < 6 else 1
		var in_ring := 6 if ring == 0 else 10
		var a := TAU * float(i % in_ring) / float(in_ring) + rng.randf_range(-0.2, 0.2) + ring * 0.3
		var r := (5.0 if ring == 0 else 9.5) + rng.randf_range(-0.6, 0.6)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if has_shrine and Vector2(p.x - shrine_local.x, p.z - shrine_local.z).length() < 2.8:
			continue   # the shrine stands here
		var wp := c + p
		var tx := wp.x / TILE_SIZE
		var tz := wp.z / TILE_SIZE
		if world and not world.is_walkable(tx, tz):
			continue
		p.y = (world.surface_y(tx, tz) if world else 0.0)
		var d := _dwelling(int(s.tier), rng)
		d.position = p
		d.rotation.y = atan2(-p.x, -p.z)  # doors face the hearth
		root.add_child(d)
		list.append(_site("dwelling", "%s · %s" % [dwell_name, s.name], c + p, 1.8, s))
	# The hearth ring of stones
	var hy := world.surface_y(s.centre.x, s.centre.y) if world else 0.0
	for i in 8:
		var a := TAU * i / 8.0
		var st := MeshInstance3D.new()
		st.mesh = _ball(0.22)
		st.position = Vector3(cos(a) * 0.8, hy + 0.1, sin(a) * 0.8)
		st.material_override = _mat(Color(0.5, 0.48, 0.46))
		root.add_child(st)
	list.append(_site("hearth", str(s.name), c, 2.4, s))
	# What they know, standing round them, all in one mesh.
	var kit := PropKit.new()
	var used: Array = []   # local Vector2 positions taken, with radius in z
	if has_shrine:
		var sp := _ground(c, shrine_local)
		_shrine(kit, PropKit.at(sp, atan2(-sp.x, -sp.z)))
		list.append(_site("shrine", "Shrine of %s" % s.name, c + sp, 1.6, s))
	var slot0 := float(posmod(int(s.id) * 5 + 3, CIVIC_SLOTS))
	var free_slots: Array = []
	for k in CIVIC_SLOTS:
		var a := TAU * (slot0 + k) / CIVIC_SLOTS
		var p := Vector3(cos(a), 0, sin(a)) * CIVIC_RING
		if _land_ok(c + p, 2.2):
			free_slots.append(p)
	# The temple faces the shrine's side of the hearth: take the slot nearest it.
	for kind in CIVIC:
		if not kinds.has(kind) or free_slots.is_empty():
			continue
		var pick := 0
		if kind == "temple":
			var best := INF
			for j in free_slots.size():
				var d: float = (free_slots[j] as Vector3).normalized().distance_to(shrine_local.normalized())
				if d < best:
					best = d
					pick = j
		var p: Vector3 = free_slots[pick]
		free_slots.remove_at(pick)
		var gp := _ground(c, p, 2.0)
		var xf := PropKit.at(gp, atan2(-p.x, -p.z))   # fronts face the hearth
		var label := ""
		match kind:
			"temple":
				_temple(kit, xf)
				label = "Temple of %s" % s.name
			"church":
				_church(kit, xf)
				label = "Church of %s" % s.name
			"granary":
				_granary(kit, xf, larder_fill(s))
				label = "%s barn · larder %d%% full" % [s.name, int(round(larder_fill(s) * 100.0))]
			"workshop":
				_workshop(kit, xf)
				label = "Workshop · %s" % s.name
			"well":
				_well(kit, xf)
				label = "Well · %s" % s.name
			"coop":
				_coop(kit, xf)
				label = "Hen coop · %s" % s.name
			"pen":
				_pen(kit, xf)
				label = "Sheep pen · %s" % s.name
		list.append(_site(kind, label, c + gp, 3.4 if kind in ["temple", "church", "pen"] else 2.6, s))
		used.append(p)
	var gate_a := TAU * (slot0 + 0.5) / CIVIC_SLOTS
	if kinds.has("walls"):
		_walls(kit, c, gate_a)
		list.append(_site("walls", "Walls of %s" % s.name, c, WALL_RING, s))
	var field_spots: Array = []
	if kinds.has("fields"):
		field_spots = _fields(kit, c, s, season, gate_a, list)
	if kinds.has("well") and not field_spots.is_empty():
		for site in list:
			if site["kind"] == "well":
				var wp: Vector2 = site["pos"]
				_channel(kit, c, Vector3(wp.x, 0, wp.y) - c, field_spots[0])
	if kinds.has("tree_house"):
		var t := _find_tile(s.centre, 4.0, 12.0, func(tile): return World.has_woods(tile) and not bool(tile.get("tree_cut", false)))
		if t.x >= 0.0:
			var p := Vector3(t.x * TILE_SIZE, 0, t.y * TILE_SIZE) - c
			var gp := _ground(c, p, 1.5)
			_tree_house(kit, PropKit.at(gp, atan2(-p.x, -p.z)))
			list.append(_site("tree_house", "Tree house · %s" % s.name, c + gp, 2.6, s))
	if kinds.has("docks"):
		var shore := _find_shore(s.centre, 20.0)
		if shore.size() == 2:
			var land: Vector2 = shore[0]
			var dir: Vector2 = shore[1]
			var p := Vector3(land.x * TILE_SIZE, 0, land.y * TILE_SIZE) - c
			p.y = world.surface_y(land.x, land.y) if world else 0.0
			_docks(kit, PropKit.at(p, atan2(dir.x, dir.y)))
			list.append(_site("docks", "Jetty · %s" % s.name, c + p + Vector3(dir.x, 0, dir.y) * 3.5, 4.0, s))
	if not kit.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = kit.commit()
		mi.material_override = _kit_material()
		root.add_child(mi)
	return root

func _site(kind: String, label: String, wpos: Vector3, radius: float, s) -> Dictionary:
	var day := int(_raised.get("%d:%s" % [s.id, kind], world.day if world else 1))
	if kind in ["hearth", "dwelling"]:
		day = int(s.founding_day)
	return {"kind": kind, "name": label, "pos": Vector2(wpos.x, wpos.z), "radius": radius,
		"day": day, "settlement": s.id,
		"settlement_name": str(s.name)}

## The building (or field, wall, hearth) nearest a world point, within its radius.
## Prefers small things over the ring of walls round them.
func pick(world_xz: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for id in sites:
		for site in sites[id]:
			var p: Vector2 = site["pos"]
			var r: float = site["radius"]
			var d := world_xz.distance_to(p)
			if site["kind"] == "walls":
				d = absf(d - r)
				if d > 1.6:
					continue
				d += 1.0   # anything else this close wins
			elif d > r:
				continue
			else:
				d = d / r
			if d < best_d:
				best_d = d
				best = site
	return best

## Every site of one kind (tests, the island screen).
func sites_of(settlement_id: int) -> Array:
	return sites.get(settlement_id, [])

# ── Placement ────────────────────────────────────────────────────────────────

## Ground under a local point (metres from the hearth), sunk to the lowest of a
## few samples across the footprint so nothing floats on a slope.
func _ground(c: Vector3, p: Vector3, foot: float = 0.8) -> Vector3:
	if world == null:
		return p
	var y := INF
	for o in [Vector2.ZERO, Vector2(foot, 0), Vector2(-foot, 0), Vector2(0, foot), Vector2(0, -foot)]:
		var w := Vector2(c.x + p.x + o.x, c.z + p.z + o.y) / TILE_SIZE
		y = minf(y, world.surface_y(w.x, w.y))
	return Vector3(p.x, y, p.z)

func _land_ok(wp: Vector3, foot: float) -> bool:
	if world == null:
		return true
	for o in [Vector2.ZERO, Vector2(foot, 0), Vector2(-foot, 0), Vector2(0, foot), Vector2(0, -foot)]:
		var t := Vector2(wp.x + o.x, wp.z + o.y) / TILE_SIZE
		if not world.is_walkable(t.x, t.y):
			return false
	return true

## Nearest tile (as its centre, tile space) between r0 and r1 tiles that passes ok.
func _find_tile(centre: Vector2, r0: float, r1: float, ok: Callable) -> Vector2:
	if world == null:
		return Vector2(-1, -1)
	var best := Vector2(-1, -1)
	var best_d := INF
	var ri := int(ceil(r1))
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := int(centre.x) + dx
			var z := int(centre.y) + dz
			var p := Vector2(x + 0.5, z + 0.5)
			var d := p.distance_to(centre)
			if d < r0 or d > r1 or d >= best_d:
				continue
			var tile := world.get_tile(x, z)
			if tile.is_empty() or not world.is_walkable(p.x, p.y):
				continue
			if ok.call(tile):
				best = p
				best_d = d
	return best

## Nearest land tile by the sea within r tiles: [tile centre, direction to the water].
func _find_shore(centre: Vector2, r: float) -> Array:
	if world == null:
		return []
	var best: Array = []
	var best_d := INF
	var ri := int(ceil(r))
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := int(centre.x) + dx
			var z := int(centre.y) + dz
			var p := Vector2(x + 0.5, z + 0.5)
			var d := p.distance_to(centre)
			if d > r or d >= best_d or not world.is_walkable(p.x, p.y):
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var t := world.get_tile(x + o.x, z + o.y)
				var t2 := world.get_tile(x + o.x * 3, z + o.y * 3)
				if t.is_empty() or t2.is_empty():
					continue
				var wet := int(t["type"]) in [World.TileType.WATER, World.TileType.DEEP_WATER]
				var wet2 := int(t2["type"]) in [World.TileType.WATER, World.TileType.DEEP_WATER]
				if wet and wet2:
					best = [p, Vector2(o.x, o.y)]
					best_d = d
					break
	return best

# ── Buildings (PropKit, local transforms; +z is the front) ───────────────────

func _c(col: Color, rng_v: float = 0.0) -> Color:
	return LookStyle.g(col.darkened(rng_v))

static func _story() -> bool:
	return not LookStyle.naturalist()

func _shrine(k: PropKit, xf: Transform3D) -> void:
	var stone := _c(Color(0.70, 0.67, 0.62))
	k.cyl(0.95, 1.05, 0.22, xf, _c(Color(0.58, 0.55, 0.50)), 10)
	k.cyl(0.32, 0.42, 1.1, xf * PropKit.at(Vector3(0, 0.22, 0)), stone, 6)
	var totem := _c(Color(0.94, 0.50, 0.24) if _story() else Color(0.72, 0.56, 0.32))
	k.cyl(0.0, 0.3, 0.6, xf * PropKit.at(Vector3(0, 1.32, 0)), totem, 5)
	k.ball(0.17, xf * PropKit.at(Vector3(0, 2.0, 0)), _c(Color(0.12, 0.62, 0.58) if _story() else Color(0.56, 0.60, 0.48)))
	# A ring of white stones round it: reads as a sacred place from the sky.
	for i in 9:
		var a := TAU * i / 9.0
		k.ball(0.2, xf * PropKit.at(Vector3(cos(a) * 1.6, 0.08, sin(a) * 1.6)), _c(Color(0.92, 0.90, 0.84)), 0.7)
	# Two carved posts with a cloth between.
	for side in [-1.0, 1.0]:
		k.cyl(0.08, 0.1, 1.9, xf * PropKit.at(Vector3(side * 1.1, 0, -0.6)), _c(Color(0.42, 0.30, 0.20)), 5)
	k.box(Vector3(2.1, 0.32, 0.04), xf * PropKit.at(Vector3(0, 1.7, -0.6)), _c(Color(0.85, 0.30, 0.36) if _story() else Color(0.62, 0.42, 0.34)))

func _temple(k: PropKit, xf: Transform3D) -> void:
	var stone := _c(Color(0.90, 0.86, 0.78))
	var shade := _c(Color(0.78, 0.74, 0.66))
	k.box(Vector3(6.4, 0.45, 5.0), xf * PropKit.at(Vector3(0, 0.22, 0)), shade)
	k.box(Vector3(5.8, 0.4, 4.4), xf * PropKit.at(Vector3(0, 0.62, 0)), stone)
	for ix in 4:
		for iz in [-1.0, 1.0]:
			var x := -2.3 + ix * (4.6 / 3.0)
			k.cyl(0.24, 0.28, 2.5, xf * PropKit.at(Vector3(x, 0.82, iz * 1.75)), stone, 8)
	k.box(Vector3(4.2, 2.3, 2.6), xf * PropKit.at(Vector3(0, 1.95, -0.2)), shade)   # the inner room
	k.box(Vector3(6.0, 0.45, 4.6), xf * PropKit.at(Vector3(0, 3.55, 0)), stone)
	var roof := _c(Color(0.78, 0.40, 0.28) if _story() else Color(0.55, 0.42, 0.36))
	k.prism(Vector3(6.2, 1.3, 4.8), xf * PropKit.at(Vector3(0, 3.78, 0)), roof)
	k.box(Vector3(0.9, 1.5, 0.08), xf * PropKit.at(Vector3(0, 1.55, 1.12)), _c(Color(0.26, 0.18, 0.12)))

func _church(k: PropKit, xf: Transform3D) -> void:
	var wall := _c(Color(0.84, 0.82, 0.76))
	var slate := _c(Color(0.32, 0.36, 0.44) if _story() else Color(0.30, 0.30, 0.30))
	k.box(Vector3(3.4, 2.7, 5.6), xf * PropKit.at(Vector3(0, 1.35, -0.6)), wall)
	k.prism(Vector3(5.8, 1.8, 3.9), xf * PropKit.at(Vector3(0, 2.7, -0.6), PI / 2.0), slate)
	# Tower and spire at the front.
	k.box(Vector3(1.9, 4.6, 1.9), xf * PropKit.at(Vector3(0, 2.3, 2.5)), wall)
	k.cyl(0.0, 1.35, 3.2, xf * PropKit.at(Vector3(0, 4.6, 2.5), PI / 4.0), slate, 4)
	var cross := _c(Color(0.95, 0.80, 0.30) if _story() else Color(0.20, 0.18, 0.16))
	k.box(Vector3(0.12, 0.9, 0.12), xf * PropKit.at(Vector3(0, 8.2, 2.5)), cross)
	k.box(Vector3(0.55, 0.12, 0.12), xf * PropKit.at(Vector3(0, 8.35, 2.5)), cross)
	k.box(Vector3(0.8, 1.4, 0.08), xf * PropKit.at(Vector3(0, 0.7, 3.46)), _c(Color(0.30, 0.20, 0.14)))
	k.ball(0.35, xf * PropKit.at(Vector3(0, 3.4, 3.46)), _c(Color(0.55, 0.75, 0.90) if _story() else Color(0.50, 0.55, 0.55)), 1.0)

func _granary(k: PropKit, xf: Transform3D, fill: float) -> void:
	var red := _c(Color(0.72, 0.24, 0.18) if _story() else Color(0.55, 0.32, 0.24))
	var trim := _c(Color(0.95, 0.92, 0.84))
	k.box(Vector3(4.2, 0.2, 3.4), xf * PropKit.at(Vector3(0, 0.1, 0)), _c(Color(0.50, 0.44, 0.36)))
	k.box(Vector3(3.8, 2.3, 3.0), xf * PropKit.at(Vector3(0, 1.35, 0)), red)
	# A hip roof: a four-sided cone, turned square to the walls.
	k.cyl(0.0, 2.75, 1.7, xf * Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3(0, 2.5, 0)), _c(Color(0.36, 0.20, 0.14)), 4)
	k.box(Vector3(1.6, 1.6, 0.06), xf * PropKit.at(Vector3(0, 1.0, 1.52)), _c(Color(0.28, 0.12, 0.08)))
	k.box(Vector3(0.1, 1.6, 0.08), xf * PropKit.at(Vector3(0, 1.0, 1.56)), trim)
	k.box(Vector3(1.6, 0.1, 0.08), xf * PropKit.at(Vector3(0, 1.8, 1.56)), trim)
	# What's in the larder: a bale or sack per fifth full, stacked at the side.
	var bales := int(round(fill * 5.0))
	var hay := _c(Color(0.90, 0.76, 0.36))
	for i in bales:
		var bx := 2.5 + float(i % 2) * 0.85
		var by := 0.35 + float(i / 2) * 0.62
		k.cyl(0.32, 0.32, 0.75, xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(bx, by, -0.4 + float(i % 3) * 0.35)), hay, 8)

func _workshop(k: PropKit, xf: Transform3D) -> void:
	var post := _c(Color(0.42, 0.28, 0.18))
	k.box(Vector3(4.0, 0.15, 3.0), xf * PropKit.at(Vector3(0, 0.07, 0)), _c(Color(0.52, 0.46, 0.38)))
	for x in [-1.8, 1.8]:
		for z in [-1.3, 1.3]:
			k.cyl(0.1, 0.12, 2.2 if z < 0.0 else 1.8, xf * PropKit.at(Vector3(x, 0, z)), post, 6)
	var roof := _c(Color(0.94, 0.52, 0.26) if _story() else Color(0.55, 0.42, 0.28))
	k.box(Vector3(4.3, 0.12, 3.3), xf * Transform3D(Basis(Vector3.RIGHT, -0.16), Vector3(0, 2.05, 0)), roof)
	k.box(Vector3(1.8, 0.14, 0.7), xf * PropKit.at(Vector3(-0.5, 0.85, 0)), _c(Color(0.62, 0.46, 0.30)))
	for x in [-1.2, 0.2]:
		k.box(Vector3(0.12, 0.8, 0.5), xf * PropKit.at(Vector3(x, 0.42, 0)), post)
	k.cyl(0.32, 0.36, 0.55, xf * PropKit.at(Vector3(1.0, 0, 0.6)), _c(Color(0.55, 0.40, 0.26)), 8)   # chopping block
	for i in 4:   # log pile
		k.cyl(0.2, 0.2, 1.4, xf * Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(-2.6, 0.22 + float(i / 2) * 0.36, -0.6 + float(i % 2) * 0.42 + float(i / 2) * 0.2)), _c(Color(0.58, 0.42, 0.26)), 7)
	k.cyl(0.25, 0.3, 0.5, xf * PropKit.at(Vector3(0.6, 0.92, -0.1)), _c(Color(0.78, 0.48, 0.32)), 8)   # a pot on the bench

func _well(k: PropKit, xf: Transform3D) -> void:
	var stone := _c(Color(0.62, 0.60, 0.56))
	k.cyl(0.8, 0.85, 0.8, xf, stone, 10)
	k.cyl(0.62, 0.62, 0.05, xf * PropKit.at(Vector3(0, 0.72, 0)), _c(Color(0.24, 0.52, 0.66)), 10)
	for x in [-0.75, 0.75]:
		k.cyl(0.07, 0.08, 1.9, xf * PropKit.at(Vector3(x, 0.4, 0)), _c(Color(0.42, 0.28, 0.18)), 5)
	k.prism(Vector3(1.9, 0.6, 1.3), xf * PropKit.at(Vector3(0, 2.25, 0)), _c(Color(0.78, 0.64, 0.36) if _story() else Color(0.50, 0.44, 0.32)))
	k.cyl(0.14, 0.12, 0.25, xf * PropKit.at(Vector3(0.2, 1.45, 0)), _c(Color(0.50, 0.36, 0.22)), 6)

func _coop(k: PropKit, xf: Transform3D) -> void:
	var wood := _c(Color(0.70, 0.55, 0.36))
	for x in [-0.6, 0.6]:
		for z in [-0.45, 0.45]:
			k.cyl(0.06, 0.06, 0.55, xf * PropKit.at(Vector3(x, 0, z)), _c(Color(0.42, 0.30, 0.20)), 4)
	k.box(Vector3(1.5, 0.9, 1.1), xf * PropKit.at(Vector3(0, 1.0, 0)), wood)
	k.prism(Vector3(1.7, 0.6, 1.3), xf * PropKit.at(Vector3(0, 1.45, 0)), _c(Color(0.76, 0.34, 0.24) if _story() else Color(0.48, 0.36, 0.28)))
	k.box(Vector3(0.35, 0.05, 1.0), xf * Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0.3, 0.3, 0.9)), wood)
	for i in 3:
		var p := Vector3(-0.9 + i * 0.75, 0.2, 1.3 + float(i % 2) * 0.4)
		k.ball(0.18, xf * PropKit.at(p), _c(Color(0.96, 0.94, 0.88) if i != 1 else Color(0.70, 0.42, 0.22)), 0.85)
		k.ball(0.08, xf * PropKit.at(p + Vector3(0, 0.18, 0.14)), _c(Color(0.86, 0.22, 0.20)))

func _pen(k: PropKit, xf: Transform3D) -> void:
	var wood := _c(Color(0.55, 0.40, 0.26))
	var w := 6.0
	var d := 4.4
	var corners := [Vector3(-w / 2, 0, -d / 2), Vector3(w / 2, 0, -d / 2), Vector3(w / 2, 0, d / 2), Vector3(-w / 2, 0, d / 2)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var len := a.distance_to(b)
		var n := int(len / 1.4)
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			k.cyl(0.07, 0.08, 1.0, xf * PropKit.at(p), wood, 4)
		var mid := (a + b) * 0.5
		var yaw := atan2(b.x - a.x, b.z - a.z)
		for hgt in [0.45, 0.85]:
			if i == 2 and hgt < 0.5:
				continue   # a gap to step through
			k.box(Vector3(0.06, 0.08, len), xf * PropKit.at(mid + Vector3(0, hgt, 0), yaw), wood)
	var wool := _c(Color(0.96, 0.94, 0.88))
	var face := _c(Color(0.22, 0.18, 0.16))
	for i in 3:
		var p := Vector3(-1.6 + i * 1.5, 0.55, -0.6 + float(i % 2) * 1.1)
		k.ball(0.5, xf * PropKit.at(p), wool, 0.78)
		k.ball(0.2, xf * PropKit.at(p + Vector3(0.45, 0.12, 0)), face)
		for lx in [-0.2, 0.2]:
			k.cyl(0.05, 0.05, 0.35, xf * PropKit.at(p + Vector3(lx, -0.55, 0)), face, 4)

func _tree_house(k: PropKit, xf: Transform3D) -> void:
	var bark := _c(Color(0.40, 0.28, 0.18))
	k.cyl(0.32, 0.45, 6.5, xf, bark, 7)
	k.ball(2.6, xf * PropKit.at(Vector3(0, 6.8, 0)), _c(Color(0.30, 0.55, 0.24)), 0.85)
	k.ball(1.8, xf * PropKit.at(Vector3(1.3, 5.6, -0.6)), _c(Color(0.36, 0.60, 0.26)), 0.85)
	var deck := 3.0
	k.box(Vector3(3.2, 0.18, 3.2), xf * PropKit.at(Vector3(0, deck, 0)), _c(Color(0.62, 0.46, 0.30)))
	for x in [-1.4, 1.4]:
		for z in [-1.4, 1.4]:
			k.cyl(0.08, 0.1, deck, xf * PropKit.at(Vector3(x, 0, z)), bark, 5)
	k.box(Vector3(1.8, 1.3, 1.5), xf * PropKit.at(Vector3(0.3, deck + 0.75, -0.3)), _c(Color(0.80, 0.66, 0.44)))
	k.cyl(0.0, 1.45, 0.9, xf * PropKit.at(Vector3(0.3, deck + 1.4, -0.3), PI / 4.0), _c(Color(0.28, 0.48, 0.24) if _story() else Color(0.36, 0.40, 0.28)), 4)
	k.box(Vector3(0.5, 0.8, 0.06), xf * PropKit.at(Vector3(0.3, deck + 0.5, 0.46)), _c(Color(0.28, 0.18, 0.12)))
	for x in [-0.25, 0.25]:   # ladder
		k.box(Vector3(0.06, deck, 0.06), xf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(-0.9 + x, deck * 0.5, 1.9)), bark)
	for i in 6:
		k.box(Vector3(0.5, 0.05, 0.05), xf * PropKit.at(Vector3(-0.9, 0.35 + i * 0.48, 2.12 - i * 0.085)), bark)

func _docks(k: PropKit, xf: Transform3D) -> void:
	# xf faces the sea along +z, standing at the shore tile's centre.
	var plank := _c(Color(0.62, 0.46, 0.30))
	var post := _c(Color(0.36, 0.26, 0.18))
	var origin := xf.origin
	var deck_y := 0.45
	for i in 10:
		var z := 0.6 + i * 0.75
		var local := Vector3(0, 0, z)
		var wp := xf * local
		var y := maxf(deck_y, (world.surface_y(wp.x / TILE_SIZE, wp.z / TILE_SIZE) if world else 0.0) + 0.15) - origin.y
		k.box(Vector3(1.6, 0.1, 0.62), xf * PropKit.at(Vector3(0, y, z)), plank.darkened(0.06 * float(i % 2)))
		if i % 3 == 0:
			for x in [-0.75, 0.75]:
				k.cyl(0.09, 0.1, y + 1.6, xf * PropKit.at(Vector3(x, -1.4, z)), post, 5)
	# A boat tied alongside.
	var hull := _c(Color(0.55, 0.34, 0.22) if _story() else Color(0.42, 0.32, 0.24))
	var bp := Vector3(1.7, 0.12 - origin.y, 5.2)
	k.ball(1.0, xf * Transform3D(Basis.from_scale(Vector3(0.7, 0.42, 1.9)), bp), hull)
	k.box(Vector3(1.0, 0.1, 2.6), xf * PropKit.at(bp + Vector3(0, 0.3, 0)), _c(Color(0.70, 0.54, 0.36)))
	k.cyl(0.05, 0.06, 2.6, xf * PropKit.at(bp + Vector3(0, 0.3, 0.2)), post, 5)
	k.box(Vector3(0.04, 1.6, 1.2), xf * PropKit.at(bp + Vector3(0, 1.75, -0.35)), _c(Color(0.96, 0.92, 0.82) if _story() else Color(0.80, 0.76, 0.66)))

## A ring of dry-stone wall round the town, with a gate and two towers.
func _walls(k: PropKit, c: Vector3, gate_a: float) -> void:
	var n := int(TAU * WALL_RING / 2.0)
	var stone := Color(0.66, 0.63, 0.58)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x * 31.0 + c.z * 17.0)
	for i in n:
		var a := TAU * (float(i) + 0.5) / n
		var gap := absf(wrapf(a - gate_a, -PI, PI))
		if gap < 0.13:
			continue
		var p := Vector3(cos(a), 0, sin(a)) * WALL_RING
		if not _land_ok(c + p, 0.4):
			continue
		var gp := _ground(c, p, 0.9)
		var h := 0.8 + rng.randf_range(-0.08, 0.08)
		# Along the ring (yaw -a turned the blocks to point outwards, so the
		# wall read as a ring of stepping stones).
		var along := -a + PI / 2.0
		k.box(Vector3(2.15, h + 0.4, 0.6), PropKit.at(gp + Vector3(0, (h + 0.4) * 0.5 - 0.4, 0), along), _c(stone, rng.randf() * 0.12))
		k.box(Vector3(2.2, 0.14, 0.72), PropKit.at(gp + Vector3(0, h + 0.04, 0), along), _c(stone.lightened(0.12)))
	for side in [-1.0, 1.0]:
		var a: float = gate_a + side * 0.17
		var p := Vector3(cos(a), 0, sin(a)) * WALL_RING
		if not _land_ok(c + p, 0.8):
			continue
		var gp := _ground(c, p, 1.0)
		k.cyl(0.95, 1.05, 2.6, PropKit.at(gp + Vector3(0, -0.3, 0)), _c(stone), 8)
		k.cyl(0.0, 1.25, 1.2, PropKit.at(gp + Vector3(0, 2.3, 0)), _c(Color(0.80, 0.42, 0.28) if _story() else Color(0.40, 0.38, 0.36)), 8)

## Two to four plots of crops outside the town, rows facing the hearth. The
## crop follows the season: green shoots, tall green-gold, gold with sheaves,
## then bare ridges. Returns the plots' local centres.
func _fields(k: PropKit, c: Vector3, s, season: String, gate_a: float, list: Array) -> Array:
	var spots: Array = []
	var want := clampi(2 + int(s.member_ids.size() / 8), 2, 4)
	var soil := _c(Color(0.45, 0.32, 0.20))
	var soil_dark := _c(Color(0.36, 0.25, 0.16))
	var crop := Color(0.52, 0.74, 0.34)
	var tall := 0.35
	match season:
		"summer": crop = Color(0.72, 0.74, 0.30); tall = 0.8
		"autumn": crop = Color(0.92, 0.74, 0.30); tall = 0.95
		"winter": tall = 0.0
	crop = _c(crop)
	var crop_name := "Wheat field" if season != "winter" else "Fallow field"
	for k_i in 10:
		if spots.size() >= want:
			break
		var a := gate_a + PI + (float(k_i) - 4.5) * 0.42
		var p := Vector3(cos(a), 0, sin(a)) * FIELD_RING
		var wp := c + p
		if not _land_ok(wp, 3.4):
			continue
		var tile := world.get_tile_f(wp.x / TILE_SIZE, wp.z / TILE_SIZE) if world else {}
		if not tile.is_empty() and int(tile["type"]) != World.TileType.GRASS:
			continue
		var clash := false
		for q in spots:
			if (q as Vector3).distance_to(p) < 8.0:
				clash = true
		if clash:
			continue
		spots.append(p)
		var yaw := -a + PI / 2.0
		var basis := Basis(Vector3.UP, yaw)
		for row in 7:
			var rx := -3.0 + row
			for j in 9:
				var lz := -2.0 + j * 0.5
				var lp := p + basis * Vector3(rx, 0, lz)
				var gy := (world.surface_y((c.x + lp.x) / TILE_SIZE, (c.z + lp.z) / TILE_SIZE) if world else 0.0)
				k.box(Vector3(0.55, 0.16, 0.56), PropKit.at(Vector3(lp.x, gy + 0.02, lp.z), yaw), soil if row % 2 == 0 else soil_dark)
				if tall > 0.0:
					var h := tall * (0.85 + 0.15 * sin(float(row * 7 + j * 3)))
					k.cyl(0.0, 0.2, h, PropKit.at(Vector3(lp.x, gy + 0.08, lp.z), float(j)), crop.darkened(0.05 * float((row + j) % 3)), 4)
		if season == "autumn":
			for j in 3:
				var lp := p + basis * Vector3(3.6, 0, -1.5 + j * 1.5)
				var gy := (world.surface_y((c.x + lp.x) / TILE_SIZE, (c.z + lp.z) / TILE_SIZE) if world else 0.0)
				k.cyl(0.05, 0.3, 0.9, PropKit.at(Vector3(lp.x, gy, lp.z)), crop.lightened(0.08), 6)
		list.append(_site("fields", "%s · %s" % [crop_name, s.name], c + p, 4.2, s))
	return spots

## A stone-lined water channel from the well out to the first field.
func _channel(k: PropKit, c: Vector3, from: Vector3, to: Vector3) -> void:
	var water := _c(Color(0.30, 0.62, 0.74))
	var edge := _c(Color(0.55, 0.52, 0.48))
	var dir := (to - from)
	dir.y = 0.0
	var len := dir.length() - 3.0
	if len <= 1.0:
		return
	dir = dir.normalized()
	var yaw := atan2(dir.x, dir.z)
	var side := Vector3(dir.z, 0, -dir.x)
	var steps := int(len / 0.8)
	for i in range(1, steps):
		var p := from + dir * (i * 0.8)
		var gy := (world.surface_y((c.x + p.x) / TILE_SIZE, (c.z + p.z) / TILE_SIZE) if world else 0.0)
		k.box(Vector3(0.36, 0.06, 0.84), PropKit.at(Vector3(p.x, gy + 0.03, p.z), yaw), water)
		for sgn in [-1.0, 1.0]:
			var e: Vector3 = p + side * 0.28 * sgn
			k.box(Vector3(0.16, 0.14, 0.84), PropKit.at(Vector3(e.x, gy + 0.05, e.z), yaw), edge)

# ── Dwellings (as before) ────────────────────────────────────────────────────

func _dwelling(tier: int, rng: RandomNumberGenerator) -> Node3D:
	var d := Node3D.new()
	match tier:
		0:  # hide tent
			var tent := MeshInstance3D.new()
			tent.mesh = _cone(1.5, 2.6, 6)
			tent.position.y = 1.3
			tent.material_override = _mat(Color(0.74, 0.60, 0.44).darkened(rng.randf() * 0.15))
			d.add_child(tent)
			var pole := MeshInstance3D.new()
			pole.mesh = _cone(0.05, 0.9, 4)
			pole.position.y = 2.8
			pole.material_override = _mat(Color(0.4, 0.3, 0.2))
			d.add_child(pole)
		1:  # round hut, thatched
			var wall := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.5
			cyl.bottom_radius = 1.6
			cyl.height = 1.4
			cyl.radial_segments = 10
			wall.mesh = cyl
			wall.position.y = 0.7
			wall.material_override = _mat(Color(0.70, 0.58, 0.42))
			d.add_child(wall)
			var roof := MeshInstance3D.new()
			roof.mesh = _cone(2.1, 1.7, 10)
			roof.position.y = 2.25
			roof.material_override = _mat(Color(0.78, 0.66, 0.36).darkened(rng.randf() * 0.12))
			d.add_child(roof)
		_:  # timber house with a pitched roof
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.0, 1.8, 2.4)
			box.mesh = bm
			box.position.y = 0.9
			box.material_override = _mat(Color(0.86, 0.80, 0.68))
			d.add_child(box)
			var roof := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(3.4, 1.3, 2.8)
			roof.mesh = pm
			roof.position.y = 2.45
			roof.material_override = _mat(Color(0.62, 0.30, 0.22).darkened(rng.randf() * 0.15))
			d.add_child(roof)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.6, 0.9, 0.05)
	door.mesh = dm
	door.position = Vector3(0, 0.45, 1.45 if tier > 0 else 1.0)
	door.material_override = _mat(Color(0.25, 0.18, 0.12))
	d.add_child(door)
	return d

func _sync_fires(fires: Dictionary) -> void:
	for key in fires:
		if _fires.has(key):
			continue
		var p: PackedStringArray = str(key).split(",")
		var tx := float(p[0]) + 0.5
		var tz := float(p[1]) + 0.5
		var node := Node3D.new()
		node.position = Vector3(tx * TILE_SIZE, world.surface_y(tx, tz) if world else 0.0, tz * TILE_SIZE)
		var flame := MeshInstance3D.new()
		flame.mesh = _cone(0.3, 0.8, 6)
		flame.position.y = 0.4
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.62, 0.22)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.45, 0.12)
		fm.emission_energy_multiplier = 5.0
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame.material_override = fm
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(flame)
		var light: OmniLight3D = null
		if _fires.size() < MAX_FIRE_LIGHTS:
			light = OmniLight3D.new()
			light.light_color = Color(1.0, 0.6, 0.3)
			light.omni_range = 12.0
			light.position.y = 1.2
			node.add_child(light)
		add_child(node)
		_fires[key] = {"node": node, "light": light}
	for key in _fires.keys():
		if not fires.has(key):
			(_fires[key]["node"] as Node).queue_free()
			_fires.erase(key)
	for key in _fires:
		var l: OmniLight3D = _fires[key]["light"]
		if l:
			l.light_energy = lerpf(0.4, 3.0, darkness) * (0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.013 + l.position.x))

func _kit_material() -> StandardMaterial3D:
	if _kit_mat == null:
		_kit_mat = StandardMaterial3D.new()
		_kit_mat.vertex_color_use_as_albedo = true
		_kit_mat.vertex_color_is_srgb = true
		_kit_mat.roughness = 0.92
	return _kit_mat

func _mat(c: Color) -> StandardMaterial3D:
	var col := LookStyle.g(c)
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.95
		_mats[key] = m
	return _mats[key]

static func _cone(r: float, h: float, segs: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.8
	s.radial_segments = 6
	s.rings = 4
	return s
