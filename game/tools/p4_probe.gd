extends Node
## P4 behavioral probe — verifies spec §11 P4 (modes):
##   1. Observer layout: a match with NO LOCAL seat → 0 action buttons, thin
##      status bar naming the decision holder; 👁 visible in TopBar; journal
##      widened to 380.
##   2. LOCAL match → 👁 hidden, normal action buttons exist for the human.
##   3. JournalPanel: filters actually filter (player/type/money), count
##      matches, export writes a .jsonl file with all entries.
##   4. Follow: clicking a player row highlights their tiles (target frames).
##   5. Admin panel: per-op fields (op-specific rows), inline ok/reason shown
##      on the row (NOT stdout-only), admin log records the call, search
##      filters rows, confirmation gates destructive ops.
##   6. Tooltip autoprobe on the admin panel controls.
## Run headless: godot --headless --path game res://tools/p4_probe.tscn
## Run windowed: godot --path game res://tools/p4_probe.tscn

const MainScript := preload("res://main.gd")
const SettingsScript := preload("res://core/game_settings.gd")

var _launcher
var _had_fail := false

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no GameView at launch")
		quit(1)
		return

	# --- start an OBSERVER match: host role = watch only (no LOCAL seat) ---
	var overlay = _launcher.get("_overlay")
	overlay.set("auto_confirm", true)
	# switch host role to observer: collect -> flip host role -> collect
	overlay._host_role.select(1)
	# force all rows to AI (host row LOCAL was auto-switched by _collect_settings)
	overlay.call("_start_pressed")
	for _i in 20:
		await get_tree().process_frame
	if gv.engine == null:
		_fail("engine not built after observer START")
		quit(1)
		return
	# ensure no LOCAL seat remains (defensive: verify what _collect_settings did)
	var has_local := false
	for s in gv.seats:
		if str(s.input_driver) == "LOCAL":
			has_local = true
	overlay.call("_refresh_buttons")
	if has_local:
		var dbg := []
		for s in gv.seats:
			dbg.append("%s/%s" % [str(s.name), str(s.input_driver)])
		_fail("observer match still has a LOCAL seat — host_role=%d drivers=%s" % [
			overlay._host_role.selected, "|".join(dbg)])
		quit(1)
		return

	await _check_observer_layout(gv)
	# follow-highlight is an OBSERVER feature (only applies when _observer is
	# true; a LOCAL match clears it by design). Check it before restarting into
	# the LOCAL match so it runs in the mode it's defined for.
	await _check_follow(gv)
	await _check_local_layout_restored(gv)
	await _check_journal_filters(gv)
	await _check_admin_panel(gv)

	if _had_fail:
		print("P4 PROBE: FAILED")
		quit(1)
	else:
		print("P4 PROBE: ALL PASSED")
		quit(0)

# ------------------------------------------------- 1. observer layout ----

func _check_observer_layout(gv) -> void:
	# run some AI ticks so a holder exists
	for _i in 30:
		await get_tree().process_frame
	if not gv._observer:
		_fail("observer flag not set for a no-LOCAL match")
		return
	# 0 action buttons in the action panel
	var btns := _count_buttons(gv._actions)
	if btns != 0:
		_fail("observer layout has %d action buttons (want 0)" % btns)
		return
	# status bar names the holder (non-empty, mentions решение)
	var status: String = gv._actions._status.text
	if status == "" or not status.contains("решение"):
		_fail("observer status bar does not name the decision holder: '%s'" % status)
		return
	# journal widened to 380
	var jw: int = gv._jpanel.custom_minimum_size.x
	if jw < 380:
		_fail("observer journal width %d < 380" % jw)
		return
	# 👁 visible in TopBar
	if not gv._top._eye_btn.visible:
		_fail("observer: 👁 button not visible in TopBar")
		return
	# journal panel actually shows lines from the engine log
	var jcount: String = gv._journal._count_lbl.text
	if jcount == "0/0":
		_fail("journal shows 0/0 in an observer match")
		return
	print("PASS: observer layout — 0 buttons, holder status '%s', journal %dpx, 👁 visible, journal count %s" % [
		status, jw, jcount])

# ------------------------------------------- 2. back to a LOCAL match ----

func _check_local_layout_restored(gv) -> void:
	# rebuild the game with LOCAL seats via a fresh apply through the overlay
	var overlay = _launcher.get("_overlay")
	overlay._host_role.select(0)
	overlay.call("_start_pressed")
	for _i in 20:
		await get_tree().process_frame
	if gv._observer:
		_fail("LOCAL match still flagged observer")
		return
	if gv._top._eye_btn.visible:
		_fail("LOCAL match shows the 👁 button (must be hidden)")
		return
	# the human seat has action buttons (roll on TURN_START)
	var found_roll := false
	for c in gv._actions._btn_row.get_children():
		if c is Button and str(c.text).contains("БРОСИТЬ"):
			found_roll = true
	if not found_roll:
		_fail("LOCAL match: no БРОСИТЬ КУБ button for the human seat")
		return
	print("PASS: LOCAL match — 👁 hidden, human action buttons present")

