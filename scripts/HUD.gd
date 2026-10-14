extends CanvasLayer

@onready var lbl_population: Label  = $Panel/VBox/Population
@onready var lbl_day: Label         = $Panel/VBox/Day
@onready var lbl_time: Label        = $Panel/VBox/Time
@onready var lbl_season: Label      = $Panel/VBox/Season
@onready var lbl_weather: Label     = $Panel/VBox/Weather
@onready var lbl_era: Label         = $Panel/VBox/Era
@onready var lbl_disaster: Label    = $Panel/VBox/Disaster
@onready var lbl_concepts: Label    = $Panel/VBox/Concepts

@onready var btn_pause: Button      = $Panel/VBox/SpeedPanel/BtnPause
@onready var btn_1x: Button         = $Panel/VBox/SpeedPanel/Btn1x
@onready var btn_5x: Button         = $Panel/VBox/SpeedPanel/Btn5x
@onready var btn_20x: Button        = $Panel/VBox/SpeedPanel/Btn20x

@onready var notification_list: VBoxContainer = $Notifications
@onready var game_over_panel: Panel = $GameOver
@onready var go_label: Label        = $GameOver/VBox/Label

@onready var agent_panel: Panel          = $AgentPanel
@onready var agent_name_lbl: Label       = $AgentPanel/VBox/Name
@onready var agent_state_lbl: Label      = $AgentPanel/VBox/State
@onready var agent_hunger_bar: ProgressBar = $AgentPanel/VBox/Hunger
@onready var agent_energy_bar: ProgressBar = $AgentPanel/VBox/Energy
@onready var agent_age_lbl: Label        = $AgentPanel/VBox/Age
@onready var agent_task_lbl: Label       = $AgentPanel/VBox/Task
@onready var agent_knows_lbl: Label      = $AgentPanel/VBox/Knowledge

@onready var history_panel: Panel        = $HistoryPanel
@onready var history_list: VBoxContainer = $HistoryPanel/VBox/HistoryList

# Built in code (kept out of HUD.tscn): what they're thinking, family, home;
# the walker's prompt; and a one-line reminder of the controls.
var agent_doing_lbl: Label
var agent_thought_lbl: Label
var agent_family_lbl: Label
var prompt_lbl: Label
var hint_lbl: Label

const HINT_OBSERVE := "Click someone to follow · F follow · Tab walk among them · WASD/QE/drag move · Space pause"
const HINT_FOLLOW  := "Following · F or Esc to let go · Tab walk beside them"
const HINT_WALK    := "Walking unseen · WASD move · Shift hurry · mouse look · E listen in · Tab back to the sky"

const MAX_NOTIFS := 5
var _notifs: Array = []
var _main: Node = null  # reference to Main for speed buttons

func _ready() -> void:
	if game_over_panel: game_over_panel.visible = false
	if agent_panel:     agent_panel.visible = false

	# Speed button signals — wired here so HUD.tscn stays signal-free
	if btn_pause: btn_pause.pressed.connect(_on_pause)
	if btn_1x:    btn_1x.pressed.connect(_on_1x)
	if btn_5x:    btn_5x.pressed.connect(_on_5x)
	if btn_20x:   btn_20x.pressed.connect(_on_20x)
	_build_extras()

func _build_extras() -> void:
	if agent_panel:
		# Below the stats panel (and its speed row), not centred over it.
		agent_panel.anchor_top = 0.0
		agent_panel.anchor_bottom = 0.0
		agent_panel.offset_top = 352.0
		agent_panel.offset_bottom = 690.0
		($Panel as Panel).offset_bottom = 342.0
		agent_panel.offset_right = 250.0
		var vbox := agent_panel.get_node("VBox")
		agent_doing_lbl = _small_label(Color(0.8, 0.9, 1.0))
		vbox.add_child(agent_doing_lbl)
		vbox.move_child(agent_doing_lbl, 2)
		agent_thought_lbl = _small_label(Color(1.0, 0.95, 0.8))
		vbox.add_child(agent_thought_lbl)
		vbox.move_child(agent_thought_lbl, 3)
		agent_family_lbl = _small_label(Color(0.85, 0.85, 0.85))
		vbox.add_child(agent_family_lbl)

	prompt_lbl = Label.new()
	prompt_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_lbl.offset_left = -200.0
	prompt_lbl.offset_right = 200.0
	prompt_lbl.offset_top = -90.0
	prompt_lbl.offset_bottom = -60.0
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_font_size_override("font_size", 20)
	prompt_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	prompt_lbl.add_theme_constant_override("outline_size", 6)
	add_child(prompt_lbl)

	hint_lbl = Label.new()
	hint_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_lbl.offset_left = 10.0
	hint_lbl.offset_top = -28.0
	hint_lbl.offset_right = 900.0
	hint_lbl.offset_bottom = -8.0
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	hint_lbl.add_theme_constant_override("outline_size", 4)
	hint_lbl.text = HINT_OBSERVE
	add_child(hint_lbl)

