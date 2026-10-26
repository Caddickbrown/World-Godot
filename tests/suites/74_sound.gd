extends RefCounted
## Sound: the mixer picks the right layers for a scene, levels follow distance,
## the bank renders clean loops, and the live soundscape reads the world
## without touching it (or the global dice). Runs headless (Dummy driver).

func run(t) -> void:
	_mixer(t)
	_distance(t)
	_land(t)
	_bank(t)
	_settings(t)
	_live(t)

func _mixer(t) -> void:
	var shore_dawn := SoundMixer.mix({"hour": 6.3, "season": "Spring", "sea": 0.55, "woods": 0.3,
		"rain": 0.0, "storm": 0.0, "height": 2.0, "walk": true})
	var inland_rain_night := SoundMixer.mix({"hour": 1.0, "season": "Summer", "sea": 0.0, "woods": 0.6,
		"rain": 1.0, "storm": 0.0, "height": 2.0, "walk": true})
	var inland_night := SoundMixer.mix({"hour": 23.0, "season": "Summer", "sea": 0.0, "woods": 0.2,
		"fresh": 0.6, "rain": 0.0, "height": 2.0, "walk": true})
	t.check("the shore at dawn: the sea (%.2f) and the dawn chorus (%.2f)" % [shore_dawn["surf"], shore_dawn["chorus"]],
		shore_dawn["surf"] > 0.4 and shore_dawn["chorus"] > 0.3 and shore_dawn["bird_rate"] > 0.3)
	t.check("...no crickets, no rain, gulls about", shore_dawn["crickets"] < 0.05
		and shore_dawn["rain_soft"] == 0.0 and shore_dawn["rain_leaves"] == 0.0 and shore_dawn["gull_rate"] > 0.0)
	t.check("inland at night in the rain: rain on the leaves (%.2f), no sea, no birds" % inland_rain_night["rain_leaves"],
		inland_rain_night["rain_leaves"] > 0.4 and inland_rain_night["surf"] == 0.0
		and inland_rain_night["chorus"] < 0.02 and inland_rain_night["bird_rate"] < 0.01)
	t.check("...and the rain hushes the crickets (%.2f vs %.2f dry)" % [inland_rain_night["crickets"], inland_night["crickets"]],
		inland_rain_night["crickets"] < inland_night["crickets"] * 0.3 and inland_night["crickets"] > 0.3)
	t.check("frogs sing by fresh water at night", inland_night["frog_rate"] > 0.1 and shore_dawn["frog_rate"] == 0.0)
	var winter_night := SoundMixer.mix({"hour": 23.0, "season": "Winter", "sea": 0.0, "woods": 0.2, "fresh": 0.6})
	t.check("no crickets or frogs on a winter night", winter_night["crickets"] == 0.0 and winter_night["frog_rate"] == 0.0)
	var spring := SoundMixer.mix({"hour": 6.5, "season": "Spring", "woods": 0.5})
	var autumn := SoundMixer.mix({"hour": 6.5, "season": "Autumn", "woods": 0.5})
	var noon := SoundMixer.mix({"hour": 13.0, "season": "Spring", "woods": 0.5})
	t.check("the dawn chorus is a spring thing (%.2f spring, %.2f autumn, %.2f at noon)" % [spring["chorus"], autumn["chorus"], noon["chorus"]],
		spring["chorus"] > autumn["chorus"] * 2.0 and spring["chorus"] > noon["chorus"] * 2.0)
	var calm_low := SoundMixer.mix({"hour": 12.0, "height": 2.0})
	var high := SoundMixer.mix({"hour": 12.0, "height": 250.0})
	var storm := SoundMixer.mix({"hour": 12.0, "height": 2.0, "rain": 1.0, "storm": 1.0})
	t.check("wind: a breath on the ground (%.2f), more up high (%.2f), most in a storm (%.2f)" % [calm_low["wind"], high["wind"], storm["wind"]],
		calm_low["wind"] < 0.3 and high["wind"] > calm_low["wind"] + 0.3 and storm["wind"] > 0.75)
	var open_rain := SoundMixer.mix({"hour": 12.0, "rain": 1.0, "woods": 0.0})
	t.check("rain in the open is the soft kind", open_rain["rain_soft"] > 0.8 and open_rain["rain_leaves"] == 0.0)
	var rs := SoundMixer.rain_from_overcast(WeatherSystem.OVERCAST[WeatherSystem.WeatherType.RAIN])
	var cs := SoundMixer.rain_from_overcast(WeatherSystem.OVERCAST[WeatherSystem.WeatherType.CLOUDY])
	t.check("rain follows the sky where you look (rain %.2f, cloudy %.2f)" % [rs.x, cs.x], rs.x > 0.9 and cs.x == 0.0)
	var lone_island := SoundMixer.mix({"hour": 12.0, "sea": 1.0})
	t.check("out at sea the birds are gulls, not songbirds", lone_island["chorus"] == 0.0 and lone_island["gull_rate"] > 0.05)