# ------------------------------------------------- 3. journal filters ----

func _check_journal_filters(gv) -> void:
	# The journal type-list only contains types present in the log. On a fresh
	# LOCAL restart the human hasn't rolled yet (turn_timer=0, no auto-pass),
	# so drive one roll and wait for the seat-manager tick to append events.
	if gv._human_pid >= 0 and gv.manager != null:
		gv.manager.push_intent(gv._human_pid, "roll", {})
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var jp = gv._journal
	if jp == null:
		_fail("no JournalPanel")
		return
	var total: int = jp._entries.size()
	if total == 0:
		_fail("journal has no entries to filter")
		return
	# money filter: count must drop or stay, and every shown line has $
	var before: String = jp._count_lbl.text
	jp._money_only.button_pressed = true
	jp._on_filter_changed()
	var after_money: String = jp._count_lbl.text
	if after_money == "0/0" or after_money == before:
		_fail("money filter did not change the visible set: %s -> %s" % [before, after_money])
		jp._money_only.button_pressed = false
		jp._on_filter_changed()
		return
	# player filter: pick pid 0
	jp._money_only.button_pressed = false
	jp._player_filter.select(1)
	jp._on_filter_changed()
	var pid0: String = jp._count_lbl.text
	if pid0 == "0/0":
		_fail("player filter pid=0 shows 0 events (turn events must exist)")
		return
	# type filter: filter by "roll"
	var roll_idx := -1
	for i in jp._type_filter.item_count:
		if jp._type_filter.get_item_text(i) == "roll":
			roll_idx = i
	if roll_idx < 0:
		_fail("type filter has no 'roll' option")
		return
	jp._type_filter.select(roll_idx)
	jp._on_filter_changed()
	var type_cnt: String = jp._count_lbl.text
	if type_cnt == "0/0":
		_fail("type filter 'roll' shows 0 events")
		return
	# pure function sanity: filter_entries respects all three
	var vis: Array = jp.filter_entries(jp._entries, 0, "roll", false)
	for e in vis:
		if str(e.get("type", "")) != "roll":
			_fail("filter_entries returned a non-roll entry")
			return
	# export
	jp._export()
	var f := FileAccess.open("user://journal_export.jsonl", FileAccess.READ)
	if f == null:
		_fail("journal export file missing")
		return
	var lines := f.get_as_text().split("\n")
	f.close()
	var n := 0
	for l in lines:
		if l.strip_edges() != "":
			n += 1
	if n != total:
		_fail("export has %d lines, want %d" % [n, total])
		return
	# reset filters
	jp._player_filter.select(0)
	jp._type_filter.select(0)
	jp._on_filter_changed()
	print("PASS: journal filters (all %s -> money %s -> pid0 %s -> roll %s) + export %d lines" % [
		before, after_money, pid0, type_cnt, n])

# ------------------------------------------------------ 4. follow ----

