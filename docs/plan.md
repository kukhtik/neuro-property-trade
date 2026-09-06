# Development Plan

Feasibility verdict (Sep 2026): standalone property-trading game with Neuro SDK.
Reasoning: commercial Monopoly targets blocked (NEW MONOPOLY 2024: Denuvo+IL2CPP,
36% reviews, trade-freeze bug; Monopoly Plus delisted; TTS stance of Vedal unknown),
while Vedal's own AI now handles routine integration mods — the community lane is
a full game (his words: creative/intellectual work stays with people).

## Model routing (this profile)

Game-concept decisions (seat model, full config schema, Vedal admin console)
are in `docs/specs/game-concept-spec.md` — authoritative before seat/lobby work.

| Role | Model | Note |
|---|---|---|
| DEV (heavy code / ARCH / REVIEW) | deepseek-v4-flash | smartest of the equal-cost pair; default of this profile |
| DEV (parallel) | minimax-m2.7 | same usage/cost tier |
| Executor on crisply-specified goal (QA/DOCS/aggregation) | gemma4 | cheapest; needs fully-specified goals |

Rule of thumb: CREATE/design/undefined or investigate a discrepancy →
deepseek-v4-flash; bulk GDScript on fixed interface → minimax-m2.7;
execute-a-listed-schema / tests/docs/aggregation → gemma4.
`delegation.reasoning_effort: high` is set for creative review.

## Completed foundations (Phases 0–5, 2026-09-06)

All base systems are DONE and merged to `main`:
- **Phase 0** engine skeleton (40 tiles, board.json, Player, RNG, EventLog,
  headless test runner, 23 tests).
- **Phase 1** full rules engine (turn loop, doubles, jail, auctions, rent,
  houses/hotels, mortgage, bankruptcy, trades, cards — 81 tests).
- **Phase 2** Neuro SDK adapter (actions, projection, decision controller;
  Randy soak passes).
- **Phase 3** seat layer (LOCAL/AI/CHAT/SDK drivers, timeout auto-pass,
  spectator projection; 109 tests).
- **Phase 4** admin console + snapshot + Tony scenarios + WebGL build
  (146 tests). Token-guarded admin gate (190 tests).
- **Phase 5** code-built visual layer (board, tokens, spectacle, event
  overlay, procedural SFX; 161→190 tests).

Ground truth for what's shipped: `docs/plan.md` here + the design docs under
`docs/superpowers/{specs,plans}/2026-09-06-*`. Test ladder is green headless;
WebGL export builds and boots in a browser (frame-capture under SwiftShader is
a proven environment limitation, not a build bug).

## Current phase — UI/UX overhaul (branch `ui/overhaul`)

The UI is being reworked per the **v2 redesign concept**
`docs/superpowers/specs/2026-09-07-ui-ux-redesign-concept-v2.md`
(single source of truth; supersedes the 2026-09-06 concept).

Key decisions already locked (do NOT re-litigate):
- **One screen.** No separate lobby scene; `GameView` is always the root. The
  old `lobby.gd` becomes a `SettingsOverlay` opened via F1/⚙ (and shown on
  first run). Match start, restart, in-game settings edits all happen through
  this overlay on top of the live board.
- **Board always whole.** Spectacle camera is optional and OFF by default; the
  full 40-tile ring always fits in the viewport (cell = min(w,h)/11, compact
  mode < 44px).
- **Center of the board is the stage** — BG3-style dice animation, decision
  cards (purchase/auction), and major banners live there.
- **`core/player_identity.gd`** is the single source of player color+token;
  the four duplicated color arrays (seat_config/lobby/board_view/tile_view)
  are deleted.
- **Tiles** get `short` names in `board.json`, SVG art (tile.svg, type/corner
  icons, house/hotel), owner = 2px frame + badge; mortgaged = desaturated +
  hatched.
- **Host-only admin** on the F12 panel; WebGL build does not create the panel
  at all.
- Every phase ends with **behavioral probes, not llvmpipe screenshots**.

### Phase status (per v2)

| Phase | Scope | Status |
|-------|-------|--------|
| A | Adaptive layout, tooltips everywhere, inspector auto-hide, tile/token rework, bigger window | DONE (2026-09-06) |
| G | SVG asset copy → `game/assets/`, AssetLoader seam in `theme.gd`, tile/token/button/dice/house/hotel/corner/type art wired in | assets copied + imported; **in progress** |
| P0 | **Core UI skeleton** — `main.gd` boots straight to `GameView`, `SettingsOverlay` (ex-lobby) with full match config, restart + game-over flow from TopBar, host-only admin gate eats F12 | DONE (2026-09-07) — `tools/p0_probe.tscn` (host + `-- --spectator`) |
| P1 | PlayerIdentity + token/halo/fan layout + walking token animation + player cards | DONE (2026-09-07) — `tools/p1_probe.tscn` (4 checks) |
| P2 | Tile rework (SVG, short names, owner frame, compact mode, highlight frame) | after P0, can parallel P3 |
| P3 | Toast stack + banners + timer ring + BG3 dice + inspector pin (auto-hide) + tooltip autotest | after P0, can parallel P2 |
| P4 | Observer mode (host = not LOCAL), richer journal with filters/export, admin panel tabs + inline results | after P3 |
| P5 | Full RU/EN i18n (dict-based), 5-breakpoint adaptivity (rails/drawers), SFX for dice/toasts/timer | last |

**Validation per phase:** `godot --headless --path game --script res://tests/run.gd`
(`SCRIPT ERROR` grep mandatory), `tools/tony.tscn`, plus phase-specific probes
(`ui_smoke*.tscn`, tooltip coverage probe, etc.). Commit per phase.

Full phase-by-phase file lists, behavioral probes, and the done-criteria for
all 17 tracked UI problems are in the v2 concept doc (sections 11 and the
"Definition of Done" summary). Use that as the working checklist; this plan
only tracks the roadmap, not every sub-task.

## Up next (post-UI)

1. **In-browser WebGL playthrough smoke** (the only Phase-4/5 deferral that
   still matters for stream): run the Web build on real Chrome/Firefox, click
   through a full game, confirm 60 FS-wise acceptable on an overlay.
2. **Real `evil` over a second SDK connection** — requires re-vendoring the
   SDK singleton into per-connection instances; plan is in the dev skill, do
   not start without a live second SDK server.
3. **REMOTE browser client (post-MVP)** — the third human driver, only after
   the UI overhaul is stable.

## Risks (still live)

- Hasbro trade dress → mitigated in `docs/licensing.md`, enforced by review.
- Neuro action spam mid-animation → force only at decision points, engine queue.
- WebGL export quirks with the SDK → POC done, real-browser run pending.
- `llvmpipe` screenshots unreliable → all UI phases judged by behavioral probes.
