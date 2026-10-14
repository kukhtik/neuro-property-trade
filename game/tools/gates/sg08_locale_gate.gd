extends Node
## SG-08 gate — live locale (docs/restoration/gates.md, SG-08).
##
## Contract: RU<->EN switches EVERYTHING in place, mid-match, without a rebuild, and nothing
## keeps the old language. The gate runs a real match, drives the feed, then switches the
## locale from outside the panels (exactly what the settings sheet / language button does) and
## walks the LIVE tree:
##   · the journal's furniture (title, counter, export, filters) is in the new language;
##   · a journal ROW that read "бросает 3+4" reads "rolls 3+4" (rows are re-composed from the
##     raw events, not left stale);
##   · no visible label anywhere shows a `{key}` sentinel after the switch;
##   · at least a handful of labels actually changed (the switch was not a no-op);
##   · switching BACK restores the original wording (two switches, per the criterion).
##
## Verdict: ==> SG-08 PASSED (...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg08_locale_gate.tscn

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

const DRIVE_ORDER := ["roll", "buy", "end_turn", "pay", "use_card", "pass"]

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 6
var _drive_frames := 0
var _fails: Array = []
var _checks := 0
var _ru_snapshot: Dictionary = {}
var _title_ru := ""


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	match _state:
		"boot":
			_wait -= 1
			if _wait > 0:
				return
			_launcher.call("_autostart")
			_state = "drive"
			_wait = 6
		"drive":
			_wait -= 1
			if _wait > 0:
				return
			_wait = 4
			_drive_frames += 1
			_drive_human()
			if _journal_total() >= 5 or _drive_frames > 700:
				_state = "ru_snapshot"
				_wait = 10
		"ru_snapshot":
			_wait -= 1
			if _wait > 0:
				return
			_take_ru_snapshot()
			I18n.set_locale("en")
			_state = "check_en"
			_wait = 15
		"check_en":
			_wait -= 1
			if _wait > 0:
				return
			_drive_human()   # one sync through the panels in the new language
			_check_en()
			I18n.set_locale("ru")
			_state = "check_ru"
			_wait = 15
		"check_ru":
			_wait -= 1
			if _wait > 0:
				return
			_check_ru_back()
			_report()


func _drive_human() -> void:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return
	var act = gv.find_child("act", true, false)
	if act == null or not bool(act.get("_human_now")):
		return
	var legal: Array = act.get("_last_legal")
	var pid: int = int(gv.get("_human_pid"))
	var mgr = gv.get("_mgr")
	if pid < 0 or mgr == null:
		return
	for a in DRIVE_ORDER:
		if legal.has(a):
			mgr.call("push_intent", pid, str(a), {})
			return


func _take_ru_snapshot() -> void:
	var jrn = _journal()
	if jrn == null:
		_fail("no journal panel")
		return
	_title_ru = str((jrn.get("_title") as Label).text)
	var want := I18n.t("jrn.title")
	if _title_ru != want:
		_fail("RU title is `%s`, expected `%s`" % [_title_ru, want])
	else:
		_checks += 1
	_ru_snapshot = _label_map()
	print("SG-08: RU baseline - %d labels, %d feed lines" % [_ru_snapshot.size(), _journal_total()])


func _check_en() -> void:
	var jrn = _journal()
	if jrn == null:
		_fail("journal vanished")
		return
	# the journal furniture switched
	var title := str((jrn.get("_title") as Label).text)
	if title != I18n.t("jrn.title") or title == _title_ru:
		_fail("EN title `%s` did not switch (RU was `%s`)" % [title, _title_ru])
		return
	_checks += 1
	var cnt := str((jrn.get("_count") as Label).text)
	if not cnt.begins_with("shown"):
		_fail("counter `%s` still not in EN (expected «shown N / M»)" % cnt)
		return
	_checks += 1
	var exp_btn := str((jrn.get("_export_btn") as Button).text)
	if exp_btn != I18n.t("jrn.export"):
		_fail("export button `%s` not in EN" % exp_btn)
		return
	_checks += 1
	# a journal ROW re-composed: the roll template is deterministic per language
	var roll := _find_row_text(jrn, "rolls")
	if roll == "":
		_fail("no roll row reads `rolls …` in EN - rows were not re-composed on the switch")
		return
	_checks += 1
	# no {key} sentinels anywhere visible
	var bad := _find_sentinel()
	if bad != "":
		_fail("label `%s` shows a `{key}` after the switch" % bad)
		return
	_checks += 1
	# the switch really happened: a handful of labels changed
	var after := _label_map()
	var changed := 0
	for k in _ru_snapshot.keys():
		if after.has(k) and str(after[k]) != str(_ru_snapshot[k]):
			changed += 1
	if changed < 4:
		_fail("only %d label(s) changed on the switch - the locale pass is not reaching the tree" % changed)
		return
	_checks += 1
	print("SG-08: EN - %d labels changed, roll row reads `%s`" % [changed, roll])


func _check_ru_back() -> void:
	var jrn = _journal()
	if jrn == null:
		_fail("journal vanished on the way back")
		return
	var title := str((jrn.get("_title") as Label).text)
	if title != _title_ru:
		_fail("title `%s` did not come back to RU (`%s`)" % [title, _title_ru])
		return
	_checks += 1
	if _find_row_text(jrn, "бросает") == "":
		_fail("no roll row reads `бросает …` after switching back to RU")
		return
	_checks += 1


## The first journal row label whose text carries the probe word.
func _find_row_text(jrn, probe: String) -> String:
	for lbl in _labels_under(jrn):
		var t := str((lbl as Label).text)
		if t.contains(probe):
			return t
	return ""


func _find_sentinel() -> String:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return ""
	for lbl in _labels_under(gv):
		var t := str((lbl as Label).text)
		if t.contains("{") and t.contains("}"):
			return t
	return ""


## path -> text for every visible label (used to count real changes).
func _label_map() -> Dictionary:
	var out := {}
	var gv = _launcher.get("_game_view")
	if gv == null:
		return out
	for lbl in _labels_under(gv):
		var c := lbl as Control
		if c.is_visible_in_tree():
			out[str(c.get_path())] = str((lbl as Label).text)
	return out


func _journal():
	var gv = _launcher.get("_game_view")
	if gv == null:
		return null
	return gv.find_child("journal", true, false)


func _journal_total() -> int:
	var jrn = _journal()
	return int(jrn.call("total")) if jrn != null else 0


func _labels_under(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels_under(c))
	return out


## A silent runtime abort leaves 0 checks and used to still say PASSED (SG-09 lesson):
## the report refuses a run that did not actually check anything.
const MIN_CHECKS := 6   # >= 6 independent checks


func _report() -> void:
	print("SG-08: %d checks" % _checks)
	if _checks < MIN_CHECKS:
		_fail("only %d check(s) ran - the gate aborted silently (want >= %d)" % [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> SG-08 PASSED (the switch reached furniture, rows and the whole tree - twice)")
		get_tree().quit(0)
	else:
		print("==> SG-08 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
