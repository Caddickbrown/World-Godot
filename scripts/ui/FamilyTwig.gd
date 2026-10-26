class_name FamilyTwig
extends Control
## A small drawn family tree for one person (feat/generations): grandparents,
## parents, the person and their partner, children and grandchildren, joined
## by twigs. Storybook draws ink twigs with leaves; field notes, hairlines.
## The dead are paler; legends wear a small star. Clicking a relative emits
## `chosen` with their id (the Lives screen opens their life).

signal chosen(agent_id: int)

const NODE_W := 96.0
const NODE_H := 40.0
const GAP := 10.0
const ROW_GAP := 26.0
const MAX_ROW := 7

## [{id, row, pos (top-left), dead, legend, focus, more}]
var nodes: Array = []
## [[from node index, to node index, "blood" | "partner"]]
var links: Array = []
var focus_id := -1

## Lay the tree out for `id`. Returns self.
func build(lineage: LineageTracker, id: int) -> FamilyTwig:
	focus_id = id
	nodes.clear()
	links.clear()
	for ch in get_children():
		ch.queue_free()
	if lineage == null or lineage.person(id).is_empty():
		custom_minimum_size = Vector2.ZERO
		return self
	var me: Dictionary = lineage.person(id)
	var rows: Array = [[], [], [], [], []]   # each: [{id, parent (node index or -1)}]
	var idx := {}   # agent id -> node index (filled as rows are placed)
	var parents: Array = (me["parents"] as Array).filter(func(x): return not lineage.person(int(x)).is_empty())
	for pid in parents:
		for gid in lineage.person(int(pid))["parents"]:
			if not lineage.person(int(gid)).is_empty():
				rows[0].append({"id": int(gid), "up_of": int(pid)})
	for pid in parents:
		rows[1].append({"id": int(pid)})
	rows[2].append({"id": id})
	var partner := int(me["partner"])
	if partner >= 0 and not lineage.person(partner).is_empty():
		rows[2].append({"id": partner, "partner": true})
	for cid in me["children"]:
		if not lineage.person(int(cid)).is_empty():
			rows[3].append({"id": int(cid)})
	for c in rows[3]:
		for gid in lineage.person(int(c["id"]))["children"]:
			if not lineage.person(int(gid)).is_empty():
				rows[4].append({"id": int(gid), "down_of": int(c["id"])})

	var used: Array = []
	for r in 5:
		if not rows[r].is_empty():
			used.append(r)
	var widest := 0.0
	for r in used:
		widest = maxf(widest, mini(rows[r].size(), MAX_ROW + 1) * (NODE_W + GAP) - GAP)
	var y := 0.0
	for r in used:
		var row: Array = rows[r]
		var extra := row.size() - MAX_ROW
		var shown: Array = row.slice(0, MAX_ROW) if extra > 0 else row
		var n := shown.size() + (1 if extra > 0 else 0)
		var x := (widest - (n * (NODE_W + GAP) - GAP)) / 2.0
		for item in shown:
			var pid := int(item["id"])
			var p := lineage.person(pid)
			var node := {"id": pid, "row": r, "pos": Vector2(x, y), "dead": int(p["died_day"]) >= 0,
				"legend": lineage.is_legend(pid), "focus": pid == id, "more": 0, "name": str(p["name"])}
			nodes.append(node)
			idx[pid] = nodes.size() - 1
			x += NODE_W + GAP
		if extra > 0:
			nodes.append({"id": -1, "row": r, "pos": Vector2(x, y), "dead": false, "legend": false,
				"focus": false, "more": extra, "name": "+%d" % extra})
		y += NODE_H + ROW_GAP
	# Twigs: grandparents to parent, parents to me, me (and partner) to
	# children, children to grandchildren.
	for item in rows[0]:
		_link(idx, int(item["id"]), int(item["up_of"]), "blood")
	for item in rows[1]:
		_link(idx, int(item["id"]), id, "blood")
	if rows[2].size() > 1:
		_link(idx, id, int(rows[2][1]["id"]), "partner")
	for item in rows[3]:
		_link(idx, id, int(item["id"]), "blood")
	for item in rows[4]:
		_link(idx, int(item["down_of"]), int(item["id"]), "blood")

	for i in nodes.size():
		var node: Dictionary = nodes[i]
		var b: Control
		if int(node["more"]) > 0:
			var l := UiTheme.label(node["name"], "strong", 15, "muted")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			b = l
		else:
			var btn := UiTheme.button(node["name"], bool(node["focus"]), 14)
			btn.clip_text = true
			btn.tooltip_text = _tip(lineage, node)
			if node["dead"] and not node["focus"]:
				btn.modulate = Color(1, 1, 1, 0.62)
			var aid := int(node["id"])
			btn.pressed.connect(func(): chosen.emit(aid))
			b = btn
		b.position = node["pos"]
		b.size = Vector2(NODE_W, NODE_H)
		b.custom_minimum_size = Vector2(NODE_W, NODE_H)
		add_child(b)
		if bool(node["legend"]):
			var st := Star.new()
			st.mouse_filter = Control.MOUSE_FILTER_IGNORE
			st.position = node["pos"] + Vector2(NODE_W - 12.0, -6.0)
			st.size = Vector2(16, 16)
			add_child(st)
	custom_minimum_size = Vector2(widest, maxf(0.0, y - ROW_GAP))
	queue_redraw()
	return self

