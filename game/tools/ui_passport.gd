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
