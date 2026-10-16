extends Node
## SG-05 gate — notifications never cover the game (docs/restoration/gates.md SG-05; DESIGN §4
## P-5/F-68). Port of the archived `toast_guard_probe` (whose node names died in the swap) onto
## the CURRENT tree, and on all four profiles instead of two sizes.
##
## Contract, measured on the LIVE layout:
##   · wide/desktop/1280 - the toast host sits in the RIGHT DOCK: no toast rect may cross the
##     stage (board) or the console (act), and the host stays inside the window. (The modal
##     sheet is a presence-only region: a closed modal cannot be overlapped.)
##   · compact - the dock host folds away; the notification is the console's one-line ticker,
##     which lives INSIDE the console by construction: nothing may float over the board.
##
## Verdict: ==> SG-05 PASSED (...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg05_toast_gate.tscn

const MainScript := preload("res://main.gd")

const PROFILES := [
	{"label": "1440x900", "size": Vector2i(1440, 900)},
	{"label": "1280x720", "size": Vector2i(1280, 720)},
	{"label": "1000x650", "size": Vector2i(1000, 650)},
	{"label": "880x600", "size": Vector2i(880, 600)},
]
## Events that always toast (the toast.* family exists for exactly these).
const EVENTS := [
	{"type": "purchase", "data": {"player": "Tester", "tile": 1, "cost": 120}},
	{"type": "rent", "data": {"from": "Tester", "to": "Tester", "tile": 3, "amount": 24}},
	{"type": "free_parking", "data": {"player": "Tester", "amount": 77}},
]

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 6
var _profile_idx := 0
var _fails: Array = []
var _checks := 0


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
			_wait = 30
		"settle":
			_wait -= 1
			if _wait > 0:
				return
			_check_profile(PROFILES[_profile_idx])
			_profile_idx += 1
			if _profile_idx < PROFILES.size():
				get_tree().root.size = PROFILES[_profile_idx].size
				DisplayServer.window_set_size(PROFILES[_profile_idx].size)
				_wait = 16
				return
			_report()


func _check_profile(profile: Dictionary) -> void:
	var label := str(profile["label"])
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("%s: no game view" % label)
		return
	var host = gv.find_child("toast", true, false)
	if host == null:
		_fail("%s: no toast host in the tree" % label)
		return
	host.call("dismiss_all")
	# the REAL path: events go through the shell exactly as the match feeds them
	gv.call("_on_events", EVENTS)
	var ps: Vector2i = profile["size"]
	var compact: bool = ps.x < 1280 or ps.y <= 700
	if compact:
		# the dock folds away and the ticker inside the console carries the text
		if (host as Control).is_visible_in_tree():
			_fail("%s: compact keeps the floating toast host over the board" % label)
			return
		var act = gv.find_child("act", true, false)
		var ticker = act.get("_ticker") if act != null else null
		if ticker == null or not (ticker as Label).visible or str((ticker as Label).text) == "":
			_fail("%s: compact folded the host AND left the console ticker empty - the notification vanished" % label)
			return
		_checks += 2
		print("SG-05 %s (compact): host folded away, ticker carries `%s`" % [label, str((ticker as Label).text)])
		return
	# wide/desktop: the host lives in the right dock, clear of the game
	if not (host as Control).is_visible_in_tree():
		_fail("%s: the wide profile hid the toast host - notifications have nowhere to land" % label)
		return
	if int(host.call("toast_count")) < 1:
		_fail("%s: no toast was raised for a full event batch" % label)
		return
	var game: Array = []
	# ZOOM-01: the board now lives under a CAMERA that scales and moves it, so the board's own
	# `get_global_rect()` is a pre-transform rect - measuring it compares the toast against a place
	# the board is not (this went red the moment the console freed height and the camera grew). The
	# thing that occupies the space on screen is the CAMERA; measure that, and keep "stage" as a
	# fallback for a tree without one.
	for nm in ["stage-camera", "act"]:
		var node = gv.find_child(nm, true, false)
		if node == null and nm == "stage-camera":
			node = gv.find_child("stage", true, false)
		if node != null:
			game.append([nm, (node as Control).get_global_rect()])
	for toast in (host as Control).get_children():
		if not (toast is Control) or not (toast as Control).is_visible_in_tree():
			continue
		var tr: Rect2 = (toast as Control).get_global_rect()
		for pair in game:
			if tr.intersects(pair[1]):
				_fail("%s: a toast covers %s (toast %s vs %s)" % [label, pair[0], _rect_str(tr), _rect_str(pair[1])])
				return
	var hr: Rect2 = (host as Control).get_global_rect()
	var vs := Rect2(Vector2.ZERO, Vector2(get_tree().root.size))
	if hr.position.x < -1.0 or hr.end.x > vs.size.x + 1.0 or hr.position.y < -1.0 or hr.end.y > vs.size.y + 1.0:
		_fail("%s: toast host leaves the window (%s vs %s)" % [label, _rect_str(hr), _rect_str(vs)])
		return
	_checks += 2
	print("SG-05 %s (wide): %d toast(s) in the right dock, clear of stage/act" % [label, int(host.call("toast_count"))])


func _rect_str(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]


## A silent runtime abort leaves 0 checks and used to still say PASSED (SG-09 lesson):
## the report refuses a run that did not actually check anything.
const MIN_CHECKS := 8   # 4 profiles x 2 checks = 8


func _report() -> void:
	print("SG-05: %d checks" % _checks)
	if _checks < MIN_CHECKS:
		_fail("only %d check(s) ran - the gate aborted silently (want >= %d)" % [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> SG-05 PASSED (4 profiles: toasts stay in the right dock, compact folds to the console ticker)")
		get_tree().quit(0)
	else:
		print("==> SG-05 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
