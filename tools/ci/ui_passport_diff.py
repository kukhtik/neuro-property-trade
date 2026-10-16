#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ui_passport_diff.py - what changed between two UI passports.

Usage:
    python ui_passport_diff.py <repo> [--baseline=build/ui-passport/baseline]

Compares  current  <repo>/build/ui-passport/*.tree.json
     against baseline <dir>/*.tree.json   (default: build/ui-passport/baseline)

Writes <repo>/build/ui-passport/diff.md and prints
  `==> UI PASSPORT DIFF: S states, +A added, -R removed, ~C changed, ΔM micro-shifts`
or `==> UI PASSPORT DIFF FAILED: <reason>` (exit 1) when there is no baseline.

Keys are node paths with Godot's auto-numbering (`@Panel@145`) stripped, so a control keeps its
identity between runs; the added/removed lines are exactly how a renamed or deleted control
shows up. Rects are compared with a 1px tolerance (micro-shifts up to 4px are counted apart),
and text, font size, colour, tooltip, the clipped flag and the region are compared exactly.
"""

import glob
import json
import os
import re
import sys

AUTO = re.compile(r"@\d+$")
FIELDS = ("txt", "fs", "col", "tip", "clipped", "region")
LIST_CAP = 12


def key_of(node):
    path = str(node.get("path", ""))
    return "/".join(AUTO.sub("", p) for p in path.split("/"))


def rect_of(n):
    return (int(n.get("x", 0)), int(n.get("y", 0)), int(n.get("w", 0)), int(n.get("h", 0)))


def load(d):
    out = {}
    for p in glob.glob(os.path.join(d, "*.tree.json")):
        try:
            with open(p, encoding="utf-8") as fh:
                out[os.path.basename(p)] = json.load(fh)
        except (OSError, ValueError):
            print("WARN: cannot read %s" % p)
    return out


def facts_line(doc):
    f = doc.get("facts", {})
    return "nodes=%s text=%s offscreen=%s clipped=%s small=%s min_font=%s" % (
        f.get("nodes", "?"), f.get("text", "?"), f.get("offscreen", "?"),
        f.get("clipped", "?"), f.get("small", "?"), f.get("min_font", "?"))


def main():
    argv = sys.argv[1:]
    repo = os.path.abspath(argv[0]) if argv and not argv[0].startswith("--") else os.getcwd()
    base_rel = "build/ui-passport/baseline"
    for a in argv:
        if a.startswith("--baseline="):
            base_rel = a.split("=", 1)[1]
    cur_dir = os.path.join(repo, "build", "ui-passport")
    for a_ in argv:
        if a_.startswith("--dir="):
            cur_dir = os.path.abspath(a_.split("=", 1)[1])
    base_dir = base_rel if os.path.isabs(base_rel) else os.path.join(repo, base_rel)
    cur = load(cur_dir)
    base = load(base_dir)
    if not cur:
        print("==> UI PASSPORT DIFF FAILED: no dumps in %s" % cur_dir)
        return 1
    if not base:
        print("==> UI PASSPORT DIFF FAILED: no baseline in %s (run ui_passport.sh --save-baseline first)"
              % base_dir)
        return 1

    lines = ["# UI passport diff", "",
             "- current : %s" % cur_dir,
             "- baseline: %s" % base_dir,
             "- правило: ключ = путь узла без авто-нумерации (@NNN); rect с допуском 1px;",
             "  текст/кегль/цвет/тултип/клип/регион — точно; микро-сдвиги ≤4px считаются отдельно.",
             ""]
    tot_add = tot_rem = tot_ch = tot_sh = 0
    states = 0
    for name in sorted(cur):
        states += 1
        if name not in base:
            lines.append("## %s\n\n- НОВОЕ состояние (нет в базе)\n" % name)
            continue
        cdoc, bdoc = cur[name], base[name]
        cn = {key_of(n): n for n in cdoc.get("nodes", [])}
        bn = {key_of(n): n for n in bdoc.get("nodes", [])}
        added = sorted(k for k in cn if k not in bn)
        removed = sorted(k for k in bn if k not in cn)
        changed, shifted = [], []
        for k in sorted(set(cn) & set(bn)):
            x, y = cn[k], bn[k]
            rx, ry = rect_of(x), rect_of(y)
            d = sum(abs(rx[i] - ry[i]) for i in range(4))
            rec = []
            if d > 1:
                rec.append("rect %s -> %s" % (ry, rx))
            for f in FIELDS:
                vx, vy = str(x.get(f, "")), str(y.get(f, ""))
                if vx != vy:
                    rec.append("%s «%s» -> «%s»" % (f, vy[:36], vx[:36]))
            if not rec:
                continue
            if d <= 4 and all(r.startswith("rect ") for r in rec):
                shifted.append((k, rec))
            else:
                changed.append((k, rec))
        tot_add += len(added)
        tot_rem += len(removed)
        tot_ch += len(changed)
        tot_sh += len(shifted)
        fdiff = ""
        if facts_line(cdoc) != facts_line(bdoc):
            fdiff = "\n- facts: %s  ->  %s" % (facts_line(bdoc), facts_line(cdoc))
        else:
            fdiff = "\n- facts: без изменений (%s)" % facts_line(cdoc)
        lines.append("## %s\n\n+%d added, -%d removed, ~%d changed, Δ%d micro-shifts%s\n"
                     % (name, len(added), len(removed), len(changed), len(shifted), fdiff))
        for k in added[:LIST_CAP]:
            lines.append("- + %s" % k)
        if len(added) > LIST_CAP:
            lines.append("- + ...и ещё %d" % (len(added) - LIST_CAP))
        for k in removed[:LIST_CAP]:
            lines.append("- - %s" % k)
        if len(removed) > LIST_CAP:
            lines.append("- - ...и ещё %d" % (len(removed) - LIST_CAP))
        for k, rec in changed[:LIST_CAP]:
            lines.append("- ~ %s :: %s" % (k, "; ".join(rec)))
        if len(changed) > LIST_CAP:
            lines.append("- ~ ...и ещё %d" % (len(changed) - LIST_CAP))
        for k, rec in shifted[:LIST_CAP]:
            lines.append("- Δ %s :: %s" % (k, "; ".join(rec)))
        lines.append("")

    gone = [n for n in base if n not in cur]
    if gone:
        lines.append("## Исчезли состояния\n")
        for n in sorted(gone):
            lines.append("- %s" % n)

    out_path = os.path.join(cur_dir, "diff.md")
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("==> UI PASSPORT DIFF: %d states, +%d added, -%d removed, ~%d changed, Δ%d micro-shifts "
          "(diff.md)" % (states, tot_add, tot_rem, tot_ch, tot_sh))
    return 0


if __name__ == "__main__":
    sys.exit(main())
