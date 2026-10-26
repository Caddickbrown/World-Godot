# Ideas that matter

Started by the ideas agent (ConceptEffects, the effect rules, items, data); the agent was stopped
by a container restart half-way through Agent.gd, and the integrator finished it: the missing
helpers (firsts, foraging, warmth, the evening hearth, fishing spots, far shores, health rates),
and the 19 effects nothing read yet (teaching, peace, larders, burial, temples, trade reach,
tracking, maps, myths, felling and replanting, conservation, buildings, stone towns).

Every effect key in `data/concepts.json` is declared in `ConceptEffects.RULES` (how several
combine and the clamp), and `tests/suites/40_ideas.gd` fails if one is not read by some code,
or if an `items.json` key is not. Firsts (`Agent._deed`) are told once per world in the chronicle
and the person's life story.

| Idea | Era | What it does |
|---|---|---|
| Clothing | 1 | weather_protection 0.2; max_age_bonus 0.08 |
| Cooking | 1 | hunger_efficiency 1.6; max_age_bonus 0.2; cooks_food |
| Fire | 1 | max_age_bonus 0.15; warmth_satisfied; weather_protection 0.25 |
| Fishing | 1 | gather_efficiency 1.1; can_fish |
| Honey Gathering | 1 | honey_food |
| Hunting | 1 | gather_efficiency 1.1; forest_bonus |
| Language | 1 | spread_rate_multiplier 2.0 |
| Medicine | 1 | max_age_bonus 0.2; herb_healing; vitality_regen 0.0008 |
| Observation | 1 | discovery_bonus 1.05 |
| Plant Lore | 1 | gather_efficiency 1.1; safe_foraging |
| Rope | 1 | rest_efficiency 1.1; carrying_capacity_bonus 1.1 |
| Rope Making | 1 | rest_efficiency 1.05 |
| Shelter | 1 | rest_efficiency 1.5; max_age_bonus 0.1; weather_protection 0.35 |
| Stone Tools | 1 | gather_efficiency 1.25 |
| Swimming | 1 | unlocks_wading |
| Tanning | 1 | weather_protection 0.1; builds: drying_racks |
| Tracking | 1 | gather_efficiency 1.05; reads_tracks |
| Weaving | 1 | rest_efficiency 1.2; carrying_capacity_bonus 1.2 |
| Woodcutting | 1 | wood_gathering |
| Agriculture | 2 | gather_efficiency 1.1; grass_bonus; carrying_capacity_bonus 1.25; max_age_bonus 0.1; builds: fields |
| Animal Domestication | 2 | gather_efficiency 1.1; carrying_capacity_bonus 1.3; builds: pens |
| Animism | 2 | unlocks_burial_ritual; builds: shrine |
| Art | 2 | fire_morale; builds: murals |
| Barn | 2 | gather_efficiency 1.05; store_bonus 1.5; builds: barn |
| Beekeeping | 2 | hunger_efficiency 1.08; gather_efficiency 1.05; honey_food; builds: hives |
| Boat Building | 2 | unlocks_water_travel |
| Cartography | 2 | discovery_bonus 1.15; map_memory |
| Church | 2 | spread_rate_multiplier 1.12; builds: church |
| Community | 2 | reproduction_cooldown_mult 0.82; max_age_bonus 0.05 |
| Chicken Coop | 2 | hunger_efficiency 1.05; builds: coop |
| Curiosity Culture | 2 | discovery_bonus 1.2 |
| Dairy | 2 | hunger_efficiency 1.05; builds: dairy |
| Domestication | 2 | gather_efficiency 1.05; reads_tracks |
| Dyeing | 2 | spread_rate_multiplier 1.05; builds: dye_vats |
| Fermentation | 2 | hunger_efficiency 1.1; max_age_bonus 0.05; preserves_food |
| Forestry | 2 | replants |
| Herbalism | 2 | max_age_bonus 0.1; herb_healing_mult 1.5 |
| Herding | 2 | gather_efficiency 1.05; builds: pens |
| Horse Taming | 2 | can_ride_horses; builds: stables |
| Housing | 2 | weather_protection 0.2; rest_efficiency 1.15; max_age_bonus 0.1 |
| Irrigation | 2 | gather_efficiency 1.05; carrying_capacity_bonus 1.15; field_near_water; builds: ditches |
| Metal Tools | 2 | gather_efficiency 1.25; builds: forge |
| Mining | 2 | gather_efficiency 1.05; builds: quarry |
| Mountain Climbing | 2 | unlocks_mountain_travel |
| Oral Tradition | 2 | concept_spread_rate_mult 1.25; fire_story_bonus 0.25 |
| Organisation | 2 | unlocks_tasks |
| Pottery | 2 | hunger_efficiency 1.15; preserves_food; builds: kiln |
| Preservation | 2 | hunger_efficiency 1.12; preserves_food; max_age_bonus 0.1; builds: smokehouse |
| Ritual | 2 | unlocks_temple_use; holds_rituals; spread_rate_multiplier 1.05 |
| Sailing | 2 | unlocks_water_travel |
| Temple | 2 | spread_rate_multiplier 1.1; builds: temple |
| Tree House | 2 | rest_efficiency 1.08; weather_protection 0.05; sleeps_in_trees; builds: tree_houses |
| Woodworking | 2 | gather_efficiency 1.05; builds: workshop |
| Writing | 2 | spread_rate_multiplier 1.5 |
| Animal Breeding | 3 | gather_efficiency 1.1; carrying_capacity_bonus 1.1 |
| Astronomy | 3 | discovery_bonus 1.15; builds: standing_stones |
| Calendar | 3 | gather_efficiency 1.05; max_age_bonus 0.05; times_seasons |
| Conservation | 3 | carrying_capacity_bonus 1.1; max_age_bonus 0.05; enables_reintroduction; spares_depleted_land |
| Cosmology | 3 | settlement_morale_bonus 0.15; discovery_bonus 1.1 |
| Currency | 3 | hunger_efficiency 1.1; spread_rate_multiplier 1.2; trade_reach |
| Diplomacy | 3 | spread_rate_multiplier 1.25; reproduction_cooldown_mult 0.92; keeps_peace 0.5 |
| Ecology | 3 | gather_efficiency 1.05; carrying_capacity_bonus 1.1; spares_depleted_land |
| Engineering | 3 | gather_efficiency 1.1; carrying_capacity_bonus 1.15; unlocks_bridge_building |
| Governance | 3 | reproduction_cooldown_mult 0.88; spread_rate_multiplier 1.2; keeps_peace 0.2; builds: hall |
| Law | 3 | spread_rate_multiplier 1.15; reproduction_cooldown_mult 0.9; keeps_peace 0.35 |
| Masonry | 3 | weather_protection 0.3; rest_efficiency 1.2; builds: walls |
| Mathematics | 3 | gather_efficiency 1.05; discovery_bonus 1.1; store_bonus 1.2 |
| Metallurgy | 3 | gather_efficiency 1.1; builds: forge |
| Military Tactics | 3 | wins_clashes; builds: watchtower |
| Music | 3 | reproduction_cooldown_mult 0.92; discovery_bonus 1.05; plays_music |
| Mythology | 3 | cultural_identity; spread_rate_multiplier 1.1 |
| Navigation | 3 | unlocks_deep_water_travel; discovery_bonus 1.1 |
| Philosophy | 3 | discovery_bonus 1.15; curiosity_bonus 0.15 |
| Poetry | 3 | curiosity_bonus 0.1; discovery_bonus 1.05; fire_story_bonus 0.3 |
| Printing | 3 | spread_rate_multiplier 1.8; discovery_bonus 1.1; builds: press |
| Rope Bridge | 3 | unlocks_bridge_building |
| Taxation | 3 | carrying_capacity_bonus 1.1; spread_rate_multiplier 1.1; tithe 0.15 |
| Trade | 3 | hunger_efficiency 1.1; spread_rate_multiplier 1.3; trades; builds: market |
| Architecture | 4 | unlocks_stone_buildings; weather_protection 0.3 |
| City Planning | 4 | carrying_capacity_bonus 1.1; weather_protection 0.2; store_bonus 1.2; builds: streets |
| Advanced Medicine | 4 | max_age_bonus 0.2; vitality_regen 0.0015; herb_healing_mult 1.3 |
| Seafaring | 4 | unlocks_ocean_crossing; unlocks_water_travel; discovery_bonus 1.1 |
| Trade Routes | 4 | spread_rate_multiplier 1.5; hunger_efficiency 1.15; trade_reach; builds: roads |

