#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ui_passport_report.py - turn the UI passport dumps into ONE dossier an agent can read.

Usage:
    python ui_passport_report.py <repo>

Reads  <repo>/build/ui-passport/*.tree.json   (written by game/tools/ui_passport.gd)
Writes <repo>/build/ui-passport/for-agent.md      - the whole interface as text, one file
       <repo>/build/ui-passport/report.html       - the same, with frames when they exist
       <repo>/build/ui-passport/annotated_*.png   - frames annotated from the SAME rects
                                                    (only when Pillow is importable)

Prints `==> UI PASSPORT REPORT OK (N states, F frames, K annotated)` and exits 0/1.
Stdlib only; Pillow is optional and only used for the annotated frames.
"""

import glob
import html
import json
import os
import sys

REGION_IDS = ("top", "topbar", "seats", "stage", "rightcol", "act", "console", "modal",
              "rail-left", "rail-right", "drawer", "journal", "inspector", "players",
              "stat", "ownbar", "board", "center",
              # the web producer's landmarks: HTML tags and roles land as region ids too
              "header", "nav", "main", "aside", "footer", "section", "article", "form", "dialog")
BOX_CAP = 900


def synth_text_md(doc):
    """The screen as text, derived from the tree - for producers that write no .text.md."""
    f = doc.get("facts", {})
    floor = int(f.get("min_font_floor", 9))
    out = ["# UI паспорт: %s" % doc.get("state", "?"), "",
           "producer=%s profile=%s size=%dx%d" % (doc.get("producer", "godot"),
                                                  doc.get("label", "?"),
                                                  int(doc.get("w", 0)), int(doc.get("h", 0))), "",
           "facts: nodes=%s text=%s offscreen=%s clipped=%s small=%s min_font=%s"
           % (f.get("nodes", "?"), f.get("text", "?"), f.get("offscreen", "?"),
              f.get("clipped", "?"), f.get("small", "?"), f.get("min_font", "?")), ""]
    regions = {}
    for e in doc.get("nodes", []):
        if not e.get("txt"):
            continue
        regions.setdefault(str(e.get("region", "other")), []).append(e)
    out.append("## Регионы\n")
    for reg, ents in sorted(regions.items(),
                            key=lambda kv: min(int(e.get("y", 0)) for e in kv[1])):
        ents.sort(key=lambda e: (int(e.get("y", 0)), int(e.get("x", 0))))
        out.append("### %s (y≈%d, %d строк)\n" % (reg, int(ents[0].get("y", 0)), len(ents)))
        for e in ents:
            flags = ""
            if e.get("clipped"):
                flags += " [обрезан]"
            fs = int(e.get("fs", 0))
            if fs and fs < floor and len(str(e["txt"])) > 1:
                flags += " [мелко]"
            if e.get("tip"):
                flags += " [tip]"
            out.append("- (%d,%d) f%d «%s»%s"
                       % (int(e.get("x", 0)), int(e.get("y", 0)), fs, e["txt"], flags))
        out.append("")
    out.append("## Красные флаги\n")
    for title, items in (("вне экрана", f.get("offscreen_list", [])),
                         ("обрезанный текст", f.get("clipped_list", [])),
                         ("ниже пола читаемости", f.get("small_list", []))):
        if items:
            out.append("- %s: %d" % (title, len(items)))
            for it in items:
                out.append("  - %s" % it)
        else:
            out.append("- %s: нет" % title)
    return "\n".join(out) + "\n"


def annotate(frame_path, out_path, doc, Image, ImageDraw):
    """Draw the region frames and every text rect from the SAME tree that produced the dump.
    Returns True when the frame was annotated, False when it does not match the dump (a frame
    of another size would put every box in the wrong place - a lie is worse than a skip)."""
    try:
        img = Image.open(frame_path).convert("RGB")
    except Exception:
        return False
    w, h = int(doc.get("w", 0)), int(doc.get("h", 0))
    if img.size != (w, h):
        return False
    dr = ImageDraw.Draw(img)
    boxes = 0
    for e in doc.get("nodes", []):
        if boxes >= BOX_CAP:
            break
        x, y = int(e.get("x", 0)), int(e.get("y", 0))
        ew, eh = int(e.get("w", 0)), int(e.get("h", 0))
        if ew <= 0 or eh <= 0:
            continue
        nid = str(e.get("id", ""))
        if nid in REGION_IDS:
            dr.rectangle([x, y, x + ew, y + eh], outline=(255, 210, 60), width=2)
            dr.text((x + 3, y + 2), nid, fill=(255, 210, 60))
            boxes += 1
        elif e.get("txt"):
            small = int(e.get("fs", 99)) < 11 or e.get("clipped")
            col = (255, 90, 90) if small else (110, 200, 255)
            dr.rectangle([x, y, x + ew, y + eh], outline=col, width=1)
            boxes += 1
    img.save(out_path)
    return boxes > 0


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    repo = os.path.abspath(argv[0]) if argv else os.getcwd()
    d = os.path.join(repo, "build", "ui-passport")
    for a_ in sys.argv[1:]:
        if a_.startswith("--dir="):
            d = os.path.abspath(a_.split("=", 1)[1])
    files = sorted(glob.glob(os.path.join(d, "*.tree.json")))
    if not files:
        print("==> UI PASSPORT REPORT FAILED: no *.tree.json in %s" % d)
        return 1
    docs = []
    for p in files:
        try:
            with open(p, encoding="utf-8") as fh:
                docs.append(json.load(fh))
        except (OSError, ValueError) as exc:
            print("WARN: cannot read %s: %s" % (p, exc))
    if not docs:
        print("==> UI PASSPORT REPORT FAILED: every dump is unreadable")
        return 1
    docs.sort(key=lambda x: (str(x.get("seq")), str(x.get("label")), str(x.get("state"))))

    Image = ImageDraw = None
    try:
        from PIL import Image as _I, ImageDraw as _D
        Image, ImageDraw = _I, _D
    except ImportError:
        print("NOTE: Pillow not importable - annotated frames skipped (run with `py -3.12`)")

    frames_dir = os.path.join(repo, "build", "renders")
    annotated = frames = 0
    rows = []
    sections = []
    html_blocks = []

    for doc in docs:
        state = str(doc.get("state"))
        label = str(doc.get("label"))
        skin = str(doc.get("skin") or doc.get("producer", "?"))
        facts = doc.get("facts", {})
        w = int(doc.get("w", 0) or facts.get("w", 0))
        h = int(doc.get("h", 0) or facts.get("h", 0))
        md_name = "%s_%s.text.md" % (state, label)
        body = ""
        md_path = os.path.join(d, md_name)
        if os.path.isfile(md_path):
            with open(md_path, encoding="utf-8") as fh:
                body = fh.read()
        if not body:
            # ANY producer may write only the tree + the frame: the text map is derived here,
            # which is what keeps the report universal across the Godot and the web producers.
            body = synth_text_md(doc)
        # The frame for a state: the SG-07 series (build/renders/<state>_<skin>.png) for the game,
        # or a capture sitting NEXT TO the dump (the web passport writes its own screenshot there).
        frame = os.path.join(frames_dir, "%s_%s.png" % (state, skin))
        if not os.path.isfile(frame):
            frame = os.path.join(d, "%s_%s.png" % (state, label))
        has_frame = os.path.isfile(frame)
        # A frame of another SIZE is not this state's frame: pairing a 1440x900 capture with a
        # 1280x720 dump would put every box (and every claim) in the wrong place. Match or skip.
        frame_ok = has_frame
        if has_frame and Image is not None:
            try:
                frame_ok = (Image.open(frame).size == (w, h))
            except Exception:
                frame_ok = False
        if frame_ok:
            frames += 1
        ann_name = "annotated_%s_%s.png" % (state, label)
        ann = ""
        if frame_ok and Image is not None and os.environ.get("NPT_NO_ANNOTATE") != "1":
            if annotate(frame, os.path.join(d, ann_name), doc, Image, ImageDraw):
                ann = ann_name
                annotated += 1
        rows.append((state, label, skin, "%dx%d" % (w, h), int(facts.get("nodes", 0)),
                     int(facts.get("text", 0)), int(facts.get("offscreen", 0)),
                     int(facts.get("clipped", 0)), int(facts.get("small", 0)),
                     int(facts.get("min_font", 0)),
                     "да" if frame_ok else ("другой размер" if has_frame else "нет"),
                     ann or "-", md_name))
        sections.append(body if body else "# %s (%s)\n\n_текстовая карта не найдена_\n"
                        % (state, label))
        img_html = ""
        rel = "../renders/%s_%s.png" % (state, skin)
        if ann:
            img_html += "<img src='%s' alt='annotated'>" % ann
        elif frame_ok:
            img_html += "<img src='%s' alt='frame'>" % rel
        html_blocks.append(
            "<h2>%s <span class='f'>%s · %s · %dx%d · skin=%s</span></h2>%s<pre>%s</pre>"
            % (html.escape(state), html.escape(label), html.escape(skin), w, h,
               html.escape(skin), img_html, html.escape(body)))

    head = ["# Паспорт интерфейса - досье для агента", "",
            "Как читать:",
            "- `for-agent.md` (этот файл) - весь экран словами: состояния, регионы, тексты,",
            "  кегли, флаги;",
            "- `*.tree.json` - то же машинно: узел = id/класс/прямоугольник/текст/кегль/цвет/"
            "клиппинг;",
            "- `annotated_*.png` - кадр с рамками регионов (жёлтые) и текста (голубые; красные ="
            " мелко/обрезано);",
            "- кадры берутся из серии SG-07 (`build/renders/<state>_<skin>.png`), если она"
            " снята; у веб-производителя кадр лежит рядом с дампом.", ""]
    table = ["| состояние | профиль | размер | узлов | текстов | вне экрана | обрезано |"
             " мелко | min кегль | кадр | разметка |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        table.append("| %s | %s | %s | %d | %d | %d | %d | %d | %d | %s | %s |"
                     % (r[0], r[1], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11]))
    out_md = "\n".join(head + table + ["", "Полный текст по состояниям:", ""])
    for i, sec in enumerate(sections):
        out_md += "\n---\n\n" + sec
    out_md += "\n"
    with open(os.path.join(d, "for-agent.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(out_md)
    with open(os.path.join(d, "report.html"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(["<html><head><meta charset='utf-8'><title>UI passport</title>",
                            "<style>body{font:14px system-ui;background:#141018;color:#efe8f6;"
                            "margin:24px}img{max-width:100%;border:1px solid #443a55;"
                            "display:block;margin:8px 0}h2{margin:28px 0 6px}"
                            "pre{background:#1d1727;padding:10px;overflow:auto;font-size:12px}"
                            ".f{color:#b9aecb;font-weight:400}</style></head><body>",
                            "<h1>UI passport</h1>"] + html_blocks + ["</body></html>"]))
    print("==> UI PASSPORT REPORT OK (%d states, %d frames, %d annotated)"
          % (len(docs), frames, annotated))
    return 0


if __name__ == "__main__":
    sys.exit(main())
