class_name AudioSystem
extends Node
## Main's handle on sound. It owns the Soundscape (the island's living sound,
## scripts/audio/) and keeps Main's old calls (play_birth, play_death...) as
## gentle stingers instead of the beeps they were. Sound only reads the world.
##
## Hooks for other systems (connect a signal straight to these):
##   on_festival_started(kind, pos)   pos: tile Vector2 or metres Vector3
##   on_festival_ended(kind, pos)
##   on_moment(id, title)             an album sticker was earned (a chime)

var soundscape: Soundscape

func _ready() -> void:
	soundscape = Soundscape.new()
	soundscape.main = get_parent()
	add_child(soundscape)

# ---------------------------------------------------------------------------
# Stingers (Main's calls; names kept)
# ---------------------------------------------------------------------------

func play_discovery() -> void:
	_sting("discovery", 0.8)

func play_birth() -> void:
	_sting("birth", 0.45)

func play_death() -> void:
	_sting("death", 0.45)

func play_weather_change() -> void:
	_sting("weather", 0.5)

func play_disaster() -> void:
	_sting("disaster", 0.8)

func play_achievement() -> void:
	_sting("achievement", 0.8)

## An album moment you witnessed: the gentle chime.
func play_moment() -> void:
	_sting("moment", 1.0)

func on_moment(_id: String = "", _title: String = "") -> void:
	play_moment()

func _sting(kind: String, gain: float) -> void:
	if soundscape:
		soundscape.stinger(kind, gain)

# ---------------------------------------------------------------------------
# Festivals (the festivals feature emits festival_started(kind, pos))
# ---------------------------------------------------------------------------

func on_festival_started(kind = "", pos = null, _a = null, _b = null) -> void:
	if soundscape:
		soundscape.add_festival(str(kind), pos)

func on_festival_ended(_kind = "", pos = null, _a = null, _b = null) -> void:
	if soundscape:
		soundscape.end_festival(pos)
