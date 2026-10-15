class_name LifeRecord
extends RefCounted
## One person's story, as the StoryKeeper has seen it. Kept after they die.

var agent_id := 0
var name := ""
var born_day := 1
var founder := false
var parents: Array = []    # names
var partner := ""
var children: Array = []   # names
var firsts: Array = []     # concept ids they were first to think of
var taught: Dictionary = {}  # concept id -> people taught
var events: Array = []     # {day, text, kind}
var died_day := -1
var cause := ""
var last_line := ""

func alive() -> bool:
	return died_day < 0

func total_taught() -> int:
	var n := 0
	for id in taught:
		n += int(taught[id])
	return n