func _distance(t) -> void:
	var ok := true
	var last := 2.0
	for d in [0.0, 2.0, 5.0, 10.0, 20.0, 40.0, 80.0, 200.0]:
		var g := SoundMixer.falloff(d, 9.0, 60.0)
		if g > last or g < 0.0 or g > 1.0:
			ok = false
		last = g
	t.check("a source fades with distance, and is gone past the radius", ok and SoundMixer.falloff(61.0, 9.0, 60.0) == 0.0
		and is_equal_approx(SoundMixer.falloff(9.0, 9.0), 0.5))
	var walk := SoundMixer.hearing(true, 6.0)
	var sky := SoundMixer.hearing(false, 90.0)
	var far := SoundMixer.hearing(false, 320.0)
	# A fire 3 m away for the wisp; the same fire under the sky's ear (0.35 of the camera distance up).
	var g_walk := SoundMixer.falloff(3.0, walk["ref"], walk["radius"]) * float(walk["detail"])
	var g_sky := SoundMixer.falloff(0.35 * 90.0, sky["ref"], sky["radius"]) * float(sky["detail"])
	var g_far := SoundMixer.falloff(0.35 * 320.0, far["ref"], far["radius"]) * float(far["detail"])
	t.check("the wisp hears a hearth closer than the sky does (%.2f > %.2f > %.2f)" % [g_walk, g_sky, g_far],
		g_walk > g_sky and g_sky > g_far)
	t.check("the sky hears farther (radius %.0f m vs the wisp's %.0f m)" % [sky["radius"], walk["radius"]],
		float(sky["radius"]) > float(walk["radius"]) and float(far["radius"]) > float(sky["radius"]))
	t.check("thunder comes later from farther (%.2f s at 20 m, %.2f s at 200 m)" % [SoundMixer.thunder_delay(20.0), SoundMixer.thunder_delay(200.0)],
		SoundMixer.thunder_delay(200.0) > SoundMixer.thunder_delay(20.0) + 1.0)
	t.check("...and quieter, but still a grumble", SoundMixer.thunder_gain(200.0) < SoundMixer.thunder_gain(20.0)
		and SoundMixer.thunder_gain(5000.0) > 0.1)

func _land(t) -> void:
	var w := World.new(7)
	var shore := Vector2i(-1, -1)
	var inland := Vector2i(-1, -1)
	var best_inland := 0
	for z in range(4, w.height - 4, 2):
		for x in range(4, w.width - 4, 2):
			if not w.is_walkable(x + 0.5, z + 0.5):
				continue
			var near_water := 99
			for r in range(1, 16):
				var hit := false
				for k in 16:
					var a := TAU * k / 16.0
					var tt := w.get_tile(int(x + cos(a) * r), int(z + sin(a) * r))
					if tt.is_empty() or int(tt["type"]) in [World.TileType.WATER, World.TileType.DEEP_WATER]:
						hit = true
						break
				if hit:
					near_water = r
					break
			if near_water <= 2 and shore.x < 0:
				shore = Vector2i(x, z)
			if near_water > best_inland:
				best_inland = near_water
				inland = Vector2i(x, z)
	var s := Soundscape.survey_land(w, Vector2(shore) + Vector2(0.5, 0.5), 10.0)
	var i := Soundscape.survey_land(w, Vector2(inland) + Vector2(0.5, 0.5), 10.0)
	t.check("the shore hears the sea (%.2f), inland doesn't (%.2f)" % [s["sea"], i["sea"]],
		shore.x >= 0 and s["sea"] > 0.15 and i["sea"] < 0.05 and s["sea_dir"].length() > 0.02)
	var corner := Soundscape.survey_land(w, Vector2(1, 1), 10.0)
	t.check("off the edge of the island is all sea (%.2f)" % corner["sea"], corner["sea"] > 0.7)

