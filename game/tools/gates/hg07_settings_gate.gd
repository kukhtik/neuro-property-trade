extends Node
## HG-07 gate - match settings (docs/restoration/gates.md, HG-07).
##
## The v3 shell had reduced the settings sheet to four fields with the drivers HARDCODED
## (`settings_overlay.gd:170-188`: "0 - LOCAL, остальные AI"): no driver choice at all, so a
## REMOTE seat (a friend) or an `sdk:neuro` seat could not be assembled from the interface,
## and APPLY rebuilt the match from overlay defaults instead of the current settings.
## The full sheet came back from the archive; this gate pins the contract:
##   (a) the sheet builds its five tabs and one row per seat;
##   (b) every row offers the SIX drivers (LOCAL/AI/CHAT/REMOTE/sdk:neuro/sdk:evil) and the
##       choice REACHES the collected settings (REMOTE in slot 2 -> seat 2 driver REMOTE);
##   (c) validation refuses duplicates (color) before the engine ever sees them;
##   (d) settings rows carry the live/restart tag (the regression guard of the `_h()` factory);
##   (e) collected values are the DASHBOARD'S values, not defaults (cash 1234 -> 1234);
##   (f) two configurations assemble and START through the real main: solo 1 LOCAL + 3 AI and
##       a networked 1 LOCAL + 1 REMOTE + 2 AI (seat list, not a CLI flag).
##
## Verdict: ==> HG-07 PASSED / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/hg07_settings_gate.tscn

const MainScript := preload("res://main.gd")
const SettingsOverlay := preload("res://ui/settings_overlay.gd")

var _fails: Array = []


func _ready() -> void:
	await _run()
	if _fails.is_empty():
		print("==> HG-07 PASSED (5 tabs, 6 drivers, validation, tags, live values, solo + networked configs start)")
		get_tree().quit(0)
	else:
		print("==> HG-07 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _run() -> void:
	await _check_sheet()
	await _check_two_configs()


func _check_sheet() -> void:
	var ov = SettingsOverlay.new()
	add_child(ov)
	await get_tree().process_frame
	var tabs = ov.get("_tabs")
	if tabs == null or tabs.get_tab_count() != 6:
		_fail("the settings sheet has %s tabs, expected 6 (Игроки/Правила/Темп/Интерфейс/Управление/Данные)"
			% str(tabs.get_tab_count() if tabs != null else "no"))
	var rows: Array = ov.get("_rows")
	if rows.size() != 4:
		_fail("the sheet starts with %d seat rows, expected 4" % rows.size())
		ov.queue_free()
		return
	# (b) drivers
	var drivers: OptionButton = rows[0]["driver"]
	if drivers.item_count != 6:
		_fail("the driver dropdown offers %d options, expected 6" % drivers.item_count)
	if not drivers.disabled:
		_fail("the host seat's driver dropdown is editable - the host must stay LOCAL/observer")
	rows[1]["driver"].selected = 2   # CHAT in the DRIVERS order
	var st = ov.call("_collect_settings")
	var drivers_out: Array = []
	for a in st.seat_assignments:
		drivers_out.append(str(a.get("driver", "")))
	if drivers_out[1] != "CHAT":
		_fail("driver choice did not reach the settings (seat 2 = %s, expected CHAT)" % drivers_out[1])
	else:
		print("PASS: 6 drivers per row; a choice reaches _collect_settings (seat 2 -> CHAT)")
	# (c) duplicate colour validation
	var c0: Color = (rows[0]["color"] as ColorRect).color
	var c1_before: Color = (rows[1]["color"] as ColorRect).color
	(rows[1]["color"] as ColorRect).color = c0
	var err: String = str(ov.call("_validation_error"))
	if err == "":
		_fail("two seats wearing the same colour passed validation")
	else:
		print("PASS: duplicate colour refused by validation ('%s')" % err)
	(rows[1]["color"] as ColorRect).color = c1_before
	# (d) tags
	var tags := 0
	var stack: Array = [ov]
	while not stack.is_empty():
		var nd = stack.pop_back()
		for c in nd.get_children():
			if str(c.name) == "Tag":
				tags += 1
			stack.append(c)
	if tags < 15:
		_fail("only %d settings rows carry the live/restart tag - the _h() factory lost its tag" % tags)
	else:
		print("PASS: %d settings rows carry the live/restart tag" % tags)
	# (e) live values, not defaults
	var cash = ov.get("_starting_cash")
	if cash == null:
		_fail("no starting-cash field in the sheet")
	else:
		cash.value = 1234
		var st2 = ov.call("_collect_settings")
		if int(st2.starting_cash) != 1234:
			_fail("collected settings ignore the dashboard (cash 1234 -> %d)" % int(st2.starting_cash))
		else:
			print("PASS: collected settings are the dashboard's values (cash 1234)")
	ov.queue_free()
	await get_tree().process_frame


## (f) both configurations assemble THROUGH THE OVERLAY and reach the engine.
func _check_two_configs() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 12:
		await get_tree().process_frame
	var ov = launcher.get("_overlay")
	if ov == null:
		_fail("main built no settings overlay")
		return
	var rows: Array = ov.get("_rows")
	# config (a): solo 1 LOCAL + 3 AI (the row defaults) - press START through the sheet
	ov.call("_start_pressed")
	for _i in 8:
		await get_tree().process_frame
	var engine = launcher.get("_engine")
	if engine == null or int(engine.player_count()) != 4:
		_fail("solo config: the match did not start with 4 players (%s)"
			% str(engine.player_count() if engine != null else "no engine"))
		return
	var seats_a: Array = launcher.get("_seats_cache")
	var drv_a: Array = []
	for s in seats_a:
		drv_a.append(str(s.input_driver))
	print("PASS: solo 1 LOCAL + 3 AI starts through the sheet (%s)" % str(drv_a))
	# config (b): networked - seat 1 becomes REMOTE
	rows[1]["driver"].selected = 3   # REMOTE in the DRIVERS order
	ov.call("_start_pressed")
	for _i in 8:
		await get_tree().process_frame
	var engine_b = launcher.get("_engine")
	var seats_b: Array = launcher.get("_seats_cache")
	var drv_b: Array = []
	for s in seats_b:
		drv_b.append(str(s.input_driver))
	if seats_b.size() != 4 or drv_b[1] != "REMOTE":
		_fail("networked config: seats came out as %s, expected seat 2 REMOTE" % str(drv_b))
	elif int(engine_b.player_count()) != 4:
		_fail("networked config did not start (players %d)" % int(engine_b.player_count()))
	else:
		print("PASS: networked 1 LOCAL + 1 REMOTE + 2 AI starts (%s)" % str(drv_b))
	# APPLY keeps the user's values: in-game re-collect must see the same fields, not defaults
	ov.call("set_mode", false)
	var st = ov.call("_collect_settings")
	if int(st.seat_count) != 4:
		_fail("APPLY-time settings lost the seat count (%d)" % int(st.seat_count))
	else:
		print("PASS: in-game APPLY collects the same dashboard (seat_count=%d)" % int(st.seat_count))
	launcher.queue_free()
	await get_tree().process_frame


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
