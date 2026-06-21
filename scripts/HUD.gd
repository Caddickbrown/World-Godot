extends CanvasLayer

@onready var lbl_population: Label = $Panel/VBox/Population
@onready var lbl_day: Label        = $Panel/VBox/Day
@onready var lbl_time: Label       = $Panel/VBox/Time
@onready var lbl_season: Label     = $Panel/VBox/Season
@onready var lbl_weather: Label    = $Panel/VBox/Weather
@onready var lbl_era: Label        = $Panel/VBox/Era
@onready var lbl_concepts: Label   = $Panel/VBox/Concepts

@onready var notification_list: VBoxContainer = $Notifications
@onready var game_over_panel: Panel = $GameOver
@onready var go_label: Label = $GameOver/VBox/Label

@onready var agent_panel: Panel = $AgentPanel
@onready var agent_name_lbl: Label   = $AgentPanel/VBox/Name
@onready var agent_state_lbl: Label  = $AgentPanel/VBox/State
@onready var agent_hunger_bar: ProgressBar = $AgentPanel/VBox/Hunger
@onready var agent_energy_bar: ProgressBar = $AgentPanel/VBox/Energy
@onready var agent_age_lbl: Label    = $AgentPanel/VBox/Age
@onready var agent_task_lbl: Label   = $AgentPanel/VBox/Task
@onready var agent_knows_lbl: Label  = $AgentPanel/VBox/Knowledge

const MAX_NOTIFS := 5
var _notifs: Array = []

func _ready() -> void:
	if game_over_panel:
		game_over_panel.visible = false
	if agent_panel:
		agent_panel.visible = false

func update(data: Dictionary) -> void:
	_set_text(lbl_population, "Population: %d / %d" % [data.get("population", 0), data.get("capacity", 0)])
	_set_text(lbl_day,    "Day %d" % data.get("day", 1))
	_set_text(lbl_season, data.get("season", "Spring"))

	var h: float = data.get("hour", 8.0)
	var hh := int(h)
	var mm := int((h - hh) * 60.0)
	_set_text(lbl_time, "%02d:%02d" % [hh, mm])
	_set_text(lbl_weather, data.get("weather", "Clear") + "  " + data.get("temp", ""))
	_set_text(lbl_era, data.get("era", "Stone Age"))

	var concepts: Array = data.get("concepts", [])
	if concepts.is_empty():
		_set_text(lbl_concepts, "No discoveries yet")
	else:
		var recent := concepts.slice(maxi(0, concepts.size() - 4))
		_set_text(lbl_concepts, "\n".join(recent.map(func(c): return c.get("name", "?"))))

	# Agent inspector
	var selected: Agent = data.get("selected_agent", null)
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

	# Tick notifications
	_tick_notifications()

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
		lbl.text = n["msg"]
		lbl.add_theme_color_override("font_color", Color(1, 1, 0.8))
		notification_list.add_child(lbl)

func show_game_over(day: int, discoveries: int) -> void:
	if game_over_panel:
		game_over_panel.visible = true
	if go_label:
		go_label.text = "Civilisation has fallen\nSurvived to Day %d\n%d discoveries" % [day, discoveries]
