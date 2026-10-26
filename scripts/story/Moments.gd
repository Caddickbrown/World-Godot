class_name Moments
extends RefCounted
## The album: things you were there for. A moment unlocks only when its event
## happens where you can see it (StoryKeeper asks Main), or, for world-wide
## moments, while you're playing at all. Kept across worlds in a small save.

## id: [name, hint, kind, needs_witness]
const DEFS := {
	"first_idea":    ["A first thought", "someone thinks of something new", "firsts", true],
	"first_fire":    ["The first fire", "someone tames fire", "firsts", true],
	"first_words":   ["First words", "someone invents language", "firsts", true],
	"first_crossing":["The first crossing", "someone learns to sail", "firsts", true],
	"first_harvest": ["First harvest", "someone works out farming", "firsts", true],
	"first_story":   ["The first story", "someone starts an oral tradition", "firsts", true],
	"first_hunt":    ["The first hunt", "someone brings down an animal", "firsts", true],
	"first_felling": ["The first axe", "someone fells a tree for timber", "firsts", true],
	"planted":       ["A tree for later", "someone plants a tree", "people", true],
	"fire_circle":   ["Round the fire", "watch an evening round the hearth", "people", true],
	"pairing":       ["Two hearts", "two people pair up", "people", true],
	"birth":         ["A new face", "a child is born", "people", true],
	"long_life":     ["A long life", "someone dies of old age", "people", true],
	"teacher":       ["The teacher", "someone teaches an idea to ten people", "people", true],
	"last_founder":  ["The last founder", "the last of the first forty dies", "people", false],
	"idea_lost":     ["Forgotten", "an idea dies with the last who knew it", "ideas", false],
	"idea_refound":  ["Found again", "a lost idea is rediscovered", "ideas", true],
	"ten_ideas":     ["Ten ideas", "the world holds ten ideas at once", "ideas", false],
	"first_camp":    ["A camp", "people settle together", "world", true],
	"hamlet":        ["A hamlet", "a camp grows and takes a name", "world", true],
	"contact":       ["Strangers meet", "two settlements make contact", "world", true],
	"larder":        ["Put by", "a camp's stored food feeds someone hungry", "world", true],
	"woods_return":  ["The woods come back", "seedlings rise where a wood burned", "world", true],
	"camp_moves":    ["Moving on", "a camp leaves stripped land for better", "world", true],
	"storm_passed":  ["After the storm", "watch a storm blow through", "world", true],
	"lightning":     ["Lightning", "see lightning strike the forest", "world", true],
	"full_year":     ["A whole year", "watch the seasons turn once round", "world", false],
	"hundred":       ["A hundred souls", "the population reaches a hundred", "world", false],
	"whole_island":  ["The whole island", "pull right back and see it all", "world", false],
	"night_watch":   ["Night watch", "watch the island at midnight", "world", false],
	"walk":          ["Among them", "walk among them for the first time", "world", false],
	"listen":        ["Eavesdropper", "listen in on someone", "people", false],
	"whale_breach":  ["A whale breaches", "see a whale leap clear of the sea", "world", true],
	"frog_chorus":   ["The frog chorus", "be by the water when the frogs start up at dusk", "world", true],
	"wild_honey":    ["Wild honey", "someone eats honey from a bees' nest in the woods", "firsts", true],
	# festivals (feat/festivals)
	"fest_planting": ["The first sowing", "watch a camp sow its meadow together in spring", "people", true],
	"fest_midsummer":["Midsummer fire", "be there when a camp dances round its midsummer fire", "people", true],
	"fest_harvest":  ["The harvest feast", "be at the long table when a camp eats its harvest", "people", true],
	"fest_mourning": ["Remembering", "be there when a camp remembers its dead at the shrine", "people", true],
	"fest_midwinter":["The longest night", "see a camp's lights on midwinter night", "people", true],
	# generations (feat/generations)
	"named_for":     ["Named for them", "a child is named after someone gone", "people", true],
	"four_generations": ["Four generations", "a child is born while a great-grandparent lives", "people", true],
	"legend_told":   ["A legend told", "hear an elder tell a legend at the evening fire", "people", true],
	"myth":          ["Into myth", "a legend outlives everyone who knew them", "ideas", false],
	"pressed_life":  ["Pressed flower", "press a life into the album", "people", false],
}

var save_path := "user://world_album.json"
var unlocked: Dictionary = {}   # id -> {day, note}
## Lives pressed into the album (PressedLife.page), kept across worlds.
var pressed: Array = []
const MAX_PRESSED := 30

func load_album() -> void:
	unlocked.clear()
	pressed = []
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.get("unlocked") is Dictionary:
		unlocked = data["unlocked"]
	if data is Dictionary and data.get("pressed") is Array:
		pressed = data["pressed"]

func save_album(extra: Dictionary = {}) -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	var data := {"v": 1, "unlocked": unlocked, "pressed": pressed}
	data.merge(extra)
	f.store_string(JSON.stringify(data))

func needs_witness(id: String) -> bool:
	return bool((DEFS.get(id, ["", "", "", true]) as Array)[3])

## Returns true if this call unlocked it (first time).
func unlock(id: String, day: int, note: String) -> bool:
	if not DEFS.has(id) or unlocked.has(id):
		return false
	unlocked[id] = {"day": day, "note": note}
	return true

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)

func name_of(id: String) -> String:
	return str((DEFS.get(id, [id]) as Array)[0])

## For the album screen: [{id, name, hint, kind, found, note}] in definition order.
func entries() -> Array:
	var out: Array = []
	for id in DEFS:
		var d: Array = DEFS[id]
		var u: Dictionary = unlocked.get(id, {})
		out.append({"id": id, "name": d[0], "hint": d[1], "kind": d[2], "found": not u.is_empty(),
			"note": str(u.get("note", ""))})
	return out

## Press (or re-press, keeping it current) a life page.
func press(page: Dictionary) -> void:
	var i := pressed_index(str(page.get("key", "")))
	if i >= 0:
		pressed[i] = page
	else:
		pressed.append(page)
		if pressed.size() > MAX_PRESSED:
			pressed.pop_front()

func pressed_index(key: String) -> int:
	for i in pressed.size():
		if str((pressed[i] as Dictionary).get("key", "")) == key:
			return i
	return -1
