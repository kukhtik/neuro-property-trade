extends Node
## P0 behavioral probe — verifies the v2 one-screen skeleton per spec §11 P0:
##   1. main builds GameView immediately (cold board, no engine yet).
##   2. SettingsOverlay (ex-lobby) opens on first run, pre-game mode.
##   3. START builds the engine; the rng_seed is applied (probe: seed applied).
##   4. ESC closes the overlay without starting -> cold board with a START button.
##   5. Restart (ПРИМЕНИТЬ) rebuilds the engine with a new seed.
##   6. is_host gate: on WebGL / --spectator the AdminPanel is NOT created
##      (probe: get_node_or_null("AdminPanel") == null).
## Run windowed: godot --path game res://tools/p0_probe.tscn
## Run spectator: godot --path game res://tools/p0_probe.tscn -- --spectator

const MainScript := preload("res://main.gd")
const Settings := preload("res://core/game_settings.gd")

var _launcher
var _had_fail := false

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	# --- 1) one screen: GameView exists immediately, cold ---
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no GameView at launch")
		return
	if not gv._cold:
		_fail("GameView should be cold before START")
		return
	print("PASS: GameView built immediately, cold state")

	# --- 2) settings overlay opens on first run, pre-game mode ---
	var overlay = _launcher.get("_overlay")
	if overlay == null:
		_fail("no SettingsOverlay at launch")
		return
	if not overlay.visible:
		_fail("SettingsOverlay should be visible on first run")
		return
	if not overlay._pre_game:
		_fail("overlay should be in pre-game mode before START")
		return
	print("PASS: SettingsOverlay visible on first run, pre-game mode")

	# --- 3) ESC closes overlay without starting -> cold board + START button ---
	_launcher.call("_on_overlay_closed")
	for _i in 5:
		await get_tree().process_frame
	if overlay.visible:
		_fail("overlay should be hidden after ESC")
		return
	var start_btn = _find_start_button(gv._actions)
	if start_btn == null:
		_fail("cold board should show a START button in the action panel")
		return
	print("PASS: ESC closes overlay -> cold board with START button")

	# --- 4) START builds the engine; seed applied ---
	overlay._rng_seed.value = 12345
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	var eng = gv.engine
	if eng == null:
		_fail("engine not built after START")
		return
	if gv._cold:
		_fail("GameView should not be cold after START")
		return
	# seed applied: the engine's settings must carry the seed
	if not _seed_applied(eng, 12345):
		_fail("rng_seed 12345 not applied to engine")
		return
	print("PASS: engine built after START; rng_seed applied")

	# --- 5) restart (ПРИМЕНИТЬ) rebuilds the engine with a new seed ---
	overlay._rng_seed.value = 999
	overlay.call("_apply_pressed")
	for _i in 15:
		await get_tree().process_frame
	var eng2 = gv.engine   # re-fetch: restart rebuilt the engine
	if eng2 == null or eng2 == eng:
		_fail("restart did not rebuild the engine (same instance)")
		return
	if not _seed_applied(eng2, 999):
		_fail("restart did not apply new seed 999")
		return
	print("PASS: restart rebuilt engine with new seed 999")

	# --- 6) is_host gate: AdminPanel present on host, absent on spectator ---
	var is_spectator := _has_flag("--spectator")
	var panel = _launcher.get("_panel")
	if is_spectator:
		if panel != null:
			_fail("AdminPanel should NOT be created on spectator")
			return
		print("PASS: AdminPanel absent on spectator (is_host=false)")
	else:
		if panel == null:
			_fail("AdminPanel should be created on host")
			return
		print("PASS: AdminPanel present on host (is_host=true)")

	# --- 7) game_over -> results banner wiring ---
	# Force the engine to END_GAME (bankrupt everyone but one player) and let
	# the seat_manager emit game_over; the GameView must show the banner.
	_force_game_over(gv)
	# the seat_manager ticks every 0.4s; wait ~1.5s of real time for it to emit
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not gv._game_over_shown:
		_fail("game_over did not trigger the results banner")
		return
	print("PASS: game_over -> results banner shown")

	if _had_fail:
		quit(1)
	else:
		print("P0 PROBE: ALL PASSED")
		quit(0)

func _force_game_over(gv) -> void:
	# Bankrupt all players except player 0 (bank as creditor), which removes
	# them and calls _check_winner -> END_GAME when only one remains. After each
	# removal the next player shifts to index 1, so bankrupt index 1 repeatedly.
	var eng = gv.engine
	while eng.player_count() > 1:
		eng._go_bankrupt(1, -1)

func _seed_applied(eng, seed: int) -> bool:
	# The engine stores the seed in settings and seeds its RNG from it in
	# setup(). The honest "seed applied" check: the live engine's settings carry
	# the seed. Determinism of the seeded RNG is proven separately by two fresh
	# engines with the same seed producing the same first roll.
	if eng.settings == null or int(eng.settings.rng_seed) != seed:
		return false
	var names: Array = []
	for s in gv_seats():
		names.append(str(s.name))
	var s1 = Settings.new(); s1.rng_seed = seed; s1.seat_count = names.size()
	var s2 = Settings.new(); s2.rng_seed = seed; s2.seat_count = names.size()
	var e1 = load("res://core/engine.gd").new(); e1.setup(s1, names)
	var e2 = load("res://core/engine.gd").new(); e2.setup(s2, names)
	var r1 = e1.rng.roll_two_dice()
	var r2 = e2.rng.roll_two_dice()
	return r1.get("sum", -1) == r2.get("sum", -1) and r1.get("d1", -1) == r2.get("d1", -1)

var _gv_seats_cache: Array = []
func gv_seats() -> Array:
	if _gv_seats_cache.is_empty():
		_gv_seats_cache = _launcher.get("_game_view").seats
	return _gv_seats_cache

func _find_start_button(actions) -> Button:
	for c in actions._btn_row.get_children():
		if c is Button and str(c.text).contains("НАЧАТЬ"):
			return c
	return null

func _has_flag(flag: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == flag:
			return true
	return false

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