func _small_label(color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(220, 0)
	return l

func set_prompt(text: String) -> void:
	if prompt_lbl:
		prompt_lbl.text = text
		prompt_lbl.visible = not text.is_empty()

func set_view_hint(walking: bool, following: bool) -> void:
	if hint_lbl:
		hint_lbl.text = HINT_WALK if walking else (HINT_FOLLOW if following else HINT_OBSERVE)

func set_main(main: Node) -> void:
	_main = main

# ── Speed buttons ─────────────────────────────────────────────────────────────

func _on_pause() -> void:
	if _main and _main.has_method("_set_speed"): _main._set_speed(0.0)
func _on_1x() -> void:
	if _main and _main.has_method("_set_speed"): _main._set_speed(1.0)
func _on_5x() -> void:
	if _main and _main.has_method("_set_speed"): _main._set_speed(5.0)
func _on_20x() -> void:
	if _main and _main.has_method("_set_speed"): _main._set_speed(20.0)

# ── Main update ───────────────────────────────────────────────────────────────

func update(data: Dictionary) -> void:
	_set_text(lbl_population, "Population: %d / %d" % [data.get("population", 0), data.get("capacity", 0)])
	_set_text(lbl_day, "Day %d" % data.get("day", 1))
	_set_text(lbl_season, str(data.get("season", "Spring")))

	var h: float = float(data.get("hour", 8.0))
	var hh := int(h)
	var mm := int((h - hh) * 60.0)
	_set_text(lbl_time, "%02d:%02d" % [hh, mm])
	_set_text(lbl_weather, str(data.get("weather", "Clear")) + "  " + str(data.get("temp", "")))
	_set_text(lbl_era, str(data.get("era", "Stone Age")))

	# Disaster
	var disaster: String = str(data.get("disaster", ""))
	if lbl_disaster:
		lbl_disaster.visible = not disaster.is_empty()
		if not disaster.is_empty():
			lbl_disaster.text = "⚠ " + disaster

	# Speed indicator
	var speed: float = float(data.get("speed", 1.0))
	_highlight_speed_btn(speed)

	# Concepts
	var concepts: Array = data.get("concepts", [])
	if concepts.is_empty():
		_set_text(lbl_concepts, "No discoveries yet")
	else:
		var recent := concepts.slice(maxi(0, concepts.size() - 4))
		_set_text(lbl_concepts, "\n".join(recent.map(func(c): return str(c.get("name", "?")))))

	# History panel
	_refresh_history(data.get("history", []))

	# Agent inspector
	var selected: Agent = data.get("selected_agent", null) as Agent
	if selected and is_instance_valid(selected) and selected.health > 0.0:
		agent_panel.visible = true
		agent_name_lbl.text  = selected.agent_name
		agent_state_lbl.text = selected.life_stage.capitalize() + (" · " + selected.task.capitalize() if not selected.task.is_empty() else "")
		if agent_doing_lbl: agent_doing_lbl.text = AgentThoughts.doing(selected).capitalize()
		if agent_thought_lbl: agent_thought_lbl.text = "“" + AgentThoughts.thought(selected) + "”"
		if agent_family_lbl: agent_family_lbl.text = str(data.get("selected_family", ""))
		agent_hunger_bar.value = selected.needs.get("hunger", 0.0) * 100.0
		agent_energy_bar.value = selected.needs.get("energy", 0.0) * 100.0
		agent_age_lbl.text   = "Age: %d / %d" % [int(selected.age), int(selected.life_expectancy)]
		agent_task_lbl.text  = str(data.get("selected_home", ""))
		var known: Array = selected.knowledge.keys()
		agent_knows_lbl.text = ("Knows %d: " % known.size() + ", ".join(known.slice(maxi(0, known.size() - 5)))) if not known.is_empty() else "Knows nothing yet"
		agent_knows_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		if agent_panel: agent_panel.visible = false

	_tick_notifications()

# ── History ───────────────────────────────────────────────────────────────────

func _refresh_history(entries: Array) -> void:
	if not history_list: return
	for child in history_list.get_children():
		child.queue_free()
	var icons: Dictionary = {
		"discovery": "💡", "birth": "👶", "death": "💀",
		"disaster": "⚠", "achievement": "🏆", "conflict": "⚔",
		"war": "🔥", "trade": "🤝", "craft": "🔨",
		"ecology": "🌿", "disease": "🤒", "milestone": "⭐",
	}
	for entry in entries:
		var lbl := Label.new()
		var etype: String = str(entry.get("type", ""))
		var icon: String = str(icons.get(etype, "•"))
		lbl.text = icon + " " + str(entry.get("msg", ""))
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		history_list.add_child(lbl)

# ── Speed highlight ───────────────────────────────────────────────────────────

func _highlight_speed_btn(speed: float) -> void:
	var active := Color(0.9, 0.7, 0.1)
	var inactive := Color(1, 1, 1)
	if btn_pause: btn_pause.modulate = active if speed == 0.0 else inactive
	if btn_1x:    btn_1x.modulate   = active if speed == 1.0 else inactive
	if btn_5x:    btn_5x.modulate   = active if speed == 5.0 else inactive
	if btn_20x:   btn_20x.modulate  = active if speed == 20.0 else inactive

# ── Notifications ─────────────────────────────────────────────────────────────

func _set_text(lbl: Label, text: String) -> void:
	if lbl: lbl.text = text

func show_notification(msg: String) -> void:
	_notifs.append({"msg": msg, "timer": 4.0})
	_refresh_notifications()

func _tick_notifications() -> void:
	for i in range(_notifs.size() - 1, -1, -1):
		_notifs[i]["timer"] -= get_process_delta_time()
		if _notifs[i]["timer"] <= 0.0:
			_notifs.remove_at(i)
	_refresh_notifications()

func _refresh_notifications() -> void:
	if not notification_list: return
	for child in notification_list.get_children():
		child.queue_free()
	var recent := _notifs.slice(maxi(0, _notifs.size() - MAX_NOTIFS))
	for n in recent:
		var lbl := Label.new()
		lbl.text = str(n["msg"])
		lbl.add_theme_color_override("font_color", Color(1, 1, 0.8))
		notification_list.add_child(lbl)

func show_game_over(day: int, discoveries: int) -> void:
	if game_over_panel: game_over_panel.visible = true
	if go_label:
		go_label.text = "Civilisation has fallen\nSurvived to Day %d\n%d discoveries" % [day, discoveries]
