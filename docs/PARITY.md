# World → Godot: Feature Inventory

The original **World** (`../World`, 18.2k lines of JS + Three.js) was a *concept piece*. It is
a design document, not a reference implementation: it proves which systems are interesting and
how they interact, but its structure was shaped by a browser canvas renderer, a Web Worker, and
per-species hand-written mesh builders. None of those constraints apply here.

So this file is **not** a port checklist. Each row records what the concept piece established,
where the Godot build stands, and a verdict:

- **Done** — covered, no further work
- **Port** — the concept-piece logic is right; translate it
- **Redesign** — the idea is worth keeping, the JS approach is not
- **Drop** — an artefact of the browser build with no reason to exist here
- **New** — worth doing in Godot even though the concept piece never had it

Baseline: `world-godot` runs clean headless on Godot 4.7 (`--headless --quit-after 300`, zero errors).
Note that `.godot/` is gitignored, so a fresh clone must be opened in the editor once (or run
`--headless --editor --quit`) to generate `global_script_class_cache.cfg`, or every `class_name`
fails to resolve.

## Settled direction

| Decision | Choice |
|---|---|
| World size | **128×128** — matched to the concept piece before feature work, so density-tuned systems are calibrated once |
| Threading | **Single-threaded** — tick in `_process`; revisit only if profiling shows the sim starving the frame |
| Assets | **Free to replace** — Synty / BrokenVector / EverydayMotion already in `sources/`, not bound to the JS look |

---

## 1. World generation

| Feature | Concept piece | Godot now | Verdict |
|---|---|---|---|
| Heightmap + tile types | `World.js` `_generate` | `World.gd` `_generate` | **Port** — widen 32² → 128² |
| Rivers | `_generateRivers` | `_generate_rivers` | Done |
| Glaciers + melt | `_generateGlaciers`, `updateGlaciers` | `_generate_glaciers` | **Port** — melt/temperature response missing |
| Caves | `_generateCaves` | `_generate_caves` | Done |
| Lava fields | `_generateLava` | — | **Port** |
| Water connectivity repair | `_fixWaterConnectivity` | — | **Port** — matters much more at 128² |
| Resource growth / depletion | `updateResources`, `updateDepletion` | present | Done |
| Flora slow tick | `floraSlowTick` | `flora_slow_tick` | Done |
| Traversal cost + knowledge gates | `canTraverse`, `traversalCost` | present | Done |
| Chicken nests | `initChickenNests`, `updateChickenNests` | — | **Redesign** — fold into a general nesting/spawn-point concept, not a chicken special case |
| Cow herd update | `updateCows` | — | **Redesign** — belongs in the fauna system, not `World` |
| Domestication | `updateDomestication` | — | **Port** |
| Trade traffic decay | `decayTradeTraffic` | — | **Port** |
| Serialize / save / load | `serialize` | — | **Redesign** — use Godot `Resource` + `ResourceSaver`, not the JS JSON shape |
| Biome variety (desert, swamp, tundra) | never built | — | **New** — listed as future work in the concept piece; 128² makes it worthwhile |

## 2. Agents

`Agent.js` 1348 lines → `Agent.gd` 595 lines.

| Feature | Concept piece | Godot now | Verdict |
|---|---|---|---|
| Needs, personality, life stages | yes | yes | Done |
| Movement, arrival, wander/gather targets | yes | yes | Done |
| Discovery + concept spread | yes | yes | Done |
| Socialising, bonding, reproduction | yes | yes | Done |
| Disease infection + immunity | yes | yes (inline) | Done |
| Inventory, eating, medicine | yes | yes | Done |
| Tasks (gatherer/teacher/scout/carer) | yes | yes | Done |
| Spatial memory — food sources, danger | `_rememberFoodSource`, `_rememberDanger` | — | **Port** — big behavioural payoff, cheap |
| Roles (distinct from tasks) | `_assignRole`, `_applyRoleBonus` | — | **Redesign** — roles and tasks overlap; collapse to one system |
| Trader journeys | `_startTraderJourney`, `_onTraderArrival`, `_finishTraderJourney` | `State.TRADING` enum exists, never entered | **Port** |
| Rituals + morale boost | `_ritualTimer`, `ritualMoraleBoost` | `State.RITUAL` enum exists, never entered | **Port** |
| Seasonal tile preference | `_seasonalTileScore` | — | **Port** |
| Ground item pickup | `_pickUpGroundItems` | drop only | **Port** |
| Wolf domestication | `tryDomesticateWolves` | — | **Port** (after fauna) |
| Family / lineage queries | `getFamily` | `parents`/`children` stored, unused | **Port** |
| Dawn / dusk behaviour | `isDawnTime`, `isDuskTime` | `TimeSystem.is_dawn/is_dusk` exists, unused by agents | **Port** |
| Horse riding | `mountedHorse`, `_rideTimer` | — | **Port** (after fauna) |
| Fishing trips | `_fishingTrip` | partial — state entered, no trip logic | **Port** |
| Drag-to-move agent | `isDragged` | — | **Drop** — a canvas debug affordance |