func _bank(t) -> void:
	var t0 := Time.get_ticks_msec()
	SoundBank.build_now()
	print("  sound bank: %.0f ms to render %.0f s of audio" % [SoundBank.build_ms, SoundBank.seconds_of_audio])
	t.check("the bank renders", SoundBank.is_ready() and Time.get_ticks_msec() - t0 >= 0)
	var missing: Array = []
	for n in SoundBank.LOOPS + ["birds", "gulls", "owls", "coos", "frogs", "sheep", "cows", "wolves", "thunder_near", "thunder_far",
			"st_moment", "st_discovery", "st_birth", "st_death", "st_achievement", "st_disaster", "st_weather", "st_festival"]:
		if not SoundBank.names().has(n):
			missing.append(n)
	t.check("every sound is there (%s)" % ", ".join(missing), missing.is_empty())
	var bad: Array = []
	for n in SoundBank.LOOPS:
		var s: AudioStreamWAV = SoundBank.get_stream(n)
		var a := SoundBank.samples_of(s)
		var pk := SoundSynth.peak(a)
		var seam := absf(a[0] - a[a.size() - 1])
		if s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_end != a.size():
			bad.append(n + " not looped")
		if pk >= 0.999 or pk < 0.05:
			bad.append("%s peak %.2f" % [n, pk])
		if seam > 0.1:
			bad.append("%s clicks at the loop (%.3f)" % [n, seam])
	t.check("loops loop, without clipping or a click at the seam (%s)" % ", ".join(bad), bad.is_empty())
	var rng := RandomNumberGenerator.new()
	var shots := 0
	for n in ["birds", "frogs", "wolves", "thunder_near"]:
		var st: AudioStreamWAV = SoundBank.pick(n, rng)
		if st and st.loop_mode == AudioStreamWAV.LOOP_DISABLED and SoundSynth.peak(SoundBank.samples_of(st)) < 0.999:
			shots += 1
	t.check("calls play once and don't clip", shots == 4)
	var chime := SoundBank.samples_of(SoundBank.get_stream("st_moment"))
	t.check("the album chime is gentle (peak %.2f, %.1f s)" % [SoundSynth.peak(chime), chime.size() / float(SoundSynth.SR)],
		SoundSynth.peak(chime) <= 0.7 and chime.size() > SoundSynth.SR)

func _settings(t) -> void:
	SoundSettings.path = "user://test_sound_settings.json"
	SoundSettings.ensure_buses()
	var ok := true
	for b in SoundSettings.BUSES:
		if AudioServer.get_bus_index(b) == -1:
			ok = false
	t.check("the mixing desk has Master, Ambience, Effects and UI", ok)
	t.check("...each feeding Master", AudioServer.get_bus_send(AudioServer.get_bus_index("Ambience")) == &"Master")
	var was: bool = SoundSettings.muted
	SoundSettings.toggle_mute()
	t.check("N hushes everything", AudioServer.is_bus_mute(0) != was)
	SoundSettings.toggle_mute()
	t.check("...and brings it back", AudioServer.is_bus_mute(0) == was)
	var keep: float = SoundSettings.volumes["Ambience"]
	SoundSettings.set_volume("Ambience", 0.5)
	t.check("a volume slider sets its bus", absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")) - linear_to_db(0.25)) < 0.01)
	SoundSettings.set_volume("Ambience", keep)
	var panel := SoundSettings.panel()
	t.check("the Look screen's sound card builds", panel != null)
	panel.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SoundSettings.path))
	SoundSettings.path = "user://sound_settings.json"

