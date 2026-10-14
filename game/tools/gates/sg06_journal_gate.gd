extends Node
## SG-06 gate — the journal explains the match (docs/restoration/gates.md, SG-06).
##
## The audit's complaint: "лента не объясняет партию". The rows were built straight from the
## engine vocabulary (`event_type.<raw type>` with a fallback to the key itself), tiles were
## numbers ("клетка 17"), categories were raw types, and there was no counter, no filters, no
## export, no empty state. This gate walks the LIVE tree and demands:
##   1. the empty state: a cold feed shows the friendly line, not a bare panel;
##   2. human language in rows: no raw engine vocabulary, no `{keys}`, no "клетка N"/"tile N" -
##      tiles are NAMED, the tag is a translated category;
##   3. the counter reads "показано N / M" and M equals the feed size;
##   4. the filters really filter: seat filter -> that seat's rows only; category filter ->
##      that category's rows only; back to "all" -> everything;
##   5. export writes .jsonl: one JSON object per line, count == feed size.
##
## Feed production: the LOCAL seat is driven through REAL intents (the manager's push_intent -
## the same wire the buttons use), AI seats play themselves. Button-press fidelity is HG-02's
## job; here we need a rich, real feed, not a stub.
##
## Verdict: ==> SG-06 PASSED (...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg06_journal_gate.tscn

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

## Raw engine vocabulary that must never reach a journal row (adapting it is the adapter's
## entire purpose: free_parking -> park -> "парковка").
const ENGINE_RAW := ["setup", "roll", "move", "teleport", "go_bonus", "purchase", "rent", "tax",
	"free_parking", "card_draw", "card_gain", "card_land", "card_null", "jail", "auction_start",
	"auction_bid", "auction_pass", "auction_win", "auction_unwon", "build", "sell", "mortgage",
	"unmortgage", "trade_proposed", "trade", "trade_declined", "bankrupt", "winner",
	"pass_on_purchase", "purchase_dropped", "collect", "collect_from_all", "pay_each_player",
	"cash", "pay"]
## The LOCAL seat's wish list, in priority order — enough to walk a whole round.
const DRIVE_ORDER := ["roll", "buy", "end_turn", "pay", "use_card", "pass"]
const MIN_LINES := 8

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 6
var _drive_frames := 0
var _intents := 0
var _fails: Array = []
var _checks := 0


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
			_check_empty_state()
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
			var total := _journal_total()
			if total >= MIN_LINES or _drive_frames > 900:
				_state = "settle"
				_wait = 12
		"settle":
			_wait -= 1
			if _wait > 0:
				return
			_check_feed()
			_report()


## 1. Cold feed: the friendly empty state, not an empty panel.
func _check_empty_state() -> void:
	var jrn = _journal()
	if jrn == null:
		_fail("no journal panel in the tree at cold start")
		return
	var empty = jrn.find_child("jrn-empty", true, false)
	if empty == null or not (empty as Control).visible:
		_fail("cold feed shows no empty-state line - a player sees a bare panel")
		return
	var want := I18n.t("jrn.empty")
	if str((empty as Label).text) != want:
		_fail("empty-state text is `%s`, expected `%s`" % [str((empty as Label).text), want])
		return
	_checks += 1
	if int(jrn.call("total")) != 0:
		_fail("cold journal already carries %d rows" % int(jrn.call("total")))
	else:
		_checks += 1


## The LOCAL seat plays a whole round through real intents; AI seats play themselves.
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
			var verdict: Dictionary = mgr.call("push_intent", pid, str(a), {})
			_intents += 1
			if not bool(verdict.get("ok", false)):
				print("SG-06 note: intent %s refused: %s" % [str(a), str(verdict.get("reason", "?"))])
			return


