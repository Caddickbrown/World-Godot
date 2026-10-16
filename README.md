# World (Godot)

A pocket of people, watched with love. Forty strangers wake on an island; you watch them find
fire, fall in love, lose ideas and find them again. You never control anyone: you watch from the
sky, follow one life, or drift among them as an unseen wisp.

The Godot rebuild of the browser concept piece [Caddickbrown/World](https://github.com/Caddickbrown/World).
What the game is: `docs/GAME_DESIGN.md`. How it looks: `docs/ART_DIRECTION.md`. What the
concept piece proved and what each system's verdict is: `docs/PARITY.md`.

## Running

Open the folder in Godot 4.7 and press Play (`scenes/Main.tscn`).

| Input | Does |
|---|---|
| Click someone | Follow them (the camera rides along, their card opens) |
| F / Esc | Follow the selected person / let go |
| Tab | Walk among them as the wisp, or go back up to the sky |
| WASD, Q/E, drag, wheel | Sky: pan, turn, tumble, zoom. Wisp: move (Shift to hurry), mouse to look |
| E (as the wisp) | Listen in on the person beside you |
| Space, 1/2/3 | Pause; 1×, 5×, 20× |
| L, I, J | Lives, the Idea Garden, the Album (with hunches) |
| T | Switch look: storybook (A) or field notes (B), for the UI and the world |
| H, R | Back to the people; new world |

## Builds

Every push that passes CI builds a Linux version (x86_64): open the run under
**Actions**, then **Artifacts → World-linux-x86_64** (kept 14 days). Pushing a
tag `v*` (`git tag v0.1.0 && git push origin v0.1.0`) also publishes it as a
GitHub Release. Unpack and run `./World.x86_64`; keep `libworld_kernels.so`
beside it.

Locally: `tools/export/fetch_templates.py 4.7.2 linux_release.x86_64 linux_debug.x86_64`
once (just the Linux export templates, not the 1.3 GB archive), then
`GODOT=/path/to/godot tools/export/build_linux.sh` → `dist/`. The build is
smoke-run headless before it's packed.

## Layout

| Path | What |
|---|---|
| `scripts/Main.gd` | Owns the world, ticks every system, switches views |
| `scripts/simulation/` | `World` (map, resources), `Agent` (people), `AgentThoughts` (their words), `ConceptGraph`, `AnimalSim` |
| `scripts/systems/` | Time, weather, settlements, conflict, disease, trade and the rest |
| `scripts/view/` | `ObserverCamera` (sky and follow), `Wanderer` (the wisp) |
| `scripts/look/` | `Heightfield` (the smooth ground), `LookStyle` (world palettes), `SkyLook` |
| `scripts/renderer/` | Terrain, people (with pins, names and bubbles), animals, flora, settlements |
| `scripts/story/` | `StoryKeeper` (chronicle, lives), `IdeaLedger`, `Moments`, `Hunches`: read the sim, never write it |
| `scripts/ui/` | `GameHud`, `UiTheme` (both looks as tokens), the Lives / Ideas / Album screens |
| `scripts/mockup/ArtMockup.gd` | The art-direction mockup: the target look, same world generator |
| `tests/` | `Runner.tscn` (unit and integration checks) and `run_ci.sh` |
| `tools/` | `capture/` (review shots), `balance.gd` (population per day), `smoke.gd` (long soak) |

## Checks

```bash
GODOT=/path/to/godot tests/run_ci.sh                                   # what CI runs
GODOT=/path/to/godot tools/capture/shots.sh shots                      # game review shots
GODOT=/path/to/godot tools/capture/mockup.sh shots/mockup              # art mockup shots
godot --headless --path . --script res://tools/balance.gd -- --days=14 # balance probe
```
