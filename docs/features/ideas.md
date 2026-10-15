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

Open: UtilityAI.gd is still never instantiated and LineageTracker is written but not read
(IdeaLedger and LifeRecord cover what it would show); both are candidates for deletion.