## Lost, and found again (feat/ideas)

The pitch promises an idea lost when the last person who knew it dies, and found again
later. Before this, none ever was (0 in 3 seeds x 15 days): spreading is fast, everyone meets
everyone, and few die in a fortnight (20-80 of about 200), so a widely held idea can't die.
Measured dead ends: crafts at an eighth of the pace, or taught only within a camp or family,
still reached 140 of 150; a two-to-six-day window before an inventor could teach gave 0-2
losses and slowed the whole tree.

**Master crafts** (`IdeaMemory.MASTER_CRAFTS`): pottery, sailing, boat building, navigation,
cartography, printing, beekeeping, dyeing, herbalism, advanced medicine, horse taming. The
specialist trades; none is a prerequisite that whole branches wait on (metallurgy, metal
tools and woodworking stay ordinary crafts because towns and stone buildings need them).

- A master takes on at most two apprentices in each (`apprentices`).
- An apprentice knows the craft only when the apprenticeship is done, three days later
  (`apprenticeship`), on meeting their master again. If the master dies first, it ends.
- While anyone alive holds a master craft, nobody works it out alone (`reinvent` = 0).
- A camp's pool of ideas never hands one out (the pool now only teaches what a living member
  holds; it used to bring back ideas whose holders had all died, unseen).

