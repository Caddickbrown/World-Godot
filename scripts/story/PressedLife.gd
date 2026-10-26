class_name PressedLife
extends RefCounted
## A life page pressed into the album (feat/generations): a plain Dictionary
## that survives the world (Moments.pressed, saved with the album as JSON).

const EVENTS_KEPT := 10

static func key(agent_id: int, world_seed: int) -> String:
	return "%d:%d" % [world_seed, agent_id]

static func page(life: LifeRecord, ledger: IdeaLedger, lineage: LineageTracker, world_seed: int, day: int) -> Dictionary:
	var firsts: Array = []
	for id in life.firsts:
		firsts.append(ledger.name_of(id).to_lower() if ledger else str(id))
	var named_for := ""
	var legend := ""
	var grandchildren := 0
	var greats := 0
	if lineage:
		var p := lineage.person(life.agent_id)
		if int(p.get("named_for", -1)) >= 0:
			named_for = str(lineage.person(int(p["named_for"])).get("name", ""))
		if lineage.is_legend(life.agent_id):
			legend = str(lineage.legends[life.agent_id]["deed"])
		grandchildren = lineage.descendants(life.agent_id, 2).size()
		greats = lineage.descendants(life.agent_id, 3).size()
	var events: Array = []
	for e in life.events.slice(maxi(0, life.events.size() - EVENTS_KEPT)):
		events.append({"day": int(e["day"]), "text": str(e["text"])})
	return {
		"key": key(life.agent_id, world_seed), "world": world_seed, "name": life.name,
		"born_day": life.born_day, "died_day": life.died_day, "founder": life.founder,
		"parents": life.parents.duplicate(), "partner": life.partner, "children": life.children.duplicate(),
		"grandchildren": grandchildren, "great_grandchildren": greats, "firsts": firsts,
		"named_for": named_for, "legend": legend, "last_line": life.last_line, "events": events,
		"pressed_day": day,
	}

## "Day 3 to day 11" / "Born day 3, still living when pressed".
static func span(pg: Dictionary) -> String:
	var born := "One of the first forty" if bool(pg.get("founder", false)) else "Born day %d" % int(pg.get("born_day", 1))
	if int(pg.get("died_day", -1)) >= 0:
		return "%s, died day %d" % [born, int(pg["died_day"])]
	return "%s, living when pressed (day %d)" % [born, int(pg.get("pressed_day", 1))]

## One line of family: "Partner of Lin · 4 children · 6 grandchildren".
static func family(pg: Dictionary) -> String:
	var bits: Array = []
	if str(pg.get("partner", "")) != "":
		bits.append("Partner of %s" % pg["partner"])
	var kids := (pg.get("children", []) as Array).size()
	if kids > 0:
		bits.append("%d %s" % [kids, "child" if kids == 1 else "children"])
	if int(pg.get("grandchildren", 0)) > 0:
		bits.append("%d grandchildren" % int(pg["grandchildren"]))
	if int(pg.get("great_grandchildren", 0)) > 0:
		bits.append("%d great-grandchildren" % int(pg["great_grandchildren"]))
	return " · ".join(bits) if not bits.is_empty() else "No family of their own"
