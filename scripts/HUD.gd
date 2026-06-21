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
		agent_state_lbl.text = Agent.State.keys()[selected.state].capitalize()
		agent_hunger_bar.value = selected.needs.get("hunger", 0.0) * 100.0
		agent_energy_bar.value = selected.needs.get("energy", 0.0) * 100.0
		agent_age_lbl.text   = "Age: %d / %d" % [int(selected.age), int(selected.life_expectancy)]
		agent_task_lbl.text  = selected.task.capitalize() if not selected.task.is_empty() else ""
		var knows := ", ".join(selected.knowledge.keys().slice(0, 6))
		agent_knows_lbl.text = knows if not knows.is_empty() else "—"
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
