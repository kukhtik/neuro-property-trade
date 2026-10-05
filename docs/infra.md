# Infrastructure

What makes this repo reproducible: one pinned engine, one oracle command, one
replay format. Everything here is executable - no step lives only in prose.

## 1. Pinned engine

| | |
|---|---|
| Engine | **Godot 4.7.2-stable** (`.tools/godot-version`, single source of truth) |
| Location | `.tools/godot/` (git-ignored; fetched, never vendored) |
| Fetch | `tools/ci/fetch_godot.sh` - downloads and **sha512-verifies** before unpacking |
| Resolve | `tools/ci/godot_bin.sh` prints the binary path (`$GODOT_BIN` overrides) |

Why pinned: the engine build is part of the determinism contract. Replay
fingerprints are guaranteed *within one build* - every log stores
`godot_version`, and the replay loader refuses to compare fingerprints recorded
by a different engine.

## 2. The oracle

```bash
tools/ci/run_tests.sh            # the gate: exit 0 == green
tools/ci/run_tests.sh --fast     # skip the import pass (warm .godot/)
```

It runs `godot --headless --path game --script res://tests/run.gd` and applies
five gates:

1. an `--import` pass has populated `.godot/` - **a fresh clone has no class
   cache, so `class_name` globals (`I18n`, ...) fail to resolve**; without this
   pass 4 tests fail on a pristine checkout;
2. the runner exit code is 0;
3. the runner printed `ALL TESTS PASSED`;
4. the test count is >= `MIN_TESTS` (default 200) - this is not paranoia: when a
   module fails to compile, `run.gd` skips it, prints `ALL TESTS PASSED` anyway
   and exits 0. The floor is what turns that into a red build;
5. **zero** `SCRIPT ERROR` / `Failed to load script` lines.

`tools/ci/check_clean_clone.sh` is the self-test for all of this: it clones HEAD
into a temp dir, asserts `.tools/` and `game/.godot/` did not leak into the
clone, and runs the oracle there.

### Why not GUT

The suite is a plain-function runner (`tests/run.gd` + a `test_list()` per
module), 227 tests, zero third-party dependencies. GUT would add a plugin, a
second runner and a second config format without adding coverage, and its
default pass criterion is weaker than what the CI requirement actually needs
(count floor + SCRIPT ERROR detection, above).

## 3. Replay / determinism

Harness `game/tools/replay.gd`, CLI `game/tools/replay_cli.gd`. A log is JSONL:
a header, then one line per decision.

```jsonl
{"kind":"header","schema":1,"godot_version":"4.7.2.stable.ed1daf0bf...","game":"g10000","seed":10000,
 "names":["Neuro","Ada","Bo","Cyd"],"settings":{...},"fingerprint0":"<sha256>","fingerprint":"<sha256>"}
{"kind":"call","n":0,"pid":0,"phase":"TURN_START","turn":0,"action":"roll","params":{},"legal":["roll",...],
 "ok":true,"reason":"","features":{...}}
```

* **fingerprint** = `sha256(JSON.stringify(to_snapshot()))` - the whole
  authoritative state, not a summary. Same seed + same decisions + same engine
  build => identical fingerprint, byte for byte.
* **decision replay** is the property that matters: the engine owns all
  randomness, so the recorded decision sequence fully determines the game and a
  log replays without recording dice. This is the "same seeds == same state"
  regression, and the divergence debugger for engine-vs-intent drift.
* **JSON number handling**: `JSON.parse_string` yields floats, so the loader
  re-coerces declared `int`/`bool`/`String` settings fields and integral params
  (`{"tile": 1.0}` -> `{"tile": 1}`). Without it, `rng_seed` arrives as a float,
  `from_data` assigns it to an int var, the Rng is never seeded and every replay
  diverges - and `Array.has(1)` silently misses a `1.0` ownership check.
* **path handling**: `res://`, `user://`, project-relative, MSYS `/c/...` and
  bare MSYS temp paths (`mktemp -d` -> `/tmp/tmp.XXXX`) all resolve to something
  `FileAccess` can open. (A Git-bash path used to open a nonexistent directory,
  and the corpus step then reported "no logs found" while still exiting 0.)
