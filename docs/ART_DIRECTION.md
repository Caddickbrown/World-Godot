# Art direction: how World looks

Reference: the in-engine mockup (`scripts/mockup/ArtMockup.gd`, rendered by
`tools/capture/mockup.sh`) and the UI design canvas ("World — Whimsy Redesign"). The current
game's tiled look is being replaced; the mockup is the target.

## Two options (undecided)

| | A · Storybook | B · Field notes |
|---|---|---|
| World | Bright greens, turquoise sea, the odd orange tree | Same world graded to warm olive and earth; calmer sea; taller pines; less haze |
| People | Big heads, dot eyes, bright tunics | Real-ish proportions, no eyes drawn, hide and plant-dyed cloth |
| UI | Paper stickers, ink outlines, tilt, Fredoka + Patrick Hand | Dark glass panels, hairlines, no tilt, Alegreya Sans + Alegreya italic; moss `#7E9A6A`, ochre `#C9A04E`, rust `#B5674A`, bone `#ECE6D6` on `#1C2723` |
| Shots | `docs/shots/mockup/m*.jpg` | `docs/shots/mockup/n*.jpg` (`--style=naturalist`) |

The rest of this file describes A; B changes only the values in the table above.

## The look in one line

**A storybook diorama you're peering into:** smooth hills, turquoise shallows, round trees, chunky
readable little people, warm firelight, and a tilt-shift blur that makes it feel like a world on
your desk.

## World

| Element | Rule |
|---|---|
| Terrain | Smooth heightfield (1 m vertices), real relief: meadows roll, forests sit on hills, mountains rise steeply. Colour comes from the same continuous noise as the biome, so borders curve and never step along tile edges |
| Coast | The world is an island: land falls to the sea at the map edge. Sand band by height; wet sand below the waterline. The land/sea corrections are blurred (`Heightfield.BLUR_PASSES`) so the shore curves; only tile centres are held to their tile |
| Water | Depth-coloured: turquoise shallows → teal → ink blue. A broken foam line breathes along the shore |
| Sky and air | Procedural sky, a real sun with soft shadows, light haze into the distance, filmic tonemap. Dusk goes peach, never brown |
| Weather | Rain and storms grey the sky, flatten the sun and thicken the haze (`SkyLook.overcast`, eased, never a cut); rain is streaks in a box over where you're looking. Shot `8_storm` |
| Flora | Two tree families: pines (stacked cones, cool greens) on high ground, broadleaf (clustered balls, warm greens, the odd orange one) lower. Grouped by a slow noise into woods and clearings. Per-tree colour variation |
| Camps | Hide tents (cones), a stone fire ring with a real light, trampled earth painted into the ground (never a decal slab) |

## People

- **Readable from the sky.** Big heads (about a quarter of their height), round bodies, tunics in
  tribe colours (terracotta, ochre, rust, cream), dark eyes bigger than life.
- Children are 0.65 scale. Elders get pale hair.
- From far away, a pin over each head; up close, a name tag; with something to say, a bubble.
- **The wisp** (you, walking): a small pale-blue glowing orb with trailing motes. Plainly not a
  person.

## UI

| Token | Value |
|---|---|
| Ink (text, outlines) | `#22304A` |
| Paper (panels) | `#FFF4E0` |
| Tangerine | `#F0803C` |
| Sun | `#FFD25A` (selection, highlights) |
| Teal | `#1E9E95` (fills); `#17807A` for text on paper |
| Berry | `#D9496B` |
| Meadow | `#6DB04A` |
| Sky | `#BFE3F2` |
| Type | Fredoka (UI, 500–700) and Patrick Hand (anything a person "says" or "writes") |

- Panels are **stickers**: paper fill, 3–4 px ink outline, a solid ink drop-shadow offset
  straight down (no blur), and a slight tilt (±1–4°). Nothing is a plain grey box.
- Speech is white with an ink outline; unspoken thought (listening in) is pale blue and in
  brackets.
- Icons are simple stroke drawings in ink, never emoji. Speeds are a snail, a rabbit and a bird.
- Touch targets at least 44 px. Text on paper at least 4.5:1.

## Review shots

`tools/capture/shots.sh` renders the game's standard shots; `tools/capture/mockup.sh` the
mockup's. Every visual change gets the shots and a review by someone who didn't make the change,
against this file. Feedback must carry a reason.