## 2-5. The feed's language, the counter, the filters, the export.
func _check_feed() -> void:
	var jrn = _journal()
	if jrn == null:
		_fail("journal panel vanished mid-run")
		return
	var total := int(jrn.call("total"))
	print("SG-06: %d intents driven, feed holds %d line(s)" % [_intents, total])
	if total < MIN_LINES:
		_fail("the feed holds only %d line(s) after a driven round - not enough to judge" % total)
		return
	_checks += 1
	# (2) rows read as human language
	var bad_raw: Array = []
	var bad_key: Array = []
	var bad_num: Array = []
	var named := 0
	for lbl in _labels_under(jrn):
		var t := str((lbl as Label).text)
		if t.strip_edges() == "" or t == I18n.t("jrn.empty") or t == I18n.t("jrn.no_match"):
			continue
		if ENGINE_RAW.has(t.strip_edges()):
			bad_raw.append(t)
		if t.contains("{") and t.contains("}"):
			bad_key.append(t)
		if _looks_like_tile_number(t.to_lower()):
			bad_num.append(t)
		if t.contains("«") and t.contains("»"):
			named += 1
	if not bad_raw.is_empty():
		_fail("row shows RAW engine vocabulary `%s` (the adapter was bypassed again)" % bad_raw[0])
	if not bad_key.is_empty():
		_fail("row shows an unresolved i18n key `%s`" % bad_key[0])
	if not bad_num.is_empty():
		_fail("row says `%s` - tiles are NAMED in the journal (no «клетка N»)" % bad_num[0])
	if named == 0:
		_fail("no row names a tile (no «...» anywhere) - tile names are not reaching the feed")
	if bad_raw.is_empty() and bad_key.is_empty() and bad_num.is_empty() and named > 0:
		_checks += 1
	# (3) counter: показано N / M, M == feed size
	var cnt = jrn.get("_count")
	var rx_cnt := RegEx.new()
	rx_cnt.compile("(\\d+)\\s*/\\s*(\\d+)")
	var m = rx_cnt.search(str((cnt as Label).text)) if cnt != null else null
	if m == null:
		_fail("counter `%s` does not read «показано N / M»" % str((cnt as Label).text if cnt != null else "<missing>"))
	else:
		if int(m.get_string(2)) != total:
			_fail("counter totals %s but the feed holds %d" % [m.get_string(2), total])
		elif int(m.get_string(1)) != total:
			_fail("counter shows %s of %d with no filter set" % [m.get_string(1), total])
		else:
			_checks += 1
	# (4) filters really filter
	_check_filters(jrn, total)
	# (5) export
	_check_export(jrn, total)


func _check_filters(jrn, total: int) -> void:
	var rows: Array = jrn.get("_rows")
	var pf = jrn.get("_pfilter")
	var cf = jrn.get("_cfilter")
	if pf == null or cf == null:
		_fail("the journal has no filter controls")
		return
	# seat filter -> only that seat's rows
	var gv = _launcher.get("_game_view")
	var pid := int(gv.get("_human_pid"))
	var want := 0
	for r in rows:
		if int((r["line"] as Dictionary).get("pid", -1)) == pid:
			want += 1
	(pf as OptionButton).selected = 1
	(pf as OptionButton).item_selected.emit(1)
	var got := int(jrn.call("shown"))
	if got != want or (got == total and want == total and total > 0):
		# got == want is not enough when the filter is a no-op and everything belongs to one
		# seat: require the VISIBLE list to change OR the numbers to agree exactly.
		if got != want:
			_fail("seat filter of seat #1 shows %d rows, expected %d" % [got, want])
			return
	(pf as OptionButton).selected = 0
	(pf as OptionButton).item_selected.emit(0)
	if int(jrn.call("shown")) != total:
		_fail("clearing the seat filter did not restore all %d rows (got %d)" % [total, int(jrn.call("shown"))])
		return
	# category filter -> build only
	var build_idx := 0
	for i in (cf as OptionButton).item_count:
		if str((cf as OptionButton).get_item_text(i)) == I18n.t("ty.build"):
			build_idx = i
	if build_idx == 0:
		_fail("the category filter has no «%s» entry" % I18n.t("ty.build"))
		return
	var want_build := 0
	for r in rows:
		if str((r["line"] as Dictionary).get("cat", "")) == "build":
			want_build += 1
	(cf as OptionButton).selected = build_idx
	(cf as OptionButton).item_selected.emit(build_idx)
	if int(jrn.call("shown")) != want_build:
		_fail("category filter «стройка» shows %d rows, expected %d" % [int(jrn.call("shown")), want_build])
		return
	(cf as OptionButton).selected = 0
	(cf as OptionButton).item_selected.emit(0)
	if int(jrn.call("shown")) != total:
		_fail("clearing the category filter did not restore all rows")
		return
	_checks += 3


func _check_export(jrn, total: int) -> void:
	var path := str(jrn.call("export_jsonl"))
	if path == "" or not FileAccess.file_exists(path):
		_fail("export produced no file")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("export file exists but cannot be read")
		return
	var lines := 0
	var parsed := 0
	while not f.eof_reached():
		var ln := f.get_line()
		if ln.strip_edges() == "":
			continue
		lines += 1
		var obj = JSON.parse_string(ln)
		if obj is Dictionary and (obj as Dictionary).has("text") and (obj as Dictionary).has("cat"):
			parsed += 1
	f.close()
	if lines != total or parsed != total:
		_fail("export holds %d line(s) (%d parseable), expected %d" % [lines, parsed, total])
		return
	_checks += 1


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


func _report() -> void:
	print("SG-06: %d checks" % _checks)
	if _fails.is_empty():
		print("==> SG-06 PASSED (%d intents, feed lines are human, counter/filters/export work)" % _intents)
		get_tree().quit(0)
	else:
		print("==> SG-06 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


## "клетка 17" / "tile 17" / "тайл 17" - the exact wording the audit forbids in the journal.
func _looks_like_tile_number(low: String) -> bool:
	for stem in ["клетка ", "tile ", "тайл "]:
		var at := low.find(stem)
		while at >= 0:
			var rest := low.substr(at + stem.length())
			if rest.length() > 0 and rest[0] >= "0" and rest[0] <= "9":
				return true
			at = low.find(stem, at + 1)
	return false


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
