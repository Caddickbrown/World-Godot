class_name Culture
extends RefCounted
## What makes a camp itself: the dye its people wear, how it roofs and decorates
## its homes, how close it builds, the food it loves, the craft it is known for,
## and how it names the camps it founds. Derived, never rolled from the global
## RNG: a fresh camp's traits come from hash(world seed, settlement id); a
## daughter camp copies its mother's and drifts a little. Knowledge decides the
## favourite food and craft (each camp has its own order of preference, so two
## camps that know the same things still differ). docs/features/cultures.md.

## Plant and earth dyes, storybook-bright (LookStyle.g greys them for field notes).
const DYES := [
	["madder red", Color(0.80, 0.26, 0.22)],
	["woad blue", Color(0.24, 0.42, 0.74)],
	["weld yellow", Color(0.92, 0.76, 0.22)],
	["moss green", Color(0.36, 0.60, 0.28)],
	["lichen purple", Color(0.56, 0.32, 0.62)],
	["red ochre", Color(0.78, 0.44, 0.20)],
	["sea teal", Color(0.16, 0.60, 0.60)],
	["rose", Color(0.90, 0.52, 0.62)],
	["walnut brown", Color(0.46, 0.30, 0.18)],
	["chalk white", Color(0.94, 0.92, 0.84)],
]
## Undyed cloth and hide, before a camp knows dyeing: its colour is a hint.
const UNDYED := Color(0.74, 0.62, 0.46)
## Roofs: [name, hut thatch colour, town roof colour, tent hide tint]
const ROOFS := [
	["straw thatch", Color(0.86, 0.72, 0.36), Color(0.82, 0.62, 0.28)],
	["grey reed", Color(0.62, 0.60, 0.54), Color(0.36, 0.40, 0.48)],
	["green turf", Color(0.42, 0.58, 0.30), Color(0.34, 0.50, 0.28)],
	["red ochre", Color(0.76, 0.38, 0.24), Color(0.74, 0.34, 0.20)],
	["dark heather", Color(0.42, 0.30, 0.36), Color(0.30, 0.26, 0.30)],
	["pale birch bark", Color(0.90, 0.86, 0.76), Color(0.82, 0.78, 0.70)],
]
## Decorations on every home (SettlementRenderer draws them, CultureLook).
const DECOS := ["pennants", "antlers", "lanterns", "painted bands", "bunting", "carved posts"]
## Favourite foods: [food, the ideas (any one) or land that make it possible]
const FOODS := [
	["smoked fish", ["fishing"]], ["flatbread", ["agriculture"]], ["honey cakes", ["honey_gathering", "beekeeping"]],
	["soft cheese", ["dairy"]], ["roast hare", ["hunting"]], ["mushroom stew", ["cooking"]],
	["pickled greens", ["fermentation", "preservation"]], ["nettle soup", ["herbalism", "plant_lore"]],
	["berries and nuts", []],
]
## Crafts: [what they are known for, the idea it needs]
const CRAFTS := [
	["baskets", "weaving"], ["painted pots", "pottery"], ["carved bowls", "woodworking"],
	["dyed cloth", "dyeing"], ["bone flutes", "music"], ["painted stones", "art"],
	["soft leather", "tanning"], ["knotted cord", "rope_making"], ["bronze pins", "metallurgy"],
	["stitched hides", "clothing"],
]
## Before a camp has crafts of its own (two craft ideas), it is known for a folk craft.
const FOLK_CRAFTS := ["shell necklaces", "grass dolls", "feather charms", "pebble games", "string figures", "acorn cups"]
const CRAFT_IDEAS_NEEDED := 2
## How a camp names its daughters ("%s": the mother's name, or a part of it).
const NAME_STYLES := ["New %s", "Little %s", "Far %s", "Upper %s", "%s End", "%s Green"]

