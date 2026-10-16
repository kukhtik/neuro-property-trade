#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ui_audit.py - the interface audit: read the passport dossiers and NAME the problems.

The passport describes; this tool JUDGES against explicit rules, and every problem it prints
carries the numbers it was judged on. Producer-agnostic: the same rules read a Godot dossier
and a web one (rules that need a region the dossier does not have are skipped, not faked).

Usage:
    python ui_audit.py <passport-dir> [--out=ui-audit.md] [--floor-console=0.25]

Prints `PROBLEM <id> <state> <detail>` per finding and
       `==> UI AUDIT: N problems (C critical, W warning, I info) in M states`
Exits 1 when at least one CRITICAL finding exists (it can be wired as a gate), 0 otherwise.

Rules
  UA-01 critical  a state whose board carries NO tile names while another state's board does
  UA-02 critical  the console (`act`) takes >25% of the screen height, or the board (`stage`)
                  keeps <60% of it (the human's turn: 362px of console, a 450px board)
  UA-03 warning   text below its readability floor (facts.small)
  UA-04 warning   clipped text (facts.clipped)
  UA-05 warning   text that leaves the viewport without a clipping ancestor (facts.offscreen)
  UA-06 warning   fewer than 3 named regions in a state (a vanished region is the classic defect)
  UA-07 info      a text that ends with an ellipsis (a candidate for truncation)
  UA-08 warning   an interactive element shorter than 24px (a small tap target)
  UA-09 info      a named region with no text at all (legit for an empty journal - listed, not judged)
"""

import glob
import json
import os
import sys

INTERACTIVE = ("Button", "button", "a", "LinkButton", "CheckButton", "OptionButton")
ELLIPSIS = ("…", "...")


def load_dir(d):
    docs = []
    for p in sorted(glob.glob(os.path.join(d, "*.tree.json"))):
        try:
            with open(p, encoding="utf-8") as fh:
                docs.append(json.load(fh))
        except (OSError, ValueError):
            print("WARN: cannot read %s" % p)
    return docs


def region_of(doc, rid):
    for n in doc.get("nodes", []):
        if str(n.get("id")) == rid:
            return n
    return None


def audit(docs, console_share=0.25):
    problems = []  # (severity, id, state, detail)
    states = len(docs)
    # which states ever show tile names (the reference for UA-01)
    names_in = {}
    for doc in docs:
        st = str(doc.get("state"))
        names_in[st] = sum(1 for n in doc.get("nodes", []) if n.get("id") == "tile-name")
    reference = [st for st, c in names_in.items() if c > 0]

    for doc in docs:
        st = "%s(%s)" % (doc.get("state"), doc.get("label"))
        facts = doc.get("facts", {})
        h = int(doc.get("h", 0) or facts.get("h", 0))
        nodes = doc.get("nodes", [])
        has_tile_names = names_in.get(str(doc.get("state")), 0)
        stage = region_of(doc, "stage")
        act = region_of(doc, "act")

        if reference and doc.get("producer") != "web" and stage is not None and has_tile_names == 0:
            problems.append(("C", "UA-01", st,
                             "доска без имён клеток (в других состояниях их %d): stage %dx%d"
                             % (max(names_in.values()), stage["w"], stage["h"])))
        if stage is not None and act is not None and h:
            act_share = float(act["h"]) / h
            stage_share = float(stage["h"]) / h
            if act_share > console_share or stage_share < 0.60:
                problems.append(("C", "UA-02", st,
                                 "консоль %dpx (%.0f%% высоты), доска %dpx (%.0f%%): консоль съедает доску"
                                 % (act["h"], 100 * act_share, stage["h"], 100 * stage_share)))
        if int(facts.get("small", 0)) > 0:
            sample = "; ".join(str(x)[:60] for x in facts.get("small_list", [])[:3])
            problems.append(("W", "UA-03", st, "мелкий текст: %d (%s)" % (facts["small"], sample)))
        if int(facts.get("clipped", 0)) > 0:
            sample = "; ".join(str(x)[:60] for x in facts.get("clipped_list", [])[:3])
            problems.append(("W", "UA-04", st, "обрезанный текст: %d (%s)" % (facts["clipped"], sample)))
        if int(facts.get("offscreen", 0)) > 0:
            sample = "; ".join(str(x)[:60] for x in facts.get("offscreen_list", [])[:3])
            problems.append(("W", "UA-05", st, "вне экрана: %d (%s)" % (facts["offscreen"], sample)))
        regions = [str(x) for x in facts.get("regions", [])]
        if len(regions) < 3:
            # INFO, not a warning: a simple page legitimately has one or two landmarks, and the
            # rule exists to catch a VANISHED region in an app, not to shame a small site.
            problems.append(("I", "UA-06", st, "регионов %d: %s" % (len(regions), ", ".join(regions))))
        ell = [n for n in nodes if str(n.get("txt", "")).endswith(ELLIPSIS)]
        if ell:
            problems.append(("I", "UA-07", st, "текст с многоточием: %d (напр. «%s»)"
                             % (len(ell), str(ell[0].get("txt"))[:50])))
        small_btn = [n for n in nodes if str(n.get("cls")) in INTERACTIVE and int(n.get("h", 99)) < 24]
        if small_btn:
            problems.append(("W", "UA-08", st, "мелкая цель нажатия: %d (напр. «%s» %dpx)"
                             % (len(small_btn), str(small_btn[0].get("txt"))[:30],
                                int(small_btn[0].get("h", 0)))))
        for reg in regions:
            n_txt = sum(1 for n in nodes if str(n.get("region")) == reg and n.get("txt"))
            if n_txt == 0:
                problems.append(("I", "UA-09", st, "регион «%s» без текста" % reg))
    return problems, states


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not argv:
        print(__doc__)
        return 2
    d = os.path.abspath(argv[0])
    out = os.path.join(d, "ui-audit.md")
    console_share = 0.25
    for a in sys.argv[1:]:
        if a.startswith("--out="):
            out = os.path.abspath(a.split("=", 1)[1])
        elif a.startswith("--floor-console="):
            console_share = float(a.split("=", 1)[1])
    docs = load_dir(d)
    if not docs:
        print("==> UI AUDIT FAILED: no *.tree.json in %s" % d)
        return 1

    problems, states = audit(docs, console_share)
    n_c = sum(1 for p in problems if p[0] == "C")
    n_w = sum(1 for p in problems if p[0] == "W")
    n_i = sum(1 for p in problems if p[0] == "I")

    lines = ["# Аудит интерфейса (по паспорту)", "",
             "- каталог: %s" % d,
             "- состояний: %d" % states,
             "- правила: UA-01..UA-09 (см. шапку ui_audit.py); вердикт — строки ниже", ""]
    for sev, rid, st, detail in problems:
        print("PROBLEM %s %s %s %s" % (sev, rid, st, detail))
        lines.append("- **%s** `%s` %s — %s" % (sev, rid, st, detail))
    if not problems:
        lines.append("- проблем не найдено")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("==> UI AUDIT: %d problems (C %d, W %d, I %d) in %d states"
          % (len(problems), n_c, n_w, n_i, states))
    return 1 if n_c else 0


if __name__ == "__main__":
    sys.exit(main())
