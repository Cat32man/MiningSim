# MiningSim (working title)

First-person mining + automation game — Satisfactory meets Deep Rock Galactic.
Design: [DESIGN.md](DESIGN.md). Godot 4.5.1, pure GDScript, no external assets.

## Run

Open the folder in Godot 4.5.1 and press F5, or:

```
Godot_v4.5.1-stable_win64.exe --path C:\projects\MiningSim
```

Controls: WASD move · Shift sprint · Space jump · LMB use tool · 1 pickaxe · 2 hand drill ·
Q ore scanner · F flashlight · G throw flare · E drop pod terminal (deposit, refuel,
build/upgrade drill) · Esc pause menu (save, quit).

Saves live in `%APPDATA%\Godot\app_userdata\MiningSim\saves\`.

## Checks

```
Godot_v4.5.1-stable_win64_console.exe --headless --path . --quit-after 3000 -- --selftest
Godot_v4.5.1-stable_win64_console.exe --headless --path . --quit-after 3000 -- --reloadtest   # after --selftest: reload its save, check for stale chunk meshes
Godot_v4.5.1-stable_win64_console.exe --path . --quit-after 4000 -- --screenshot=shot.png
```

## Layout

- `scripts/world/` — terrain: generator (density + ore), surface-nets mesher, `VoxelWorld`
  (threaded streaming, `apply_edit()` — the single entry point for all terrain changes).
- `scripts/player/` — FPS controller, tools, weight-based backpack.
- `scripts/base/drop_pod.gd` — ore deposit + drill refuel.
- `scripts/items/flare.gd`, `scripts/ui/hud.gd`, `scripts/main.gd` (scene assembly, test modes).

## Editing game text

Title screen → **Text editor** lists every player-facing string in the scripts, by file. Edits
autosave to `text_edits.json`; write them back into the code with:

    python tools/apply_text_edits.py            # add --dry-run to preview
