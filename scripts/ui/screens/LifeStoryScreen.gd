class_name LifeStoryScreen
extends HudScreen
## Lives: the people worth knowing (who you follow, the notable, the founders)
## and the remembered dead, each told as a short story from their LifeRecord.

var _chosen := -1

func kicker() -> String: return "A life, told"
func title() -> String: return "Lives"
func subtitle() -> String: return "Everyone the island remembers: who they were, what they found, who they loved."

func fill() -> void:
	var m := main()
	if _chosen < 0 and m.selected_agent:
		_chosen = m.selected_agent.agent_id
	var row := UiTheme.hbox(28)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(row)

	var list: Array = scroll_column(300, 6)
	(list[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(list[0])
	var col: VBoxContainer = list[1]
	var living: Array = []
	var gone: Array = []
	for id in m.story.lives:
		var life: LifeRecord = m.story.lives[id]
		if life.alive():
			if id == _chosen or life.founder or not life.firsts.is_empty() or life.total_taught() >= 5 or life.children.size() >= 3:
				living.append(life)
		else:
			gone.append(life)
	living.sort_custom(func(x, y): return _weight(x) > _weight(y))
	gone.sort_custom(func(x, y): return x.died_day > y.died_day)
	if _chosen < 0 and not living.is_empty():
		_chosen = living[0].agent_id
	col.add_child(UiTheme.caps("Living", "accent", 12))
	for life in living.slice(0, 40):
		col.add_child(_person_button(life))
	col.add_child(UiTheme.caps("Remembered", "accent", 12))
	if gone.is_empty():
		col.add_child(UiTheme.label("No one has died yet.", "hand", 16, "muted"))
	for life in gone.slice(0, 40):
		col.add_child(_person_button(life))

	var detail: Array = scroll_column(560, 14)
	(detail[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(detail[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(detail[0])
	if m.story.lives.has(_chosen):
		_tell(detail[1], m.story.lives[_chosen])

static func _weight(l: LifeRecord) -> int:
	return l.firsts.size() * 10 + l.total_taught() + l.children.size() * 2 + (3 if l.founder else 0)

func _person_button(life: LifeRecord) -> Button:
	var tag := ""
	if not life.firsts.is_empty():
		tag = " · found " + main().story.ledger.name_of(life.firsts[0]).to_lower()
	elif not life.alive():
		tag = " · day %d" % life.died_day
	var b := UiTheme.button(life.name + tag, life.agent_id == _chosen, 15)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size.x = 280
	b.pressed.connect(func(): _chosen = life.agent_id; _rebuild())
	return b

func _rebuild() -> void:
	for ch in body.get_children():
		ch.queue_free()
	fill()

func _tell(v: VBoxContainer, life: LifeRecord) -> void:
	var m := main()
	v.add_child(UiTheme.label(life.name, "display", 48))
	var born := "Born day %d" % life.born_day
	if not life.parents.is_empty():
		born += " to " + " and ".join(life.parents)
	elif life.founder:
		born = "One of the first forty, woken on the shore"
	var status := " · living" if life.alive() else " · died day %d" % life.died_day
	v.add_child(UiTheme.label(born + status, "body", 17, "muted"))
	if not life.alive() and life.last_line != "":
		v.add_child(UiTheme.wrap(UiTheme.label("“%s”" % life.last_line, "hand", 22, "accent" if UiTheme.style == "fieldnotes" else "warn"), 620))

	var two := UiTheme.hbox(36)
	v.add_child(two)
	var story := UiTheme.vbox(8)
	story.custom_minimum_size.x = 380
	story.add_child(UiTheme.caps("Their days", "faint"))
	if life.events.is_empty():
		story.add_child(UiTheme.label("Nothing remarkable yet.", "hand", 18, "muted"))
	for e in life.events.slice(maxi(0, life.events.size() - 14)):
		var line := UiTheme.hbox(12)
		var d := UiTheme.label("Day %d" % e["day"], "strong", 14, "accent")
		d.custom_minimum_size.x = 64
		line.add_child(d)
		line.add_child(UiTheme.wrap(UiTheme.label(e["text"], "hand", 18), 300))
		story.add_child(line)
	two.add_child(story)

	var side := UiTheme.vbox(10)
	side.custom_minimum_size.x = 260
	side.add_child(UiTheme.caps("Ideas", "faint"))
	var ideas: Array = []
	for id in life.firsts:
		ideas.append("First to think of %s" % m.story.ledger.name_of(id).to_lower())
	for id in life.taught:
		if int(life.taught[id]) >= 2:
			ideas.append("Taught %s to %d" % [m.story.ledger.name_of(id).to_lower(), life.taught[id]])
	if ideas.is_empty():
		ideas.append("Learned what others knew.")
	for t in ideas.slice(0, 6):
		side.add_child(UiTheme.wrap(UiTheme.label(t, "body", 16), 250))
	side.add_child(UiTheme.caps("Family", "faint"))
	side.add_child(UiTheme.wrap(UiTheme.label("Partner: " + (life.partner if life.partner != "" else "none"), "body", 16), 250))
	side.add_child(UiTheme.wrap(UiTheme.label("Children: " + (", ".join(life.children) if not life.children.is_empty() else "none"), "body", 16), 250))
	if life.alive():
		var a: Agent = m._find_agent(life.agent_id)
		if a:
			var follow := UiTheme.button("Follow " + life.name, true, 15)
			follow.pressed.connect(func(): m.follow(a); hud.close_screen())
			side.add_child(follow)
	two.add_child(side)
