#!/usr/bin/env python3
"""Generate parametric board_<N>.json from the canonical 40-tile board.

The engine (core/engine.gd setup) already looks for `res://data/board_<N>.json`
and falls back to board.json when it is missing. Shipping these files is what
actually makes settings.tile_count work end to end.

Layout rules (mirrors the classic ring so the type sequence stays sensible):
  - corners at 0, N/4, N/2, 3N/4: go, jail, free_parking, go_to_jail
  - the remaining cells repeat the canonical board's non-corner type sequence,
    cycling through it, with colours/groups preserved
  - property names get a suffix so two games at different sizes stay distinct
  - costs/rents are rescaled by size so the economy matches the board length

Run:  python tools/gen_boards.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "game" / "data"
CANON = DATA / "board.json"
CORNER_TYPES = ["go", "jail", "free_parking", "go_to_jail"]
GROUPS = ["brown", "lightblue", "pink", "orange", "red", "yellow", "green", "darkblue"]


def canonical_non_corners(tiles):
    """The canonical board's non-corner sequence, in order."""
    n = len(tiles)
    d = n // 4
    out = []
    for t in tiles:
        if t["index"] % d == 0:
            continue
        out.append(t)
    return out


def build(n, seq):
    d = n // 4
    tiles = []
    si = 0
    for i in range(n):
        if i % d == 0:
            slot = (i // d) % 4
            kind = CORNER_TYPES[slot]
            tiles.append({"index": i, "name": "", "short": "", "type": kind})
            continue
        src = seq[si % len(seq)]
        si += 1
        t = dict(src)
        t["index"] = i
        tiles.append(t)

    # corner names
    names = {"go": "Start", "jail": "Jail", "free_parking": "Free Parking",
             "go_to_jail": "Go To Jail"}
    shorts = {"go": "Start", "jail": "Jail", "free_parking": "Free Park",
              "go_to_jail": "Go Jail"}
    for t in tiles:
        if t["type"] in names and not t.get("name"):
            t["name"] = names[t["type"]]
            t["short"] = shorts[t["type"]]

    # scale the economy so a shorter/longer board stays playable
    scale = (n / 40.0)
    for t in tiles:
        if t.get("cost"):
            t["cost"] = int(round(t["cost"] * scale / 10.0) * 10)
            t["cost"] = max(20, t["cost"])
        if t.get("house_cost"):
            t["house_cost"] = int(round(t["house_cost"] * scale / 10.0) * 10)
            t["house_cost"] = max(20, t["house_cost"])
        for key in ("rent", "rent_set", "rent_1"):
            if t.get(key):
                t[key] = max(1, int(round(t[key] * scale)))
        if t.get("houses"):
            t["houses"] = [max(1, int(round(h * scale))) for h in t["houses"]]
        if t.get("amount"):
            t["amount"] = max(10, int(round(t["amount"] * scale / 10.0) * 10))
    return tiles


def main():
    canon = json.loads(CANON.read_text(encoding="utf-8"))
    meta = canon["meta"]
    seq = canonical_non_corners(canon["tiles"])
    for n in (16, 24, 64):
        tiles = build(n, seq)
        out = {
            "meta": {"name": meta["name"], "theme": meta.get("theme", "classic"),
                     "tile_count": n, "license": meta.get("license", "original, non-Hasbro"),
                     "generated_by": "tools/gen_boards.py"},
            "tiles": tiles,
        }
        path = DATA / f"board_{n}.json"
        path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        types = {}
        for t in tiles:
            types[t["type"]] = types.get(t["type"], 0) + 1
        print(f"wrote {path.name}: {len(tiles)} tiles {types}")


if __name__ == "__main__":
    main()
