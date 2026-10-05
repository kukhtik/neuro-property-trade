# Neuro Property Trade

Standalone property-trading board game (classic Monopoly mechanics, original theme)
built for [Neuro-sama](https://twitch.tv/vedal987) integration via the
[Neuro SDK](https://github.com/VedalAI/neuro-sdk).

Target: multi-seat play — Neuro, Evil Neuro and human players at the same board,
with the game fully under its own rules engine's control (AI players submit
intents; the engine validates and executes them; the AI can never corrupt state).

## Why standalone

- Monopoly **mechanics are public domain** (patent expired; see `docs/licensing.md`).
  Hasbro trademarks are NOT used: original name, street names, tokens and art.
- Full control over game state → clean, reliable Neuro state-reads and action
  validation without reverse-engineering a commercial title.
- Sits in the gap Vedal described as "intellectually challenging work" for the
  community, after his internal AI started handling routine game-integration mods.

## Stack

- **Godot 4.x** (2D board, WebGL export) + official [Godot Neuro SDK](https://github.com/VedalAI/neuro-sdk/tree/main/Godot)
- Rules engine in GDScript, deterministic, unit-tested headless
- Seats: human players (local/remote) + AI seats (`neuro`, `evil`) via SDK
- Optional voice-chat side-channel (`API/VOICE_CHAT.md`) for table talk

## Repo layout

```
game/            Godot 4 project: core rules engine, sdk adapter, seats, UI
  core/          authoritative engine (deterministic, headless-testable)
  sdk/           Neuro adapter: state projection, actions, force windows
  seats/         seat layer + drivers (LOCAL/AI/CHAT/SDK)
  tools/         headless probes, replay/corpus/soak CLIs
  tests/         headless test modules (run via res://tests/run.gd)
tools/ci/        pinned toolchain fetch + the oracle + web-build verify
corpus/games/    recorded decision corpus (replayable JSONL logs)
docs/            Licensing, plan, infra, decision records
```

## Build & test

```bash
tools/ci/fetch_godot.sh      # pinned Godot, sha512-verified (~86 MB)
tools/ci/run_tests.sh        # THE ORACLE: import + suite + SCRIPT ERROR gate
```

The engine needs no renderer, so the whole rules suite runs headless. `--import`
first is mandatory: a fresh clone has no `.godot/` class cache and `class_name`
globals fail to resolve without it — the script does that for you.

Determinism and robustness checks (all run in CI):

```bash
godot --headless --path game --script res://tools/replay_cli.gd -- --verify-all corpus/games
godot --headless --path game --script res://tools/soak_cli.gd -- --sweep 40 --seed 2000 --players 4
godot --headless --path game --script res://tools/corpus.gd -- --out build/corpus --games 4 --seed 20000
```

Every game is fully determined by (settings, names, seed, decision sequence), so
a recorded log replays to a byte-identical state fingerprint — that is how
engine-vs-intent divergence gets caught. Full details: `docs/infra.md`.

## Status

Engines, seats, admin console and the visual layer are implemented (Phases 0-5,
226 headless tests green). The UI/UX overhaul is the current phase; headless
infrastructure (CI, replay, corpus, soak) is in place. Roadmap: `docs/plan.md`.

## License

Code: MIT. Game content: original, non-Hasbro. "Monopoly" is referenced
descriptively only. See `docs/licensing.md`.