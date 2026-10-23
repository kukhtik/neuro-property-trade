# Neuro Property Trade

Standalone property-trading board game (the classic tabletop property-trading
mechanics, original theme)
built for [Neuro-sama](https://twitch.tv/vedal987) integration via the
[Neuro SDK](https://github.com/VedalAI/neuro-sdk).

Target: multi-seat play — Neuro, Evil Neuro and human players at the same board,
with the game fully under its own rules engine's control (AI players submit
intents; the engine validates and executes them; the AI can never corrupt state).

## Why standalone

- The **mechanics are public domain**: the patent expired in 1954, and a game's rules
  are an idea, not expression (see `docs/licensing.md`). Third-party trademarks and
  trade dress are NOT used: original name, street names, tokens and art.
- Full control over game state → clean, reliable Neuro state-reads and action
  validation without reverse-engineering a commercial title.
- A board game is a good fit for the Neuro API: low actions per minute, a state that
  can be described in text, and decisions (buy, bid, trade) worth arguing about. The
  Neuro SDK lists board games among the ones that work well.

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
docs/            program.md (the plan), licensing, infra, specs, how-to-play
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
model and forces its legal actions; the engine still validates every intent.

**Several SDK seats can share one process.** A seat with its OWN endpoint gets its own
connection (`sdk_endpoint` in the seat settings); a seat without one uses the shared
`NEURO_SDK_WS_URL`, and only the FIRST such seat can use it — the rest play as the
internal AI, and the journal says so out loud rather than silently downgrading. This is
proven end to end by `tools/ci/gates/hg08_sdk_seat_gate.sh` (one seat against a mock
websocket) and `tools/ci/multi_sdk_gate.sh` (TWO seats, two connections, one process).

The endpoint variables used by the multi-seat tooling are `NPT_SDK_A` / `NPT_SDK_B`.
They are a local extension of ours, not part of the SDK specification: the published
protocol has one websocket per character.

## Status

The engine, seats, network host, admin console, visual layer and the UI overhaul are implemented.
Verified by the oracle, the probes and the gate program — all run in CI:

```bash
tools/ci/run_tests.sh     # 428 headless tests (rules engine + the projection contract + UI core)
tools/ci/run_probes.sh    # 3 behavioral probes (i18n, skin, v3 layout)
tools/ci/run_gates.sh     # 46 gates (38 required + 8 in quarantine): functionality (HG) + interface (SG), report in build/gates/
```

Plus determinism (every recorded game replays to a byte-identical fingerprint), a regenerated
decision corpus and seeded soaks, and a WebGL export that a real browser was driven through.
`python tools/ci/unused_symbols.py` reports product code with no consumer (orphan symbols,
unlistened signals, settings nobody applies).

The board is one ring that IS the frame: at 1600x1200 the band is 190px, a cell is 91px and the
four corner cells carry the glance layer (whose turn, phase, bank, round) at a size that still
reads 12px when the frame is scaled to a 390px phone. Both requirements are functions of the
frame, so the same layout holds from 1600x1200 to 4K; the one frame that cannot carry both is
1920x1080 (16:9), and `docs/restoration/gates.md` shows the arithmetic.

Two interface gates compare the live frame with the reference mockup: `MOCK-01` measures the
consistency zone by zone, `MOCK-02` measures the visual taste (every font size is a step of the
skin's scale, nothing is above the 48px cap, and a role is never overridden under the screen).
Both are still in quarantine and both have a checked negative.

The open task is resource consumption: the target is the frugality of 2000-era games — no
allocations in the frame, no tree lookups in the frame, memory that does not grow over a long
match, and repaints on events rather than every frame. The gates for it (`ECO-01…ECO-05`) are
**not written yet** and no budget is fixed, so the word "optimized" claims nothing today; the
plan is `docs/program.md` §4a. The rule of the phase: measure, change one thing, keep every
quality gate green, measure again — a lighter build that looks or plays worse is rejected.

The package already carries nothing the game does not use: the release `.pck` went from
1 074 960 to 676 612 bytes (−37.1 %, 492 → 310 files) after the CI probes were excluded, and
the acceptance check proves both directions — no foreign file under `res://tools/`, and the
product's own `replay.gd` still in the pack. The engine itself (`index.wasm`, 39.5 MB) is 58
times the pack and can only be trimmed by building a custom export template.

Roadmap and known gaps: `docs/program.md` (the single plan) + the current snapshot in
`docs/restoration/`.

## License

Code: MIT. Game content: original — no third-party trademarks, trade dress or character
designs are used. The mechanics themselves are public domain (the patent expired in
1954); the legal basis and the naming rules are in `docs/licensing.md`.