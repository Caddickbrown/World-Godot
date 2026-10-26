# Generations and legacy

Built on branch `feat/generations`. Pillars: **people, not population** (families you can read
three generations deep) and **whimsy** (names that come back, stories round the fire, gently sad
when a story is forgotten). Nothing here gives the player a lever: the naming, the legends and
their telling all happen in the simulation, with dice that depend on the world seed only.

## The family register (`scripts/systems/LineageTracker.gd`, simulation side)

LineageTracker used to record only first discoveries (and nothing read it). It is now the
island's memory of who came from whom, keyed by agent id so the dead stay after burial:
name, parents, children, partner, born/died day, age at death, cause, founder, how many people
they taught, whom they were named for, and their camp (refreshed every 3 s while alive).

Main feeds it: founders at `_init_world`, `note_birth` in `_handle_births` (before the child is
drawn or told, so a new name shows everywhere), `note_taught` on every spread event,
`note_death` when a death is logged, and `tick` once a frame before the story. Its events
(`drain_events`) go to `StoryKeeper.on_lineage`.

## Names that carry on

| Rule | Value |
|---|---|
| A child is named for a dead grandparent | 40% when one has died (`NAMED_FOR_GRANDPARENT`) |
| ...else for a legend of the parents' camp | 15% when the camp has one (`NAMED_FOR_LEGEND`) |
| A name worn by anyone living is never given again | so two living people never share a name |
| The dice | `World.roll(world seed, child id, k)`: a hash, never the global RNG, never the player |

The chronicle notes it ("Mara is named for Aya, a grandparent gone before they were born"), both
lives remember it ("Named for Aya." / "Mara was named for them."), and the Lives screen and
follow card say so. People have no gender in the simulation, so words stay neutral
("grandparent", "Old Aya").

## Legends

When someone dies they become a **legend of their camp** if they were the first to think of an
idea, raised 7+ children, taught 100+ people (teaching counts every person taught each idea; measured, the busiest teachers reach 36 to 134), or lived 9+ days (of a 6–10 day life). The deed is
told in their words: "first made fire", "spoke the first words", "raised 7 children",
"lived to a great age".

- **Who knew them:** at death, everyone living in the same camp, plus family.
- **Telling:** an elder at the fire, or awake anywhere in the evening (18:00 to 23:00), with
  no line already in the air, tells a legend they knew (or heard, or a myth of their camp) with
  a chance of 1/25 per second (multiplied by delta). The least-told legend goes first. The line
  is a speech bubble: "My parent Aya first made fire.", "Old Aya first made fire, they say.",
  "Long ago, Aya first made fire, they say." Everyone awake within 5 tiles hears it, and it
  stays on their mind for half a day (listening in shows it as their thought). Nobody tells a
  story to no one. The evening rule is there because, measured, the fire ring is almost always
  empty (12 samples of someone at a fire in 9 days of seed 3), so "at the fire" alone meant one
  telling a world.
- **Fading:** when the last person who knew them has died, the legend fades ("No one is left
  who remembers Aya...") unless a living member of their camp knows **oral tradition**
  (`oral_tradition` in `data/concepts.json`): then it becomes a **myth** and any elder of the
  camp may tell it, for as long as the camp lasts.
- The register rolls its own `RandomNumberGenerator`, seeded from the world seed, so the world's
  dice are untouched (tested).

## Family twig (`scripts/ui/FamilyTwig.gd`)

On a life's page (Lives, L): grandparents, parents, the person and their partner, children and
grandchildren (6 a row, then "+N"), joined by bent twigs. Storybook: ink twigs with a leaf, a
berry dot on the partner line. Field notes: ochre hairlines. The dead are paler; a legend wears
a small star. Click a relative to open their life. Great-grandchildren are counted under it.
The follow card adds "Named for Aya." and "3 grandchildren.".

## Pressing a life (`scripts/story/PressedLife.gd`)

"Press into the album" on any life page keeps a page (name, span, last line, legend, family,
firsts, the last 10 events) in the album save (`Moments.pressed`, up to 30, across worlds).
Someone you are following when they die is pressed for you. Pressing again updates the page.
The album has a "Pressed lives" tab.

## Album moments

| Moment | When | Witness |
|---|---|---|
| Named for them | a child is named for someone gone | at the birth |
| Four generations | a child is born while a great-grandparent lives | at the birth |
| A legend told | an elder tells a legend at the fire | the teller or a listener on screen |
| Into myth | a legend outlives everyone who knew them | world-wide |
| Pressed flower | you press a life | always |

## Tests

`tests/suites/71_generations.gd`: the register, naming (rate, never a living grandparent, no
two living namesakes, deterministic), four generations, legends (who, deed, telling, hearing,
thoughts), fading and myth, telling per second not per frame, no global dice, the story and
album (chronicle lines, moments, pressing across a reload), and the twig in both looks.

## Measured

`tools/balance.gd --days=14` (it now prints a `generations:` line), with evening telling but
the teaching legend still at 30 taught (since raised to 100, which removes most of the
"taught" legends: they were 22 of 39 in seeds 1 and 3):

| Seed | Deaths | Legends | Tellings | Named for someone | Four generations |
|---|---|---|---|---|---|
| 1 | 17 | 15 | 31 | 2 | 4 |
| 3 | 47 | 30 | 82 | 17 | 33 |
| 5 | 71 | 47 | 42 | 24 | 56 |

Four generations is common (lives of 6-10 days, adults at day 2), so only the first is told
loudly in the chronicle; the rest are minor (shown for people you follow).

## Open

- Legends belong to a camp id; a camp that dissolves takes its untold legends with it.
- The twig shows two generations either side; deeper lines are only counted.