var seed: int = 0
var dye_i: int = 0
var hue_shift: float = 0.0      # daughters drift away from the mother's dye
var roof_i: int = 0
var deco_i: int = 0
var density: float = 1.0        # 0.8 close-built .. 1.25 spread out (SettlementRenderer)
var name_style: int = 0
var food: String = ""
var craft: String = ""
var dyed: bool = false          # the camp knows dyeing: full colour
var food_order: Array = []      # this camp's own preference order (indices into FOODS)
var craft_order: Array = []
var folk_i: int = 0
var mother_id: int = -1
var mother_name: String = ""
var generation: int = 0
var version: int = 0            # bumps whenever something drawn changes

## A fresh culture for a camp nobody founded from another: from the world's
## seed and the camp's id, avoiding dyes living camps already wear.
## used: {"dye": [...], "roof": [...], "deco": [...]} worn by other living camps;
## a new camp takes the first of its own (seeded) preferences nobody has.
static func make(world_seed: int, settlement_id: int, used: Dictionary = {}) -> Culture:
	var c := Culture.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, settlement_id, "culture"])
	c.seed = int(rng.seed)
	c.dye_i = _first_free(_shuffled(rng, DYES.size()), used.get("dye", []))
	c.roof_i = _first_free(_shuffled(rng, ROOFS.size()), used.get("roof", []))
	c.deco_i = _first_free(_shuffled(rng, DECOS.size()), used.get("deco", []))
	c.density = rng.randf_range(0.8, 1.25)
	c.name_style = rng.randi() % NAME_STYLES.size()
	c.food_order = _shuffled(rng, FOODS.size() - 1)   # the last ("berries") is everyone's fallback
	c.craft_order = _shuffled(rng, CRAFTS.size())
	c.folk_i = rng.randi() % FOLK_CRAFTS.size()
	return c

## A daughter keeps her mother's ways and drifts a little: the dye's hue moves,
## sometimes the decoration or the roof changes, the spacing shifts.
static func daughter_of(mother: Culture, settlement_id: int, mother_id: int, mother_name: String) -> Culture:
	var c := Culture.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([mother.seed, settlement_id, "daughter"])
	c.seed = int(rng.seed)
	c.dye_i = mother.dye_i
	c.hue_shift = mother.hue_shift + (0.05 + rng.randf() * 0.05) * (1.0 if rng.randf() < 0.5 else -1.0)
	c.roof_i = mother.roof_i if rng.randf() < 0.7 else rng.randi() % ROOFS.size()
	c.deco_i = mother.deco_i if rng.randf() < 0.6 else rng.randi() % DECOS.size()
	c.density = clampf(mother.density + rng.randf_range(-0.12, 0.12), 0.8, 1.25)
	c.name_style = mother.name_style
	c.food_order = mother.food_order.duplicate()
	c.craft_order = mother.craft_order.duplicate()
	c.folk_i = mother.folk_i
	if rng.randf() < 0.5 and c.craft_order.size() > 1:
		c.craft_order.push_front(c.craft_order.pop_back())   # a new fashion
	c.food = mother.food
	c.craft = mother.craft if rng.randf() < 0.5 else ""   # or a new fashion, picked from what it knows
	c.dyed = mother.dyed
	c.mother_id = mother_id
	c.mother_name = mother_name
	c.generation = mother.generation + 1
	return c

static func _first_free(order: Array, used: Array) -> int:
	for i in order:
		if not used.has(int(i)):
			return int(i)
	return int(order[0])

