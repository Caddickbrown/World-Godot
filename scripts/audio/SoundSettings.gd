class_name SoundSettings
extends RefCounted
## The mixing desk: four buses (Master, Ambience, Effects, UI; the layout is
## default_bus_layout.tres, and they're made here too if it's missing), their
## volumes, mute (N), kept in user://sound_settings.json. `panel()` builds the
## little volume card the Look screen shows.

const BUSES := ["Master", "Ambience", "Effects", "UI"]
const LABELS := {"Master": "All sound", "Ambience": "The island", "Effects": "Creatures & weather", "UI": "Chimes"}
const DEFAULTS := {"Master": 0.8, "Ambience": 0.9, "Effects": 0.85, "UI": 0.7}

static var path := "user://sound_settings.json"
static var volumes: Dictionary = DEFAULTS.duplicate()
static var muted := false
static var _loaded := false

static func ensure_buses() -> void:
	for i in range(1, BUSES.size()):
		var bus: String = BUSES[i]
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")

static func load_settings() -> void:
	ensure_buses()
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			var d = JSON.parse_string(f.get_as_text()) if f else null
			if d is Dictionary:
				for b in BUSES:
					volumes[b] = clampf(float(d.get(b, volumes[b])), 0.0, 1.0)
				muted = bool(d.get("muted", false))
	apply()

static func save_settings() -> void:
	var d := volumes.duplicate()
	d["muted"] = muted
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

## Push the volumes to the buses (a slider's 0..1 is perceptual: squared).
static func apply() -> void:
	for b in BUSES:
		var idx := AudioServer.get_bus_index(b)
		if idx == -1:
			continue
		var v: float = volumes.get(b, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v * v, 0.00001)))
		AudioServer.set_bus_mute(idx, (muted and b == "Master") or v <= 0.001)

static func set_volume(bus: String, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	apply()
	save_settings()

static func toggle_mute() -> bool:
	muted = not muted
	apply()
	save_settings()
	return muted

## A card of sliders for the settings screen (built from UiTheme).
static func panel() -> Control:
	load_settings()
	var p := UiTheme.panel()
	var v := UiTheme.vbox(6)
	p.add_child(v)
	var head := UiTheme.hbox(12)
	head.add_child(UiTheme.caps("Sound", "accent", 12))
	var mute := CheckBox.new()
	mute.text = "Hush (N)"
	mute.button_pressed = muted
	mute.add_theme_font_override("font", UiTheme.font("body"))
	mute.add_theme_color_override("font_color", UiTheme.c("text"))
	mute.toggled.connect(func(on: bool):
		if on != muted:
			toggle_mute())
	head.add_child(mute)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for b in BUSES:
		var l := UiTheme.label(LABELS[b], "body", 15, "muted")
		grid.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = float(volumes[b])
		s.custom_minimum_size = Vector2(170, 20)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.tooltip_text = "%s volume" % LABELS[b]
		s.value_changed.connect(func(x: float): set_volume(b, x))
		grid.add_child(s)
	return p