## 3. Systems

| System | Concept piece | Godot now | Verdict |
|---|---|---|---|
| TimeSystem | 50 ln | 41 ln | Done |
| HistoryLog | 62 ln | 45 ln | Done |
| SpatialGrid | 73 ln | 84 ln | Done |
| TileItems | 90 ln | 138 ln | Done |
| CraftingSystem | 49 ln | 184 ln | Done — Godot exceeds it |
| TradingSystem | 83 ln | 183 ln | Done — Godot exceeds it |
| ConflictSystem | 210 ln | 147 ln (factions, wars) | Done |
| SettlementSystem | 373 ln | 341 ln (+ dialect, tier upgrades) | Done — Godot exceeds it |
| EcologySystem | 268 ln | 211 ln | Done |
| FireSystem | 137 ln | 146 ln | Done |
| DisasterSystem | 128 ln | 97 ln | Done |
| Achievements | 124 ln | 111 ln | **Port** — persistence (`_load`/`_save`) missing |
| AnimalSkillSystem | 86 ln | 78 ln | Done |
| AudioSystem | 146 ln (WebAudio tones) | 150 ln (generated samples) | **Redesign** — replace synth beeps with real audio |
| UtilityAI | 171 ln | 109 ln | **Port** — narrower action set in Godot |
| WeatherSystem | 266 ln, **zonal** (per-tile weather zones) | 77 ln, **global** | **Port** — zonal weather is the interesting half and it's missing |
| DiseaseSystem | 92 ln, coordinated outbreaks | inline in `Agent.gd` only | **Port** — no outbreak/medicine-access layer |
| LineageTracker | 62 ln — who discovered what, when | — | **Port** — cheap, feeds the timeline UI |
| GatheringSystem | 238 ln | folded into `Agent.gd` | **Redesign** — decide whether to re-extract |
| PopulationManager | 272 ln, Lotka-Volterra pred/prey + reintroduction | — | **Port** — this is the ecology's backbone |
| ChunkSystem | 219 ln, worker-driven streaming | — | **Redesign** — Godot needs chunked *meshing* at 128², but not the worker protocol |

## 4. Fauna

The concept piece has 11 simulation classes and 17 renderers, one per species. `AnimalSim.gd`
(234 ln) compresses all of it into type-enum branches, and `AnimalRenderer.gd` (252 ln) draws them.

**Verdict: Redesign.** Neither extreme is right. Define species in `data/animals.json`
(diet, speed, herd size, biome, flee/chase behaviour, mesh, scale) and drive one behaviour
system + MultiMesh rendering from the data. Adding a species then costs a JSON entry and a mesh.

Species proven by the concept piece: deer, wolf, fox, frog, whale, fish shoal, insect swarm,
wild horse, rabbit, sheep, pig, highland cow, bee, butterfly, bird flock, eagle, robin.

Behaviours worth keeping regardless of representation: herd cohesion, predator/prey chase and
flee, Lotka-Volterra population dynamics (`PopulationManager`), domestication, per-animal skill
learning (already ported), and biome-gated spawning (already in `_pick_type_for_biome`).

Open question flagged in the concept piece's own README: *animals shouldn't swim unless they're
meant to*. Encode swimmability per species in the data.

## 5. Rendering & presentation

