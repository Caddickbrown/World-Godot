# Sky and seasons

Built by the sky agent (interrupted by a container restart before it wired anything into Main,
wrote tests or notes); wired, tested and finished by the integrator.

- **Sky** (`SkyLook.gd`, `shaders/sky_world.gdshader`): drifting clouds by day, thicker when
  overcast; at night stars, a Milky Way band, the moon opposite the sun, shooting stars (per second,
  local RNG). Storybook nights are brighter (bigger moon, richer stars) than Field notes.
- **Weather where you look** (`WeatherView.gd`, `WeatherSystem` zones): the overcast and rain you see
  are the 4x4 zone at the camera's focus, blended with its neighbours, not the worst zone anywhere;
  cloud banks and grey rain curtains hang over the other zones; lightning bolts in storms. Lightning
  fires are now a per-second chance (`Main.LIGHTNING_FIRE_PER_SECOND`, was rolled per frame).
- **Rainbow**: when rain over a zone clears in daylight, an arc stands on the far side of it, opposite
  the sun, fading in and out.
- **Seasons on the land** (`SeasonLook.gd`, `terrain_season` / `flora_season` shaders): snow lies in
  winter and the broadleaf go bare; autumn turns them orange, red and gold; spring is fresh green with
  meadow flowers; late summer goes to straw. Continuous blends eased over a season's first days, fed
  as shader uniforms (no rebuild).
- **Disasters** (`DisasterSystem.gd`): a day or three, local, ramping in and out. Drought browns the
  ground and caps what the land yields (to 45% at its heart); blight greys it (30%) and spoils stores
  faster; a flood rises from the sea over low shore and river beds (up to 1.6 m), drowned tiles can't be
  walked and yield nothing, and a water sheet lies over them (`DisasterView.gd`).

Capture: `--season=winter`, `--rainbow`, `--disaster=drought|flood|blight` (at its height; a flood
picks its own place). Tests: `tests/suites/30_sky.gd`.

Integration fixes: the flood was measured from its centre's ground height, so a centre at a hill's
foot drowned all the lowland (now from sea level); `intensity` ramps from zero, so forced disasters
start at mid-duration; terrain repaints a few chunks a frame (`flush_all()` for captures); the
flood sheet's overlapping quads drew a grid; a glossy sheet blew out into glare.

Open: flood edges are tile-blocky (a smoothed shoreline mesh would read better); blight not shot yet;
pines take no snow; clouds can sit between a low camera and the land.