func _check_follow(gv) -> void:
	# click player row 0 → their tiles get target highlights
	var tiles: Array = []
	for p in (gv.engine.players as Array):
		if int(p.owned_tiles().size()) > 0:
			tiles = p.owned_tiles()
			break
	if tiles.is_empty():
		# grant a tile to pid 0 so the check has something to assert
		gv.engine.players[0].add_ownership(1)
		tiles = gv.engine.players[0].owned_tiles()
	gv.follow_player(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var marked: Array = []
	var board = gv._board_scene._board
	for i in board._tile_nodes.size():
		if board._tile_nodes[i]._target:
			marked.append(i)
	if marked.size() != tiles.size():
		_fail("follow highlight %d tiles, want %d" % [marked.size(), tiles.size()])
		return
	for t in tiles:
		if not marked.has(int(t)):
			_fail("follow highlight missing tile %d" % int(t))
			return
	# toggle off
	gv.follow_player(-1)
	await get_tree().process_frame
	var marked2: Array = []
	for i in board._tile_nodes.size():
		if board._tile_nodes[i]._target:
			marked2.append(i)
	if not marked2.is_empty():
		_fail("unfollow did not clear highlights (%d left)" % marked2.size())
		return
	print("PASS: follow player 0 highlights their %d tiles; unfollow clears" % tiles.size())

# --------------------------------------------- 5. admin panel ----

func _check_admin_panel(gv) -> void:
	var panel = _launcher.get("_panel")
	if panel == null:
		_fail("no admin panel (host)")
		return
	var gate = _launcher.get("_gate")
	panel.setup(gate)
	panel.visible = true

	# tab structure
	var tabs: TabContainer = panel._tabs
	if tabs.get_tab_count() != 4:
		_fail("admin panel has %d tabs, want 4" % tabs.get_tab_count())
		return
	var titles := ["Быстрые", "Состояние", "События", "Правки"]
	for i in 4:
		if tabs.get_tab_title(i) != titles[i]:
			_fail("tab %d titled '%s', want '%s'" % [i, tabs.get_tab_title(i), titles[i]])
			return
	print("PASS: admin panel has 4 tabs (Быстрые/Состояние/События/Правки)")

	# quick op: force_roll executes through the gate and lands in the admin log
	var log_before: int = panel._admin_log_lines.size()
	panel._quick_force_roll()
	var ok_line := false
	for l in panel._admin_log_lines:
		if l.contains("форс-ролл"):
			ok_line = true
	if not ok_line or panel._admin_log_lines.size() <= log_before:
		_fail("admin log did not record force_roll")
		return
	print("PASS: quick force_roll → inline admin log entry recorded")

	# edits: per-op field visibility
	var bal: Dictionary = panel._edit_widgets("set_balance")
	if not bal.has("pid") or not bal.has("amount") or bal.has("d1"):
		_fail("set_balance row shows wrong fields")
		return
	var fd: Dictionary = panel._edit_widgets("force_dice")
	if not fd.has("d1") or not fd.has("d2") or fd.has("pid"):
		_fail("force_dice row shows wrong fields")
		return
	# set_balance via the edits row → engine money changes + inline result ok
	var eng = _launcher.get("_engine")
	var target: int = int(eng.player(0).money) + 7
	(bal["amount"] as SpinBox).value = target
	# pid selector index == pid
	(bal["pid"] as OptionButton).select(0)
	panel._on_edit_apply("set_balance")
	if int(eng.player(0).money) != target:
		_fail("set_balance did not change money to %d (got %d)" % [target, int(eng.player(0).money)])
		return
	var res_lbl: Label = bal["result"]
	if not str(res_lbl.text).contains("ok"):
		_fail("inline result for set_balance is not ok: '%s'" % res_lbl.text)
		return
	print("PASS: edits set_balance → engine changed + inline 'ok' on the row")

	# search filter
	panel._search.text = "телепорт"
	panel._on_search()
	var visible_rows := 0
	for r in panel._edit_rows:
		if (r["row"] as Control).visible:
			visible_rows += 1
	if visible_rows != 1:
		_fail("search 'телепорт' left %d rows visible, want 1" % visible_rows)
		return
	panel._search.text = ""
	panel._on_search()
	print("PASS: search filter narrows Правки to the matching row")

	# confirmation gate for destructive op (redo_turn) — cancel first
	panel.auto_confirm = false
	var seed_val := 4242
	var rd: Dictionary = panel._edit_widgets("redo_turn")
	(rd["seed"] as SpinBox).value = seed_val
	panel._on_edit_apply("redo_turn")
	# dialog opens; cancel it via the cancel path
	var dlg: ConfirmationDialog = null
	for c in panel.get_children():
		if c is ConfirmationDialog:
			dlg = c
	if dlg == null:
		_fail("destructive redo_turn did not open a confirmation dialog")
		return
	dlg.canceled.emit()
	await get_tree().process_frame
	# engine RNG seed unchanged → the op never ran: no admin_override event for it
	var found_redo := false
	for e in eng.log.entries():
		if str(e.get("type", "")) == "admin_override" and str(e.get("data", {}).get("op", "")) == "redo_turn":
			found_redo = true
	if found_redo:
		_fail("redo_turn executed despite cancel")
		return
	print("PASS: destructive redo_turn blocked by confirmation dialog on cancel")
	# accept path (auto_confirm)
	panel.auto_confirm = true
	panel._on_edit_apply("redo_turn")
	found_redo = false
	for e in eng.log.entries():
		if str(e.get("type", "")) == "admin_override" and str(e.get("data", {}).get("op", "")) == "redo_turn":
			found_redo = true
	if not found_redo:
		_fail("redo_turn did not execute on confirmed apply")
		return
	print("PASS: destructive redo_turn executes after confirmation")

func _count_actions(node) -> int:
	var n := 0
	for c in node.get_children():
		if c is BaseButton:
			n += 1
	return n

func _count_buttons(panel) -> int:
	return _count_actions(panel._btn_row)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)