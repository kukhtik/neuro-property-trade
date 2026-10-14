extends Node
## SG-04 gate — the two text roles and the single-grow row (docs/restoration/gates.md, SG-04;
## DESIGN §3 P-3/P-4). This is the direct guard of the regression `3d6928c`, which forced
## WORD_SMART + EXPAND_FILL on ALL labels: layout got 2.6-3.6x more expensive and every value
## in a row pushed its neighbours around.
##
## Mirrors the mockup's own live audit (`ui-prototype.html` → `audit()`):
##   1. every text element carries ONE of the two roles —
##        value: `AUTOWRAP_OFF` (UiTheme.label)      para: `AUTOWRAP_WORD_SMART` (UiTheme.label_wrap);
##        anything else is the forbidden third role;
##   2. a para fills its parent (`EXPAND_FILL`) — a wrapping label that does NOT grow wraps into
##        a sliver and clips itself;
##   3. exactly ONE stretching child per flex row (the mockup's `data-grow` rule): a horizontal
##        row with 2+ `EXPAND_FILL` children distributes slack unpredictably — the 3d6928c class.
##
## Runs on the desktop and the compact profile: roles must hold in both.
##
## Verdict: ==> SG-04 PASSED (...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg04_text_roles_gate.tscn

const MainScript := preload("res://main.gd")

const PROFILES := [
	{"label": "1440x900", "size": Vector2i(1440, 900)},
	{"label": "880x600", "size": Vector2i(880, 600)},
]
## The app always shows at least this many labels once a match runs - a floor against a scan
## that silently sees nothing.
const MIN_LABELS := 30

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 6
var _profile_idx := 0
var _fails: Array = []
var _checks := 0
var _values := 0
var _paras := 0


func _ready() -> void:
	DisplayServer.window_set_size(PROFILES[0].size)
	get_tree().root.size = PROFILES[0].size
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
			_state = "settle"
			_wait = 90   # let the first turns fill the panels
		"settle":
			_wait -= 1
			if _wait > 0:
				return
			_check_profile(PROFILES[_profile_idx])
			_profile_idx += 1
			if _profile_idx < PROFILES.size():
				get_tree().root.size = PROFILES[_profile_idx].size
				DisplayServer.window_set_size(PROFILES[_profile_idx].size)
				_wait = 20
				return
			_report()


func _check_profile(profile: Dictionary) -> void:
	var label := str(profile["label"])
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("%s: no game view" % label)
		return
	var counters: Array = [0, 0]
	var v0 := _values
	var p0 := _paras
	_walk(gv, label, counters)
	var local_labels: int = int(counters[0])
	print("SG-04 %s: %d labels (%d value / %d para), %d row(s) with 2+ stretches" % [label,
		local_labels, _values - v0, _paras - p0, int(counters[1])])
	if local_labels < MIN_LABELS:
		_fail("%s: only %d label(s) visible - the scan cannot be proving anything" % [label, local_labels])
	else:
		_checks += 1


func _walk(node: Node, label: String, counters: Array) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.is_visible_in_tree() and c.size.x > 0.5:
				if c is HBoxContainer:
					_audit_row(c as HBoxContainer, label, counters)
				if c is Label:
					_audit_label(c as Label, label, counters)
		_walk(child, label, counters)


## 1-2: every label is exactly one of the two roles, and a para fills its parent.
func _audit_label(l: Label, label: String, counters: Array) -> void:
	if l.text.strip_edges() == "":
		return
	counters[0] = int(counters[0]) + 1
	var mode := l.autowrap_mode
	if mode == TextServer.AUTOWRAP_OFF:
		_values += 1
		return
	if mode != TextServer.AUTOWRAP_WORD_SMART:
		_fail("%s: `%s` shows `%s` in the FORBIDDEN third role (autowrap=%d; only OFF and WORD_SMART exist)"
			% [label, _where(l), l.text, int(mode)])
		return
	_paras += 1
	if _on_board(l):
		return   # tile names are laid out by tile_layout, not by flex rules
	if l.size_flags_horizontal & Control.SIZE_EXPAND == 0:
		_fail("%s: paragraph `%s` (`%s`) does NOT fill its parent - it wraps into a sliver and clips itself (use label_wrap)"
			% [label, _where(l), l.text.substr(0, 30)])


## 3: exactly one stretching child per flex row (the mockup's data-grow rule).
func _audit_row(row: HBoxContainer, label: String, counters: Array) -> void:
	# THE ONE SANCTIONED FLEX EXCEPTION (mockup has `data-nowrap-row` for the same): the
	# ownership bar is an equal-split visualisation - every segment must stretch equally.
	# Keep this list at most one name long; anything else gets a spacer instead.
	if str(row.name) == "ownbar":
		return
	var growers: Array = []
	for ch in row.get_children():
		if ch is Control and (ch as Control).visible \
				and (ch as Control).size_flags_horizontal & Control.SIZE_EXPAND != 0:
			growers.append(ch)
	if growers.size() > 1:
		counters[1] = int(counters[1]) + 1
		var names: Array = []
		for g in growers:
			names.append(str((g as Control).name))
		_fail("%s: flex row `%s` stretches %d children (%s) - exactly one per row (P-4)"
			% [label, _where(row), growers.size(), ", ".join(names)])


## True inside the board subtree (board_scene/tile_view own their geometry).
func _on_board(c: Control) -> bool:
	var p: Node = c
	while p != null and p != _launcher:
		var scr = p.get_script()
		if scr != null and str(scr.resource_path).contains("board"):
			return true
		p = p.get_parent()
	return false


func _where(c: Control) -> String:
	var parts := str(c.get_path()).split("/")
	var from := maxi(0, parts.size() - 4)
	var out: Array = []
	for i in range(from, parts.size()):
		out.append(str(parts[i]))
	return "/".join(out)


func _report() -> void:
	print("SG-04: %d checks, %d value + %d paragraph labels audited" % [_checks, _values, _paras])
	if _fails.is_empty():
		print("==> SG-04 PASSED (both profiles: every label is a value or a paragraph, one stretch per row)")
		get_tree().quit(0)
	else:
		print("==> SG-04 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