static func _shuffled(rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = range(n)
	for i in range(n - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out

## Re-read what the camp knows. Returns what changed: {"food": old, "craft": old}
## (empty when nothing did). near_water: fish only for camps by the water.
func refresh(knowledge: Dictionary, near_water: bool = true) -> Dictionary:
	var changed := {}
	var f := _pick_food(knowledge, near_water)
	if f != food:
		changed["food"] = food
		food = f
	# What a camp is known for sticks once it is known for something.
	var cr := craft if has_own_craft() else _pick_craft(knowledge)
	if cr != craft:
		changed["craft"] = craft
		craft = cr
	var d := knowledge.has("dyeing")
	if d != dyed:
		dyed = d
		version += 1
		changed["dyed"] = true
	return changed

func _pick_food(knowledge: Dictionary, near_water: bool) -> String:
	for i in food_order:
		var row: Array = FOODS[int(i)]
		if row[0] == "smoked fish" and not near_water:
			continue
		for id in row[1]:
			if knowledge.has(id):
				return str(row[0])
	return str(FOODS[-1][0])

## Its own craft once it knows CRAFT_IDEAS_NEEDED craft ideas (the first in
## its own order), so camps learning the same first idea still differ.
func _pick_craft(knowledge: Dictionary) -> String:
	var known := 0
	var pick := ""
	for i in craft_order:
		var row: Array = CRAFTS[int(i)]
		if knowledge.has(str(row[1])):
			known += 1
			if pick == "":
				pick = str(row[0])
	return pick if known >= CRAFT_IDEAS_NEEDED else str(FOLK_CRAFTS[folk_i])

## Known for a craft from its ideas (not a folk craft): it sticks.
func has_own_craft() -> bool:
	return craft != "" and not FOLK_CRAFTS.has(craft)

## Drift one small step (daughters, now and then): the dye wanders.
func drift(step: float) -> void:
	hue_shift = clampf(hue_shift + step, -0.22, 0.22)
	version += 1

# ── What it looks like ───────────────────────────────────────────────────────

func dye_name() -> String:
	return str(DYES[dye_i][0])

## The colour its people wear: their dye (hue drifted for daughters); muted
## towards undyed cloth until the camp knows dyeing.
func dye() -> Color:
	var c: Color = DYES[dye_i][1]
	if hue_shift != 0.0:
		c = Color.from_hsv(fposmod(c.h + hue_shift, 1.0), c.s, c.v)
	return c if dyed else UNDYED.lerp(c, 0.62)

func roof_name() -> String:
	return str(ROOFS[roof_i][0])

func hut_roof() -> Color:
	return ROOFS[roof_i][1]

func town_roof() -> Color:
	return ROOFS[roof_i][2]

func deco() -> String:
	return str(DECOS[deco_i])

func layout_word() -> String:
	if density < 0.92:
		return "close-built"
	if density > 1.12:
		return "spread out"
	return ""

## One line for the follow card and the inspect card.
func describe() -> String:
	var bits: Array = ["%s cloth" % dye_name() if dyed else "%s-tinted hides" % dye_name(), "%s roofs" % roof_name(), deco()]
	var lw := layout_word()
	if lw != "":
		bits.append(lw)
	var out := ", ".join(bits) + "."
	if food != "":
		out += " Loves %s; known for %s." % [food, craft]
	return out

## Short, for the follow card: "Woad blue cloth · loves flatbread · baskets".
func short() -> String:
	var dn := dye_name()
	var bits: Array = ["%s%s %s" % [dn.left(1).to_upper(), dn.substr(1), "cloth" if dyed else "hides"]]
	if food != "":
		bits.append("loves %s" % food)
	if craft != "":
		bits.append(craft)
	return " · ".join(bits)

## A daughter's name in this culture's style, from the mother's name.
func daughter_name(mother: String, taken: Dictionary) -> String:
	var words := mother.split(" ")
	# "New Ash Vale" has a daughter "Little Vale", not "Little New Ash Vale".
	var base := mother if words.size() <= 2 and not (words[0] in ["New", "Little", "Far", "Upper"]) else words[-1]
	for k in NAME_STYLES.size():
		var style: String = NAME_STYLES[(name_style + k) % NAME_STYLES.size()]
		var word := style.replace("%s", "").strip_edges()
		if word in words:
			continue   # not "Green Ford Green"
		var n := style % base
		if not taken.has(n):
			return n
	return "%s %d" % [base, generation + 2]
