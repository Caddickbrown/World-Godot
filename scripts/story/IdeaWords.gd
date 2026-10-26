class_name IdeaWords
extends RefCounted
## How the chronicle talks about an idea being lost and found again
## (feat/ideas). "No one remembers how to fire clay now. Mara was the last."

## Ideas you know how to DO: "remembers how to ...", "worked out how to ... again".
const HOW := {
	"fire": "make fire", "stone_tools": "knap stone tools", "shelter": "raise a shelter",
	"housing": "build a house", "tree_house": "build in the trees", "cooking": "cook",
	"sailing": "sail", "mountain_climbing": "climb the mountains", "clothing": "make clothes",
	"weaving": "weave", "pottery": "fire clay", "fishing": "fish", "hunting": "hunt",
	"animal_domestication": "tame animals", "agriculture": "grow crops", "writing": "write",
	"metal_tools": "make metal tools", "herding": "herd animals", "preservation": "smoke food to keep",
	"rope": "twist rope", "masonry": "build in stone", "music": "make music",
	"navigation": "steer by the stars", "horse_taming": "tame horses", "woodcutting": "fell trees",
	"forestry": "plant the woods back", "honey_gathering": "find wild honey",
	"herbalism": "heal with herbs", "barn": "build a barn", "dairy": "make cheese",
	"coop": "keep chickens", "swimming": "swim", "tracking": "read tracks", "tanning": "tan hides",
	"domestication": "keep animals", "fermentation": "ferment food", "irrigation": "water the fields",
	"cartography": "draw maps", "mining": "dig for ore", "metallurgy": "smelt metal",
	"printing": "print", "woodworking": "work wood", "rope_bridge": "build rope bridges",
	"seafaring": "cross the open sea", "rope_making": "make rope", "boat_building": "build boats",
	"beekeeping": "keep bees", "dyeing": "dye cloth", "animal_breeding": "breed animals",
	"engineering": "build bridges and wheels", "architecture": "raise stone halls",
	"medicine": "tend the sick", "medicine_advanced": "set bones and heal fevers",
}

## "how to fire clay", or the idea's name for ideas you know rather than do.
static func what(id: String, name: String) -> String:
	return ("how to " + HOW[id]) if HOW.has(id) else name.to_lower()

static func lost_line(id: String, name: String, last: String) -> String:
	var w := what(id, name)
	if last == "":
		return "No one remembers %s now." % w
	return "No one remembers %s now. %s was the last." % [w, last]

## who: the finder; days: since it was lost; born_after: the finder was born
## after it was lost; near: found close to where it was last known.
static func refound_line(id: String, name: String, who: String, days: int, born_after: bool = false,
		near: bool = false, last: String = "") -> String:
	var w := what(id, name)
	var did := ("has worked out %s again" % w) if HOW.has(id) else ("has thought of %s again" % w)
	var when := "the same day it was lost"
	if days == 1:
		when = "a day after it was lost"
	elif days > 1:
		when = "%s days after it was lost" % number(days)
	var line := "%s%s %s, %s" % [who, ", born after it was lost," if born_after else "", did, when]
	if near and last != "":
		line += ", not far from where %s last knew it" % last
	return line + "."

const _ONES := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const _TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

## 90 -> "ninety", 23 -> "twenty-three"; 100 and over stay digits.
static func number(n: int) -> String:
	if n < 0 or n >= 100:
		return str(n)
	if n < 20:
		return _ONES[n]
	return _TENS[n / 10] + ("" if n % 10 == 0 else "-" + _ONES[n % 10])
