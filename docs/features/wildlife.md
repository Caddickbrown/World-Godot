# Wild things

Built by the wildlife agent (interrupted by a container restart before it wrote notes; salvaged
and finished by the integrator). Code: `scripts/simulation/AmbientLife.gd` (light simulation,
own RNG), `scripts/renderer/AmbientRenderer.gd` (MultiMeshes), tests `tests/suites/10_wildlife.gd`.

| Creature | Count | Behaviour |
|---|---|---|
| Whales | 3 | Offshore in water at least 4 m deep; dive 35–70 s, surface 10–16 s with a spout, breach about once a game day island-wide |
| Fish shoals | 10 sea, 4 river | 6–10 fish each, drift within 10 m of home; fishing within 5 tiles of a shoal catches x1.6, none in reach x0.7; a catch thins the shoal (one fish back per 30 s) |
| Bird flocks | 3 × 10 | Boids over meadow and coast at 9 m; roost in trees 19:30–05:30 |
| Robins | 8 | Hop round people and camps |
| Butterflies | 28 | Over meadows in spring and summer only |
| Swarms | 8 | Midges over water and woods at dusk |
| Wild bees | 4 nests × 6 | Out 07:00–19:00; nests hang 1.6 m up in the woods |
| Frogs | 14 | By fresh water; croak at dusk |

Hooks into the people's world (the only two): fishing yield follows shoals; someone who knows
honey gathering, hungry and within 12 tiles of a nest, may walk there and eat honey (a nest refills
in a day in spring and summer). `ConceptGraph`'s `near_bee_hive` condition now uses real nests.

Integration fixes: the suite left a test camera and a test Main current, which stole the next
scene's camera (they're now removed from the tree before freeing); `Main._begin` checks it is still
in the tree. The whale's mist was unshaded white and bloomed into a blob (now lit, softer, a
smaller splash). Capture: `--wild=whales|shoals|flocks|robins|butterflies|swarms|hives|frogs`
frames one (a whale is brought to the surface for the shot), `--no-wild` hides them.

Open: the sea has two overlapping water surfaces (a visible rectangle and a sun glare blob at some
angles; water roughness raised 0.08 to 0.2 to soften it, the overlap itself is not fixed); whales can
swim close to the map edge; hives are hard to see from the sky.
