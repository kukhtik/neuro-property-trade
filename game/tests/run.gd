extends SceneTree
## Headless test runner.
##
## Usage:  godot --headless --path game --script res://tests/run.gd
##
## Each test module (e.g. board_test.gd) exposes a static `test_list()`
## returning Array[String] of test-function names. Each test runs as a
## static func returning ""/null on pass, or an error string on failure.
## No test-class framework (project convention: plain functions).

var _failures: Array = []
var _count: int = 0

func _init() -> void:
	print("=== Neuro Property Trade — headless tests ===")
	var modules: Array[String] = [
		"res://tests/board_test.gd",
		"res://tests/rng_test.gd",
		"res://tests/player_test.gd",
		"res://tests/event_log_test.gd",
		"res://tests/card_test.gd",
		"res://tests/game_settings_test.gd",
		"res://tests/engine_test.gd",
		"res://tests/seats_test.gd",
		"res://tests/sdk_test.gd",
		"res://tests/admin_test.gd",
		"res://tests/admin_controller_test.gd",
		"res://tests/snapshot_test.gd",
		"res://tests/tony_test.gd",
		"res://tests/voice_test.gd",
		"res://tests/admin_gate_test.gd",
		"res://tests/player_identity_test.gd",
		"res://tests/i18n_test.gd",
		"res://tests/replay_test.gd",
		"res://tests/skin_manager_test.gd",
		"res://tests/ui_live_test.gd",
		"res://tests/server_test.gd",
		# CHAT-01: the Twitch chat seat (promise S2) had every piece and NO acceptance
		# test - `grep -c CHAT-01 tools/ci/run_gates.sh` was 0.
		"res://tests/chat_test.gd",
		"res://tests/remote_driver_test.gd",
		"res://tests/launch_params_test.gd",
		"res://tests/network_handover_test.gd",
		# back in the set: the v3 swap left this module on disk but dropped it from `modules`,
		# so its 6 palette tests never ran while the suite stayed green.
		"res://tests/theme_test.gd",
		# HG-10: the projection contract (pins outputs, scans UI reads, `pot` regression case)
		"res://tests/ui_contract_test.gd",
		# UI-core pure-function tests: EventAdapter, Money, IntentMap,
		# LayoutProfile, UiProfile, UiStore, JournalLines
		# E-4: an auction is visible on the sheet AND on the board (clock + central plate)
		"res://tests/auction_ui_test.gd",
		# E-3: the rent a tile charges NOW is visible (projection rent_now == the engine's own rule)
		"res://tests/projection_rent_test.gd",
		# E-2: an event is visible ON THE BOARD (banner queue + cell flash)
		"res://tests/board_event_test.gd",
		# E-1: a trade tells the reader WHAT is traded (composition in tile names)
		"res://tests/modal_trade_test.gd",
		# READ-1: the board cell is READABLE (font floors, `short`, label_step, house counter)
		"res://tests/tile_view_test.gd",
		# The board's VISUAL GRAMMAR: a fact about a cell is a FORM, not a word (R-21..R-26).
		# The owner asked for it in words: "не пиши, а показывай в дизайне".
		"res://tests/state_glyphs_test.gd",
		# P1.1 (brief §4.1): the ring's centre is a four-zone turn panno - zones, ratios, projection
		# source and the no-absolute-layout rule are pinned here.
		"res://tests/panno_test.gd",
		# AUDIO (track 2): `game_settings.sound`, the SoundManager switch/log, one asset per sound name
		# and the engine-event -> sound binding. Before this module the product shipped a "Звук"
		# checkbox that wrote nothing and no sound files at all.
		"res://tests/sound_test.gd",
		# E-5 / D13: карточка игрока показывает ЧТО у него (список клеток по именам в подсказке), а
		# отдельное действие карточки выделяет его клетки на доске. До этого карточка несла только
		# чип «В собственности: N» - количество без списка.
		"res://tests/players_tooltip_test.gd",
	]
	_check_orphan_modules(modules)
	for path in modules:
		_run_module(path)
	_summary()
	quit(0 if _failures.size() == 0 else 1)

