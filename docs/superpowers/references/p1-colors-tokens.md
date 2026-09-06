# P1 — Colors + tokens (2026-09-07)

Committed `ffbaf60` on `ui/overhaul`. Implements spec §11 P1 of
`docs/superpowers/specs/2026-09-07-ui-ux-redesign-concept-v2.md`.

## What changed

- `core/player_identity.gd` (NEW) — single source of player color + token.
  8 high-contrast colors on #16191f + 8 token ids matching
  `game/assets/tokens/*.svg`. `color_of(pid)` / `token_of(pid)` /
  `token_path(id)` / `is_known_token(id)`. Kills the 4 duplicated color
  arrays (seat_config, settings_overlay, board_view, tile_view).
- `visual/token_panel.gd` — SVG sprite (no recolor) on a PlayerIdentity halo
  circle; compact-mode initial over the halo; fan-out along a 120° arc
  (radius 0.45×cell) for co-located pieces; step-by-step walk along the ring
  (70ms/tile, ease-in-out) with a gold GO flash; active-player bob (1 Hz);
  jail pieces offset toward the corner center. All gated by
  `settings.animations=false`.
- `visual/board_view.gd` — groups tokens by tile for fan-out, resolves
  token_id/color from the seat list (fallback PlayerIdentity), sets active
  player, `set_seats()`.
- `visual/tile_view.gd` — owner marker color now from PlayerIdentity.
- `ui/players_panel.gd` — token avatar (halo + sprite), name in player color,
  money, position BY TILE NAME, houses/mortgaged/jail-card/away/bankrupt
  badges, active ▶, full tooltip.
- `sdk/projection.gd` — player views gain `houses` + `mortgaged` counts.
- `seats/seat_config.gd` + `ui/settings_overlay.gd` — colors/tokens from
  PlayerIdentity.
- `visual/board_scene.gd` + `ui/game_view.gd` — pass seats through to the board.
- `tests/player_identity_test.gd` (7 tests) + `tools/p1_probe.tscn/.gd`.

## Probe

```
godot --path game res://tools/p1_probe.tscn
```
4 checks: (1) owner marker == token halo == players-panel row (hex compare),
(2) 4 tokens on one tile fan out (pairwise dist >= 0.7×diameter),
(3) tokens are SVG sprites (TextureRect child), (4) players panel shows
position by tile name.

## Gotchas hit (all fixed)

1. **`seat_config.from_settings` must set `driver_label`/`input_driver` for
   BOTH the assignment and default branches** — I initially moved them inside
   the `else` (default) branch, so assigned seats got empty `driver_label`
   and `test_assignment_parsing` failed ("label LOCAL"). They belong after the
   if/else, applied to every seat.
2. **`var lum := 0.299*c.r + ...` is a parse error** in a headless test
   (Color components are Variant-typed) — annotate `var lum: float = ...`.
3. **The spec's fan geometry (60° arc, 0.35×cell radius) CANNOT satisfy the
   probe gate (0.7×diameter spacing) for 4 pieces** — the arc is too tight.
   Widened to 120° arc, 0.45×cell radius (min pairwise dist 21.9 >= 18.9).
   The probe is the definition-of-done; tune the geometry, not the probe.
4. **Active-player bob fights the walk tween** — both write `position.y`.
   Gate the bob with a `_walking` flag (set true on walk start, cleared by a
   `tween_callback` at the end of the walk tween).
5. **`_grant_property` doesn't exist** — grant ownership via
   `engine.players[pid].add_ownership(tile)` (the admin op is
   `admin_override("grant_property", ...)`).
6. **Probe fan-out must disable animations** (`set_animations(false)`) or the
   walk tween leaves tokens mid-flight and the distance check reads 0.0.
7. **`seats_soak.tscn` stalls without a live SDK server** (Randy at ws:8000) —
   pre-existing environmental dependency, NOT a regression. The headless
   `seats_test.gd` (no server) passes.

## Verification

- 197 headless tests green (190 baseline + 7 new), 0 masked SCRIPT ERRORs.
- `p1_probe.tscn` ALL PASSED.
- `p0_probe.tscn` (host) ALL PASSED — P0 behavior intact.
- `ui_smoke.tscn` (1440) + `ui_smoke_small.tscn` (800) green.
- `docs/plan.md` P1 row → DONE.
