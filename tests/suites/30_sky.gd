extends RefCounted
## Sky and seasons: the calendar's look, weather by zone, the rainbow,
## disasters that change the land, lightning by the second.

func run(t) -> void:
	_seasons(t)
	_weather(t)
	_disasters(t)

func _blend_mid(si: int) -> Dictionary:
	return SeasonLook.blend((si * TimeSystem.SEASON_DAYS + 3.5))

func _seasons(t) -> void:
	var spring := _blend_mid(0)
	var summer := _blend_mid(1)
	var autumn := _blend_mid(2)
	var winter := _blend_mid(3)
	t.check("winter lays snow and bares the broadleaf", float(winter["snow"]) > 0.5 and float(winter["bare"]) > 0.5)
	t.check("summer has no snow", float(summer["snow"]) == 0.0)
	t.check("autumn turns the leaves", float(autumn["autumn"]) > 0.5)
	t.check("spring is fresh and the meadows flower", float(spring["spring"]) > 0.3 and float(spring["bloom"]) > 0.3)
	# Eased, never a cut: the first hours of winter aren't full winter.
	var edge := SeasonLook.blend(3 * TimeSystem.SEASON_DAYS + 0.05)
	t.check("a season comes in gradually (snow %.2f at its first hour)" % float(edge["snow"]), float(edge["snow"]) < float(winter["snow"]))

func _weather(t) -> void:
	var ws := WeatherSystem.new()
	ws.set_zone_state(0, 0, WeatherSystem.WeatherType.STORM)
	ws.set_zone_state(3, 3, WeatherSystem.WeatherType.CLEAR)
	var w := float(World.WORLD_WIDTH)
	var storm_x := w / 8.0
	var clear_x := w - w / 8.0
	t.check("it rains where it rains (zone storm)", ws.is_raining_at(storm_x, storm_x))
	t.check("...and not across the island", not ws.is_raining_at(clear_x, clear_x))
	t.check("the sky is greyer under the storm (%.2f vs %.2f)" % [ws.overcast_at(storm_x, storm_x), ws.overcast_at(clear_x, clear_x)],
		ws.overcast_at(storm_x, storm_x) > ws.overcast_at(clear_x, clear_x) + 0.3)
	ws.force_rainbow(clear_x, clear_x)
	t.check("a rainbow stands where rain has cleared", ws.rainbow and ws.rainbow_pos() != Vector2(-1, -1))
	t.check("...fading in rather than appearing at once", ws.rainbow_strength < 0.05)
	ws._rainbow_timer = WeatherSystem.RAINBOW_SECONDS * 0.6
	t.check("...then standing bright", ws.rainbow_strength > 0.9)
	t.check("lightning fires are a per-second chance", Engine.get_main_loop() != null and load("res://scripts/Main.gd").get_script_constant_map().has("LIGHTNING_FIRE_PER_SECOND"))

func _disasters(t) -> void:
	t.check("disasters last days, not months (drought %.1f days)" % (DisasterSystem.DURATION_DROUGHT / TimeSystem.DAY_LENGTH),
		DisasterSystem.DURATION_DROUGHT <= 3.0 * TimeSystem.DAY_LENGTH)
	var w := World.new(7)
	w.heightfield = Heightfield.new().build(w)
	var meadow: Vector2i = t._first_tile(w, [World.TileType.GRASS])
	var ds := DisasterSystem.new()
	var hist := HistoryLog.new()
	ds.start(DisasterSystem.DisasterType.DROUGHT, 5, hist, w, Vector2(meadow.x + 0.5, meadow.y + 0.5))
	ds.remaining_time = ds.duration * 0.5   # at its height (intensity ramps in and out)
	ds.apply(w, [])
	var mt := w.get_tile(meadow.x, meadow.y)
	t.check("a drought browns the ground where it is (%.2f)" % float(mt.get("drought", 0.0)), float(mt.get("drought", 0.0)) > 0.5)
	t.check("...and the land there yields less (%.2f)" % ds.gather_mult_at(meadow.x + 0.5, meadow.y + 0.5),
		ds.gather_mult_at(meadow.x + 0.5, meadow.y + 0.5) < 0.8)
	var far := Vector2(w.width - meadow.x, w.height - meadow.y)
	t.check("...but not across the island", ds.gather_mult_at(far.x, far.y) > 0.99 or far.distance_to(Vector2(meadow)) < DisasterSystem.DROUGHT_RADIUS)
	var meadow_col := LookStyle.ground(0.1, 2.0, Vector3.UP, {"type": World.TileType.GRASS}, 0.5)
	t.check("a drought browns the meadow's colour", LookStyle.disaster_tint(meadow_col, float(mt.get("drought", 0.0)), 0.0) != meadow_col)
	ds._end(6, hist, w)
	t.check("...and the land recovers when it ends", float(mt.get("drought", 0.0)) == 0.0)
	var wet := {"type": World.TileType.GRASS, "flooded": true, "x": 0, "z": 0}
	t.check("flooded ground can't be walked", DisasterSystem.is_tile_flooded(wet))
	var ft := w.get_tile(meadow.x, meadow.y)
	ft["flooded"] = true
	t.check("...World agrees", not w.is_walkable(meadow.x + 0.5, meadow.y + 0.5))
	ft.erase("flooded")
	# A real flood: picks low ground by a river or the shore, and draws water there.
	var fl := DisasterSystem.new()
	fl.start(DisasterSystem.DisasterType.FLOOD, 5, hist, w)
	fl.remaining_time = fl.duration * 0.5
	fl.apply(w, [])
	var view := DisasterView.new()
	t.add_child(view)
	view.update(fl, w)
	t.check("a flood puts low ground under water (%d tiles), drawn as water" % fl.flooded_count,
		fl.flooded_count > 0 and view.shown == fl.flooded_count)
	fl._end(6, hist, w)
	view.update(fl, w)
	t.check("...and the water goes when it ends", view.shown == 0)
	view.queue_free()