func _live(t) -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.album_path = "user://test_sound_main.json"
	main.world_seed = 7
	t.add_child(main)
	var ss: Soundscape = main.audio_system.soundscape
	t.check("Main has a soundscape that reads it", ss != null and ss.is_inside_tree() and ss.main == main)
	main.time_system.set_speed(0.0)
	ss.tick(0.3)
	var beds_ok := true
	for b in SoundMixer.BEDS:
		if not ss.levels.has(b):
			beds_ok = false
	t.check("a tick surveys the scene and mixes every bed", not ss.scene.is_empty() and beds_ok)
	# The global dice are the simulation's: sound never draws from them.
	seed(4242)
	var expect := randi()
	seed(4242)
	for i in 20:
		ss.tick(0.25)
	ss.on_lightning(main.observer.target + Vector3(30, 0, 0))
	for i in 10:
		ss.tick(0.25)
	t.check("the soundscape never touches the global RNG", randi() == expect)
	# The sky over the shore vs over the middle of the island.
	var w: World = main.world
	var shore := Vector2(-1, -1)
	var inland := Vector2(-1, -1)
	var best := -1.0
	var most_sea := 0.0
	for z in range(6, w.height - 6, 3):
		for x in range(6, w.width - 6, 3):
			if not w.is_walkable(x + 0.5, z + 0.5):
				continue
			var land := Soundscape.survey_land(w, Vector2(x + 0.5, z + 0.5), 8.0)
			if land["sea"] > most_sea:
				most_sea = land["sea"]
				shore = Vector2(x + 0.5, z + 0.5)
			var d := 1.0 - float(land["sea"])
			if d >= best and land["sea"] == 0.0:
				best = d
				inland = Vector2(x + 0.5, z + 0.5)
	main.observer.distance = 40.0
	main.observer.look_at_point(Vector3(shore.x, 0, shore.y) * World.TILE_SIZE)
	ss.survey()
	var shore_surf: float = ss.levels["surf"]
	main.observer.look_at_point(Vector3(inland.x, 0, inland.y) * World.TILE_SIZE)
	ss.survey()
	var inland_surf: float = ss.levels["surf"]
	t.check("looking at the shore you hear the sea (%.2f), inland hardly (%.2f)" % [shore_surf, inland_surf],
		shore_surf > 0.25 and shore_surf > inland_surf + 0.2)
	# A hearth by the wisp: heard clearly on foot, faintly from the sky.
	main.set_view_mode(main.ViewMode.WALK)
	var wt: Vector2 = main.wanderer.tile_pos
	var key := "%d,%d" % [int(wt.x) + 1, int(wt.y)]
	var had: bool = w.natural_fires.has(key)
	w.natural_fires[key] = {"end_time": 1e9}
	ss.survey()
	var on_foot: float = ss.heard_fires[0]["gain"] if not ss.heard_fires.is_empty() else 0.0
	main.set_view_mode(main.ViewMode.OBSERVE)
	main.observer.distance = 200.0
	main.observer.look_at_point(main.wanderer.world_position())
	ss.survey()
	var from_sky: float = ss.heard_fires[0]["gain"] if not ss.heard_fires.is_empty() else 0.0
	t.check("a fire crackles beside the wisp (%.2f) and is faint from the sky (%.2f)" % [on_foot, from_sky],
		on_foot > 0.5 and from_sky < on_foot * 0.5)
	if not had:
		w.natural_fires.erase(key)
	# Thunder after lightning: the sky's bolt reaches the ears, late.
	var before := ss.thunder_pending()
	main.sky.weather_view.strike_at(main.observer.target + Vector3(80, 0, 0))
	t.check("lightning queues its thunder", ss.thunder_pending() == before + 1)
	for i in 40:
		ss.tick(0.1)
	t.check("...which arrives within a few seconds", ss.thunder_pending() == 0
		and int(ss.calls_played.get("thunder_far", 0)) + int(ss.calls_played.get("thunder_near", 0)) >= 1)
	# Stingers: a moment chimes; a rush of births stays calm.
	t.check("an album moment chimes", ss.stinger("moment"))
	t.check("...and two births at once only ring once", ss.stinger("birth") and not ss.stinger("birth"))
	# The festivals hook: a band where it's happening, till it ends.
	main.observer.distance = 40.0
	main.observer.look_at_point(main.wanderer.world_position())
	main.audio_system.on_festival_started("harvest", main.wanderer.tile_pos)
	ss.survey()
	t.check("a festival plays where it is (%.2f)" % ss._spot_target["festival"], ss.festivals.size() == 1 and ss._spot_target["festival"] > 0.2)
	main.audio_system.on_festival_ended("harvest", main.wanderer.tile_pos)
	ss.survey()
	t.check("...and stops when it ends", ss.festivals.is_empty() and ss._spot_target["festival"] == 0.0)
	# Listening changes nothing: the sim's people are as they were.
	var snap: Array = main.agents.map(func(a): return [a.pos, a.state, a.needs.duplicate()])
	for i in 10:
		ss.tick(0.2)
	t.check("sound leaves the world as it was", main.agents.map(func(a): return [a.pos, a.state, a.needs.duplicate()]) == snap)
	main.get_parent().remove_child(main)
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sound_main.json"))
