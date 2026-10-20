extends Node
## STREAM-READ — "the picture a viewer sees from a PHONE can be read" (docs/program.md P1.1).
##
## WHY THIS EXISTS AND WHY IT IS NOT READ-01: the owner's correction of 16.10 says watching the
## stream from a phone is NOT the same as playing in a 390px game window. The product promises a
## STREAM PICTURE drawn at a native large resolution, which a viewer watches on a small screen.
## So the honest measure is not "does the layout fit in 390px" (nothing promises that) but
## "when the frame is scaled down to a phone, is the text still readable".
##
## THE MEASURE (the plan's own formula):
##     effective_px = frame_px * (PHONE_WIDTH / frame_width)
## A 14px label in a 1920px frame lands at 14 * 390/1920 = 2.8px on a phone - invisible. To reach
## 12px on a phone the label needs ~59px in the frame. The gate measures the labels a viewer must
## grasp from ONE GLANCE (whose turn it is, what is happening, the money, the journal heading),
## finds them BY NAME (never by guessing from text or font - a heuristic that matches nothing says
## nothing), and judges the smallest effective size against a floor.
##
## It measures the LIVE tree, not a PNG: a screenshot answers "is there a blob", and a blob is not
## a word. The frame size is REAL (--rendering-driver opengl3 at 1920x1080) because a headless root
## viewport is 64x64 and would measure a window nobody has.
##
## Verdicts (one line each, matched by prefix):
##   ==> STREAM-READ PASSED/FAILED (the glance set, effective phone px)
##   ==> STREAM-READ ROW <label> ... (context rows: measured but not judged)
##
## Usage:
##   godot --path game --rendering-driver opengl3 res://tools/gates/stream_read_gate.tscn -- \
##         --outdir=<abs dir> [--skin=<id>] [--smoke-seed=4242]
const MainScript := preload("res://main.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const I18n := preload("res://i18n/i18n.gd")
const LayoutProfile := preload("res://ui/core/layout_profile.gd")

## The frame the stream is drawn at. 1920x1080 is the floor the owner named; the gate measures it
## and reports the phone width used, so the number cannot be read without its arithmetic.
const FRAME := Vector2i(1920, 1080)
const FRAME_LABEL := "1920x1080"
## The phone the viewer holds - a CSS-px width, the same the rule in LayoutProfile is derived at.
const PHONE_WIDTH := LayoutProfile.PHONE_CSS_WIDTH
## The floor for "understood from one glance" on the phone. READ FROM THE RULE'S ONE HOME
## (LayoutProfile.GLANCE_MIN_PHONE_PX), never re-typed here: a gate that hard-codes the number it
## judges would keep passing after the product changed what "legible" means.
const GLANCE_FLOOR := LayoutProfile.GLANCE_MIN_PHONE_PX
## The roles that carry the glance. Each entry: the node name as the product sets it, a human
## label for the report, and whether it is judged (a money tag or a name may carry a different
## floor by design; the gate reports all of them and judges the set below).
const GLANCE_SET := [
	{"node": "panno-turn", "role": "whose turn + what is happening (the panno)"},
	{"node": "panno-event-text", "role": "what just happened (the panno)"},
	{"node": "panno-jrn-text", "role": "the newest journal line (the panno)"},
	# B1 moved these four facts OUT of the header into the four corner screens (the corners are the
	# only place with room for a 50px line). The screens are judged here; the header keeps carrying
	# the same facts as a control strip and is reported as context (see NOT_JUDGED below) - a
	# duplicate at 13px is not the glance layer any more.
	{"node": "glance-turn", "role": "whose turn (the Start corner screen)"},
	{"node": "glance-phase", "role": "the phase (the Jail corner screen)"},
	{"node": "glance-bank", "role": "the parking bank (the Parking corner screen)"},
	{"node": "glance-round", "role": "the round (the Go-to-jail corner screen)"},
	{"node": "turn-name", "role": "whose turn (the header, context)", "context": true},
	{"node": "turn-phase", "role": "what is happening (the header, context)", "context": true},
	{"node": "top-round", "role": "the round (the header, context)", "context": true},
	{"node": "top-pot", "role": "the money (the header, context)", "context": true},
	# THE DOCK'S JOURNAL IS MEASURED ONLY WHEN IT IS DRAWN. At every frame narrower than 2000px the
	# app runs compact and hides the right dock, so jrn-title/jrn-text exist as nodes nobody sees -
	# the gate used to hand them the verdict and describe a picture that was not on screen (measured:
	# at 1600x1200 and at 1920x1080 the dock is hidden and the panno carries the journal instead).
	{"node": "jrn-title", "role": "the journal heading (the dock, when drawn)", "drawn_only": true},
	{"node": "jrn-text", "role": "the newest journal line (the dock, when drawn)", "drawn_only": true},
]
## Roles that may sit below the glance floor by design (a single-glyph tag, a secondary counter):
## reported as context, never judged. Empty today - the point is that the exclusion is a written
## decision, not a silent skip.
##
## WHY THIS STAYS EMPTY. The obvious move is to list the HUD here and call STREAM-READ green - no
## HUD text can reach 59px in a 56px bar. But `layout_profile.gd` already records, at length, that the
## promise is self-defeating: the frame is scaled down by exactly the factor the text would have to
## grow by, so a 13px label reads 2.6px from a 1920 frame and 1.3px from 3840, and at 854 the
## requirement is still 26px. Excluding roles here would bury the arithmetic in a second home and
## make the gate look satisfied when nothing was decided. The gate reports the number; the decision
## belongs to the owner.
const BELOW_FLOOR_OK := []

## A fixed seed so the measured match is the same every run (a gate whose numbers move is not a
## gate): reaches main.gd through the product's own CLI, exactly like the READ gate.
const FIXED_SEED := 4242

var _outdir := "user://stream"
var _skin := ""
var _launcher = null
var _state := "boot"
var _wait := 6
var _done := false
var _t0 := 0
var _fails: Array = []
## attempts to make the root take the stream frame size (see _resize)
var _resizes := 0
## frames spent waiting for the journal to draw its first line (see _warm)
var _warms := 0
## [{node, role, px, eff, found}]
var _rows: Array = []
const WATCHDOG_MS := 300000


func _ready() -> void:
	DisplayServer.window_set_size(FRAME)
	get_tree().root.size = FRAME
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--outdir="):
			_outdir = s.substr(9)
		elif s.begins_with("--skin="):
			_skin = s.substr(7)
	DirAccess.make_dir_recursive_absolute(_outdir)
	if _skin != "":
		SkinManager.chosen = _skin
	_t0 = Time.get_ticks_msec()
	_state = "boot"
	_wait = 6


func _process(_dt: float) -> void:
	if _done:
		return
	if Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_finish()
		return
	_wait -= 1
	if _wait > 0:
		return
	match _state:
		"boot":
			_spawn()
		"settle":
			_settle()
		"resize":
			_resize()
		"warm":
			_warm()
		"measure":
			_measure()
			_state = "done"
			_wait = 2
		"done":
			_finish()


## The app's own `main._ready` sets the window to 1440x900 (the playable shell), which beats the
## size this probe asked for BEFORE the app existed - so the first run measured a 1440-wide window
## while claiming 1920. Re-assert the frame and only measure once the root reports it. A number
## from a window that refused the size is a number about ANOTHER window (phone_fit_probe's lesson).
func _resize() -> void:
	if get_tree().root.size != FRAME:
		_resizes += 1
		if _resizes > 60:
			_fail("the root never took the stream frame size (%dx%d, still %dx%d) - this profile cannot be measured"
				% [FRAME.x, FRAME.y, get_tree().root.size.x, get_tree().root.size.y])
			_state = "measure"
			_wait = 4
			return
		DisplayServer.window_set_size(FRAME)
		get_tree().root.size = FRAME
		_wait = 5
		return
	_resizes = 0
	# let the layout settle at the new size before reading font sizes and geometry
	_wait = 6
	_state = "warm"


## The journal only has lines once the match has produced events, so a measurement taken the
## instant after _autostart would judge the empty state (the gate's first run did exactly that and
## reported "jrn-text not found"). Wait for the feed to draw a line, the way the READ gate waits for
## a human turn - bounded, and honest if it never comes.
func _warm() -> void:
	if _find_label_by_name("jrn-text") != null:
		_state = "measure"
		_wait = 4
		return
	_warms += 1
	if _warms > 300:
		# not a pass: say what was awaited and measure anyway so the failure names the reason
		_fail("no journal line was ever drawn (waited %d frames) - the gate cannot read 'what is happening'" % _warms)
		_state = "measure"
		_wait = 4
		return
	_wait = 4


func _spawn() -> void:
	I18n.set_locale("ru")
	_launcher = MainScript.new()
	add_child(_launcher)
	_state = "settle"
	_wait = 30


func _settle() -> void:
	# THE SEED COMES FROM THE COMMAND LINE, set by the wrapper as --smoke-seed=<FIXED_SEED>, which
	# the product's own `main._cli_value` reads - not an invented environment variable that nothing
	# would read (the fake-fix shape this project keeps finding).
	if _launcher != null and _launcher.has_method("_autostart"):
		_launcher.call("_autostart")
	var e = _launcher.get("_engine")
	if e != null and e.settings != null:
		# a capture may not race a decision clock
		e.settings.turn_timer = 0
		e.settings.auction_timer = 0
	# a tile selected so the inspector body is BUILT, and one sync so every panel has painted
	var gv = _launcher.get("_game_view")
	if gv != null and gv.has_method("_sync_all"):
		var insp = gv.find_child("inspector", true, false)
		if insp != null:
			insp.call("select", 1)
		gv.call("_sync_all")
	# the app has taken its own window size by now; make it take the STREAM frame before measuring
	_state = "resize"
	_wait = 6


## Walk the WHOLE live tree once, collecting every Label that carries one of the glance names.
## Names are matched exactly: the product names its own labels (turn-name, jrn-text, ...), so a
## rename cannot silently make this gate measure nothing - a missing role is a FAILURE below.
func _measure() -> void:
	for spec in GLANCE_SET:
		var node: Label = _find_label_by_name(str(spec["node"]))
		if node == null:
			_rows.append({"node": spec["node"], "role": spec["role"], "px": -1.0, "eff": -1.0, "found": false})
			_fails.append("%s (%s): not found in the live tree - the gate would judge a role it cannot see" % [spec["role"], spec["node"]])
			continue
		var px := float(node.get_theme_font_size("font_size"))
		var eff: float = px * (PHONE_WIDTH / float(FRAME.x))
		var drawn: bool = node.is_visible_in_tree()
		if bool(spec.get("context", false)):
			_rows.append({"node": spec["node"], "role": spec["role"], "px": px, "eff": eff,
				"found": true, "visible": drawn, "context": true})
			print("STREAM-READ ROW %s=%s px=%.0f effective_on_phone=%.1f - CONTEXT (the glance layer lives in the corner screens in B1)"
				% [spec["node"], spec["role"], px, eff])
			continue
		if bool(spec.get("drawn_only", false)) and not drawn:
			_rows.append({"node": spec["node"], "role": spec["role"], "px": px, "eff": eff, "found": true, "visible": false})
			print("STREAM-READ ROW %s=%s px=%.0f NOT DRAWN in this frame (compact: the dock is folded) - not judged"
				% [spec["node"], spec["role"], px])
			continue
		_rows.append({"node": spec["node"], "role": spec["role"], "px": px, "eff": eff, "found": true, "visible": drawn})
		print("STREAM-READ ROW %s=%s px=%.0f effective_on_phone=%.1f  (%.0f px in a %d px frame; the floor is %.0f px here)"
			% [spec["node"], spec["role"], px, eff, px, FRAME.x,
				LayoutProfile.glance_floor_px(float(FRAME.x))])


func _find_label_by_name(nm: String) -> Label:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return null
	var n: Node = gv.find_child(nm, true, false)
	if n is Label:
		return n as Label
	# the journal rows live in a scroll list; find_child searches recursively, so a miss here is
	# a real miss unless the journal has not drawn a line yet - which the failure names.
	return null


func _finish() -> void:
	if _done:
		return
	_done = true
	var root_size := get_tree().root.size
	if root_size.x != FRAME.x or root_size.y != FRAME.y:
		_fails.append("the root did not take the stream frame size (root %dx%d vs %dx%d) - the numbers describe another window"
			% [root_size.x, root_size.y, FRAME.x, FRAME.y])
	var judged := 0
	var worst := 999.0
	var worst_role := ""
	for row in _rows:
		if not bool(row["found"]):
			continue
		if not bool(row.get("visible", true)):
			continue
		if str(row["node"]) in BELOW_FLOOR_OK:
			continue
		judged += 1
		if float(row["eff"]) < worst:
			worst = float(row["eff"])
			worst_role = str(row["role"])
	# a gate that measured nothing must not pass: "0 findings" must never look like "all good"
	if judged == 0:
		_fails.append("not one glance role was measured at %s - the gate would pass on nothing" % FRAME_LABEL)
	print("STREAM-READ frame=%s phone_width=%.0f floor=%.0fpx judged=%d of %d role(s)"
		% [FRAME_LABEL, PHONE_WIDTH, GLANCE_FLOOR, judged, GLANCE_SET.size()])
	for f in _fails:
		print("STREAM-READ NOTE %s" % f)
	if not _fails.is_empty() or (judged > 0 and worst < GLANCE_FLOOR):
		var why := "; ".join(_fails) if not _fails.is_empty() else \
			"the smallest glance label is %.1fpx on a phone (%s: %.0fpx in the %s frame) - below the %.0fpx floor" % [
				worst, worst_role, _px_of(worst_role), FRAME_LABEL, GLANCE_FLOOR]
		print("==> STREAM-READ FAILED: %s" % why)
		get_tree().quit(1)
		return
	print("==> STREAM-READ PASSED (the %s frame scaled to a %.0fpx phone keeps every glance label at >= %.0fpx effective; smallest is %.1fpx, %s)" % [
		FRAME_LABEL, PHONE_WIDTH, GLANCE_FLOOR, worst, worst_role])
	get_tree().quit(0)


func _px_of(role: String) -> float:
	for row in _rows:
		if str(row["role"]) == role:
			return float(row["px"])
	return -1.0


func _fail(msg: String) -> void:
	if not _fails.has(msg):
		_fails.append(msg)
