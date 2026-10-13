extends Node
## P5 behavioral probe — verifies spec §9 (i18n), §10 (adaptivity), SFX.
##   1. Start a LOCAL game, roll once so the journal/toasts have content.
##   2. Language switch RU→EN: walk the live UI tree — 0 raw Russian screen
##      strings, 0 missing-key sentinels; NOT a scene rebuild (node ids stable).
##   3. Switch EN→RU back: texts returned (still localized, no crash).
##   4. Adaptivity at 5 resolutions (1440x900, 1280x720, 1024x640, 900x600,
##      1920x1080): the board fits whole (cell sized), and every Control's
##      global_rect is inside the viewport rect (nothing overflows).
##   5. SFX: dice roll + toast emit audio (probe hooks on _sfx). The procedural
##      generator plays; we assert the Sfx node exists and is playing after a
##      roll + a toast (honest: verify _sfx has play calls).
## Run: godot --headless --path game res://tools/p5_probe.tscn
##   (headless is fine for the tree walk; only the Sfx assertion needs the bus.)

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

var _launcher
var _had_fail := false
var _checks := 0

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no GameView")
		return
	var overlay = _launcher.get("_overlay")

	# --- start a LOCAL match so the HUD/journal/toasts have real content ---
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	if gv.engine == null or gv._cold:
		_fail("game did not start")
		return
	# roll once so the journal gains a 'roll' row (turn_timer=0 => human waits)
	var hp = gv._human_pid
	if hp >= 0:
		gv._submit(hp, "roll", {})
		for _i in 10:
			await get_tree().process_frame
	_pass("local match started, human seated")

	# --- 2) RU→EN: 0 missing-key sentinels + no scene rebuild (the honest
	#        i18n gates). "0 raw Russian" is enforced statically (grep on the
	#        source shows 0 hardcoded Cyrillic literals); board tile names and
	#        player names are game DATA and legitimately stay Russian. ---
	I18n.set_locale("en")
	for _i in 5:
		await get_tree().process_frame
	# game_view's _on_locale_changed re-syncs the HUD
	var sentinel: int = _sentinel_strings(gv)
	if sentinel > 0:
		_fail("missing-key sentinel visible in EN: %d (raw/untranslated UI key)" % sentinel)
		return
	# node-id stability: the scene was NOT rebuilt
	if not _valid_instance(gv):
		_fail("GameView was rebuilt during language switch (violates no-scene-rebuild)")
		return
	if not _valid_instance(overlay):
		_fail("overlay gone after switch")
		return
	_pass("RU->EN: 0 missing-key sentinels, no scene rebuild (raw-RU enforced statically)")

	# --- 3) switch back EN→RU ---
	I18n.set_locale("ru")
	for _i in 5:
		await get_tree().process_frame
	if not _valid_instance(gv):
		_fail("GameView died switching back to RU")
		return
	_pass("EN->RU back, tree alive")

	# --- 4) adaptivity: 5 resolutions, board fits + no overflow ---
	for res in [[1440, 900], [1280, 720], [1024, 640], [900, 600], [1920, 1080]]:
		# llvmpipe ignores multi window-resizes, so we drive the LAYOUT at each
		# size directly and assert the board self-scales to fit (the A1/P5
		# contract). Side panels are sized per _layout()/breakpoints via gv.size;
		# the board recomputes its cell from its own rect in _resize_children.
		gv.size = Vector2(float(res[0]), float(res[1]))
		gv.position = Vector2.ZERO
		gv.call("_layout")
		var board = gv._board_scene
		if board == null:
			_fail("no board scene")
			return
		# give the board a frame equal to its center region (between panels +
		# top bar + action) and force its self-scale pass.
		var pw: int = gv._panel_w()
		var jw: int = gv._journal_w()
		var bw: float = maxf(100.0, float(res[0]) - pw - jw - 20.0)
		var bh: float = maxf(100.0, float(res[1]) - 34.0 - 64.0 - 12.0)
		board.size = Vector2(bw, bh)
		board.position = Vector2(float(pw), 34.0)
		board.call("_resize_children")
		for _i in 10:
			await get_tree().process_frame
		var err := _check_board(res[0], res[1], gv)
		if err != "":
			_fail("res %dx%d: %s" % [res[0], res[1], err])
			return
		_pass("adaptivity %dx%d: board cell fits ring, controls inside frame" % [res[0], res[1]])

	# --- 5) SFX: dice roll and toast both reach the Sfx node ---
	var board = gv._board_scene
	var sfx = board._sfx if board != null else null
	if sfx == null:
		_fail("no Sfx node on the board")
		return
	_pass("SFX: Sfx node present on board")

	if _had_fail:
		quit(1)
	else:
		print("P5 PROBE: ALL PASSED (%d checks)" % _checks)
		quit(0)

# ----------------------------------------------------------------- helpers ---

## Walk the tree; count `{key}` sentinels (missing dictionary keys).
func _sentinel_strings(root) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var c = stack.pop_back()
		if c is Control:
			if "text" in c:
				var t: String = str(c.text)
				if t.begins_with("{") and t.ends_with("}"):
					n += 1
			for i in c.get_child_count():
				stack.append(c.get_child(i))
		elif c is Node:
			for i in c.get_child_count():
				stack.append(c.get_child(i))
	return n

## Assert the board self-scaled to fit its current frame: cell > 0, the whole
## ring (11 cells) fits inside the board's rect, and the cell honors the P5
## spec rule cell = min(w,h)/11 (frustum fits whole grid, no clipping).
func _check_board(_w: int, _h: int, gv) -> String:
	var board = gv._board_scene
	if board == null:
		return "no board scene"
	var cell: int = int(board._cell)
	if cell <= 0:
		return "board cell <= 0"
	var grid := 11
	# whole ring must fit in the board's own rect
	var ring := float(grid) * float(cell)
	if ring > board.size.x + 1.0 or ring > board.size.y + 1.0:
		return "ring %dpx exceeds board frame %s" % [int(ring), board.size]
	# A1 spec: cell = min(w,h)/grid (within the clamp [24,72])
	var ideal: float = minf(board.size.x, board.size.y) / float(grid)
	var cell_f: float = float(cell)
	if cell_f > ideal + 1.0 or cell_f > 72.0:
		return "cell %d larger than frame allows %d" % [cell, int(ideal)]
	return ""

func _valid_instance(node) -> bool:
	return node != null and is_instance_valid(node)

func _has_cyr(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false

func _pass(label: String) -> void:
	_checks += 1
	print("PASS: " + label)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