So a new trade lives for days in one pair of hands. Simple ideas and ordinary crafts are
untouched; no idea anyone can copy is a master craft (tested).

**The loss.** `ConceptGraph.note_death` (Main calls it for each death) asks `IdeaMemory`
whether anyone alive still holds each idea the dead knew; if not, the idea is lost and leaves a
**ghost** where they died and at their camp's hearth. `IdeaLedger` records it (day, last holder,
place), the chronicle tells it ("No one remembers how to fire clay now. Mara was the last."),
the last holder's life story says so, the Idea Garden draws it wilted and says it may be found
again near where it was last known, and the album has "An idea lost".

**Found again.** Within 14 tiles of a ghost a lost idea is 4x likelier to be thought of
(`ghost_bonus`). The chronicle says how long it was gone, and whether it was near the ghost
and the finder born after the loss ("Ivo has worked out how to fire clay again, ninety days
after it was lost, not far from where Mara last knew it."; `IdeaWords`). Moments: "Found
again", "Where it was left" (near the ghost), "New hands" (by someone born after it was lost).

Measured (`tools/balance.gd --days=14 --ideas`, which prints each idea's holders, low point,
times found and taught, and every loss):

| Seed | Ideas | Lost | Found again | Still lost |
|---|---|---|---|---|
| 1 | 55 | dyeing d11, pottery d14 | dyeing d12 | pottery |
| 3 | 41 | printing d6, cartography d9 | printing d9, cartography d11 (both near the ghost) | - |
| 5 | 13 | cartography d12 | - | cartography |

Tests: `tests/suites/70_ideas_lost.gd`.

Open: a master craft stays in 1-4 hands, so its effect (printing's faster teaching, maps,
boats) reaches few; that is the point, but watch it if a trade ever gates something big.
Seed 1 loses ideas only late (few die before day 14 there). An apprenticeship cut short by
the master's death isn't told in the chronicle yet.

Open: UtilityAI.gd is still never instantiated and LineageTracker is written but not read
(IdeaLedger and LifeRecord cover what it would show); both are candidates for deletion.
