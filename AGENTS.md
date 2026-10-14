# AGENTS.md: working in World-Godot

Godot 4.7 (4.7.2 stable), GDScript only. Read `README.md` for the layout, `docs/GAME_DESIGN.md`
for what the game is, and `docs/ART_DIRECTION.md` for how it looks.

## Check your work (required before committing)

```bash
GODOT=/path/to/godot-4.7.2 tests/run_ci.sh            # import, boot, tests, then the long soak
GODOT=/path/to/godot-4.7.2 SKIP_SOAK=1 tests/run_ci.sh # the quick part only
```

Must exit 0. Add a check to `tests/Runner.gd` for any behaviour you add or fix. If you cannot run
Godot, say so; do not claim the change works.

## Rules that have bitten this project

- **The player never changes the world.** Following, walking and listening are view-only. Tests
  check that listening leaves a person untouched; keep it that way.
- **Balance is measured.** Change a rate, lifespan or cap, then run
  `godot --headless --path . --script res://tools/balance.gd -- --days=14` and put the numbers in
  the commit message. `tools/smoke.gd` rigs its world (one agent knows everything), so it proves
  code paths, not balance.
- **Per-second chances multiply by delta.** Never roll a raw probability per frame.
- **Ground height comes from `World.surface_y()`.** Nothing is placed at y = 0.
- **Overlays update while paused.** Only the simulation stops.
- New `class_name` script? Run `--headless --editor --quit` once, or nothing resolves it.
- Tabs for indentation. Commit `.import` and `.gd.uid` files; keep `.godot/` out of git.

## Visual changes

- Render `tools/capture/shots.sh` (the game) and/or `tools/capture/mockup.sh` (the art target).
  Without a GPU, install `mesa-vulkan-drivers`; the scripts wrap themselves in `xvfb-run`.
- Have someone who didn't make the change judge the shots against `docs/ART_DIRECTION.md`.
  Feedback must carry a reason.
- Add what you learnt to `docs/LESSONS.md`.
