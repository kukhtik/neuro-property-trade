#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Symbols with no non-test consumer: one script, one command, no Godot.

WHY IT EXISTS: rule 3 of docs/program.md - "no code is committed without a live
consumer". That rule was being checked by hand, and hand-checks rot: a comment in
`layout_profile.gd` claimed `UiProfile.text_scale` "has a consumer", which was a
lie for two months. So the check is mechanical now.

WHAT IT DOES
  * walks every product .gd file (game/ui, core, server, seats, visual, data,
    main.gd) and collects declarations: func / const / var / signal / class_name;
  * counts references to each identifier in PRODUCT code (a live consumer),
    in CHECK code (tests, probes, gates, tools - they do not make code live)
    and elsewhere (addons, scenes);
  * a symbol whose product-reference count is 0 is printed as ORPHAN;
  * signals are reported separately: a `signal X` nobody in product code ever
    `connect()`s to is EMITTED-BUT-UNHEARD (this is how `speaking_changed`
    stayed invisible).

CONSUMERS count references from ANY line, string literals included, so
`call("_autostart")` / `connect("x", ...)` / `has_method("x")` count as use.
Being lenient here is deliberate: a loud false positive costs a minute, a missed
orphan costs a promise (see docs/program.md S1-S3).

USAGE (prints findings; exit code is NOT a verdict)
    python tools/ci/unused_symbols.py            # findings only
    python tools/ci/unused_symbols.py --all      # + every symbol it looked at
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
GAME = ROOT / "game"

# Product code: what the player runs. A reference from here is a live consumer.
PRODUCT_GLOBS = ["ui/**/*.gd", "core/**/*.gd", "server/**/*.gd", "seats/**/*.gd",
                 "visual/**/*.gd", "i18n/**/*.gd", "sdk/**/*.gd",
                 "admin/**/*.gd", "main.gd", "main.tscn"]
# Checks: tests, probes, gates, dev tools. A reference from here is NOT a consumer.
CHECK_GLOBS = ["tests/**/*.gd", "tools/**/*.gd", "tools/**/*.tscn"]
# Not judged at all (third-party, generated, build cache).
SKIP_PARTS = (".godot", "addons", ".import")

# Godot calls these itself; "no caller" is the correct design, not a finding.
ENGINE_VIRTUALS = {
    "_init", "_ready", "_enter_tree", "_exit_tree", "_process", "_physics_process",
    "_input", "_unhandled_input", "_unhandled_key_input", "_shortcut_input",
    "_gui_input", "_draw", "_notification", "_to_string", "_get", "_set",
    "_get_property_list", "_property_can_revert", "_validate_property", "_sort_children",
    # Control's layout virtuals: the engine asks the control, nobody "calls" them.
    "_get_minimum_size", "_has_point", "_get_tooltip", "_make_custom_tooltip",
    "_get_drag_data", "_can_drop_data", "_drop_data", "_accessibility_get_contextual_info",
}

DECL_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s*)*"                       # annotations: @export, @onready…
    r"(static\s+)?"
    r"(func\s+(?P<func>[A-Za-z_]\w*)|const\s+(?P<const>[A-Za-z_]\w*)|"
    r"var\s+(?P<var>[A-Za-z_]\w*)|signal\s+(?P<signal>[A-Za-z_]\w*)|"
    r"class_name\s+(?P<class>[A-Za-z_]\w*))")


