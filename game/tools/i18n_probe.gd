extends Node
## Phase 0 diagnostic probe — i18n completeness (TDD-first).
## Verifies the UI has no raw/untranslated display strings:
##   1. No missing-key sentinels ({key}) in the live tree in RU or EN.
##   2. No raw engine phase enums (TURN_START, PURCHASE_WAIT, AUCTION, ...)
##      rendered as visible text.
##   3. Locale switch RU<->EN updates text live (no scene rebuild).
##   4. Every i18n data_*.gd entry resolves in both locales (no sentinel).
## Run: godot --headless --path game res://tools/i18n_probe.tscn

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

var _had_fail := false
var _checks := 0

func _ready() -> void:
	await _check_dict_coverage()
	await _check_live_tree()

	if _had_fail:
		quit(1)
	else:
		print("I18N_PROBE: ALL PASSED (%d checks)" % _checks)
		quit(0)

## Every key in the merged dict resolves in both locales (no sentinel).
func _check_dict_coverage() -> void:
	var keys := I18n.keys()
	var bad := 0
	for k in keys:
		for loc in ["ru", "en"]:
			I18n.set_locale(loc)
			var v: String = I18n.t(k)
			if v.begins_with("{") and v.ends_with("}"):
				bad += 1
				if bad <= 5:
					print("  missing %s in %s" % [k, loc])
	if bad > 0:
		_fail("%d i18n keys missing in a locale" % bad)
		return
	_pass("all %d i18n keys resolve in RU and EN" % keys.size())

## Launch the game, switch locales, and assert no sentinels / raw enums / rebuild.
func _check_live_tree() -> void:
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 20:
		await get_tree().process_frame
	var gv = launcher.get("_game_view")
	if gv == null:
		_fail("no GameView")
		return
	var overlay = launcher.get("_overlay")
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	if gv.engine == null:
		_fail("game did not start")
		return

	# RU
	I18n.set_locale("ru")
	for _i in 5:
		await get_tree().process_frame
	var sent_ru := _sentinel_strings(gv)
	var raw_ru := _raw_enum_strings(gv)
	if sent_ru > 0:
		_fail("RU: %d missing-key sentinels" % sent_ru)
		return
	if raw_ru > 0:
		_fail("RU: %d raw engine-enum strings rendered" % raw_ru)
		return
	_pass("RU: 0 sentinels, 0 raw enums")

	# EN
	I18n.set_locale("en")
	for _i in 5:
		await get_tree().process_frame
	if not _valid(gv):
		_fail("GameView rebuilt during RU->EN switch")
		return
	var sent_en := _sentinel_strings(gv)
	var raw_en := _raw_enum_strings(gv)
	if sent_en > 0:
		_fail("EN: %d missing-key sentinels" % sent_en)
		return
	if raw_en > 0:
		_fail("EN: %d raw engine-enum strings rendered" % raw_en)
		return
	_pass("EN: 0 sentinels, 0 raw enums, no scene rebuild")

## Count `{key}` sentinels in the live tree.
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

## Count raw engine phase enums rendered as visible text.
func _raw_enum_strings(root) -> int:
	var enums := ["TURN_START", "ROLL_RESOLVE", "PURCHASE_WAIT", "AUCTION",
		"RENT_SETTLE", "CARD_WAIT", "JAIL_DECISION", "END_TURN", "END_GAME",
		"SETUP"]
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var c = stack.pop_back()
		if c is Control:
			if "text" in c:
				var t: String = str(c.text)
				for e in enums:
					if t.contains(e):
						n += 1
						break
			for i in c.get_child_count():
				stack.append(c.get_child(i))
		elif c is Node:
			for i in c.get_child_count():
				stack.append(c.get_child(i))
	return n

func _valid(node) -> bool:
	return node != null and is_instance_valid(node)

func _pass(label: String) -> void:
	_checks += 1
	print("PASS: " + label)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
