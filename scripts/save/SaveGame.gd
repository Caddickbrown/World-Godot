class_name SaveGame
extends RefCounted
## Save and continue: the whole simulation to one file, and back.
##
## Generic, so a new field is saved without anyone remembering to: each
## system Main holds (SYSTEMS) is saved by its script variables. Plain values
## go as they are; the objects the world is made of (people, inventories,
## settlements, animals, life records...) go once each into an object table
## and are referred to by index, so a person two systems point at is still
## one person after loading; systems pointing at each other are saved as
## their names and re-pointed at the fresh ones. Nodes, callables and weak
## refs are wiring, never state: they are skipped.
##
## Loading builds a fresh world from the saved seed the ordinary way (so all
## the wiring exists), then pours the saved state into it and redraws.
## Renderers, the camera and ambient wildlife (whales, flocks: decoration,
## with their own dice) are not saved; they are rebuilt.

const VERSION := 1
const PATH := "user://world_save.bin"

## Main's members whose objects hold the world's state.
const SYSTEMS := ["world", "concept_graph", "time_system", "weather_system", "animal_sim",
	"animal_skill_system", "fire_system", "disaster_system", "ecology_system", "conflict_system",
	"trading_system", "crafting_system", "settlement_system", "tile_items", "history_log",
	"achievements", "lineage_tracker", "hunting_system", "forest_system", "story", "disease_system",
	"population_manager", "path_system", "island_history", "animal_minds", "festival_system", "culture_system"]
## Main's own state.
const MAIN_VARS := ["agents", "birth_times", "_history_seen", "_was_storm", "game_over"]
## Per-instance state that isn't worth a file: caches rebuilt on use.
const SKIP_PROPS := ["_fx", "_fx_n", "heightfield"]
## Big fields known to hold plain data only (no objects anywhere inside):
## stored as they are, without walking them (the tiles alone took 0.4 s).
const PLAIN_PROPS := ["tiles", "trade_traffic", "glacier_data", "cut_trees", "natural_fires", "growing"]

const OBJ := "\u0001obj"
const SYS := "\u0001sys"
const SKIP := "\u0001skip"
const PLAIN := "\u0001plain"

var _objs: Array = []
var _ids: Dictionary = {}       # Object -> index in _objs
var _sys: Dictionary = {}       # Object -> system name
static var _key_of: Dictionary = {}    # Script -> class key
static var _script_of: Dictionary = {} # class key -> Script

# ── Saving ───────────────────────────────────────────────────────────────────

## Everything needed to continue this world, as plain data (no objects).
static func snapshot(main: Node) -> Dictionary:
	var s := SaveGame.new()
	return s._snapshot(main)

func _snapshot(main: Node) -> Dictionary:
	_registry()
	for name in SYSTEMS:
		var o = main.get(name)
		if o is Object:
			_sys[o] = name
	var systems := {}
	for name in SYSTEMS:
		var o = main.get(name)
		if o is Object:
			systems[name] = _props(o)
	var mains := {}
	for name in MAIN_VARS:
		mains[name] = _encode(main.get(name))
	return {
		"version": VERSION,
		"seed": int(main.world.seed_val),
		"day": int(main.time_system.day),
		"style": UiTheme.style,
		"systems": systems,
		"main": mains,
		"objects": _objs,
		"statics": {"agent_next_id": Agent._next_id, "agent_names": Agent._names_given.duplicate(true)},
	}

func _props(o: Object) -> Dictionary:
	var out := {}
	for p in o.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		if n in SKIP_PROPS:
			continue
		if n in PLAIN_PROPS:
			out[n] = {PLAIN: o.get(n)}
			continue
		var v = _encode(o.get(n))
		if v is Dictionary and v.has(SKIP):
			continue
		out[n] = v
	return out

func _encode(v):
	match typeof(v):
		TYPE_OBJECT:
			if v == null or not is_instance_valid(v):
				return null
			if _sys.has(v):
				return {SYS: _sys[v]}
			if v is Node or v is WeakRef or not (v is RefCounted):
				return {SKIP: true}
			if _ids.has(v):
				return {OBJ: _ids[v]}
			var key := _class_key(v)
			if key == "":
				return {SKIP: true}
			var idx := _objs.size()
			_ids[v] = idx
			_objs.append(null)
			_objs[idx] = {"c": key, "p": _props(v)}
			return {OBJ: idx}
		TYPE_ARRAY:
			var a: Array = []
			for e in v:
				a.append(_encode(e))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				if typeof(k) == TYPE_OBJECT:
					continue
				d[k] = _encode(v[k])
			return d
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return {SKIP: true}
	return v

# ── Loading ──────────────────────────────────────────────────────────────────

## Pour a snapshot into a Main that has just built a fresh world from the
## same seed. Returns "" or what went wrong.
static func restore(main: Node, data: Dictionary) -> String:
	if int(data.get("version", 0)) != VERSION:
		return "saved by another version"
	var s := SaveGame.new()
	return s._restore(main, data)

