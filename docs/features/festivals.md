# Festivals and the year's rhythm

Built on `feat/festivals`. Pillars: whimsy (days worth being there for), people not population
(they dance, eat and remember together), watch never steer (the simulation keeps the days; the
hints only move the camera).

## The festivals (FestivalSystem, `scripts/systems/FestivalSystem.gd`)

A camp of at least 4 keeps a festival when it knows enough, on its day and hour. Seasons are 7 days,
so day N of a season is world day `season * 7 + N + 1` (year 1).

| Festival | When | The camp must know | What happens | Album |
|---|---|---|---|---|
| Spring sowing | spring, 2nd day, 07:00–10:30 | agriculture | a line of people walks up and down a meadow past the houses; a seed basket | "The first sowing" |
| Midsummer fire | summer, 4th day, 19:00–23:30 | fire, and one of animism, ritual, art, music, mythology | a bonfire with sparks at the hearth; two rings dance round it, turning opposite ways, hopping (with music if they know it) | "Midsummer fire" |
| Harvest feast | autumn, 3rd day, 17:00–21:00 | agriculture | one long table with benches, a cloth and the harvest on it, in the meadow past the houses; the larder is shared out, hungriest first | "The harvest feast" |
| Day of remembering | autumn, 6th day, 16:00–19:00 | animism, and someone of the camp has died since it last remembered | a crescent stands at the shrine, facing it; candles and a wreath; the chronicle names the dead; grief halves | "Remembering" |
| Midwinter lights | winter, 4th day, 17:00–22:00 | fire, and oral tradition or mythology | lanterns on poles round the hearth, the camp seated in a ring (at the fire: stories carry twice as far) | "The longest night" |

- **Calendar.** A camp that knows calendar (`times_seasons`) keeps the exact day; one without guesses,
  a day early, on time or a day late, fixed per camp and festival (from the camp's id; never rolled).
- **Who comes.** Members within 40 tiles who aren't asleep, trading, afloat or at another festival,
  have eaten (hunger above 0.4; anyone comes to the feast) and aren't exhausted. They leave to eat if
  hunger drops below 0.3 (at the feast, not before it's served), if energy drops below 0.08, or if
  something else takes them away (a hunt, a tree). (At 0.25 / 0.15, starvation deaths went up
  about a third over 24 days: people danced late and slept hungry.) Measured below.
- **After.** Everyone there when it ends gets `ritual_morale` (game seconds of lighter energy drain,
  the same lift rituals and music give): sowing 30, midsummer 60 (x1.3 with music), feast 50,
  remembering 40, midwinter 60, scaled by cosmology's morale bonus. Those who leave early get half.
- **The feast makes no food.** It moves the camp store into bellies (up to 0.5 each, hungriest
  first); tested to conserve the total.
- **Once a year** per camp and kind; one festival at a time per camp.
- The agent side is one state, `Agent.State.FESTIVAL`, and three fields (`festival`,
  `festival_pose`, `festival_focus`). FestivalSystem sets the spot each frame for a dance or a
  sowing line; the agent walks there, faces the fire, table or shrine, and keeps socialising.

## For sound (and anyone else)

```gdscript
main.festival_started.connect(func(kind: String, pos: Vector3): ...)   # relayed from main.festival_system
main.festival_ended.connect(func(kind: String, pos: Vector3): ...)
```
`kind` is `planting | midsummer | harvest | mourning | midwinter`; `pos` is world metres on the
ground at the fire, table or shrine. Main's signals survive a new world (R); the system's own
signals (`festival_system.festival_started`) die with it. Under way: `festival_system.active`
(each has `kind`, `focus` tile, `people`, `music`); `FestivalSystem.POSE_DANCE` people are dancing.

## The story

- Chronicle (people): "On midsummer night the people of New Keep lit a great fire and danced round
  it to music." Told once the camp has gathered (half of it, at least 3, or 3 after an hour and a
  half). The first of each kind each year is major; the rest are minor (shown when you follow
  someone there), so nine camps' fires don't flood the HUD.
- A line in the life story of each person there, the first time they keep each kind.
- Album: five moments, a contiguous block at the end of `Moments.DEFS`. The witness rule is the
  album's own (on screen within 200 m, near the wisp, or following someone there), and it is
  checked every game second while the festival lasts, not only at one instant.

## "Something's happening" (Hints, `scripts/ui/Hints.gd`)

A small panel beside the minimap and a round marker per item: over the spot when it's in view, at
the screen's edge with an arrow when it isn't. Click either: the camera goes there
(`Main.look_at_tile`), nothing else. K toggles it (saved with the HUD's settings). At most three,
one of each kind, nearest to where you look, ranked:

1. a festival under way; 2. a life near its end (an old life within about three hours of its end,
or very sick); 3. a festival due within two hours, a new baby; 4. a storm, a new idea (after it was
thought).

It never names anyone and never forecasts an idea, so it can't answer a hunch ("who will first
think of X?"); tested. It looks at the world every 1.5 s (people, camps, the 16 weather zones), never the map.

## Numbers measured

`tools/balance.gd --days=24 --seeds=N --dt=0.05`, one seed per process, before / after:

| Seed | Before: old age / starvation, ideas | After | Festivals held (24 days) |
|---|---|---|---|
| 1 | 124 / 23, 69 | 141 / 24 (+1 wolf), 61 | midsummer 6, harvest 8, remembering 7, midwinter 4 |
| 3 | 116 / 22, 59 | 117 / 25, 60 | midsummer 6, harvest 8, remembering 6, midwinter 3 |

Population runs identical until the first festival (day 10/11), then both sit at the cap of 150.
`tools/profile.gd --days=12 --speed=20 --seed=1`: the festivals stage costs 0.18 ms a frame
(0.1%); whole frames 143.8 vs 145.7 ms, run side by side on a machine at load 17 on 4 cores, so
within noise; worst frames are other stages in both.

## Tests and shots

`tests/suites/73_festivals.gd`: calendar and requirements, a harvest from start to end (gather,
seats, the feast conserving food, the hungry leaving, morale, once a year), the midsummer dance
turning, remembering (needs a death, names them, eases grief, not twice), a real `Agent.tick` at
midwinter (walks there, sits at the fire facing it), the story and album hooks, the renderer (on
the ground, no global RNG), the hints (no names) and, in the real Main, that clicking a hint moves
only the camera.

Capture: `--festival=midsummer|harvest|midwinter|mourning|planting` (with `--sim=900`; `--hour=H`
picks the moment), `--no-hints`.

## Open

- The sim doesn't know where the renderer put the fields, so the sowing and the feast use open
  meadow past the houses, not the drawn fields.
- No festival for first snow yet (snow is a look, not a sim state).
- Dancing is a ring walk plus a hop; no arm movement (the figures have none).
- A birth can't be foreseen (it happens in one frame), so "a new baby" is a hint just after.