| Feature | Concept piece | Godot now | Verdict |
|---|---|---|---|
| Terrain mesh | `TerrainRenderer.js` 2244 ln | `TerrainRenderer.gd` 86 ln | **Redesign** — chunked meshing for 128²; most of the JS bulk is hand-built geometry Godot doesn't need |
| Agent meshes | `AgentRenderer.js` 410 ln | 239 ln, Synty + EverydayMotion | Done — better than the concept piece |
| Buildings | `BuildingRenderer.js` 604 ln | `SettlementRenderer.gd` 159 ln | **Redesign** — use Synty Fantasy Kingdom kit, not hand-built geometry |
| Per-species meshes | 17 renderers | 1 renderer | **Redesign** — see Fauna |
| Sky: clouds, stars, milky way, shooting stars | `WorldRenderer.js` | — | **Redesign** — Godot sky shader + `WorldEnvironment`, not particle hacks |
| Rain | `updateRain` | — | **Redesign** — GPUParticles3D |
| Rainbow | `_buildRainbow`, `triggerRainbow` | — | **Port** — pure charm, keep it |
| Fire / charge / ground lights | `addFireLight`, `addChargeLight`, `addGroundLight` | partial in `EnvironmentRenderer.gd` | **Port** |
| Day/night sun cycle | yes | yes (`Main.gd`) | Done |
| Water shader | flat canvas water | flat | **New** — cheap win in Godot |

## 6. UI & interaction

| Feature | Concept piece | Godot now | Verdict |
|---|---|---|---|
| Speed controls, pause | yes | yes (`HUD.gd`) | Done |
| Stats panel, era display | yes | yes | Done |
| History / notifications | yes | yes | Done |
| Game over | yes | yes | Done |
| Camera pan / orbit / zoom | yes | yes | Done |
| Agent selection | yes | yes | Done |
| Agent info panel | `updateInfoPanel` | — | **Port** |
| Tile info panel | `updateTileInfoPanel` | — | **Port** |
| Follow-agent camera | `setFollowTarget` | — | **Port** |
| Speech bubbles | `showSpeechBubble` | field exists, never rendered | **Port** |
| Discovery ring effect | `showDiscoveryRing` | `discovery_flash` field, no visual | **Port** |
| Minimap | `MinimapRenderer.js` | — | **Port** — much more valuable at 128² |
| Timeline of discoveries | `updateTimeline` | — | **Port** — needs `LineageTracker` |
| Population graph | `drawPopGraph` | — | **Port** |
| Knowledge overlay | `updateKnowledgeOverlay` | — | **Port** |
| Resource overlay | `drawResourceOverlay` | — | **Port** |
| Heatmap overlay | `drawHeatmapOverlay` | — | **Port** |
| Achievements panel | `renderAchievements` | logic only, no UI | **Port** |
| World seed input / reset | `resetWorld` | — | **Port** |
| Replay mode | never built | — | **New** — needs save/load first |

## 7. Dropped outright

| Thing | Why |
|---|---|
| `SimulationWorker.js` (654 ln) + diff-snapshot protocol | Single-threaded decision; Godot handles far more than JS could |
| `TerrainWorker.js` (159 ln) | Same |
| Service worker / PWA / manifest | Browser deployment concern |
| Three.js importmap, CDN loading | — |
| `showError` / `hideError` DOM error surface | Godot has its own error reporting |

---

## Suggested order

1. **Widen to 128²** + chunked terrain meshing and MultiMesh instancing. Everything downstream tunes against this.
2. **World-gen parity**: lava, water connectivity, glacier melt, domestication, trade traffic.
3. **Save/load** as a Godot `Resource`. Unblocks seeds, resets, and eventually replay.
4. **Agent depth**: memory, trader journeys, rituals, seasonal preference, ground pickup, dawn/dusk, lineage.
5. **Missing systems**: `LineageTracker`, `DiseaseSystem`, `PopulationManager`, zonal weather.
6. **Fauna redesign**: `data/animals.json` + one data-driven behaviour system + MultiMesh rendering.
7. **Presentation**: sky, rain, water, buildings from the Synty kit.
8. **UI parity**: minimap, overlays, timeline, info panels, follow cam, achievements panel.