def rd(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def under_globs(base: pathlib.Path, globs):
    seen = {}
    for g in globs:
        for p in base.glob(g):
            if p.is_file() and not any(s in p.parts for s in SKIP_PARTS):
                seen[str(p.resolve())] = p
    return [seen[k] for k in sorted(seen)]


TOKEN_RE = re.compile(r"[A-Za-z_]\w*")
# An ASSIGNMENT is not a consumer. `p.text_scale = 1.15` made UiProfile.text_scale look
# alive while nobody ever read it - the very defect this scanner exists for (the stream
# role "scaled the type" for months with no reader). A token followed by ` = `, `+=` … is
# written, not used; `==`, `!=` and `:=` are not assignments.
ASSIGN_AFTER = re.compile(r"\s*[+\-*/%]?=(?!=)")


def split_code_comments(text: str):
    """(code, comments) for one file. A COMMENT IS NOT A CONSUMER: the lie this
    script exists to kill was a comment in layout_profile.gd claiming
    `UiProfile.text_scale` "has a consumer". Counting raw text made the scanner
    blind to exactly that defect (found on the first real run)."""
    code, comments = [], []
    for line in text.splitlines():
        cut, in_str, esc, i = -1, False, False, 0
        while i < len(line):
            ch = line[i]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
            elif ch == '"':
                in_str = True
            elif ch == "#":
                cut = i
                break
            i += 1
        if cut < 0:
            code.append(line)
        else:
            code.append(line[:cut])
            comments.append(line[cut:])
    return "\n".join(code), "\n".join(comments)


def histogram(text: str):
    """identifier -> READ occurrences, in one pass. Whole-file tokenising, not per-symbol
    rescans: the naive version was O(declarations x files) and ran for minutes.
    Assignments are excluded (see ASSIGN_AFTER): a field nobody reads has no consumer."""
    c = {}
    for m in TOKEN_RE.finditer(text):
        if ASSIGN_AFTER.match(text, m.end()):
            continue
        t = m.group(0)
        c[t] = c.get(t, 0) + 1
    return c


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="also list symbols with consumers")
    args = ap.parse_args()

    product = under_globs(GAME, PRODUCT_GLOBS)
    checks = under_globs(GAME, CHECK_GLOBS)
    if not product:
        print("FAIL: no product file found - the scan is broken, not the code")
        return 2
    # COVERAGE GUARD (the lesson that keeps repeating in this repo): a glob that
    # stops matching - a renamed directory, a typo - shrinks the scan silently and
    # the tool then reports a confident "nothing wrong". Name every empty glob.
    empty = [g for g in PRODUCT_GLOBS if not under_globs(GAME, [g])]
    if empty:
        print("FAIL: product glob(s) matched NOTHING: " + ", ".join(empty))
        return 2

    # (name, kind, path, line) for every declaration in product code.
    decls = []
    code_hist, cmt_hist = {}, {}
    for p in product:
        code, cmt = split_code_comments(rd(p))
        code_hist[str(p)] = histogram(code)
        cmt_hist[str(p)] = histogram(cmt)
        for i, line in enumerate(code.splitlines(), 1):
            m = DECL_RE.match(line)
            if not m:
                continue
            kind = next(k for k in ("func", "const", "var", "signal", "class") if m.group(k))
            name = m.group(kind)
            if kind == "func" and name in ENGINE_VIRTUALS:
                continue
            decls.append((name, kind, p, i))

    # index check-side text once: per-symbol rescanning of ~200 files is slow.
    check_hist = histogram("\n".join(rd(p) for p in checks))
    # The vendored SDK is a LIBRARY that calls back into product: it invokes
    # `action._get_name()` / `_execute_action()` on our EngineAction. Ignoring
    # addons reported all five of those interface methods as dead on the first
    # run - a deletion that would have broken Neuro's seat outright.
    lib_hist = histogram(split_code_comments(
        "\n".join(rd(p) for p in sorted((GAME / "addons").rglob("*.gd"))))[0])
    decl_count = {}
    for name, kind, path, line in decls:
        decl_count[name] = decl_count.get(name, 0) + 1

    orphans, unheard, scanned = [], [], 0
    for name, kind, path, line in decls:
        scanned += 1
        # live = every occurrence in product CODE, minus the declarations themselves
        # (a declaration is not a use). Strings count: call("x") is a use.
        total = sum(h.get(name, 0) for h in code_hist.values())
        # `class_name Foo` is usually reached by preloading the FILE, not by naming
        # the class: `preload("res://core/player_identity.gd")` never spells
        # `PlayerIdentity`. Counting only the class name reported 12 live classes
        # as orphans on the first run.
        if kind == "class":
            total += sum(h.get(path.stem, 0) for h in code_hist.values())
        sdk_hits = lib_hist.get(name, 0)
        live = total + sdk_hits - decl_count.get(name, 0)
        check_hits = check_hist.get(name, 0)
        cmt_hits = sum(h.get(name, 0) for h in cmt_hist.values())
        rel = path.relative_to(ROOT).as_posix()
        if live == 0:
            (unheard if kind == "signal" else orphans).append(
                (kind, rel, line, name, check_hits, cmt_hits))
        elif args.all:
            print(f"ok      {kind:6s} {rel}:{line}  {name}  product_refs={live}")

    print(f"scanned: {len(product)} product file(s), {len(checks)} check file(s), "
          f"{scanned} declaration(s)")
    print(f"ORPHANS (0 reference in product code): {len(orphans)}")
    for kind, rel, line, name, ch, cm in sorted(orphans, key=lambda t: (t[0], t[1])):
        notes = []
        if ch:
            notes.append(f"{ch} check-line(s)")
        if cm:
            notes.append(f"{cm} comment mention(s) - a comment is not a consumer")
        print(f"  ORPHAN  {kind:6s} {rel}:{line}  {name}"
              + (f"  [{'; '.join(notes)}]" if notes else "  [referenced nowhere]"))
    print(f"SIGNALS emitted but never heard in product code: {len(unheard)}")
    for kind, rel, line, name, ch, cm in sorted(unheard, key=lambda t: t[1]):
        print(f"  UNHEARD {kind:6s} {rel}:{line}  {name}"
              + (f"  [{ch} check-line(s), {cm} comment(s)]" if (ch or cm) else ""))

    # The SDK's own signals matter too: `speaking_changed` was emitted by the addon
    # and listened to by nobody, so the "who is speaking" promise (VOICE-01) had no
    # wire at all - and a scan that only looked at game/ could never say so.
    addon_sigs = []
    for p in sorted((GAME / "addons").rglob("*.gd")):
        for i, line in enumerate(rd(p).splitlines(), 1):
            m = re.match(r"^\s*signal\s+([A-Za-z_]\w*)", line)
            if m:
                addon_sigs.append((p.relative_to(ROOT).as_posix(), i, m.group(1)))
    dead_addon = [s for s in addon_sigs
                  if not any(h.get(s[2], 0) for h in code_hist.values())]
    print(f"SDK/addon signals with no listener in product code: {len(dead_addon)} "
          f"(of {len(addon_sigs)} declared)")
    for rel, line, name in dead_addon:
        print(f"  UNLISTENED {rel}:{line}  {name}")

    # SETTINGS nobody applies: a field of game_settings.gd that the settings screen
    # mentions and nothing OUTSIDE game/ui reads. `spectacle` (the "cinema camera"
    # checkbox) was exactly this - the screen saved it, the engine never looked at
    # it, so the promise was decoration. A settings field is only real when the
    # engine/seats/visual side reads it; the screen alone is not a consumer.
    gs = GAME / "core" / "game_settings.gd"
    consumers = under_globs(GAME, ["core/**/*.gd", "seats/**/*.gd", "visual/**/*.gd",
                                   "server/**/*.gd", "admin/**/*.gd", "sdk/**/*.gd",
                                   "main.gd"])
    cons = histogram("\n".join(split_code_comments(rd(p))[0] for p in consumers))
    ui_hist = histogram("\n".join(split_code_comments(rd(p))[0]
                                  for p in under_globs(GAME, ["ui/**/*.gd"])))
    fields = [m.group(1) for line in split_code_comments(rd(gs))[0].splitlines()
              for m in [re.match(r"^\s*var\s+([A-Za-z_]\w*)", line)] if m]
    unapplied = [f for f in fields if cons.get(f, 0) - 1 <= 0 and ui_hist.get(f, 0) > 0]
    print(f"SETTINGS the screen offers and the game never reads: {len(unapplied)} "
          f"(of {len(fields)} fields in game_settings.gd)")
    for f in unapplied:
        print(f"  UNAPPLIED game/core/game_settings.gd  {f}")
    print("REPORT ONLY - decide per line in docs/program.md P0.2 "
          "(delete / # WIP(track) / wire it up).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
