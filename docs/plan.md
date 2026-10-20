# NPT — map of the repository (not a plan)

> This file stopped being a roadmap on 2026-10-16 (P0.3). **The plan is
> `docs/program.md`** — the only one; the gate registry is `docs/restoration/gates.md`,
> the current state snapshot is the dated `state-*.md` next to it. What remains here
> is orientation: where things live, which decisions are closed, how to run things.
> The phase tables, "up next" list and risk roll-up that used to live here were
> history and were deleted with the rest of it (git has them).

## Repo layout

```
game/              Godot 4 project
  core/            authoritative engine (deterministic, headless-testable) — NOT to be rewritten
  seats/           seat layer + drivers (LOCAL / AI / CHAT / REMOTE / SDK)
  sdk/             Neuro SDK adapter: projection, actions, force windows
  ui/              GameView + panels; ui/core/ holds the seams (profile, layout, intents, events)
  visual/          board scene, tiles, tokens, skins, effects, sfx
  admin/           F12 host console
  server/          network host (protocol is pure and socket-free)
  i18n/            dictionaries (data_*.gd) + the lookup
  tools/           headless probes, gates, replay/corpus/soak CLIs
  tests/           headless test modules (run via res://tests/run.gd)
design/            v3 "Broadcast Table" package: DESIGN.md, ui-prototype.html, tokens, coverage
tools/ci/          pinned toolchain, THE oracle, gates, exports, browser drivers
docs/              program.md + specs/ + licensing, infra, how-to-play, browser_e2e
corpus/games/      recorded decision corpus (replayable JSONL)
build/             artifacts (gitignored): web/, windows/, gates/, renders/, current/
```

## Where the truth lives

| Question | File |
|---|---|
| What are we doing next, and why | `docs/program.md` |
| Which checks exist and what they prove | `docs/restoration/gates.md` |
| What is true right now (numbers, evidence) | `docs/restoration/state-*.md` (newest) |
| What the interface must do (F-01…F-73, P-1…P-16) | `docs/specs/ui-full-redesign-spec.md` |
| How the interface should look | `design/DESIGN.md` + `design/ui-prototype.html` |
| What the engine can and cannot expose | `docs/ui_migration_notes.md` |
| Rules, seats, match config | `docs/specs/game-concept-spec.md` |
| Licensing cleanliness | `docs/licensing.md` (guardian: `game/tests/board_test.gd`) |
| CI, replay, corpus, soak | `docs/infra.md` |
| Joining a match from a browser | `docs/browser_e2e.md`, `docs/how-to-play.md` |

## Decisions already closed — do NOT re-litigate

- **One screen.** No lobby scene: `GameView` is always the root, the match config lives in
  `SettingsOverlay` on top of a live board.
- **The board is always whole.** The camera is optional and off by default; the full 40-tile
  ring fits the viewport.
- **Role is chosen at LAUNCH**, never as a UI toggle: `--stream` / `--admin` / the web build
  (`UiProfile`). Role tabs exist in the mockup and must NOT be built.
- **`core/player_identity.gd` is the single source of player colour + token**; skins seed its
  palette (`SkinManager.sync_identity_palette`). The engine never sees a colour, so seeding
  cannot break replays.
- **`TileView` / `BoardCenter` / `EffectLayer` / `BuildingStrip` are container-built** and stay
  that way — no absolute positioning inside a cell.
- **Two text roles only:** a value (no wrap, by content) and a paragraph (wraps, expands).
  A widget factory sets appearance, never container-axis flags.
- **UI is judged by behavioural probes**, not by llvmpipe/SwiftShader screenshots.
- **The engine is authoritative:** AI/remote/chat seats submit intents; the engine validates and
  executes them. Determinism runs through the seeded `Rng` only.

## Model routing (this profile)

| Role | Model | Note |
|---|---|---|
| heavy code / architecture / review | `deepseek-v4-flash` | default of this profile |
| parallel GDScript on a fixed interface | `minimax-m2.7` | same cost tier |
| crisply-specified executor (QA/docs/aggregation) | `gemma4` | cheapest; needs fully-specified goals |

CREATE/design/undefined or investigate-a-discrepancy → deepseek-v4-flash; bulk GDScript on a
fixed interface → minimax-m2.7; execute-a-listed-schema → gemma4.

## Running things

```bash
tools/ci/fetch_godot.sh          # pinned Godot 4.7.2, sha512-verified
tools/ci/run_tests.sh            # THE ORACLE: import + 421 tests + count floor + SCRIPT ERROR gate
tools/ci/run_probes.sh           # 3 behavioural probes
tools/ci/run_gates.sh            # 27 required gates, none in quarantine; report in build/gates/
python tools/ci/unused_symbols.py  # product code with no consumer (report)
```

Detailed history of the engine foundations (phases 0–5), the 2026-10 infrastructure work and the
three engine bugs the soak found is in `docs/infra.md` and in git.
