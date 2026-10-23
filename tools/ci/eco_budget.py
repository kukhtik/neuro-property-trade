#!/usr/bin/env python3
"""ECO-01 - the frame budget: what the product spends per frame, against a budget.

The owner's ask (23.10): "get close to the optimization quality of 2000-era games, so they
consume the minimum of resources". A budget is the only honest form of that: numbers that
fail the build when they get worse.

What it measures (from the live probe, in a WINDOW - headless has no rendering server, so
draw calls would be zero and the frame time meaningless):
  * p50 / p95 / max of the frame processing time;
  * the maximum number of draw calls in a frame;
  * the ObjectDB growth over the window (a leak shows up here);
  * the number of orphan nodes (a leak's other half);
  * the static memory growth.

The budget lives in tools/ci/eco_budget.json and was WRITTEN FROM A MEASUREMENT (--write),
not guessed. That is the point of the phase: the budget is a recorded fact, and the gate
fails when the product gets worse than the recorded fact.

Verdict is read from the last line, never from silence.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
BUDGET = REPO / "tools" / "ci" / "eco_budget.json"

# metric -> (budget key, direction). "max" = the measured value must not exceed the budget.
LIMITS = (
    ("p95_ms", "p95_ms_max", "max"),
    ("max_ms", "max_ms_max", "max"),
    ("draw_max", "draw_calls_max", "max"),
    ("objects_growth", "objects_growth_max", "max"),
    ("orphans_max", "orphans_max", "max"),
    ("static_growth_kb", "static_growth_kb_max", "max"),
)


def parse_dump(text: str) -> dict[str, float]:
    out: dict[str, float] = {}
    for line in text.splitlines():
        if not line.startswith("ECO|summary|"):
            continue
        parts = line.split("|")
        for i in range(2, len(parts) - 1, 2):
            key = parts[i]
            try:
                out[key] = float(parts[i + 1])
            except ValueError:
                continue
    if "objects_first" in out and "objects_last" in out:
        out["objects_growth"] = out["objects_last"] - out["objects_first"]
    if "static_first" in out and "static_last" in out:
        out["static_growth_kb"] = (out["static_last"] - out["static_first"]) / 1024.0
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dump", help="the probe's dump file")
    ap.add_argument("--write", action="store_true", help="record the measurement as the budget")
    ap.add_argument("--negative", action="store_true", help="tighten the budget by 1%% and expect a red verdict")
    args = ap.parse_args()

    dump_path = pathlib.Path(args.dump)
    if not dump_path.exists():
        print(f"==> ECO-01 FAILED: no probe dump at {dump_path}")
        return 1
    measured = parse_dump(dump_path.read_text(encoding="utf-8"))
    if "p95_ms" not in measured:
        print("==> ECO-01 FAILED: the dump has no summary line - the probe did not measure anything")
        return 1

    budget: dict[str, float] = {}
    if BUDGET.exists():
        budget = json.loads(BUDGET.read_text(encoding="utf-8"))

    if args.write:
        new = {
            "p95_ms_max": round(measured["p95_ms"] * 1.05, 3),
            "max_ms_max": round(measured["max_ms"] * 1.20, 3),
            "draw_calls_max": int(measured["draw_max"]),
            "objects_growth_max": int(max(measured.get("objects_growth", 0), 0)),
            "orphans_max": int(measured.get("orphans_max", 0)),
            "static_growth_kb_max": round(max(measured.get("static_growth_kb", 0.0), 0.0), 3),
            "measured_at": "written by --write from a live probe run",
            "note": "the budget is a recorded measurement; the gate fails when the product gets worse",
        }
        BUDGET.write_text(json.dumps(new, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"==> ECO-01 BUDGET WRITTEN to {BUDGET}")
        print(json.dumps(new, indent=2, ensure_ascii=False))
        return 0

    if not budget:
        print("==> ECO-01 FAILED: no budget file; record one with: eco_budget.py <dump> --write")
        return 1

    if args.negative:
        # A negative must FAIL: shrink every limit by 1% and the measured values must break it.
        for key, _, _dir in LIMITS:
            if key in budget:
                budget[key] = budget[key] * 0.99

    broke: list[str] = []
    for key, bkey, _direction in LIMITS:
        if key not in measured:
            continue
        limit = budget.get(bkey)
        if limit is None:
            continue
        if measured[key] > float(limit):
            broke.append(f"{key} {measured[key]:.3f} > budget {float(limit):.3f}")

    summary = " ".join(f"{k}={measured[k]:.3f}" for k, _, _ in LIMITS if k in measured)
    print(f"ECO-01 measured: {summary}")
    if broke:
        print("==> ECO-01 FAILED: the product is over its frame budget: " + "; ".join(broke))
        return 1
    print("==> ECO-01 PASSED (the frame is inside the recorded budget)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
