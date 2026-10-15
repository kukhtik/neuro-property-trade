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

`run_tests.sh` fails on a module that does not load, on a `test_*` function missing from
`test_list()`, and on any `SCRIPT ERROR` — a green suite that skipped real work is the failure
mode this gate exists to prevent.

Determinism and robustness checks (all run in CI):

```bash
godot --headless --path game --script res://tools/replay_cli.gd -- --verify-all corpus/games
godot --headless --path game --script res://tools/soak_cli.gd -- --sweep 40 --seed 2000 --players 4
godot --headless --path game --script res://tools/corpus.gd -- --out build/corpus --games 4 --seed 20000
```

Every game is fully determined by (settings, names, seed, decision sequence), so
a recorded log replays to a byte-identical state fingerprint — that is how
engine-vs-intent divergence gets caught. Full details: `docs/infra.md`.

## Playing with other people

**`docs/how-to-play.md`** — local play, play over a network (one host, everyone else joins), and
play in a browser. It has the flags, the role split and a troubleshooting table, written from
commands that were actually run.

The short version: one machine hosts the match and owns the engine; every other seat — another
copy of the game, or a browser — sends intents to it and the engine validates each one. Start the
host on a LAN with `--server-bind=0.0.0.0`, hand each friend the seat token it prints, and they
join with `--seat=<token> --host=ws://<address>:<port>`.

## The Neuro SDK seat

A seat can be played by Neuro herself. Give a seat the `sdk:neuro` driver in the settings sheet
and tell the process where the SDK lives (the vendored `game/addons/neuro-sdk` reads it at start):

```bash
NEURO_SDK_WS_URL=ws://127.0.0.1:8000 godot --path game
```

The seat's adapter (`game/sdk/sdk_adapter.gd`) registers the action set, renders the board for the
model and forces its legal actions; the engine still validates every intent. One SDK connection per
process: a second `sdk:` slot falls back to the internal AI so the match stays playable. Proven
end-to-end by `tools/ci/gates/hg08_sdk_seat_gate.sh`, which plays against a mock websocket server.

## Status

The engine, seats, network host, admin console, visual layer and the UI overhaul are implemented.
Verified by the oracle, the probes and the gate program — all run in CI:

```bash
tools/ci/run_tests.sh     # 356 headless tests (rules engine + the projection contract + UI core)
tools/ci/run_probes.sh    # 3 behavioral probes (i18n, skin, v3 layout)
tools/ci/run_gates.sh     # 21 required gates: functionality (HG) + interface (SG), report in build/gates/
```

Plus determinism (every recorded game replays to a byte-identical fingerprint), a regenerated
decision corpus and seeded soaks, and a WebGL export that a real browser was driven through.

Roadmap and known gaps: `docs/plan.md`.

## License

Code: MIT. Game content: original, non-Hasbro. "Monopoly" is referenced
descriptively only. See `docs/licensing.md`.