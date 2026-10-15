# Game design: the single source of truth for what World *is*

`docs/ART_DIRECTION.md` says how it looks; this says what you do and why. The browser concept
piece ([Caddickbrown/World](https://github.com/Caddickbrown/World)) is a **sketch**: we keep its ideas
where they're good, and we're not bound by its code, data or numbers (`docs/PARITY.md` records
each system's verdict). Change this file first, with a reason, before building something it
doesn't describe.

## Pitch

A pocket of people, watched with love. A small island wakes up with forty strangers on it, and
you watch them find fire, fall in love, lose an idea when the last person who knew it dies, and
find it again three generations later. You never control anyone. You watch from the sky, follow
one life closely, or drift among them at ground level as an unseen wisp. The game is noticing:
the moments you were there for, the lives you followed, the guesses you got right.

**Not in this game:** commanding people, building for them, miracles, resources you spend. The
world must turn out the same whether you watched or not.

## Pillars

Every feature must serve at least one. If it serves none, it waits.

1. **Watch, never steer.** The player has no lever on the simulation. Everything the player does
   is reading it: following, listening, guessing, collecting. (Enforced: tests check that
   following and listening change nothing.)
2. **People, not population.** The unit of interest is a person with a name, a face, a family and
   a story. Charts exist, but a life story beats a line graph.
3. **Small and dense.** A world you can hold in your head: one island, about 150 people at most,
   lives you can follow from birth to death in one sitting.
4. **Whimsy.** Warm, funny, gently sad. Ideas grow like plants, guesses earn glimmers, the
   chronicle reads like postcards. Nothing is grim for the sake of it.

## The three ways of looking

| View | How | What it's for |
|---|---|---|
| **The sky** (observer) | Orbit, pan, zoom over the island; pins show people from far away, names and speech up close | Seeing the whole world and spotting where things are happening |
| **Following** | Click anyone: the camera rides with them, their card shows what they're doing, thinking and who they love | Living one life alongside them |
| **Walking among them** (the wisp) | Tab drops you to the ground as an unseen wisp; WASD to drift, E to listen in on whoever's beside you | Being *there*: close enough to hear the thought, see the fire light faces |

**The wisp is unseen.** Nobody can see or hear it, and the simulation does not know it exists:
it can't block, startle, teach or help. Listening in shows the person's thought in a bubble
over their head (in brackets, to say it's unspoken) and opens their card. That's all.

## What you collect (the "game" in a game you don't control)

| System | What it is | Why it's fun |
|---|---|---|
| **Moments album** | Stickers for things you witnessed: a first fire, two people pairing up, a rainbow after a storm, someone living to old age, the whole island at once. Unlocked only if you were watching (on screen or following) when it happened | Gives watching a goal and rewards attention, not speed |
| **Life stories** | Any person's story told as a storybook page: born to whom, firsts, love, children, ideas they carried and taught, and when they die, their last line. Press a life into the album to keep it after the world ends | The emotional core: people you followed are remembered |
| **The Idea Garden** | The concept tree, drawn as a garden: seeds (unthought), sprouts (a few know), blooms (most know) and **wilted** (lost when the last person who knew it died). Lost ideas can be rediscovered | Knowledge is fragile, which makes every teaching moment matter |
| **Hunches** | Small predictions you can lock in: "Who discovers cooking first?", "Will herb lore be found again before day 20?" Right guesses add **glimmers** to a jar. Glimmers buy nothing; they just glow | Turns watching into anticipation, without giving you a lever |
| **Postcards** | A world is a seed; share it as a postcard. A friend gets the same island and a different story | Replay and sharing without saves |
| **The chronicle** | The history log as a pile of postcards (people / ideas / world), written in a warm voice | Catch up on what happened while you were looking elsewhere |

## The world

- **One island.** The map falls off to the sea at its edge (no square slab). 128×128 tiles,
  2 m each: about 256 m across, so about a minute to cross as the wisp.
- **Time.** One day = 120 s at 1× (snail). 5× (rabbit) and 20× (bird) for skipping. Seasons are
  7 days, starting in spring, so a sitting sees the year turn.
- **People.** 40 founders arrive as young adults. A life is 6–10 days (12–20 min at 1×). At most
  150 people. Measured with `tools/balance.gd`: from 3 seeds, worlds grow to the cap by about
  day 4, crash from starvation when food runs short, and recover. That boom and bust is drama we keep,
  but extinction should be rare and earned.
- **Conflict.** Only between members of different settlements, and only when someone is going
  hungry. Strangers don't fight for no reason.

## A day in the life (what the simulation does, so there's something to watch)

| When | What people do | Why it's there |
|---|---|---|
| Dawn | Hungry people go foraging; hunters stalk deer and rabbits | The day starts with purpose |
| Day | Gather, fish, hunt, wander, meet; children stay near a parent; parents feed hungry children | Families read as families from the sky |
| Dusk | Settled people walk home and sit in a ring round their hearth | The best moment to watch: faces in firelight |
| Evening | Stories round the fire spread ideas twice as fast | Knowledge has a place it lives |
| Night | Sleep where they sat | The camp at night is a picture |

Longer rhythms:
- **Teaching.** Simple ideas (fire, swimming) anyone can copy; crafts (era 2+) must be taught
  by an adult, more slowly, and children learn best from their parents. A craft held by a few
  can die with them; that's how the Idea Garden wilts.
- **Moving on.** When the land round a hearth stays stripped for two days, the camp packs up and
  walks to better ground, 10–28 tiles away.
- **Grief.** When someone dies, their partner, children and parents mourn for half a day.
  The body lies where they fell for half a day, then is buried (the Lives screen keeps them).
- **Living woods.** Trees have a size: seedlings reach full height in about three days of
  spring or summer and barely grow in winter. Woods creep into the meadows next to them as
  seedlings; grown woodland beside forest slowly turns to pine. Once people know
  woodcutting they fell grown trees near camp (stumps, then a sapling a day later), and
  timber is what turns a camp of tents into a hamlet of huts (12) and a town (30). The hearth
  burns a little each night. Forestry (a new idea, after woodcutting and plant lore)
  replants what is felled and plants groves on bare ground round home. Fire leaves black
  snags for a day, then open ground that the woods around seed again. Moments: "The first
  axe", "A tree for later", "The woods come back".
- **The larder.** What a forager gathers beyond their own fill they carry home to the camp
  store; whoever comes home hungry (most often at the evening fire) eats from it. Stores spoil
  in about two days, eight once the camp knows fermentation, so a preserving idea is what
  turns a good summer into a survivable winter.

### Balance, as measured (tools/balance.gd, 14 days, everything merged)

| Seed | Ideas | Deaths: old age / starvation / predators | Woods start → end, felled, plantings | Camps / hamlets / towns |
|---|---|---|---|---|
| 1 | 49 | 43 / 6 / 2 | 1769 → 1882, 146, 28 | 2 / 5 / 4 |
| 3 | 15 | 83 / 13 / 0 | 2190 → 2171, 0, 0 | 8 / 2 / 0 |
| 5 | 39 | 46 / 5 / 1 | 2942 → 2919, 163, 13 | 2 / 8 / 4 |

Open: seed 3 never finds stone tools in 14 days (so no woodcutting, no towns); ideas are still
never lost (open decision 0).

## Built out from the prototype

Every concept in the original browser prototype has been audited against this build and built
out; each area has its notes (rules, numbers, what is still open):

| Area | Notes | In short |
|---|---|---|
| Wild things | `docs/features/wildlife.md` | Whales, fish shoals (fishing follows them), frogs, bird flocks, robins, butterflies, midges, wild bees (honey) |
| Animal minds | `docs/features/animals.md` | Packs and herds, fear of people, rare predator attacks on the weak, dogs, horses and riders, kept flocks, eagles on thermals, culls that stick |
| Sky and seasons | `docs/features/sky.md` | Weather where you look, clouds, rain curtains, lightning, rainbows, stars, seasons on land and trees, droughts, floods, blight |
| Ideas that matter | `docs/features/ideas.md` | Every idea effect and items.json key read by code (tested); firsts in the chronicle |
| Places and maps | `docs/features/places.md` | Buildings from ideas, worn paths, discovery glow, minimap, inspect, Island screen, seed |

## Milestones

| # | Name | Done when |
|---|---|---|
| M0 | Foundation ✅ | AGENTS.md, this file, tests + CI, capture tool, balance probe; season, conflict, height and lifespan fixes |
| M1 | Three views ✅ | Sky, follow and wisp views; follow card, almanac bar, chronicle in the new UI (both looks, T to switch) |
| M2 | New look ✅ (first pass) | Island, smooth terrain, sea, sky, flora, people and settlements per `docs/ART_DIRECTION.md`. Weather: overcast and rain done. Next: animals in the same style, grass and flowers, a rainbow |
| M3 | Stories ✅ (first pass) | Chronicle voice, life records and last lines, the Lives screen. Next: family twig drawing, "press a life" into the album |
| M4 | Collecting ✅ (first pass) | Album of 29 moments (witness rule: on screen within 200 m, or following), the Idea Garden, hunches and glimmers. Next: more moments, ideas actually being lost (see open decisions) |
| M5 | Postcards and polish | Seed postcards, save/continue, sound, settings, controller, a minimap |

Each milestone ends with the standard shots (`tools/capture/shots.sh`), an independent review
against this file and `ART_DIRECTION.md`, and a green `tests/run_ci.sh`.

## Open decisions

0. **Ideas are never lost in practice.** With the current spread rate an idea
   reaches most people within a day or two, so nobody is ever its last holder
   (0 losses in 3 seeds x 15 days, `tools/balance.gd`). Options: slower spread
   for crafts that need teaching (pottery, metalwork) than for ideas anyone can
   copy, or ideas held only by a camp that is wiped out. Proposal: per-idea
   "needs a teacher" flag; measure before and after.
1. **Witnessing rule for the album.** "On screen" (simple) or "on screen and close enough to read
   names" (rewards zooming in)? Proposal: the latter.
2. **Do lost ideas come back easier?** Rediscovery could be faster near where the idea was last
   known (a "ghost" of it). Proposal: yes, a small bonus, so wilting is sad but not hopeless.
3. **What does the game call itself?** "World" is a working title.
