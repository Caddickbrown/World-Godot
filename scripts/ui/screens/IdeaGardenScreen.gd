class_name IdeaGardenScreen
extends HudScreen
## The Idea Garden: every idea as a plant, rowed by era. Seeds are ideas nobody
## has thought of; sprouts, a few hold; blooms, most do; wilted, lost.

const PETALS := [Color("F0803C"), Color("D9496B"), Color("FFD25A"), Color("BFE3F2"), Color("9BD06E"), Color("C9A27A")]
var _chosen := ""

func kicker() -> String: return "What the world knows"
func title() -> String: return "The Idea Garden"
func subtitle() -> String: return "Ideas grow as people share them and wilt when the last who knew one dies. They can be found again."

func fill() -> void:
	var m := main()
	var ledger: IdeaLedger = m.story.ledger
	var row := UiTheme.hbox(28)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(row)

	var garden: Array = scroll_column(660, 14)
	(garden[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(garden[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(garden[0])
	var col: VBoxContainer = garden[1]
	var counts := UiTheme.hbox(20)
	for st in [IdeaLedger.Stage.BLOOM, IdeaLedger.Stage.SPROUT, IdeaLedger.Stage.WILTED, IdeaLedger.Stage.SEED]:
		counts.add_child(UiTheme.label("%d %s" % [ledger.count_in(st), IdeaLedger.stage_name(st)], "strong", 15, "muted"))
	col.add_child(counts)
	var eras := {1: "First ideas", 2: "Settling", 3: "Towns and thinkers", 4: "Far horizons"}
	for era in [1, 2, 3, 4]:
		var ids: Array = []
		for id in m.concept_graph.concepts:
			if int(m.concept_graph.concepts[id].get("era", 1)) == era:
				ids.append(id)
		# Known ideas first, so the garden reads as growing from the left.
		ids.sort_custom(func(x, y): return ledger.stage_of(x) != IdeaLedger.Stage.SEED and ledger.stage_of(y) == IdeaLedger.Stage.SEED)
		col.add_child(UiTheme.caps(eras[era], "accent", 12))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for id in ids:
			grid.add_child(_plot(id, ledger))
		col.add_child(grid)
		if _chosen == "" and not ids.is_empty() and ledger.stage_of(ids[0]) != IdeaLedger.Stage.SEED:
			_chosen = ids[0]

	var side := UiTheme.vbox(12)
	side.custom_minimum_size.x = 300
	row.add_child(side)
	if _chosen != "":
		_describe(side, _chosen, ledger)

func _plot(id: String, ledger: IdeaLedger) -> Button:
	var stage := ledger.stage_of(id)
	var b := UiTheme.button("", id == _chosen, 13)
	b.custom_minimum_size = Vector2(104, 96)
	b.tooltip_text = (ledger.name_of(id) if stage != IdeaLedger.Stage.SEED else "Not yet thought of") + " · " + IdeaLedger.stage_name(stage)
	var v := UiTheme.vbox(0)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var glyph := PlantGlyph.new().setup(stage, PETALS[abs(id.hash()) % PETALS.size()])
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(glyph)
	var name_l := UiTheme.label(ledger.name_of(id) if stage != IdeaLedger.Stage.SEED else "?", "strong", 13,
		"text" if UiTheme.style == "fieldnotes" else "ink")
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.custom_minimum_size.x = 96
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	b.add_child(v)
	b.pressed.connect(func(): _chosen = id; _rebuild())
	return b

func _rebuild() -> void:
	for ch in body.get_children():
		ch.queue_free()
	fill()

func _describe(v: VBoxContainer, id: String, ledger: IdeaLedger) -> void:
	var m := main()
	var rec: Dictionary = ledger.ideas[id]
	var stage := int(rec["stage"])
	var seed := stage == IdeaLedger.Stage.SEED
	v.add_child(UiTheme.caps(IdeaLedger.stage_name(stage)))
	v.add_child(UiTheme.wrap(UiTheme.label(ledger.name_of(id) if not seed else "Not yet thought of", "display", 34), 290))
	var desc := str(m.concept_graph.concepts[id].get("description", ""))
	var story := ""
	if seed:
		var pre: Array = m.concept_graph.concepts[id].get("prerequisites", [])
		story = "Nobody has thought of this yet." + (" It needs " + ", ".join(pre.map(func(p): return ledger.name_of(p).to_lower())) + " first." if not pre.is_empty() else " It could come to anyone.")
	else:
		story = "First thought of by %s on day %d." % [rec["first_name"], rec["first_day"]] if int(rec["first_day"]) > 0 else "Known since the first days."
		if stage == IdeaLedger.Stage.WILTED:
			story += " Lost on day %d%s." % [rec["lost_day"], (" with " + str(rec["lost_with"])) if str(rec["lost_with"]) != "" else ""]
		if str(rec["refound_by"]) != "":
			story += " Found again by %s on day %d." % [rec["refound_by"], rec["refound_day"]]
	v.add_child(UiTheme.wrap(UiTheme.label(story, "hand", 19), 290))
	if not seed and desc != "":
		v.add_child(UiTheme.wrap(UiTheme.label(desc, "body", 15, "muted"), 290))
	var alive: int = m.agents.filter(func(a): return not a.is_dead).size()
	v.add_child(UiTheme.label("Held by %d of %d living" % [rec["holders"], alive], "body", 15, "muted"))
	v.add_child(UiTheme.meter(float(rec["holders"]) / maxf(1.0, float(alive)), "cool", 280))
	if int(rec["taught"]) > 0:
		v.add_child(UiTheme.label("Passed on %d times" % rec["taught"], "body", 15, "muted"))
	var leads: Array = []
	for other in m.concept_graph.concepts:
		if id in m.concept_graph.concepts[other].get("prerequisites", []):
			leads.append(ledger.name_of(other) if ledger.stage_of(other) != IdeaLedger.Stage.SEED else "?")
	if not leads.is_empty():
		v.add_child(UiTheme.wrap(UiTheme.label("Leads toward: " + ", ".join(leads), "body", 15, "muted"), 290))
