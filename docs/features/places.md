# Places and maps

Built by the places agent (buildings, paths, history, charts, discovery glow) and finished by the
integrator after a container restart stopped it (wiring, minimap, inspect card, Island screen, seed,
tests, the wall fix).

## Buildings (SettlementRenderer, from Settlement.knowledge_pool; drawn, never known to the sim)

| Building | Appears once the settlement knows | Size |
|---|---|---|
| Shrine | animism or ritual | any |
| Temple | temple | any |
| Church | church | hamlet+ |
| Barn | agriculture or barn | any |
| Fields (seasonal crops) | agriculture | any |
| Workshop | woodworking, pottery, metal tools or metallurgy | any |
| Well and channels | irrigation | any |
| Hen coop | coop, animal domestication or domestication | any |
| Sheep pen | herding or animal breeding | any |
| Tree house | tree house | any |
| Walls with a gate and towers | masonry or architecture | town only |
| Jetty and boat | boat building, sailing or seafaring | by the shore |

Built as one mesh per settlement (PropKit). Walls were first drawn with each block turned along the
radius, so a town read as a ring of stepping stones; they follow the ring now, lower, towns only.

## The watcher's tools
- **Worn paths** (PathSystem, PathRenderer): every game second each moving person adds a footfall
  to their tile (traders x3); wear fades to 55% a day, so an unwalked way greens over. Drawn as
  earth on the heightfield's own grid. A picture only: no simulation reads it.
- **Discovery glow** (AgentRenderer): a ring of light when someone has a new idea, in real time.
- **Click to inspect** (Inspect.gd): clicking anything but a person shows a card: an animal ("Dog ·
  Aman's dog", "Horse · grazing, One of a herd"), a building ("Shrine of Elm Cross, raised day 6"),
  or the ground (meadow, seedlings, felled, burnt, flooded, parched, food left, a worn path). Clicks
  now meet the real ground (they hit a plane at y = 0, metres off on hills).
- **Minimap** (M): the island one pixel per tile, settlements by size, who you follow, and a ring
  for the view; click to look there. Redrawn every 6 s.
- **Island screen** (G, or the Island button): population, ideas held and ever found, and camps,
  hamlets and towns over time, from IslandHistory (sampled every 3 game hours, thinned when full).
- **Seed**: the start screen shows the island's seed; type one, or ask for a different island.

Tests: `tests/suites/50_places.gd`. Capture: `--inspect`, `--screen=island|look`.
Open: inspect has no hover preview; the minimap doesn't show the season; paths are not drawn on
the minimap.