func _check_orphan_modules(modules: Array[String]) -> void:
	# EVERY TEST MODULE ON DISK MUST BE IN THE RUN. `theme_test.gd` (6 palette tests) sat in
	# game/tests/ while `modules` never named it — `ran N tests, 0 failed` stayed green and the
	# file was never executed. The listing is the one source that cannot be forgotten by hand:
	# compare it against the list the same way `test_list()` is compared against the methods.
	# A scan that loses its own coverage silently proves nothing, so the count is asserted too.
	var dir := DirAccess.open("res://tests")
	if dir == null:
		_failures.append("orphan check: cannot open res://tests")
		push_error("orphan check: cannot open res://tests")
		return
	var found := 0
	for f in dir.get_files():
		if not str(f).ends_with("_test.gd"):
			continue
		found += 1
		var p := "res://tests/" + str(f)
		if not modules.has(p):
			var msg := "orphan test module: %s exists but is not in modules[]" % p
			_failures.append(msg)
			push_error(msg)
	if found < 10:
		var msg2 := "orphan check: only %d test modules found on disk — the scan lost its coverage" % found
		_failures.append(msg2)
		push_error(msg2)


func _run_module(path: String) -> void:
	var mod: GDScript = load(path)
	if mod == null:
		# A MODULE THAT DOES NOT PARSE VANISHES, AND THE RUN STAYS GREEN. This happened on
		# 21.10: `sound_manager.gd` had a parse error (a `static` keyword on a comment line),
		# so `sound_test.gd` could not preload it, the module was dropped, and the oracle
		# reported "ran 444 tests, 0 failed" - while EIGHT sound tests never ran. The runner
		# caught a listed function that does not exist and a module on disk that is not
		# listed, but not a module that cannot be LOADED.
		_failures.append("cannot load %s - it does not parse, so its tests never run" % path)
		return
	var names: Array = mod.call("test_list")
	# AN EMPTY LIST MEANS THE MODULE IS BROKEN, NOT EMPTY. A module whose PRELOAD failed
	# still parses itself, so `load()` returns a script, but `test_list()` comes back with
	# nothing - and the runner counts 0 tests for it and stays green. That is what happened
	# on 21.10: `sound_manager.gd` had a parse error, `sound_test.gd` could not preload it,
	# and the oracle reported "ran 444 tests, 0 failed" while EIGHT sound tests never ran.
	if names.is_empty():
		var msg := "%s :: test_list() is EMPTY - the module is broken, not empty (a preload that failed to parse leaves the module itself parseable)" % path.get_file()
		_failures.append(msg)
		push_error(msg)
		return
	# A TEST FUNCTION THAT IS NOT LISTED IN `test_list` NEVER RUNS, and the suite stays green.
	# That happened while adding the language button: the function was written, the assertion it
	# makes was real, and `ran N tests, 0 failed` never counted it. Compare what the module
	# DECLARES against the methods it actually has, the same way a missing module is caught.
	var declared := {}
	for n in names:
		declared[str(n)] = true
	for m in mod.get_script_method_list():
		var mname := str(m.get("name", ""))
		if mname.begins_with("test_") and mname != "test_list" and not declared.has(mname):
			var msg := "%s :: %s exists but is not in test_list()" % [path.get_file(), mname]
			_failures.append(msg)
			push_error(msg)
	for test_name in names:
		_count += 1
		var err: Variant = mod.call(test_name)
		if err != null and err != "":
			_failures.append("%s :: %s" % [path.get_file(), test_name])
			push_error("%s :: %s :: %s" % [path.get_file(), test_name, err])

func _summary() -> void:
	print("---")
	print("ran %d tests, %d failed" % [_count, _failures.size()])
	if _failures.size() == 0:
		print("ALL TESTS PASSED")
	else:
		for f in _failures:
			push_error(f)
