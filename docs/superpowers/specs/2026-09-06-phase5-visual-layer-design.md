# Phase 5 — Visual / Stream Layer Design

**Date:** 2026-09-06 (evening session)
**Builds on:** Phases 0–4 complete (`main`, 146 headless tests green). Engine
+ seat/driver layer + admin console are done. This phase adds the *picture*
and stream UX around that stable engine.

## Goals (from `docs/plan.md` "Handoff — next session")

1. **Board scene** + original-themed art built from `board.json` (no asset
   files, no Hasbro trade dress). `main.tscn` today is code-built UI only
   (seat_manager + admin_panel); add a visual control tree.
2. **Camera / spectacle** auto-focus — spec §4 "Stream control (spectacle
   mode)" + settings `spectacle` (default on): highlight the active player,
   auto-focus the action area; zoom/disable-animations toggles.
3. **SFX** — procedural (no audio files) via `AudioStreamGenerator`.
4. **Replay of last event** + **`event_overlay`** stream overlay (settings
   `event_overlay`, default on) fed by the spectator-safe projection +
   `markdown_renderer.render_spectator` and engine event log.
5. **In-window smoke / screenshot validation** (WSL headful Godot runs under
   llvmpipe — verified: godot boots, exit 0). Optional in-browser WebGL smoke.

**Out of scope (deferred, confirmed):** live tile-cost/rent tweak and
deck-card insert/remove admin ops, player reorder, redo-turn-with-seed,
token-guarded remote admin panel, real `evil` over a second SDK connection,
voice-chat side channel.

## Architecture decisions

### A. Code-built UI, no asset pipeline
Every previous UI in this repo is **code-built** (admin_panel, ascii_board).
Keep that. Render the board as a grid of `Panel`/`Label` controls laid out in
a `Node2D`/`Control` scene built at runtime from `board.json`. This keeps the
visual layer headless-testable (the layout math is pure functions taking
`(tile_count, cell_size, cells_per_side) -> positions`), avoids binary asset
management, and makes the board theme data-driven from `board.json`'s
`group` fields.

### B. Layered visual scene (visual/ dir)
New `game/visual/` holds the visual layer, cleanly separated from engine/seats:
- `visual/tile_layout.gd` — **pure** layout math: ring layout for a 40-tile
  board. `static func position_for(index, side_cells, cell_size) -> Vector2` +
  helper `is_corner(index)`. Unit-testable headless (no scene).
- `visual/theme.gd` — original color palette per `group` (no Hasbro) +
  tile-type colors + text/panel theme. Pure data.
- `visual/board_view.gd` — builds the Control tree from a `Board`; exposes
  `refresh_state(proj)` to repaint owners/houses/tokens; highlights the
  active player's tile. Thin Node shell; reads from projection.
- `visual/token_panel.gd` — a single player piece (circle + label) placed on
  the board and moved on `move` events.
- `visual/event_overlay.gd` — Control overlay: last-N event lines + the
  markdown spectator render; feeds from projection + event log.
- `visual/spectacle.gd` — camera/auto-focus controller: a `Camera2D` that
  tweens to the active player's tile / pending decision tile; toggles for
  zoom and animations. Listens to engine event signals.
- `visual/sfx.gd` — procedural tone player (`AudioStreamGenerator`):
  `play(name)` with a small wavetable synth for roll/move/build/pay/card.
- `visual/board_scene.tscn` + `visual/board_scene.gd` — the assembled scene
  the UI mode runs (board + overlay + camera + sfx), wired via signals.

### C. One engine, N views
The engine stays authoritative. The visual layer is **purely a downstream
consumer**: it reads `ProjectionScript.for_spectator(engine)` (already
spectator-safe) + the raw engine object for positions, and subscribes to the
engine's `EventLog.event_appended` signal to animate/repaint. It never
mutates state. This mirrors how seats already consume the engine — the visual
layer is just another (read-only) consumer. The admin panel remains the only
host-side mutation path (unchanged).

### D. Signals over polling
The engine already emits `EventLog.event_appended(entry)` (signal exists on
`EventLog`, `class_name EventLog`). `board_view`/`spectacle`/`sfx` connect to
it in `_ready`, so repaints and animations are event-driven, not
`_process`-polled (matches phase-4 `admin_panel` which polls only because it's
a dumb panel). A slow full-refresh is also kept for safety but the primary
path is the signal.

### E. Spectator-safety invariant
The overlay must show **only spectator-safe data**: it renders
`for_spectator(engine)` — already proven in Phase 3 — and event-log entries
(public). Jail get-out-of-jail cards are already excluded by `for_spectator`.
Do NOT pass `for_player` (which would leak private cards) to the overlay.