* **`--verify-all` refuses to pass on zero logs.** "Nothing was checked" is a
  failure (exit 1) with a reason, not a green: that combination - an unresolvable
  output path plus a vacuously successful verify - is exactly how a CI job could
  have gone green while verifying nothing.

CLI:

```bash
godot --headless --path game --script res://tools/replay_cli.gd -- --verify corpus/games/g10000.jsonl
godot --headless --path game --script res://tools/replay_cli.gd -- --verify-all corpus/games
godot --headless --path game --script res://tools/replay_cli.gd -- --record build/g.jsonl --seed 10001 --turns 400
godot --headless --path game --script res://tools/replay_cli.gd      # self-test, incl. negative controls
```

Exit 0 = every requested log replayed to its recorded fingerprint. The
self-test also proves the checker can **fail**: it flips an action, bumps a bid
amount and changes a seed, and asserts each is reported as divergence.

## 4. Decision corpus (typed-decision dataset)

`game/tools/corpus.gd` plays whole games with the shared deterministic policy
(`DReplay.decide`) and records every decision point.

```bash
godot --headless --path game --script res://tools/corpus.gd -- \
      --out corpus/games --games 10 --seed 10000 --turns 300 [--no-auctions]
```

Each row is a typed decision - exactly the contract a System-1 model (Laya /
ONNX) needs in order to be benchmarked:

| field | meaning |
|---|---|
| `phase` | `TURN_START` / `PURCHASE_WAIT` / `AUCTION` / trade window |
| `legal` | the closed option set the engine offered |
| `action`, `params` | the heuristic's choice - the label to beat |
| `features` | cash, position, tile cost/rent/group/house_cost, completes_set, own-set groups, houses, jail, opponents |

`corpus/games/*.jsonl` are committed logs (replayable, verified in CI);
`corpus/games/index.json` summarizes the batch (games, decisions, plies,
action/phase histograms, winner, fingerprint, engine build).

**Adoption protocol for a learned policy** (backlog issue #1): benchmark a
candidate on these recorded rows against the recorded labels, and wire it in
only behind the engine's `legal_actions` validation if it wins materially. A
learned policy can never corrupt state - it submits intents like any other seat
and the engine validates every one. Swapping the policy is a change to
`decide()`, not to the engine.

## 5. Seeded soak

`game/tools/soak_cli.gd` plays many seeds headless and asserts progress plus
invariants (no negative cash, one owner per tile, no double-counted ownership,
the winner is the only solvent player, no stall).

```bash
godot --headless --path game --script res://tools/soak_cli.gd -- --sweep 40 --seed 2000 --turns 250 --players 4
godot --headless --path game --script res://tools/soak_cli.gd -- --seed 12345 --turns 120
godot --headless --path game --script res://tools/soak_cli.gd          # self-test, 5 seeds
```

This is the highest-yield tool in the repo so far: writing it found **three
engine bugs that froze or corrupted real games** (`docs/plan.md` has the table).
160 seeds across 2/3/4/6 players now run clean.

## 6. CI

| Workflow | Trigger | Steps |
|---|---|---|
| `.github/workflows/ci.yml` | push / PR | fetch pinned Godot -> oracle -> `--verify-all` on the committed corpus -> regenerate a batch and verify it -> soak sweeps for 2/3/4 players |
| `.github/workflows/web-export.yml` | tag `v*` / manual | fetch Godot + export templates -> `--export-release Web` -> `verify_web_build.sh` -> upload the artifact |

Both cache the pinned engine and verify checksums. The web workflow gates the
*artifact* (real wasm/pck/loader, correct wasm magic, sane sizes); the
in-browser playthrough smoke is still manual and tracked in `docs/plan.md`.

## 7. Local quickstart (pristine checkout)

```bash
git clone https://github.com/kukhtik/neuro-property-trade && cd neuro-property-trade
tools/ci/fetch_godot.sh      # ~86 MB, sha512-verified
tools/ci/run_tests.sh        # expect: ORACLE PASSED (227 tests, 0 SCRIPT ERROR)
```
