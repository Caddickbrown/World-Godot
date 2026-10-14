# Lessons

Every fix that taught us something goes here, so the next change starts smarter.
One line of cause, one line of rule.

## Simulation

- **Every world died of old age by day 4–7.** Lives were 180–360 s (1.5–3 days), too short to
  replace themselves. The soak harness hid it: its "scholar" knew every concept, and concepts
  stretch lifespans. Rule: judge balance with `tools/balance.gd` on the real Main scene and
  several seeds, never from a harness that rigs the world.
- **Forty founders "clashed" in the first minute.** Factions were `agent_id % 2`, splitting
  families down the middle, and the 20% roll ran every frame. Rule: factions come from
  settlements; any chance "per second" is multiplied by delta.
- **Day 1 was winter at -15°C.** A 365-day year started in winter, with a 120 s day.
  Rule: tune calendars to a sitting. Seasons are 7 days, and the year starts in spring.
- **Population ran to 1,000.** Capacity was a land formula (1,614 on a 128² map). Rule: cap
  people at what an observer can follow (`World.max_population`, 150).

## Code

- **Clicking a person crashed.** `Main` set `agent.selected`, which `Agent` never declared;
  GDScript only reports that when the line runs. Rule: an integration test drives every input
  path (follow, walk, listen) through the real scene.
- **Pausing froze the overlays.** `_process` returned before the renderers updated when time
  was stopped. Rule: what you see (labels, pins, panels) updates every frame; only the
  simulation pauses.
- **People and props were buried.** Renderers placed everything at y = 0 while the terrain sits
  at `elevation × HEIGHT_SCALE`. Rule: anything standing on the ground uses `World.surface_y()`.
- **New `class_name` scripts "didn't exist".** The class cache lives in `.godot/`, which is
  gitignored. Rule: run `--headless --editor --quit` after adding a class (`tests/run_ci.sh` does).

## Design

- **"Walking among them" meant unseen, not visiting.** The first build had people stop, turn and
  greet the walker. Rule: the player never changes the world, even socially. The wisp only
  listens (pillar 1).

## Visuals

- **The tiled look read as a spreadsheet.** Flat 2 m tiles stepped every border and the people
  were specks. Rule: smooth relief, colour from the continuous biome field, and people with big
  heads and bright tunics. See `docs/ART_DIRECTION.md`.
- **The world ended in a square cliff.** Rule: the map is an island; land falls to the sea at
  the edge.
- **A flat "trampled ground" disc floated on the slope.** Rule: paint ground marks into the
  terrain's vertex colour, never as a slab on top.
- **Headless shots can be the real renderer.** Mesa's lavapipe (`mesa-vulkan-drivers`) runs
  Forward+ under `xvfb-run`, so review shots match the game.
