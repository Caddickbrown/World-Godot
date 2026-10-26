# Cultures: camps with their own character

Built on branch `feat/cultures`. Every camp becomes recognisably itself, and camps meet: they
visit, marry across, fall out over land (rarely, gently) and make it up, and a crowded camp
founds a daughter camp in its own style.

## A camp's ways (Culture.gd)

| Trait | Comes from | Shows |
|---|---|---|
| Dye (10: madder red, woad blue, weld yellow, moss green, lichen purple, red ochre, sea teal, rose, walnut, chalk) | seeded preference order; the first no living camp wears | everyone's tunic; tents washed in it; pennants, bands, bunting, the hearth banner. Muted towards undyed hide until the camp knows **dyeing** |
| Roofs (6: straw thatch, grey reed, green turf, red ochre, dark heather, birch bark) | seeded, first not in use | hut thatch and town roofs |
| Decoration (6: pennants, antlers, lanterns, painted bands, bunting, carved posts) | seeded, first not in use | on every home |
| Layout density (0.8 close-built .. 1.25 spread out) | seeded | SettlementRenderer's plan: gaps and lane offsets scale with it |
| Favourite food | the camp's own (seeded) order over foods its ideas allow (fish only by water) | follow card, inspect card |
| Known for (craft) | a seeded folk craft (grass dolls, feather charms...) until it knows two craft ideas; then the first of them in its own order, and it sticks | chronicle ("Ash Vale has become known for its baskets."), cards |
| Name style (New X, Little X, Far X, Upper X, X End, X Green) | seeded | names of its daughter camps |

Derived, never rolled: `hash(world seed, settlement id)` through a local RandomNumberGenerator,
so the renderers never touch the global RNG and a world turns out the same whether watched.
Every hearth gets a 7 m banner pole with a drum of cloth in the camp's colour (a flat flag
vanished edge-on), so camps read apart from the sky. Town roofs follow the culture too.

## Meeting (CultureSystem.gd, every 2 game seconds; daily things at midnight)

- **Home and birth.** A person's home camp is where they last slept (membership by distance is
  too fluid to mean "home"); their birth camp is a parent's home when they were born, or "came
  ashore with the first forty". Both on the follow card, with the home camp's ways.
- **Visits.** Each day, for each pair of neighbouring camps (hearths within 34 tiles, both with
  3+ people, not feuding), a 60% chance an unattached adult walks over to sit at the other's
  fire that night (pinned to it), and walks home next morning. 30% of visits end with the
  visitor paired up with someone unattached there.
- **Weddings between camps.** Any couple whose homes differ (from a visit or the ordinary
  pairing of people who forage side by side) is a wedding: the one from the bigger camp moves,
  with their young children, and the ideas they carry join the new camp's pool. The chronicle
  tells it ("Omorom of Stone Gate married Irae of Iron Wood and moved there, bringing weaving with
  them."). Major news when ideas travel, or for the first three.
- **Pins** (SettlementSystem `pin_member`). Membership is by distance from the hearth, so a
  mover would drop out on the walk; a pin keeps them in the new camp (and out of every other)
  until they arrive or two days pass.

## Feuds (gentle, rare, always mended)

- Each day, for each pair of camps within 26 tiles, a 3% chance they fall out "over the hazel
  thicket between them" (doubled on stripped land, 0.4x if either knows diplomacy, governance or
  law). At most one feud on the island at a time; the same pair can't fall out again for 6 days.
- A feud is grumbling (speech bubbles: "That's OUR thicket."), no visits, and shoving: rival
  members side by side clash even when fed (ConflictSystem; a clash costs energy, never a life).
  **Nobody dies of a feud** (ConflictSystem's `trigger_war` is never called).
- Mended in at most 5 days: each day 15% + 20% per day it has lasted (+30% with diplomacy), by
  talking it through, a shared feast from full larders, a wedding between them, or "deciding
  nobody could remember what it was about".

## Daughter camps

- A camp of 16+ people (50% a day) or 9+ after a quarrel round the fire (3% a day), at least two
  days old, sends off a family (a couple and their children first) and a few others, 4–8 people,
  to good land 13–24 tiles away that crowds no one. One split a day on the island; a camp waits 3
  days between splits.
- The daughter copies the mother's ideas and a share of her larder and timber, and her culture:
  same dye drifted 0.05–0.10 in hue, roof kept 70%, decoration 60%, density nudged, craft kept
  half the time. Daughters keep drifting (30% a day, 0.02 hue), and are redrawn when they do
  (budgeted, one place a frame, as before).

## Story

- Chronicle: weddings, feuds and their mending, daughter camps, what a camp became known for.
- Life stories: "Married Irae and moved from Stone Gate to Iron Wood.", "Left Ash Vale to help
  found New Ash Vale."
- Album (Moments, `# cultures (feat/cultures)` block): **A wedding between camps**, **A new camp
  is founded**, **Old quarrel mended**.
- Follow card: "Of Iron Wood · born in Stone Gate", then "Rose hides · loves roast hare · soft
  leather". Inspect card on a building adds the place's ways and its mother.

## Numbers (tools/balance.gd, 14 days; the report ends with a `cultures:` line)

| Seed | Weddings between camps | Visits (paired) | Daughter camps | Feuds (mended) | Killed in quarrels | Pop. day 14 | Starved (before) |
|---|---|---|---|---|---|---|---|
| 1 | 3 | 25 (1) | 3 | 2 (2) | 0 | 150 | 14 (6) |
| 3 | 1 | 23 (2) | 4 | 1 (1) | 0 | 148 | 14 (15) |
| 5 | 7 | 39 (0) | 4 | 3 (3) | 0 | 148 | 14 (11) |

The first cut counted 27–42 weddings a world: membership by distance made foragers "of" any
camp they passed. Weddings now need both to have slept at their home camp two nights running,
and one a day at most. Ideas carried by movers read 0 at 14 days: ideas still reach everyone
within a day or two (GAME_DESIGN open decision 0), so a mover rarely knows something new; the
mechanism is tested and will matter once ideas spread slower.

## Tests and shots

`tests/suites/72_cultures.gd`: derived traits, avoidance, knowledge picks food and craft,
daughters drift, pins hold a walker, a wedding moves the right person and their child and their
ideas, feuds shove but harm no one and always mend, a crowded camp founds a daughter of 4–8 on
good land, story and album, two camps' huts roofed differently, a drift redraws, density spreads
the plan, people wear the dye, drawing leaves the global RNG alone.

Capture: `--pair` looks between the two nearest camps and prints their ways.

## Open

- Dialect (`Settlement.dialect`) still drifts unseen; it could shade the names a camp gives.
- A feud doesn't yet change where people forage.
- Names of children don't follow the camp's style.
