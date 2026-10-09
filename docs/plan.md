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

## Completed infrastructure (2026-10-05)

Unfreeze work for the backlog item "Godot headless CI + replay determinism"
(issue #1). Full details and every command: `docs/infra.md`.

- **Pinned engine** — Godot 4.7.2 in `.tools/godot-version`; `tools/ci/fetch_godot.sh`
  fetches and sha512-verifies it, `tools/ci/godot_bin.sh` resolves it.
- **One oracle command** — `tools/ci/run_tests.sh` (import pass + 226 tests +
  a count floor + a zero-`SCRIPT ERROR` gate). `--import` is mandatory: a fresh
  clone has no class cache, and 4 tests fail without it.
- **CI** — `.github/workflows/ci.yml` runs the oracle, replays the committed
  corpus and regenerates a fresh batch; `web-export.yml` builds and verifies the
  WebGL bundle (export templates fetched + checksum-verified).
- **Replay / determinism** — `game/tools/replay.gd` + `replay_cli.gd`. A game is
  fully determined by (settings, names, seed, decision sequence), so logs record
  DECISIONS, not dice, and re-running must reproduce a sha256 of
  `to_snapshot()` byte for byte. This is the "same seeds == same state"
  regression and the engine-vs-intent divergence debugger.
- **Decision corpus** — `game/tools/corpus.gd` plays whole games with the shared
  deterministic policy and records typed decisions (phase, closed legal set,
  chosen action, and the features a System-1 model would consume) into
  `corpus/games/*.jsonl` + `index.json`. This is the dataset the Laya/ONNX
  adoption protocol in issue #1 requires; a learned policy is only ever a
  `decide()` swap, since the engine validates every intent.
- **Seeded soak** — `game/tools/soak_cli.gd` (`--sweep N`) plays many seeds and
  asserts progress + invariants. It immediately found three engine bugs (below).

### Engine bugs found and fixed by the soak

| # | Symptom | Fix |
|---|---|---|
| 1 | **Dead game**: with 3+ players, a rent bankruptcy removed the turn player while `phase` was still `ROLL_RESOLVE`, leaving every seat with zero legal actions. | `_recover_after_player_removal()` reassigns the phase and hands the turn to the survivor `_remove_player` already selected; the trailing end-of-turn is latched off so no seat is skipped. |
| 2 | **Off-board position**: the "Go Back Three Spaces" card resolved to position `-1` (Godot's `%` keeps the dividend's sign), then opened `PURCHASE_WAIT` on a nonexistent tile. | `posmod()` for card movement; `board.type_at()` is bounds-checked (a negative index silently read the LAST tile); an invalid pending purchase now resolves instead of freezing. |
| 3 | **Dead game**: a jailed player with 3 served attempts, no cash and no card had zero legal actions. | Classic ruling: the served sentence resolves on the final attempt (roll → released, no bonus turn), so a jailed seat is never without a move. |

All three are covered by regression tests in `tests/engine_test.gd` /
`tests/seats_test.gd`, plus the new `tests/replay_test.gd` module.

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
| P2 | Tile rework (SVG, short names, owner frame, compact mode, highlight frame) | DONE (2026-09-07) — `tools/p2_probe.tscn` (8 checks) |
| P3 | Toast stack + banners + timer ring + BG3 dice + inspector pin (auto-hide) + tooltip autotest | DONE (2026-09-07) — `tools/p3_probe.tscn` (7 checks) |
| P4 | Observer mode (host = not LOCAL), richer journal with filters/export, admin panel tabs + inline results | DONE (2026-09-07) — `tools/p4_probe.tscn` (5 check-groups, 10 PASS; full detail in `docs/superpowers/references/p4-modes.md`) |
| P5 | Full RU/EN i18n (dict-based), 5-breakpoint adaptivity (rails/drawers), SFX for dice/toasts/timer | DONE (2026-09-08) — `tools/p5_probe.tscn` (9 PASS, 0 masked errors); 204 headless tests green; plan in `docs/superpowers/plans/2026-09-08-p5-i18n-adaptivity-sfx.md` |

**Validation per phase:** `godot --headless --path game --script res://tests/run.gd`
(`SCRIPT ERROR` grep mandatory), `tools/tony.tscn`, plus phase-specific probes
(`ui_smoke*.tscn`, tooltip coverage probe, etc.). Commit per phase.

Full phase-by-phase file lists, behavioral probes, and the done-criteria for
all 17 tracked UI problems are in the v2 concept doc (sections 11 and the
"Definition of Done" summary). Use that as the working checklist; this plan
only tracks the roadmap, not every sub-task.

## Up next (post-UI)

1. ~~**In-browser WebGL playthrough smoke**~~ — DONE. `tools/ci/browser_seat_e2e.py`
   drives a real headless Chrome against the WebGL export and a host seat; the
   browser joins, receives projections and sends intents the host accepts
   (`joined=True`, verdicts ok). `docs/browser_e2e.md` records the setup
   (COOP/COEP headers, `index.html?seat=<token>&host=ws://...`).
2. **Real `evil` over a second SDK connection** — still open. Requires
   re-vendoring the SDK singleton into per-connection instances; plan is in the
   dev skill, do not start without a live second SDK server.
3. ~~**REMOTE browser client (post-MVP)**~~ — DONE, and it is the same work as
   (1): the browser IS a remote seat, driving `remote_driver.gd` on the host.
   What remains is only polish, not plumbing.

**Open UI gaps** (not blockers; each is a deliberate decision, not an oversight):
- skin switcher in the UI — the palette is fully tokenised now (`surface.1`,
  `line`, `board.bg2` and friends resolve from the skin after the dotted-key
  fix), so a switcher would actually show something; the owner deferred it.
- role tabs (`ИГРОК/СТРИМ/АДМИН`) exist in the mockup but must NOT be built:
  roles are chosen at launch (`--stream`/`--admin`/web), by design.
- admin controls (`Пауза`, `Шаг`, `+$500`) live in the F12 panel rather than in
  the action bar, where the mockup puts them.

**UI-vs-mockup verification** is scripted and green: `tools/ci/smoke_all_roles.py`
drives one match with all three roles live, `compare_mockup.py` diffs the
declared palette and breakpoints, and `side_by_side.py` renders the mockup in a
browser at the app's own size. The mockup must be driven into its STARTED state
(`closeSet()` then `startMatch()`) — screenshotting it cold compares an unstarted
design against a running game.

Infrastructure is IN PLACE: see "Completed infrastructure" above and
`docs/infra.md`. When the UI branches settle, the same oracle
(`tools/ci/run_tests.sh`) already gates the engine, and the corpus + soak run in
CI per push. `run.gd` additionally fails on a test function that exists but is
absent from `test_list()`, so a silently unrun test cannot hide behind a green
suite.

## Risks (still live)

- Hasbro trade dress → mitigated in `docs/licensing.md`, enforced by review.
- Neuro action spam mid-animation → force only at decision points, engine queue.
- WebGL export quirks with the SDK → POC done, real-browser run pending.
- `llvmpipe` screenshots unreliable → all UI phases judged by behavioral probes.
