# P2 — Tiles (2026-09-07)

Committed `f988fc0` on `ui/overhaul`. Implements spec §11 P2 of
`docs/superpowers/specs/2026-09-07-ui-ux-redesign-concept-v2.md`.

## What changed

- `game/data/board.json` — every tile gains a `short` name (≤14 chars) for
  compact-mode rendering (spec §4.2). Full `name` untouched; `short` is a
  display hint only. Long names like "Harbor Station" → "Harbor Stn",
  "Crest Heights" → "Crest Hts".
- `game/sdk/projection.gd` — board entries gain `short` (falls back to
  `name`) and `owner_name` (resolved from the engine player list).
- `game/visual/tile_view.gd` — full rewrite:
  - **Base** = dark `assets/tile.svg` (light text), fallback flat panel.
  - **Group band** on the edge facing the board center (unchanged geometry).
  - **Houses/hotel** = SVG sprites (`assets/houses/*.svg`) on the band.
  - **Corner/type icons** = SVG sprites (`corner_icons/*`, `type_icons/*`).
  - **Owner** = 2px frame around the whole tile + round badge (⌀~12px) with
    the owner's initial in the corner at the OUTER edge (opposite the band).
  - **Mortgage** = desaturate base+band + diagonal hatch overlay
    (`visual/tile_hatch.gd`, drawn via `_draw`, ~20% coverage).
  - **Compact mode** (cell < 44): price hidden, short name, 1-line ellipsis.
  - **Highlights** (spec §4.2): active = glowing accent frame (pulse 0.8 Hz),
    selected = dashed accent frame, target = soft 12% fill.
- `game/visual/board_view.gd` — highlight via frames (not `modulate` that
  yellowed text); `set_selected_tile(idx)` / `set_target_tiles(indices)`;
  `_rebuild()` for probe cell-size testing.
- `game/ui/game_view.gd` — clicking a tile marks it selected on the board.
- `game/tests/board_test.gd` — `test_every_tile_has_short_name` (198 green).
- `game/tools/p2_probe.tscn/.gd` — 8 behavioral checks.

## Probe

```
godot --path game res://tools/p2_probe.tscn
```
8 checks: (1) cell=48 → full mode, cell=36 → compact mode; (2) no label
overflows its tile; (3) full name shown at cell≥48; (4) owner frame + badge
with initial; (5) SVG art wired (tile base, corner/type icons, house sprites);
(6) mortgage desaturates + shows hatch; (7) active + selected highlight
frames render.

## Gotchas hit (all fixed)

1. **Compact-mode price overflow** — the price Label's minimum height (from
   its font size) exceeds the small tile's allocated price band, so it
   overflowed every tile at cell=36. Per spec §4.2 compact mode HIDES the
   price. Set `_price.visible = not _compact` in BOTH `build()` and
   `refresh()` (a rebuilt-but-unrefreshed board still needs the right default).
2. **Probe overflow check must compare label rects in LOCAL coords** — labels
   are children of the tile, so their `position` is relative to the tile, not
   the board. Compare against `Rect2(Vector2.ZERO, tv.size)`, not
   `Rect2(tv.position, tv.size)`.
3. **Probe must refresh after `_rebuild()`** — a freshly rebuilt board has
   empty label text until `refresh_state()` runs; the short-name check read
   `''` until I added the refresh.

## Verification

- 198 headless tests green (197 baseline + 1 new), 0 masked SCRIPT ERRORs.
- `p2_probe.tscn` ALL PASSED (8 checks).
- `p1_probe.tscn` ALL PASSED (regression).
- `p0_probe.tscn` host + `-- --spectator` ALL PASSED (regression).
- `ui_smoke.tscn` (1440) + `ui_smoke_small.tscn` (800) green.
- `tony.tscn` 4/4 green.
- `docs/plan.md` P2 row → DONE.
