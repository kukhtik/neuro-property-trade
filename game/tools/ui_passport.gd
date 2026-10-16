extends Node
## UI PASSPORT — the agent's eyes and text description of the real interface.
##
## WHY: a gate answers "did READ-01 pass?", it does not let an agent SEE the screen or
## understand what is on it. This scene boots the REAL `MainScript` (headless - the layout is
## exact once the root size is pinned), drives it to named states through the same seams the
## behavioural gates use, and for every state writes a PAIR:
##
##   <state>_<profile>.tree.json  — every visible Control: id, class, rect, text, font size,
##                                  colour, tooltip, clipping, region;
##   <state>_<profile>.text.md    — the screen AS TEXT: per region, every visible string in
##                                  reading order with its font size, plus red flags
##                                  (off-screen, clipped, below the readability floor).
##
## The pair is what lets an agent "see" the interface without a screenshot and "understand" it
## without guessing; the frame PNGs (SG-07 series) can be annotated from the same rects.
##
## NOT a gate: it never judges. Verdicts live in the gates; this file describes.
##
## Usage:
##   godot --headless --path game res://tools/ui_passport.tscn -- \
##         --seq=<pre|match> --outdir=<abs dir> [--skin=<id>] [--role=<player|stream|admin>]
##         [--size=WxH] [--label=<profile name>]
##
## Prints `UI-PASSPORT STATE <state> nodes=<n> text=<t> offscreen=<o> clipped=<c> min_font=<f>`
## per state and `UI PASSPORT DONE seq=<seq> states=<n> misses=<k>` at the end.
const MainScript := preload("res://main.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const I18n := preload("res://i18n/i18n.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")

const WATCHDOG_MS := 300000
const SETTLE := 14
const NODE_CAP := 1500
const TEXT_LIMIT := 96
const OFF_TOL := 2
const SMALL_FONT := 9
## Region ids the report and the annotations group by. A node without a known region id is
## attributed to the nearest named ancestor, so every string on screen lands somewhere.
const REGION_IDS := ["top", "topbar", "seats", "stage", "rightcol", "act", "console",
					 "modal", "rail-left", "rail-right", "drawer", "journal", "inspector",
					 "players", "stat", "ownbar", "board", "center"]

var _seq := "pre"
var _skin := ""
var _role := ""
var _label := ""
var _size := Vector2i(1440, 900)
var _outdir := "user://ui-passport"
var _launcher = null
var _human := 0
var _dumps := 0
var _misses: Array = []
var _t0 := 0
var _done := false

## FILM mode (motion + behaviour): the sampler records, every `_film_dt` ms, the geometry /
## alpha / rotation / scale of every Control plus the engine phase; the script marks the actions
## it takes. Structural, not pixel: a Control that moved, faded or span is a fact of the scene
## tree - exactly what an agent can reason about. Frames for the same moment come from SG-07.
var _film_samples: Array = []
var _film_marks: Array = []
var _film_stop := false
var _film_dt := 50
var _film_t0 := 0


func _process(_dt: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_miss("watchdog", "the passport did not finish in %ds" % (WATCHDOG_MS / 1000))
		_finish()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--seq="):
			_seq = s.substr(6)
		elif s.begins_with("--skin="):
			_skin = s.substr(7)
		elif s.begins_with("--role="):
			_role = s.substr(7)
		elif s.begins_with("--label="):
			_label = s.substr(8)
		elif s.begins_with("--size="):
			var d := s.substr(7).split("x")
			if d.size() == 2:
				_size = Vector2i(int(d[0]), int(d[1]))
		elif s.begins_with("--outdir="):
			_outdir = s.substr(9)
	DirAccess.make_dir_recursive_absolute(_outdir)
	if _skin != "":
		SkinManager.chosen = _skin
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(_size)
	get_tree().root.size = _size
	_t0 = Time.get_ticks_msec()
	_launcher = MainScript.new()
	if _role != "":
		# Setup BEFORE add_child: main's _ready() derives the profile and registers actions then.
		_launcher.set("_force_profile", UiProfileScript.for_id(_role))
	add_child(_launcher)
	_run()


func _run() -> void:
	await _frames(12)
	_human = _derive_human()
	match _seq:
		"pre":
			await _seq_pre()
		"match":
			await _seq_match()
		"film":
			await _seq_film()
		_:
			_miss("seq", "unknown sequence `%s`" % _seq)
	_finish()


## --- sequences (the same seams the behavioural gates use) -------------------------------------

## Launcher states: the cold board, the settings sheet, the join screen a friend sees.
func _seq_pre() -> void:
	var overlay = _launcher.get("_overlay")
	if overlay != null:
		(overlay as Control).visible = false
	await _frames(SETTLE)
	await _dump("cold")
	if overlay != null:
		_launcher.call("_open_overlay")
		await _frames(SETTLE + 6)
		await _dump("settings")
		(overlay as Control).visible = false
	_launcher.call("_open_join_lobby")
	await _frames(SETTLE + 6)
	await _dump("join-none")


## A real match: the human's turn, the trade sheet, the inspector, the board from a bot's side.
## Order mirrors sg07_capture: the auction/decision states are deliberately NOT walked here -
## they belong to the capture series, and this scene must never wait on a person.
func _seq_match() -> void:
	_launcher.call("_autostart")
	await _frames(24)
	_human = _derive_human()
	_stabilize_match()
	var gv = _game_view()
	if gv == null:
		_miss("turn-human", "no game view after autostart")
		return
	if not await _reach("turn-human", 45.0):
		return
	await _dump("turn-human")
	gv.call("_on_action", "propose_trade", {})
	await _frames(SETTLE + 6)
	_note("trade state: %s" % _modal_desc())
	await _dump("trade")
	_close_modal()
	var insp = gv.find_child("inspector", true, false)
	if insp != null:
		insp.call("select", 1)
		await _frames(SETTLE)
		await _dump("inspector")
		insp.call("clear")
	_note("roll -> %s" % _press("roll"))
	# The roll can land on an unowned tile: the ENGINE then waits for the human (PURCHASE_WAIT)
	# and a bot turn would never come. Photograph that decision, decline it, and only then wait
	# for the other side of the table.
	if await _soft_reach("purchase", 10.0):
		await _dump("purchase")
		_note("decline -> %s" % _press("pass"))
	if await _soft_reach("ai", 45.0):
		await _dump("ai")
	else:
		_note("bot turn not reached; the human states are already on film")


## --- the dump ----------------------------------------------------------------------------------

func _dump(state: String) -> void:
	# A dump taken mid-reflow LIES. On this project `turn-human` was once photographed while the
	# board was still re-laying out after the console appeared (stage 796x450 instead of 716,
	# 40px cells, the name hidden by design's own step 3) - and a blind reviewer read it as
	# "the board carries no names". Wait until the layout stops moving before the walk.
	if not await _wait_layout_stable(4.0):
		_note("layout did not settle before the %s dump" % state)
	await _frames(SETTLE)
	var root := get_tree().root
	var nodes: Array = []
	_walk(root, nodes, 0, "", "", false)
	var facts := _facts(nodes)
	var doc := {
		"state": state,
		"seq": _seq,
		"skin": SkinManager.chosen,
		"role": _role if _role != "" else "auto",
		"label": _label if _label != "" else "%dx%d" % [_size.x, _size.y],
		"w": int(root.size.x),
		"h": int(root.size.y),
		"nodes": nodes,
		"facts": facts,
	}
	var base := "%s/%s_%s" % [_outdir, state, _label if _label != "" else "%dx%d" % [_size.x, _size.y]]
	var jpath := base + ".tree.json"
	var f := FileAccess.open(jpath, FileAccess.WRITE)
	if f == null:
		_miss(state, "cannot write %s" % jpath)
		return
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	var tpath := base + ".text.md"
	var tf := FileAccess.open(tpath, FileAccess.WRITE)
	if tf == null:
		_miss(state, "cannot write %s" % tpath)
		return
	tf.store_string(_text_report(state, doc))
	tf.close()
	_dumps += 1
	print("UI-PASSPORT STATE %s nodes=%d text=%d offscreen=%d clipped=%d small=%d min_font=%d"
		% [state, nodes.size(), int(facts["text"]), int(facts["offscreen"]),
		   int(facts["clipped"]), int(facts["small"]), int(facts["min_font"])])


## The layout signature: the rects of every named region. Identical for three frames in a row
## means the reflow has finished and a dump will describe the screen the user is looking at.
func _wait_layout_stable(budget_s: float) -> bool:
	var prev := ""
	var stable := 0
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var sig := _layout_sig()
		if sig != "" and sig == prev:
			stable += 1
			if stable >= 3:
				return true
		else:
			stable = 0
			prev = sig
		await _frames(1)
	return false


func _layout_sig() -> String:
	var parts: Array = []
	_collect_regions(get_tree().root, parts, 0)
	parts.sort()
	return "|".join(parts)


func _collect_regions(node: Node, out: Array, depth: int) -> void:
	if depth > 12 or out.size() > 60:
		return
	for c in node.get_children():
		if c is Control:
			var nm := str(c.name)
			if REGION_IDS.has(nm) and (c as Control).is_visible_in_tree():
				var r := (c as Control).get_global_rect()
				out.append("%s:%d,%d,%d,%d" % [nm, int(r.position.x), int(r.position.y),
					int(r.size.x), int(r.size.y)])
		_collect_regions(c, out, depth + 1)


## Every visible Control under the root, with the geometry and the text a reader would see.
func _walk(node: Node, out: Array, depth: int, path: String, region: String,
		clip_chain: bool) -> void:
	if out.size() >= NODE_CAP or depth > 16:
		return
	for child in node.get_children():
		var nm := str(child.name)
		var p := (path + "/" + nm) if path != "" else nm
		var r := region
		var cc := clip_chain
		if child is Control:
			var c := child as Control
			cc = cc or c.clip_contents
			if c.is_visible_in_tree():
				if r == "" and (REGION_IDS.has(nm) or nm.begins_with("rail-")):
					r = nm
				var e := {
					"id": nm,
					"cls": c.get_class(),
					"path": p,
					"x": int(c.global_position.x), "y": int(c.global_position.y),
					"w": int(c.size.x), "h": int(c.size.y),
					"clip_chain": cc,
				}
				if c.clip_contents:
					e["clip"] = true
				if c.tooltip_text != "":
					e["tip"] = _clipstr(c.tooltip_text)
				if c is Label or c is Button or c is RichTextLabel:
					var t := _clipstr(str(c.text))
					if t != "":
						e["txt"] = t
						e["fs"] = c.get_theme_font_size("font_size")
						e["col"] = c.get_theme_color("font_color").to_html(false)
						e["region"] = r if r != "" else "other"
						if c is Label and (c as Label).visible_ratio < 0.999:
							e["clipped"] = true
					out.append(e)
				else:
					out.append(e)
			else:
				# hidden subtrees are skipped whole: their layout is stale by definition
				continue
		_walk(child, out, depth + 1, p, r, cc)


## The facts an agent asks for first. Judgement stays outside: this only counts.
func _facts(nodes: Array) -> Dictionary:
	var w := int(get_tree().root.size.x)
	var h := int(get_tree().root.size.y)
	var n_text := 0
	var n_off := 0
	var n_clipped := 0
	var n_small := 0
	var min_font := 999
	var regions := {}
	var off_list: Array = []
	var small_list: Array = []
	var clipped_list: Array = []
	for e in nodes:
		var x := int(e["x"]); var y := int(e["y"])
		var ew := int(e["w"]); var eh := int(e["h"])
		if not bool(e["clip_chain"]) and (x < -OFF_TOL or y < -OFF_TOL
				or x + ew > w + OFF_TOL or y + eh > h + OFF_TOL):
			n_off += 1
			if off_list.size() < 12:
				off_list.append("%s (%d,%d %dx%d)" % [str(e["id"]), x, y, ew, eh])
		if e.has("clipped"):
			n_clipped += 1
			if clipped_list.size() < 12:
				clipped_list.append("%s «%s»" % [str(e["id"]), str(e.get("txt", ""))])
		if e.has("txt"):
			n_text += 1
			var fs := int(e.get("fs", 0))
			min_font = mini(min_font, fs)
			if fs < SMALL_FONT and str(e["txt"]).length() > 1:
				n_small += 1
				if small_list.size() < 12:
					small_list.append("%dpx %s «%s»" % [fs, str(e["id"]), str(e["txt"])])
			var reg := str(e.get("region", "other"))
			if not regions.has(reg):
				regions[reg] = []
			regions[reg].append(e)
	return {
		"w": w, "h": h,
		"nodes": nodes.size(), "text": n_text,
		"offscreen": n_off, "offscreen_list": off_list,
		"clipped": n_clipped, "clipped_list": clipped_list,
		"small": n_small, "small_list": small_list,
		"min_font": (min_font if min_font != 999 else 0),
		"regions": regions.keys(),
	}


## The screen as TEXT: per region, every visible string in reading order, with its font size.
func _text_report(state: String, doc: Dictionary) -> String:
	var facts: Dictionary = doc["facts"]
	var out := "# UI паспорт: %s\n\n" % state
	out += "profile=%s size=%dx%d skin=%s role=%s seq=%s\n\n" % [
		str(doc["label"]), int(doc["w"]), int(doc["h"]), str(doc["skin"]),
		str(doc["role"]), str(doc["seq"])]
	out += "facts: nodes=%d text=%d offscreen=%d clipped=%d small=%d min_font=%d\n\n" % [
		int(facts["nodes"]), int(facts["text"]), int(facts["offscreen"]),
		int(facts["clipped"]), int(facts["small"]), int(facts["min_font"])]
	var regions := {}
	for e in doc["nodes"]:
		if not e.has("txt"):
			continue
		var reg := str(e.get("region", "other"))
		if not regions.has(reg):
			regions[reg] = []
		regions[reg].append(e)
	out += "## Регионы\n\n"
	for reg in regions.keys():
		var ents: Array = regions[reg]
		ents.sort_custom(func(a, b):
			if int(a["y"]) != int(b["y"]):
				return int(a["y"]) < int(b["y"])
			return int(a["x"]) < int(b["x"]))
		var y0 := int(ents[0]["y"]) if not ents.is_empty() else 0
		out += "### %s (y≈%d, %d строк)\n\n" % [reg, y0, ents.size()]
		for e in ents:
			var fs := int(e.get("fs", 0))
			var flags := ""
			if bool(e.get("clipped", false)):
				flags += " [обрезан]"
			if fs < SMALL_FONT and str(e["txt"]).length() > 1:
				flags += " [мелко]"
			if e.has("tip"):
				flags += " [tip]"
			out += "- (%d,%d) f%d «%s»%s\n" % [int(e["x"]), int(e["y"]), fs, str(e["txt"]), flags]
		out += "\n"
	out += "## Красные флаги\n\n"
	out += _flag_block("вне экрана", facts["offscreen_list"])
	out += _flag_block("обрезанный текст", facts["clipped_list"])
	out += _flag_block("ниже пола читаемости (<%dpx)" % SMALL_FONT, facts["small_list"])
	return out


## GDScript passes Strings BY VALUE: a helper that appends to its argument silently writes into
## a copy (the first revision of this file shipped empty flag blocks because of exactly that).
## The helper RETURNS the block.
func _flag_block(title: String, items: Array) -> String:
	if items.is_empty():
		return "- %s: нет\n" % title
	var s := "- %s: %d\n" % [title, items.size()]
	for it in items:
		s += "  - %s\n" % str(it)
	return s


## --- film: motion and behaviour ----------------------------------------------------------------

## The static dump answers "what is on screen"; the film answers "what MOVES and what HAPPENS".
## 1. `_film_loop` samples every `_film_dt` ms until `_film_stop`.
## 2. The script marks its own actions and takes them through the real seams (roll, trade sheet).
## 3. `_film_analyze` folds the samples into per-node animation events (rect / alpha / rotation /
##    scale / appear / disappear), the phase timeline (action -> engine answer with the latency)
##    and the settle time after each mark; writes film_<label>.motion.json + film_<label>.md.
func _seq_film() -> void:
	_launcher.call("_autostart")
	await _frames(24)
	_human = _derive_human()
	_stabilize_match()
	if not await _reach("turn-human", 45.0):
		return
	_film_t0 = Time.get_ticks_msec()
	_film_samples.clear()
	_film_marks.clear()
	_film_stop = false
	_film_loop()
	_mark("turn-human")
	await _frames(8)
	_mark("roll")
	_note("film roll -> %s" % await _press_when_ready("roll", 3.0))
	await _soft_wait_phase_exit("TURN_START", 3.0)
	await _frames(36)
	_mark("after-roll")
	var gv = _game_view()
	if gv != null:
		_mark("modal-open")
		gv.call("_on_action", "propose_trade", {})
		await _frames(44)
		_mark("modal-open+")
		_close_modal()
		await _frames(30)
		_mark("modal-close")
	_film_stop = true
	await _frames(3)
	_film_analyze()


func _soft_wait_phase_exit(phase: String, budget_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var e = _engine()
		if e != null and str(e.phase) != phase:
			return
		await _frames(2)


func _film_loop() -> void:
	var last := 0
	while not _film_stop:
		var now := Time.get_ticks_msec()
		if now - last >= _film_dt:
			last = now
			var e = _engine()
			_film_samples.append({
				"t": now - _film_t0,
				"phase": str(e.phase) if e != null else "?",
				"turn": int(e.turn_player) if e != null else -1,
				"snap": _snap(),
			})
		await get_tree().process_frame


func _mark(label: String) -> void:
	var e = _engine()
	_film_marks.append({
		"t": Time.get_ticks_msec() - _film_t0,
		"label": label,
		"phase": str(e.phase) if e != null else "?",
		"turn": int(e.turn_player) if e != null else -1,
	})


## One light snapshot: [x, y, w, h, alpha%, rotation*1000, scale*100, on-screen].
func _snap() -> Dictionary:
	var out := {}
	_snap_node(get_tree().root, out, "")
	return out


func _snap_node(node: Node, out: Dictionary, path: String) -> void:
	for child in node.get_children():
		var nm := str(child.name)
		var p := (path + "/" + nm) if path != "" else nm
		if child is Control:
			var c := child as Control
			if c.is_visible_in_tree():
				out[p] = [int(c.global_position.x), int(c.global_position.y), int(c.size.x),
					int(c.size.y), int(round(c.modulate.a * 100.0)),
					int(round(c.rotation * 1000.0)), int(round(c.scale.x * 100.0)), 1]
			else:
				out[p] = [0, 0, 0, 0, 0, 0, 0, 0]
		_snap_node(child, out, p)


func _film_analyze() -> void:
	var events: Array = []
	var timeline: Array = []
	var prev_phase := ""
	for i in range(_film_samples.size()):
		var s: Dictionary = _film_samples[i]
		if i > 0:
			var a: Dictionary = _film_samples[i - 1]["snap"]
			var b: Dictionary = _film_samples[i]["snap"]
			var t0 := int(_film_samples[i - 1]["t"])
			var t1 := int(s["t"])
			for p in b.keys():
				var va: Array = a.get(p, [0, 0, 0, 0, 0, 0, 0, 0])
				var vb: Array = b[p]
				if int(va[7]) == 0 and int(vb[7]) == 1:
					events.append({"path": p, "prop": "appear", "t0": t0, "t1": t1})
					continue
				if int(va[7]) == 1 and int(vb[7]) == 0:
					events.append({"path": p, "prop": "disappear", "t0": t0, "t1": t1})
					continue
				if int(va[7]) == 0 and int(vb[7]) == 0:
					continue
				if va[0] != vb[0] or va[1] != vb[1] or va[2] != vb[2] or va[3] != vb[3]:
					events.append({"path": p, "prop": "rect",
						"from": [va[0], va[1], va[2], va[3]], "to": [vb[0], vb[1], vb[2], vb[3]],
						"t0": t0, "t1": t1})
				if va[4] != vb[4]:
					events.append({"path": p, "prop": "alpha", "from": va[4], "to": vb[4],
						"t0": t0, "t1": t1})
				if va[5] != vb[5]:
					events.append({"path": p, "prop": "rotation", "from": va[5], "to": vb[5],
						"t0": t0, "t1": t1})
				if va[6] != vb[6]:
					events.append({"path": p, "prop": "scale", "from": va[6], "to": vb[6],
						"t0": t0, "t1": t1})
		if str(s["phase"]) != prev_phase:
			timeline.append({"t": int(s["t"]), "phase": str(s["phase"]), "turn": int(s["turn"])})
			prev_phase = str(s["phase"])
	# merge consecutive events of the same node+property (an animation is one event, not forty)
	var merged: Array = []
	var open := {}
	for e in events:
		var key := str(e["path"]) + "|" + str(e["prop"])
		if open.has(key) and int(open[key]["t1"]) + _film_dt * 2 >= int(e["t0"]):
			var o: Dictionary = open[key]
			o["t1"] = e["t1"]
			if e.has("to"):
				o["to"] = e["to"]
			o["steps"] = int(o.get("steps", 1)) + 1
		else:
			var ne: Dictionary = (e as Dictionary).duplicate(true)
			ne["steps"] = 1
			open[key] = ne
			merged.append(ne)
	# FILTER: the board REBUILDS its tiles on every state push, so appear/disappear under
	# `stage/` (and every anonymous container) is re-render churn, not an animation. An
	# appearance is kept only when it is a named node OUTSIDE the board - the modal, the toast,
	# the banner, the drawer: the things a viewer actually notices. Motion (rect/alpha/rotation/
	# scale) is kept everywhere, because that is what an animation IS.
	var motion: Array = []
	var appears: Array = []
	for e in merged:
		var prop := str(e["prop"])
		if prop == "appear" or prop == "disappear":
			var last := str(e["path"]).split("/")[-1]
			if last.begins_with("@") or str(e["path"]).find("/stage/") != -1:
				continue
			appears.append(e)
		else:
			motion.append(e)

	# the settle time after each mark
	var settles: Array = []
	for mi in range(_film_marks.size()):
		var m: Dictionary = _film_marks[mi]
		var t_start := int(m["t"])
		var t_end := int(_film_samples[-1]["t"]) if not _film_samples.is_empty() else t_start
		if mi + 1 < _film_marks.size():
			t_end = int((_film_marks[mi + 1] as Dictionary)["t"])
		var last_event := 0
		for e in merged:
			if int(e["t0"]) >= t_start and int(e["t0"]) <= t_end:
				last_event = maxi(last_event, int(e["t1"]))
		settles.append({"label": str(m["label"]), "in_ms": t_start,
			"events": 0, "settle_ms": maxi(0, last_event - t_start)})
	# counts per mark window
	for se in settles:
		var t0 := int(se["in_ms"])
		var n_ev := 0
		for e in merged:
			if int(e["t0"]) == t0:
				n_ev += 0
		se["events"] = n_ev
	var moving := {}
	var longest := 0
	var longest_path := ""
	for e in motion:
		moving[str(e["path"])] = true
		var dur := int(e["t1"]) - int(e["t0"])
		if dur > longest:
			longest = dur
			longest_path = str(e["path"])
	var label := _label if _label != "" else "%dx%d" % [_size.x, _size.y]
	var doc := {
		"label": label, "skin": SkinManager.chosen, "role": _role if _role != "" else "auto",
		"interval_ms": _film_dt, "samples": _film_samples.size(),
		"duration_ms": int(_film_samples[-1]["t"]) if not _film_samples.is_empty() else 0,
		"marks": _film_marks, "timeline": timeline, "settles": settles,
		"events": motion.slice(0, 600), "appearances": appears.slice(0, 200),
		"nodes_moving": moving.keys().size(), "motion_events": motion.size(),
		"appearance_events": appears.size(),
		"longest_ms": longest, "longest_path": longest_path,
	}
	var jpath := "%s/film_%s.motion.json" % [_outdir, label]
	var f := FileAccess.open(jpath, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "  "))
		f.close()
	var mpath := "%s/film_%s.md" % [_outdir, label]
	var mf := FileAccess.open(mpath, FileAccess.WRITE)
	if mf != null:
		mf.store_string(_film_report(doc))
		mf.close()
	print("UI-PASSPORT FILM samples=%d motion=%d appear=%d nodes=%d longest=%dms settle_max=%dms phases=%d"
		% [int(doc["samples"]), motion.size(), appears.size(), int(doc["nodes_moving"]),
		   longest, _max_settle(settles), timeline.size()])


func _max_settle(settles: Array) -> int:
	var m := 0
	for s in settles:
		m = maxi(m, int(s["settle_ms"]))
	return m


## The film in words: what happened, in what order, and how long it took.
func _film_report(doc: Dictionary) -> String:
	var out := "# Фильм интерфейса: %s\n\n" % str(doc["label"])
	out += "skin=%s role=%s interval=%dms samples=%d duration=%dms\n\n" % [
		str(doc["skin"]), str(doc["role"]), int(doc["interval_ms"]),
		int(doc["samples"]), int(doc["duration_ms"])]
	out += "## Действия (марки) и отклик\n\n"
	for s in doc["settles"]:
		out += "- %s @%dms: успокоение %dms\n" % [str(s["label"]), int(s["in_ms"]), int(s["settle_ms"])]
	out += "\n## Фазы движка\n\n"
	for t in doc["timeline"]:
		out += "- %dms  %s (turn=%d)\n" % [int(t["t"]), str(t["phase"]), int(t["turn"])]
	out += "\n## Движение (rect / alpha / rotation / scale)\n\n"
	out += "событий: %d; узлов в движении: %d; самое долгое: %s, %dms\n\n" % [
		int(doc.get("motion_events", 0)), int(doc["nodes_moving"]),
		_short_path(str(doc["longest_path"])), int(doc["longest_ms"])]
	var top: Array = (doc["events"] as Array).duplicate()
	top.sort_custom(func(a, b):
		return (int(a["t1"]) - int(a["t0"])) > (int(b["t1"]) - int(b["t0"])))
	for e in top.slice(0, 40):
		var dur := int(e["t1"]) - int(e["t0"])
		out += "- %s  %s  %s -> %s  (%dms, %d сэмпл(ов))\n" % [_short_path(str(e["path"])),
			str(e["prop"]), str(e.get("from", "?")), str(e.get("to", "?")), dur,
			int(e.get("steps", 1))]
	var app: Array = doc.get("appearances", [])
	out += "\n## Появление/исчезновение вне борда (модалки, тосты, баннеры)\n\n"
	out += "событий: %d (чарн пересборки борда отфильтрован)\n\n" % int(doc.get("appearance_events", 0))
	var app_top := app.duplicate()
	app_top.sort_custom(func(a, b): return int(a["t0"]) < int(b["t0"]))
	for e in app_top.slice(0, 30):
		out += "- %dms..%dms  %s  %s\n" % [int(e["t0"]), int(e["t1"]),
			str(e["prop"]), _short_path(str(e["path"]))]
	return out


## The last three path segments: a full UiPassport/.../@Control@145/... chain is unreadable,
## and what identifies a node to a reader is its tail.
func _short_path(p: String) -> String:
	var parts := p.split("/")
	if parts.size() <= 3:
		return p
	return "…/" + "/".join(parts.slice(parts.size() - 3, parts.size()))


## --- driving (the same seams sg07_capture uses) ----------------------------------------------

## Like `_reach`, but a miss is a NOTE, not a failure: the passport describes what it could
## reach, and the wrapper counts STATES instead of trusting a silence.
func _soft_reach(state: String, budget_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var e = _engine()
		if e != null:
			var ph := str(e.phase)
			if state == "purchase" and ph == "PURCHASE_WAIT":
				return true
			if state == "ai" and ph == "TURN_START" and int(e.turn_player) != _human:
				return true
		await _frames(1)
	return false


func _reach(state: String, budget_s: float) -> bool:
	if state == "turn-human":
		return await _wait_for(func() -> bool:
			var e = _engine()
			return e != null and str(e.phase) == "TURN_START" and int(e.turn_player) == _human,
			budget_s, state)
	if state == "ai":
		return await _wait_for(func() -> bool:
			var e = _engine()
			return e != null and str(e.phase) == "TURN_START" and int(e.turn_player) != _human,
			budget_s, state)
	return true


func _wait_for(cond: Callable, budget_s: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await _frames(1)
	_miss(label, "not reached within %.0fs (phase=%s, turn=%s, human=%d)" % [
		budget_s, str(_engine_phase()), str(_engine_turn()), _human])
	return false


func _derive_human() -> int:
	var seats: Array = _launcher.get("_seats_cache")
	for s in seats:
		var d := str(s.input_driver)
		if d == "LOCAL" or d == "ADMIN":
			return int(s.pid)
	var gv = _game_view()
	if gv != null and int(gv.get("_human_pid")) >= 0:
		return int(gv.get("_human_pid"))
	return 0


func _press(key: String) -> String:
	var gv = _game_view()
	if gv == null:
		return "no-view"
	var console = gv.find_child("act", true, false)
	if console == null:
		return "no-console"
	var row = console.get("_btn_row")
	if row == null:
		return "no-button-row"
	var want := I18n.t(_label_key(key))
	for c in row.get_children():
		if c is Button and str((c as Button).text).begins_with(want):
			(c as Button).emit_signal("pressed")
			return "pressed"
	return "absent"


func _label_key(key: String) -> String:
	match key:
		"roll":
			return "act.roll"
		"pass":
			return "act.no_buy"
		"buy":
			return "act.buy"
	return key


## Like `_press`, but waits until the button exists: at the instant `_reach("turn-human")`
## returns, the console row may still be a frame away - and a film that never pressed the button
## records an interface at rest and calls it behaviour.
func _press_when_ready(key: String, budget_s: float) -> String:
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var gv = _game_view()
		if gv != null:
			var console = gv.find_child("act", true, false)
			if console != null and console.get("_btn_row") != null:
				var want := I18n.t(_label_key(key))
				for c in (console.get("_btn_row") as Node).get_children():
					if c is Button and str((c as Button).text).begins_with(want):
						(c as Button).emit_signal("pressed")
						return "pressed"
		await _frames(2)
	return "absent"


func _close_modal() -> void:
	var gv = _game_view()
	if gv == null:
		return
	var modal = gv.find_child("modal", true, false)
	if modal != null and (modal as Control).visible:
		modal.call("close")


## A passport cannot race a clock AND cannot be held hostage by a decision: zero is the engine's
## own "no timeout" value, and `auctions_on_refusal = false` keeps a declined purchase from
## turning into an auction nobody is there to bid in (auction states belong to the capture series).
func _stabilize_match() -> void:
	var e = _engine()
	if e == null or e.settings == null:
		return
	e.settings.turn_timer = 0
	e.settings.auction_timer = 0
	e.settings.auctions_on_refusal = false
	_note("match stabilized (timers off, a refused purchase opens no auction)")


func _game_view():
	return _launcher.get("_game_view")


func _engine():
	return _launcher.get("_engine")


func _engine_phase() -> String:
	var e = _engine()
	return str(e.phase) if e != null else "?"


func _engine_turn() -> String:
	var e = _engine()
	return str(int(e.turn_player)) if e != null else "?"


func _modal_desc() -> String:
	var gv = _game_view()
	if gv == null:
		return "no view"
	var modal = gv.find_child("modal", true, false)
	if modal == null:
		return "no modal"
	return "modal kind=%s visible=%s" % [str(modal.get("kind")), str((modal as Control).visible)]


func _clipstr(s: String) -> String:
	var t := s.replace("\n", " ").replace("\r", " ").strip_edges()
	if t.length() > TEXT_LIMIT:
		t = t.substr(0, TEXT_LIMIT - 1) + "…"
	return t


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _note(msg: String) -> void:
	print("UI-PASSPORT NOTE " + msg)


func _miss(state: String, reason: String) -> void:
	_misses.append("%s: %s" % [state, reason])
	print("UI-PASSPORT MISS %s %s" % [state, reason])


func _finish() -> void:
	if _done:
		return
	_done = true
	print("UI PASSPORT DONE seq=%s states=%d misses=%d in %dms outdir=%s"
		% [_seq, _dumps, _misses.size(), Time.get_ticks_msec() - _t0, _outdir])
	get_tree().quit(1 if _dumps == 0 else 0)