func _restore(main: Node, data: Dictionary) -> String:
	_registry()
	var systems := {}
	for name in SYSTEMS:
		var o = main.get(name)
		if o is Object:
			systems[name] = o
	# Pass 1: every saved object, made new; pass 2: their fields (which can
	# point at each other); then the systems' and Main's own fields.
	var made: Array = []
	for rec in data["objects"]:
		var script: Script = _script_for(rec["c"])
		if script == null:
			return "unknown class " + str(rec["c"])
		made.append(_make(script))
	for i in made.size():
		_apply(made[i], data["objects"][i]["p"], made, systems)
	for name in data["systems"]:
		if systems.has(name):
			_apply(systems[name], data["systems"][name], made, systems)
	for name in data["main"]:
		_put(main, name, _decode(data["main"][name], made, systems))
	var st: Dictionary = data.get("statics", {})
	Agent._next_id = int(st.get("agent_next_id", Agent._next_id))
	Agent._names_given = st.get("agent_names", Agent._names_given)
	return ""

func _apply(o: Object, props: Dictionary, made: Array, systems: Dictionary) -> void:
	for n in props:
		_put(o, n, _decode(props[n], made, systems))

## Set a field. Arrays and Dictionaries are filled in place: the fresh world
## shares some between systems (the story holds Main's own list of people),
## and a typed one stays typed.
func _put(o: Object, n: String, v) -> void:
	var cur = o.get(n)
	if cur is Array and v is Array:
		(cur as Array).assign(v)
	elif cur is Dictionary and v is Dictionary:
		(cur as Dictionary).assign(v)
	else:
		o.set(n, v)

func _decode(v, made: Array, systems: Dictionary):
	if v is Dictionary:
		if v.has(PLAIN):
			return v[PLAIN]
		if v.has(OBJ):
			return made[int(v[OBJ])]
		if v.has(SYS):
			return systems.get(v[SYS])
		var d := {}
		for k in v:
			d[k] = _decode(v[k], made, systems)
		return d
	if v is Array:
		var a: Array = []
		for e in v:
			a.append(_decode(e, made, systems))
		return a
	return v

## A new instance whatever its constructor wants (the fields are overwritten).
static func _make(script: Script) -> Object:
	var argc := 0
	for m in script.get_script_method_list():
		if m["name"] == "_init":
			argc = (m["args"] as Array).size() - (m["default_args"] as Array).size()
			break
	match argc:
		0: return script.new()
		1: return script.new(0)
		2: return script.new(0.0, 0.0)
		3: return script.new(0, 0, 0.0)
		4: return script.new(0, 0, 0.0, 0.0)
	return script.new()

# ── Classes ──────────────────────────────────────────────────────────────────

## Value classes are named by their script's path; an inner class by its
## outer script's path and its name.
const OUTERS := ["res://scripts/systems/SettlementSystem.gd", "res://scripts/simulation/AnimalSim.gd",
	"res://scripts/systems/WeatherSystem.gd", "res://scripts/simulation/AmbientLife.gd"]

static func _registry() -> void:
	if not _script_of.is_empty():
		return
	for path in OUTERS:
		var outer: Script = load(path)
		var consts := outer.get_script_constant_map()
		for cname in consts:
			if consts[cname] is Script:
				var key := "%s::%s" % [path, cname]
				_key_of[consts[cname]] = key
				_script_of[key] = consts[cname]

func _class_key(o: Object) -> String:
	var sc: Script = o.get_script()
	if sc == null:
		return ""
	if _key_of.has(sc):
		return _key_of[sc]
	if sc.resource_path != "" and not sc.resource_path.contains("::"):
		_key_of[sc] = sc.resource_path
		_script_of[sc.resource_path] = sc
		return sc.resource_path
	return ""

static func _script_for(key: String) -> Script:
	if _script_of.has(key):
		return _script_of[key]
	if key.begins_with("res://") and not key.contains("::"):
		var sc: Script = load(key)
		_script_of[key] = sc
		_key_of[sc] = key
		return sc
	return null

# ── Files ────────────────────────────────────────────────────────────────────

static func write(main: Node, path: String = PATH) -> String:
	var data := snapshot(main)
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "can't write " + path
	f.store_var(data)
	f.close()
	# A few words about it beside it, for the start screen (without loading it).
	var m := FileAccess.open(path + ".json", FileAccess.WRITE)
	if m:
		var alive := 0
		for a in main.agents:
			if not a.is_dead:
				alive += 1
		m.store_string(JSON.stringify({"seed": data["seed"], "day": data["day"], "people": alive,
			"saved": Time.get_datetime_string_from_system(false, true)}))
		m.close()
	return ""

## The few words written beside a save: {seed, day, people, saved} or {}.
static func about(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path + ".json"):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
	return d if d is Dictionary else {}

static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data = f.get_var()
	f.close()
	return data if data is Dictionary else {}

static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)