func _link(idx: Dictionary, a: int, b: int, kind: String) -> void:
	if idx.has(a) and idx.has(b):
		links.append([int(idx[a]), int(idx[b]), kind])

static func _tip(lineage: LineageTracker, node: Dictionary) -> String:
	var p := lineage.person(int(node["id"]))
	var t := "%s, born day %d" % [p["name"], int(p["born_day"])] if not bool(p["founder"]) else "%s, one of the first forty" % p["name"]
	if int(p["died_day"]) >= 0:
		t += ", died day %d" % int(p["died_day"])
	if bool(node["legend"]):
		t += "\nA legend: " + str(lineage.legends[int(node["id"])]["deed"])
	return t

func _draw() -> void:
	var story := UiTheme.style == "storybook"
	var ink := UiTheme.c("ink") if story else UiTheme.c("accent")
	var width := 3.0 if story else 1.2
	for l in links:
		var a: Dictionary = nodes[l[0]]
		var b: Dictionary = nodes[l[1]]
		var pa: Vector2 = a["pos"]
		var pb: Vector2 = b["pos"]
		if l[2] == "partner":
			var y := pa.y + NODE_H / 2.0
			var from := Vector2(pa.x + NODE_W, y)
			var to := Vector2(pb.x, y)
			draw_line(from, to, ink, width, true)
			draw_circle((from + to) / 2.0, 4.5 if story else 3.0, UiTheme.c("warn"))
			continue
		var top := Vector2(pa.x + NODE_W / 2.0, pa.y + NODE_H)
		var bottom := Vector2(pb.x + NODE_W / 2.0, pb.y)
		var pts := _twig(top, bottom, int(a["id"]) * 31 + int(b["id"]))
		draw_polyline(pts, ink if not (b["dead"] and a["dead"]) else Color(ink, 0.55), width, true)
		if story:
			var mid: Vector2 = pts[pts.size() >> 1]
			_leaf(mid, (int(a["id"]) + int(b["id"])) % 2 == 0)

## A gently bent stroke (a twig, not a ruler line); the bend comes from the
## pair's ids, so it is the same every frame.
static func _twig(a: Vector2, b: Vector2, salt: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var bend := (float(posmod(salt * 7919, 13)) / 13.0 - 0.5) * 10.0
	var c1 := Vector2(a.x + bend, lerpf(a.y, b.y, 0.55))
	var c2 := Vector2(b.x - bend, lerpf(a.y, b.y, 0.45))
	for i in 13:
		var t := float(i) / 12.0
		var u := 1.0 - t
		pts.append(u * u * u * a + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * b)
	return pts

func _leaf(at: Vector2, left: bool) -> void:
	var dir := Vector2(-1.0 if left else 1.0, -0.6).normalized()
	var tip := at + dir * 10.0
	var side := Vector2(-dir.y, dir.x) * 3.2
	var mid := (at + tip) / 2.0
	draw_colored_polygon(PackedVector2Array([at, mid + side, tip, mid - side]), UiTheme.c("good"))

## A legend's star, drawn over the corner of their name.
class Star extends Control:
	func _draw() -> void:
		var story := UiTheme.style == "storybook"
		FamilyTwig.star(self, Vector2(8, 8), 7.5 if story else 5.5, UiTheme.c("select"), UiTheme.c("ink") if story else Color(0, 0, 0, 0))

static func star(ci: CanvasItem, c: Vector2, r: float, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + float(i) * PI / 5.0
		pts.append(c + Vector2.from_angle(ang) * (r if i % 2 == 0 else r * 0.45))
	if edge.a > 0.0:
		var outline := pts.duplicate()
		outline.append(pts[0])
		ci.draw_colored_polygon(pts, fill)
		ci.draw_polyline(outline, edge, 1.5, true)
	else:
		ci.draw_colored_polygon(pts, fill)

## A line or two for the follow card: "Named for Aya. 3 grandchildren."
static func card_lines(lineage: LineageTracker, id: int) -> Array:
	var out: Array = []
	var p := lineage.person(id)
	if p.is_empty():
		return out
	if int(p["named_for"]) >= 0:
		out.append("Named for %s." % lineage.person(int(p["named_for"])).get("name", ""))
	var g := lineage.descendants(id, 2).size()
	var gg := lineage.descendants(id, 3).size()
	if gg > 0:
		out.append("%d great-grandchild%s." % [gg, "" if gg == 1 else "ren"])
	elif g > 0:
		out.append("%d grandchild%s." % [g, "" if g == 1 else "ren"])
	return out
