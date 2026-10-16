extends Node
## READ-01/02/03 — "the board and the panels can be READ" (master-fix-plan §1, D1-D7).
##
## WHY IT MEASURES FROM INSIDE GODOT AND NOT FROM A PNG: the defect this gate exists for was a
## 9px cell name that died in its own background. A screenshot cannot tell "text is drawn" from
## "text is legible after the compositor had it": it answers "is there a blob here", and a blob is
## not a word. So the gate walks the LIVE tree the app itself built, and asks each cell's own
## Label for its font size and whether the string ACTUALLY FITS its rect at that size - the engine
## has the font, we do not have to guess it from pixels.
##
## It is still a real window (`--rendering-driver opengl3`, 1440x900): SG-02 taught that a Control
## reports its size inflated to get_combined_minimum_size(), and "do I fit?" answered yes on a
## half-width window. Sizes here are read from a laid-out, sized board.
##
## Three verdicts, one run, printed as the gate's own lines:
##   ==> READ-01 PASSED/FAILED (cells identifiable)
##   ==> READ-02 PASSED/FAILED (dock dead zone)
##   ==> READ-03 PASSED/FAILED (minimum font size)
## The shell wrapper `tools/ci/gates/read_gate.sh` greps for these and adds the frame.
##
## Usage:
##   godot --path game --rendering-driver opengl3 res://tools/gates/read_gate.tscn -- \
##         --outdir=<abs dir> [--skin=<id>] [--profiles=1440x900,1280x720,880x600]
const MainScript := preload("res://main.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const I18n := preload("res://i18n/i18n.gd")

## How many ring cells may carry NO readable identifier before the board is unreadable. The
## corners (0/10/20/30) are special cells by design and are allowed to be icon-only.
const SILENT_ALLOWANCE := 2
## Minimum legible font size, PER ROLE - the plan's own floors (master-fix-plan §1 R-1):
##   the NAME must be >= 11px (it is the cell's word), the PRICE >= 9px (it is a money tag),
##   a single-glyph tag (the owner badge's initial, the mortgaged "M") has no floor.
## A blanket 11px floor would fail the design's own price rule; a blanket 9px would have passed
## the 8px name that this whole track exists to kill. The floor is per role because the roles
## are different sizes of claim about the cell.
const NAME_MIN := 11
const PRICE_MIN := 9
## Labels allowed below their floor by design: one capital letter in a 12px box is legible.
const FONT_ALLOWLIST_NAMES := ["tile-badge", "tile-mortgaged", "badge", "mortgaged"]
## A dock is "empty" when this fraction of its height carries no content. The map measured 60%
## dead zone in the left dock and ~530px in the right one.
const DEAD_ZONE_MAX := 0.25

## READ-01 is specified at 1440x900 ("кадр 1440x900 живого матча", master-fix-plan §1 R-1); the other
## profiles are MEASURED AND REPORTED as context, not judged. Why that split is honest rather than
## convenient: at 1280x720 the two docks take 268+344 = 612px and the console 96px, so the board's
## square ring has only ~270px of height and its cells fall to 24px - the name MUST be dropped
## there (that is what label_step step 3 is for) and the group band carries identity. Judging that
## profile with a text-size rule would demand text that cannot exist at that size.
const JUDGED_PROFILE := "1440x900"

const PROFILES := [
	{"label": "1440x900", "size": Vector2i(1440, 900)},
	{"label": "1280x720", "size": Vector2i(1280, 720)},
	{"label": "880x600", "size": Vector2i(880, 600)},
]

var _outdir := "user://read"
var _skin := ""
var _launcher = null
var _profile_idx := 0
var _state := "boot"
var _wait := 6
var _done := false
## one entry per profile: {"label", "cells_ok", "cells_total", "silent", "min_font", "left_dead", "right_dead"}
var _results: Array = []
var _fails: Array = []
## what the scan SAW below the floor (an audit that cannot name its own find is not an audit)
var _under: Array = []
var _small_named: Array = []
var _dump: Array = []
var _t0 := 0
const WATCHDOG_MS := 300000


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
		"settle2":
			_settle2()
		"measure":
			_measure()
			_next_profile()
		"done":
			_finish()


func _ready() -> void:
	DisplayServer.window_set_size(PROFILES[0].size)
	get_tree().root.size = PROFILES[0].size
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


func _spawn() -> void:
	I18n.set_locale("ru")
	_launcher = MainScript.new()
	add_child(_launcher)
	_state = "settle"
	_wait = 30


## Boot the real match, then stop the clock so the human's turn stays on screen while the gate
## walks the tree (a capture may not race a decision timer - SG-07 learned this the hard way).
func _settle() -> void:
	if _launcher != null and _launcher.has_method("_autostart"):
		_launcher.call("_autostart")
	var e = _launcher.get("_engine")
	if e != null and e.settings != null:
		e.settings.turn_timer = 0
		e.settings.auction_timer = 0
	# a tile selected, so the inspector's body is BUILT (an unbuilt panel is not measured)
	var gv = _launcher.get("_game_view")
	if gv != null and gv.has_method("_sync_all"):
		var insp = gv.find_child("inspector", true, false)
		if insp != null:
			insp.call("select", 1)
		gv.call("_sync_all")
	_state = "measure"
	_wait = 6


func _next_profile() -> void:
	_profile_idx += 1
	if _profile_idx >= PROFILES.size():
		_state = "done"
		_wait = 2
		return
	var size: Vector2i = PROFILES[_profile_idx].size
	DisplayServer.window_set_size(size)
	get_tree().root.size = size
	var gv = _launcher.get("_game_view")
	if gv != null and gv.has_method("_sync_all"):
		gv.call("_sync_all")
	_state = "settle2"
	_wait = 24


func _settle2() -> void:
	_measure()
	_next_profile()


## --- the measurement -------------------------------------------------------------------------

func _measure() -> void:
	var label: String = PROFILES[_profile_idx].label
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fails.append("%s: no game view" % label)
		return
	# board_scene names its BoardView "board"; fall back to a scan so a rename cannot silently
	# make this gate measure nothing (the map's own lesson about probes reading dead fields).
	var board: Control = null
	for c in gv.get_children():
		if str(c.name) == "board" and c is Control:
			board = c
	if board == null:
		board = _find_board_recursive(gv)
	if board == null:
		_fails.append("%s: no board in the live tree - the gate would measure nothing" % label)
		return
	var row := _read_board(board, label)
	_results.append(row)


func _find_board_recursive(n: Node) -> Control:
	for c in n.get_children():
		if c.has_method("_place_board") and c is Control:
			return c
		var d := _find_board_recursive(c)
		if d != null:
			return d
	return null


## Walk every TileView the board actually built and ask its labels two questions:
##   1. does the cell carry ANY identifier a viewer can read (a name at >= MIN_FONT, or the
##      group band plus an owner badge - the deliberate step-3 reduction)?
##   2. what is the smallest font on the board?
func _read_board(board: Control, label: String) -> Dictionary:
	# per-PROFILE accumulators: a module-level list would carry profile 1's violations into
	# profile 2 and blame the wrong window (the count IS the verdict, so it must be per profile).
	_under = []
	_dump = []
	var tiles: Array = []
	for c in board.get_children():
		if c.get("index") != null and c.has_method("apply"):
			tiles.append(c)
	var cells_total := 0
	var cells_ok := 0
	var silent: Array = []
	var min_font := 999
	var small_allow := 999
	for tv in tiles:
		cells_total += 1
		var idx: int = int(tv.get("index"))
		var name_lbl: Label = null
		var badge: Label = null
		var band: ColorRect = null
		var cell_font := 999
		for c in (tv as Control).get_children():
			if c is Label:
				var l := c as Label
				var lname := str(l.name)
				_dump.append("%s[%s]:%d" % [lname, l.text.substr(0, 6), l.get_theme_font_size("font_size")])
				# the tile names its own labels, so this gate cannot be fooled by a heuristic when
				# a label's text happens to look like another role's (the map's "probe reading dead
				# fields" defect: a heuristic that matches nothing says nothing).
				if lname == "tile-name":
					name_lbl = l
				elif lname == "tile-badge":
					badge = l
				if l.visible and l.text.strip_edges() != "":
					var fsz: int = l.get_theme_font_size("font_size")
					if lname in FONT_ALLOWLIST_NAMES:
						small_allow = mini(small_allow, fsz)
						_small_named.append("%s:%d" % [lname, fsz])
					else:
						# the NAME is the cell's word and must clear NAME_MIN; the price is a money
						# tag and must clear PRICE_MIN. Per role, because a blanket floor either
						# fails the design's own price rule or passes the 8px name this kills.
						var floor: int = NAME_MIN if lname == "tile-name" else PRICE_MIN
						cell_font = mini(cell_font, fsz)
						if fsz < floor:
							_under.append("%s=%d<floor%d" % [lname, fsz, floor])
			elif c is ColorRect and band == null:
				band = c as ColorRect
		if cell_font < 999:
			min_font = mini(min_font, cell_font)
		# AN IDENTIFIER IS TEXT, or the deliberate step-3 reduction (group band AND owner badge).
		#
		# Why the band alone does NOT count, twice over:
		#   * it is a colour swatch, not a name - counting it made this gate report 40/40 on a board
		#     whose cells rendered 7px text, i.e. it found nothing on the exact defect it exists for
		#     (the plan's own measurement was "8 of 40 cells carried readable text");
		#   * the corners (0/10/20/30) carry no band at all, so a band-only rule reduces to "are the
		#     corners special", which is true by construction.
		# The badge half of the pair is right: at step 3 the cell keeps its group colour and its
		# owner, which together do identify it - and an UNOWNED cell is never in this branch,
		# because it still has a name at a legible size.
		var named: bool = name_lbl != null and name_lbl.visible \
			and name_lbl.get_theme_font_size("font_size") >= NAME_MIN \
			and name_lbl.text.strip_edges() != ""
		var readable_price: bool = _price_ok(tv)
		var banded: bool = band != null and band.size.x > 0.0 and band.size.y > 0.0
		var badged: bool = badge != null and badge.visible and badge.text.strip_edges() != ""
		if named or readable_price or (banded and badged):
			cells_ok += 1
		else:
			silent.append(idx)
	var row := {
		"label": label,
		"cells_total": cells_total,
		"cells_ok": cells_ok,
		"silent": silent,
		"min_font": min_font,
		"small_allow": small_allow,
		"under": _under.size(),
		"board_size": "%dx%d" % [int(board.size.x), int(board.size.y)],
		"left_dead": _dead_zone(gv_dock("seats")),
		"right_dead": _dead_zone(gv_dock("journal")),
	}
	# WHY THIS PRINTS THE BOARD'S OWN SIZE: the first revision reported "0/40 identifiable" at
	# 1280x720 with every dock gap at 0.00 - the shape of a board that was never re-laid-out after
	# the window shrank, not the shape of an unreadable board. A gate that cannot tell those two
	# apart reports the wrong defect, so the row carries the geometry it measured.
	print("READ-01 ROW %s cells=%d/%d silent=%d min_font=%d small_allow=%d board=%dx%d left_dead=%.2f right_dead=%.2f"
		% [label, cells_ok, cells_total, silent.size(), min_font, small_allow, int(board.size.x), int(board.size.y),
			float(row["left_dead"]), float(row["right_dead"])])
	return row


## The cell's money tag at a legible size counts as an identifier (a priced property reads its
## price even before its owner is known). Read from the tile itself, never assumed.
func _price_ok(tv) -> bool:
	for c in (tv as Control).get_children():
		if c is Label and str((c as Label).name) == "tile-price":
			var l := c as Label
			return l.visible and l.text.strip_edges() != "" and l.get_theme_font_size("font_size") >= PRICE_MIN
	return false


func gv_dock(id: String) -> Control:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return null
	# the docks may live in a rail or a drawer in compact; take whichever exists and is visible
	var direct: Node = gv.find_child(id, true, false)
	if direct is Control and (direct as Control).visible:
		return direct as Control
	var alt := "drawer-seats" if id == "seats" else "drawer-journal"
	var alt2 := "rail-left" if id == "seats" else "rail-right"
	for name_alt in [alt, alt2]:
		var n: Node = gv.find_child(str(name_alt), true, false)
		if n is Control and (n as Control).visible:
			return n as Control
	return direct as Control if direct is Control else null


## Fraction of a dock's height that carries no content: the largest vertical gap between the
## bottom of one visible child's rect and the top of the next (plus the gap below the last child
## and above the first). This is what "555px of emptiness" means, measured rather than eyeballed.
func _dead_zone(dock: Control) -> float:
	if dock == null or dock.size.y <= 1.0:
		return 0.0
	var spans: Array = []
	for c in dock.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.y <= 0.0:
			continue
		spans.append(Vector2(r.position.y, r.position.y + r.size.y))
	if spans.is_empty():
		return 1.0
	spans.sort_custom(func(a, b): return a.x < b.x)
	var top: float = dock.get_global_rect().position.y
	var bottom: float = top + dock.size.y
	var gap := 0.0
	gap = maxf(gap, float(spans[0].x) - top)
	var cursor: float = float(spans[0].y)
	for i in range(1, spans.size()):
		gap = maxf(gap, float(spans[i].x) - cursor)
		cursor = maxf(cursor, float(spans[i].y))
	gap = maxf(gap, bottom - cursor)
	return gap / dock.size.y


## --- verdicts --------------------------------------------------------------------------------

func _finish() -> void:
	if _done:
		return
	_done = true
	var rc := 0
	# READ-01 — judged on the profile the plan names; the rest is context
	var judged: Dictionary = {}
	for row in _results:
		if str(row["label"]) == JUDGED_PROFILE:
			judged = row
	if judged.is_empty():
		echo_fail("READ-01", "profile %s was never measured - the gate would pass on nothing" % JUDGED_PROFILE)
		rc = 1
	else:
		var silent: int = (judged["silent"] as Array).size()
		var ok: int = int(judged["cells_ok"])
		var total: int = int(judged["cells_total"])
		if total < 40:
			echo_fail("READ-01", "the board built %d cells, not 40 - the gate measured the wrong tree" % total)
			rc = 1
		elif silent > SILENT_ALLOWANCE:
			echo_fail("READ-01", "%d of %d ring cells carry no identifier (allowed %d) at %s: %s"
				% [silent, total, SILENT_ALLOWANCE, JUDGED_PROFILE, str(judged["silent"])])
			rc = 1
		else:
			print("==> READ-01 PASSED (%d/%d ring cells are identifiable at %s, %d silent of an allowed %d; font sizes read from the live Labels)"
				% [ok, total, JUDGED_PROFILE, silent, SILENT_ALLOWANCE])

	# READ-02 — every measured profile
	var bad02: Array = []
	for row in _results:
		if float(row["left_dead"]) > DEAD_ZONE_MAX:
			bad02.append("%s: the left dock is %.0f%% empty (max %.0f%%)" % [row["label"], float(row["left_dead"]) * 100.0, DEAD_ZONE_MAX * 100.0])
		if float(row["right_dead"]) > DEAD_ZONE_MAX:
			bad02.append("%s: the right dock is %.0f%% empty (max %.0f%%)" % [row["label"], float(row["right_dead"]) * 100.0, DEAD_ZONE_MAX * 100.0])
	if not bad02.is_empty():
		echo_fail("READ-02", "; ".join(bad02))
		rc = 1
	else:
		print("==> READ-02 PASSED (no dock leaves more than %.0f%% of its height empty on any measured profile)" % (DEAD_ZONE_MAX * 100.0))

	# READ-03 — every PROSE label clears its role's floor in the judged profile. The count is the
	# verdict, not a global minimum: a 9px price is correct by design while a 9px name is the bug.
	if judged.is_empty():
		rc = 1
	elif int(judged["under"]) > 0:
		echo_fail("READ-03", "%d label(s) below their role floor at %s: %s"
			% [int(judged["under"]), JUDGED_PROFILE, ",".join(_under.slice(0, 8))])
		rc = 1
	else:
		print("==> READ-03 PASSED (every prose label clears its floor at %s: name >= %dpx, price >= %dpx; %d single-glyph tag(s) excluded by design)"
			% [JUDGED_PROFILE, NAME_MIN, PRICE_MIN, int(judged["small_allow"]) if int(judged["small_allow"]) < 999 else 0])

	if not _under.is_empty():
		print("READ-03 UNDER-FLOOR %s" % ",".join(_under.slice(0, 12)))
	if not _small_named.is_empty():
		print("READ-03 ALLOWED-SMALL %s" % ",".join(_small_named.slice(0, 8)))
	for f in _fails:
		print("READ NOTE %s" % f)
	print("READ DONE profiles=%d skin=%s rc=%d in %dms" % [_results.size(), SkinManager.chosen, rc, Time.get_ticks_msec() - _t0])
	get_tree().quit(0)


func echo_fail(id: String, reason: String) -> void:
	print("==> %s FAILED: %s" % [id, reason])
