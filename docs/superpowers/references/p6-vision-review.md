# Vision-Model Review — P6 UI/UX Refactor (2026-09-09)

Screenshots captured from the real launcher (`main.tscn`) via
`tools/vision_shots.tscn` (windowed, 1440x900). Use these to review the
rendered UI. **Ground truth for geometry is the headless probes** (they assert
pixel rects); the screenshots are for visual/UX review only.

## Files

| File | State | What to check |
|------|-------|---------------|
| `vision_01_overlay.png` | Pre-game settings overlay | Tabs, player rows, board-size SpinBox, layout |
| `vision_02_board.png` | Mid-game, RU | Board bands, tile labels, tokens, journal |
| `vision_03_owned.png` | Player 0 owns tile 1 + 2 houses | Owner frame+badge, house sprites |
| `vision_04_en.png` | Same game, EN locale | Live relabel (no rebuild), English text |
| `vision_05_compact.png` | 900x600 compact | Board fits, panels not collapsed, no overflow |

## What the probes already guarantee (do NOT re-litigate)

- **Band orientation** — `board_layout_probe` asserts every side tile's band
  faces the board center (7 checks green). The old bug (both vertical sides
  outward) is fixed.
- **Icon size** — icons <= 0.35*cell, centered, never over text (probe green).
- **Label overflow** — no visible Label leaves its tile (probe green).
- **Token spacing** — co-located tokens >= 0.6*token-size apart (probe green).
- **Parametric board** — ring closes for N=16/24/40/48/64, fits 900x600..4K
  (`dynamic_board_probe`, 20 checks green).
- **Skinning** — no hardcoded asset paths / Color() literals in tile/board/
  players/topbar (`skin_probe` green).
- **i18n** — 0 sentinels, 0 raw enums, live RU<->EN relabel (`i18n_probe`).

## Known visual notes (from vision-model pass)

1. **Center clutter (by design, but heavy):** the auction decision modal and
   the BG3 dice stage are centered over the board. During an auction the center
   is busy. Consider: dim the board behind the modal, or shrink the dice.
2. **Auction toasts stack** — multiple "Аукцион: «тайл 8»" toasts can overlap
   in the center. The toast anti-spam merges identical text within 1.5s, but
   distinct auction events still stack. Worth a follow-up: cap the toast stack
   height.
3. **Tile names truncate with ellipsis** ("Lake...", "Aspe...") — this is
   CORRECT Monopoly behavior (long names on a 40-tile board), not a bug. The
   `short` name is used in compact mode.
4. **Tokens/houses may be hard to see at a glance** — they are small
   (proportional to cell). The probes verify they exist and are spaced; visual
   prominence is a polish follow-up.

## How to re-capture

```bash
cd game
godot --path . res://tools/vision_shots.tscn   # windowed, DISPLAY=:0
```
Saves `vision_01..05.png` in `game/`.
