extends Node
## Audit probe: verifies regression bugs found in P0-P5.
## Run: godot --path game res://tools/ui_audit_probe.tscn

const MainScript := preload("res://main.gd")
const I := preload("res://i18n/i18n.gd")

var _launcher
var _had_fail := false

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame
	_run_tests()

func _run_tests() -> void:
	_pass("=== UI/UX Audit: P0-P5 regression bugs ===")
	_test_driver_localized()
	_test_topbar_phase_cyrillic()
	_test_language_hardcoded()
	_test_inspector_retranslate()
	_test_auctions_wrong_keys()
	if _had_fail:
		print("AUDIT PROBE: FAILED")
		get_tree().quit(1)
	else:
		print("AUDIT PROBE: ALL PASSED")
		get_tree().quit(0)


## BUG 4: Driver OptionButton items are raw DRIVERS constant strings.
func _test_driver_localized() -> void:
	var overlay: Node = _launcher.get("_overlay")
	if overlay == null:
		_fail("BUG4 setup: no overlay"); return
	var rows: Array = overlay.get("_rows")
	if rows.is_empty():
		_fail("BUG4 setup: no player rows"); return
	var driver: Node = rows[0].get("driver")
	if driver == null or not driver is Node:
		_fail("BUG4 setup: no driver button"); return
	var raw_drivers: Array = ["LOCAL", "AI", "CHAT", "sdk:neuro", "sdk:evil"]
	for i in driver.get_item_count():
		var text: String = driver.get_item_text(i)
		for raw in raw_drivers:
			if text == raw:
				_fail("BUG 4: driver item %d = '%s' (raw, not I18n.t)" % [i, raw]); return
	_pass("BUG 4: all driver items localized")


## BUG 6: TopBar._phase label has Cyrillic after EN locale switch.
func _test_topbar_phase_cyrillic() -> void:
	var gv: Node = _launcher.get("_game_view")
	if gv == null:
		_fail("BUG6 setup: no game_view"); return
	var tb: Node = gv.get("_top")
	if tb == null:
		_fail("BUG6 setup: no TopBar"); return
	I.set_locale("en")
	if tb.has_method("retranslate"):
		tb.call("retranslate")
	if tb.get("_phase") != null:
		var phase_lbl: Node = tb.get("_phase")
		if phase_lbl != null:
			var t: String = str(phase_lbl.get("text"))
			if _has_cyrillic(t):
				_fail("BUG 6: _phase has Cyrillic after EN switch: '%s'" % t); return
	_pass("BUG 6: _phase label retranslated correctly")


## BUG 8: Language selector hardcodes "Rusciy"/"English".
func _test_language_hardcoded() -> void:
	var overlay: Node = _launcher.get("_overlay")
	if overlay == null:
		_fail("BUG8 setup: no overlay"); return
	var lang_btn: Node = overlay.get("_language")
	if lang_btn == null:
		_fail("BUG8 setup: no language button"); return
	for i in lang_btn.get_item_count():
		var text: String = lang_btn.get_item_text(i)
		if text == "Rusciy" or text == "English":
			_fail("BUG 8: language item %d = '%s' (hardcoded, not I18n.t)" % [i, text]); return
	_pass("BUG 8: language items are I18n.t()-based")


## BUG 3b: TileInspector placeholder text not retranslated.
func _test_inspector_retranslate() -> void:
	var gv: Node = _launcher.get("_game_view")
	if gv == null:
		_fail("BUG3b setup: no game_view"); return
	var ti: Node = gv.get("_inspector")
	if ti == null:
		_fail("BUG3b setup: no TileInspector"); return
	I.set_locale("ru")
	# `show_tile` does not exist: the old probe called a method nothing implements, so both
	# readings were taken with the SAME locale and could never differ. `clear()` is what actually
	# writes the placeholder.
	if ti.has_method("clear"):
		ti.call("clear")
	var ru_text: String = ""
	var txt_node: Node = ti.get("_text")
	if txt_node != null:
		ru_text = str(txt_node.get("text"))
	I.set_locale("en")
	if ti.has_method("retranslate"):
		ti.call("retranslate")
	var en_text: String = ""
	txt_node = ti.get("_text")
	if txt_node != null:
		en_text = str(txt_node.get("text"))
	if ru_text == en_text and ru_text != "":
		_fail("BUG 3b: inspector text unchanged after RU->EN: '%s'" % ru_text)
	else:
		_pass("BUG 3b: inspector retranslated or empty")


## BUG 1: _auctions OptionButton uses I18n.t("settings.fp_on") ? the WRONG key.
## Detected by reading the source file directly.
func _test_auctions_wrong_keys() -> void:
	var f := FileAccess.open("res://ui/settings_overlay.gd", FileAccess.READ)
	if f == null:
		_fail("BUG1 setup: cannot open settings_overlay.gd"); return
	var source: String = f.get_as_text()
	f.close()
	## The bug is on line 329: _auctions.add_item(I18n.t("settings.fp_on"))
	## Check for the exact buggy pattern.
	var buggy: String = '_auctions.add_item(I18n.t("settings.fp_on"))'
	if source.find(buggy) >= 0:
		_fail("BUG 1: _auctions uses settings.fp_on key (free_parking key, not auctions)")
	else:
		_pass("BUG 1: auctions OptionButton uses correct keys")


## ---- helpers ----

func _has_cyrillic(s: String) -> bool:
	for i in s.length():
		var c: int = s.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false

func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	_had_fail = true

func _pass(msg: String) -> void:
	print("PASS: " + msg)
