class_name IslandScreen
extends HudScreen
## The island over time (G): how many lived, how many ideas were held and
## found, and how the camps grew, from IslandHistory's samples.

func kicker() -> String: return "The island so far"
func title() -> String: return "Island"
func subtitle() -> String: return "Every few hours the island is counted. Lines rise and fall with good years and bad."

func fill() -> void:
	var m := main()
	var h: IslandHistory = m.island_history
	var col := UiTheme.vbox(14)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(col)
	var top := UiTheme.hbox(24)
	col.add_child(top)
	var pop := _chart("People", [{"points": h.series("pop"), "color_key": "accent", "label": "living", "fill": true}])
	top.add_child(pop)
	var ideas := _chart("Ideas", [
		{"points": h.series("found"), "color_key": "cool", "label": "ever found", "fill": true},
		{"points": h.series("known"), "color_key": "good", "label": "held now", "fill": false}])
	top.add_child(ideas)
	var places := _chart("Places", [
		{"points": h.series("camps"), "color_key": "muted", "label": "camps", "fill": false},
		{"points": h.series("hamlets"), "color_key": "accent", "label": "hamlets", "fill": false},
		{"points": h.series("towns"), "color_key": "warn", "label": "towns", "fill": false}])
	col.add_child(places)
	var facts := UiTheme.hbox(28)
	col.add_child(facts)
	var last: Dictionary = h.samples[-1] if not h.samples.is_empty() else {}
	for f in [["Day", str(m.time_system.day)], ["Most alive at once", str(h.peak_pop)],
			["Ideas found", str(int(last.get("found", 0)))], ["Settlements", str(m.settlement_system.get_settlements().size())]]:
		var v := UiTheme.vbox(0)
		v.add_child(UiTheme.caps(f[0], "faint"))
		v.add_child(UiTheme.label(f[1], "display", 30))
		facts.add_child(v)

func _chart(name: String, lines: Array) -> Control:
	var v := UiTheme.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiTheme.hbox(10)
	head.add_child(UiTheme.caps(name, "accent", 12))
	for l in lines:
		var key := UiTheme.label("— " + str(l["label"]), "body", 13, str(l["color_key"]))
		head.add_child(key)
	v.add_child(head)
	var c := LineChart.new()
	c.lines = lines
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(380, 130)
	v.add_child(c)
	return v