### F. Windowed validation strategy
`game/visual/` code is tested headless (pure math, layout positions, theme
data, projection-driven repaint logic). The assembled scene is smoke-validated
**windowed** under llvmpipe: run godot headful, step the engine a few turns,
save `get_viewport().get_texture().get_image().save_png(...)`, and inspect the
screenshot. This matches the Phase 0 headless-testing gotchas but for the GUI:
- `class_name` globals from the **SDK** still don't resolve under
  `--script`; the visual layer has its OWN minimal classes, so keep visual
  tests pure (no Godot builtin `Projection` shadow — already renamed).
- Visual repaint logic should call methods on instances, never static-on-load
  (Phase 4 masked-error lesson).

## Board ring layout

40 tiles: corners at side positions. Standard Monopoly-style ring:
- Corner tiles sit at the 4 corners of an N×N grid.
- 9 tiles per long side between corners (for 40 = 11×11 grid with 9 side
  cells). Actually for 40 tiles classic layout: 11 cells per side
  (11 = 9 + 2 corners), grid 11×11. Tile 0 bottom-left corner, going
  counterclockwise to tile 39 (or clockwise to 10). We define
  `tile_layout.position_for(index)` to return the center of that tile's cell.

Layout is pure math so the plan tests it precisely (positions for corners,
side cells, wrapping direction, adjacency).

## Data flow

```
engine.gd (authoritative)
   │ intents in, events out
   ▼
EventLog.event_appended(entry) ───────────────► sfx.play(entry), 
ProjectionScript.for_spectator(engine) ───────► board_view.refresh_state(proj)
   ▲                                            spectacle.on_event(entry)
   │ read-only (same consumer pattern as seats)
   │
visual layer (board_scene) ───── main.gd hosts it
```

`main.gd` change: instantiate `board_scene.tscn` as a child, keep
seat_manager/admin_panel; the visual layer reads the same `_engine` the admin
panel does. F12 still toggles admin panel (unchanged). Spectacle settings read
from `GameSettings` (`spectacle`, `event_overlay`, `animations`).

## Settings integration (Block 5)
`spectacle` (auto-focus + highlight) and `event_overlay` are already in
`GameSettings` per the spec (defaults `on`). Add `animations` toggle if not
present (needed by spec §4 camera-zoom/disable-animations) — check
`game_settings.gd`; if absent, add it with default `on`.

## Testing ladder rung for visual layer
Reuse ladder philosophy:
- Headless unit tests for `tile_layout` (positions), `theme` (group→color
  coverage, every property tile has a color), and any pure repaint logic.
- Windowed screenshot smoke (`tools/visual_smoke.gd` + `tools/visual_smoke.tscn`):
  boots the scene, drives N turns via `submit_intent`/AI drivers, saves
  screenshots, exit 0. Human eyes confirm layout in the PNG.
- Existing 146 tests must stay green.

## Files map
- **create** (visual layer): `visual/tile_layout.gd`, `visual/theme.gd`,
  `visual/board_view.gd`, `visual/token_panel.gd`, `visual/event_overlay.gd`,
  `visual/spectacle.gd`, `visual/sfx.gd`, `visual/board_scene.tscn`,
  `visual/board_scene.gd`
- **create** (tools/tests): `tests/visual_layout_test.gd` (registered in
  run.gd), `tools/visual_smoke.gd`, `tools/visual_smoke.tscn`
- **modify**: `main.gd` (+ `main.tscn`) to host `board_scene`;
  `game_settings.gd` (add `animations` if missing); `tests/run.gd` (register
  layout test); `docs/plan.md` (Status + Handoff).
- **reference** (docs): `docs/superpowers/specs/2026-09-06-phase5-visual-layer-design.md`
  (this file), `docs/superpowers/plans/2026-09-06-phase5-visual-layer.md`.

## Risks / mitigations
- **Hasbro trade dress** — theme.gd uses original names/colors; review enforces
  `docs/licensing.md`. No "Chance"/"Community Chest" strings; board.json
  already uses "Fortune"/"Chest".
- **WebGL + SDK quirks** — visual layer is plain Control/Camera2D, no SDK
  types; should export clean. Windowed screenshot smoke is the primary
  validation; in-browser WebGL smoke is optional.
- **Overlay leaking private state** — use `for_spectator` only (Phase 3
  invariant); a dedicated test asserts the overlay's rendered text contains no
  `private` keys.
- **Animations fighting auto-pass timers** — spectacle/board anim tweens are
  cosmetic and non-blocking (fire-and-forget `create_tween`); engine never
  waits on them.
