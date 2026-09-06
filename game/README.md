# Neuro Property Trade — Godot project (Phase 0)

Rules-engine skeleton, text-first. No art/GUI yet — headless-testable core.

## Layout

```
core/         Deterministic engine classes
  board.gd     Board wrapper over data/board.json (typed accessors)
  player.gd    Player data (money, position, ownership)
  rng.gd       Seeded RNG (all randomness flows through here)
  event_log.gd Append-only event log (replay, stream overlay)
data/
  board.json   40 tiles, original non-Hasbro theme
ui/
  ascii_board.gd  ASCII renderer (demo, debug, future admin console)
tests/        Headless unit tests (plain functions, no test framework)
tools/
  ascii_demo.gd  Board snapshot demo
```

## Run tests

```bash
godot --headless --path game --script res://tests/run.gd
```

Exit code 0 = all pass. Test modules register their cases via a static
`test_list()` returning `Array[String]` of function names; each test func
returns `""`/null on pass or an error string on failure.

## Run the ASCII demo

```bash
godot --headless --path game --script res://tools/ascii_demo.gd
```

## Conventions (project)

- Deterministic engine: seeded RNG, event log; no randomness outside `Rng`.
- No `class TestXxx` — tests are plain functions (per profile convention).
- No Hasbro trademarks/trade dress anywhere (names in `board.json` are
  original; enforced by `board_test.gd`).
