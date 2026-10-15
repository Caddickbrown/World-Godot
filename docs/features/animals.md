# Animal minds

Built by the animals agent (interrupted by a container restart before rendering, tests or notes);
finished by the integrator. Code: `scripts/simulation/AnimalSim.gd` (how animals move),
`scripts/simulation/AnimalMinds.gd` (what passes between animals and people), tests
`tests/suites/20_animals.gd`.

- **Packs and herds.** Wolves run in packs and hunt together; horses, deer, sheep and cattle drift in
  loose herds and bolt together. Eagles ride thermals over high ground, circle and stoop on rabbits.
- **Fear.** Herbivores keep their distance from people (fear rises while someone is close, more for
  hunters); a hunt is now a chase: the prey bolts and tires. A hunter's dog finds game 4 tiles further.
- **Danger.** Rarely (never in the first two days, at least two days apart island-wide) a hungry wolf
  or bear goes for someone weak or alone: a child out of sight, the sick, someone far from camp at
  night. Two adults or a dog nearby drive it off. Survivors and witnesses remember the place and
  keep 6 tiles from predators after.
- **Dogs and horses.** Someone who knows animal domestication can tame a wolf beside them (a dog
  that follows and guards); horse taming gentles a wild horse that is theirs (they will walk out to
  a herd to find one). On a trip of 4+ tiles they ride: 1.8x on open grass, about 1x in forest, drawn
  in the saddle. Up to 10 dogs and 12 horses island-wide.
- **Kept animals.** Camps that know herding or domestication keep sheep, cows or pigs near the hearth
  (recruited from wild herds), spared by the population cull; a coop keeps hens. Wild rabbits breed
  in warrens; someone who knows conservation brings back a species that died out.
- **Deaths that stick.** PopulationManager's culls used to set health to 0 only, so culled animals
  kept walking; they now die properly, their bodies lie a while, then leave the list.
- **Animation.** Clips are found by keyword ("idle breath", "walk", "run", "eat", "flying"),
  skipping transitions and attacks; exact-name matching had fallen through to each file's first
  clip, so deer played their attack forever and cows "Attack" at rest.

Capture: `--rider` follows someone on horseback (with `--teach=horse_taming`).
Open: no collar on dogs (they read as wolves at a person's heels); the rider's seat height is one
number for every horse; sheep still sometimes look as if lying down at steep camera angles.
