extends Node
## DEMO: three SDK seats in one process, filmed from the app's own viewport.
##
## What it is for: an owner-visible recording of the WHOLE application while three SDK players (each
## on its own connection - multi-SDK) actually play, with the moves spaced so a viewer can follow
## them, and with the admin panel doing something real in the middle (pause, then resume).
##
## Frames come from `get_viewport().get_texture().get_image()`, the same source SG-03/SG-07 use, so
## the video IS what the app draws. Run WINDOWED: a headless viewport has nothing to photograph.
##
## Timeline (env NPT_DEMO_* override the numbers):
##   t=8    board: click a tile -> the inspector opens (the whole right side shows its work)
##   t=16   top bar: кнопка «Панели» -> the side panels fold away and come back
##   t=24   admin panel opens (the host's F12 view)
##   t=30   admin: ПАУЗА  (a global event: the header chip, the frozen clock, no seat acts)
##   t=38   admin: Продолжить
##   t=42   admin panel closes, the match keeps playing
##   t=DUR  verdict line with frames, intents per seat and the pause/resume events
##
## Run: bash tools/ci/demo_multi_sdk.sh

const MainScript := preload("res://main.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")
const I18n := preload("res://i18n/i18n.gd")

const DURATION_DEFAULT := 52.0
var DURATION := DURATION_DEFAULT
const FPS := 10.0

var _launcher = null
var _frame := 0
var _start_ms := 0
var _outdir := ""
var _shot := 0
var _next_shot_ms := 0
var _marks: Dictionary = {}     # name -> done
var _fails: Array = []
var _timeline: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--demo-outdir="):
			_outdir = arg.substr(14)
		if arg.begins_with("--demo-secs="):
			pass
	if _outdir == "":
		_outdir = OS.get_environment("NPT_DEMO_DIR")
	if _outdir == "":
		_outdir = "user://demo"
	DirAccess.make_dir_recursive_absolute(_outdir)
	var secs := OS.get_environment("NPT_DEMO_SECS")
	if secs != "":
		DURATION = float(secs)
	DisplayServer.window_set_size(Vector2i(1600, 1200))
	get_tree().root.size = Vector2i(1600, 1200)
	_launcher = MainScript.new()
	add_child(_launcher)
	_start_ms = Time.get_ticks_msec()
	print("DEMO outdir=%s duration=%.0fs fps=%.0f" % [_outdir, DURATION, FPS])


func _process(_dt: float) -> void:
	_frame += 1
	if _frame < 6:
		return
	if _frame == 6:
		_build_match()
		_start_ms = Time.get_ticks_msec()
		_next_shot_ms = _start_ms
	var t := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	_timeline_step(t)
	if Time.get_ticks_msec() >= _next_shot_ms:
		_next_shot_ms += int(1000.0 / FPS)
		_capture()
	if t >= DURATION:
		_report()


func _build_match() -> void:
	var a := OS.get_environment("NPT_SDK_A")
	var b := OS.get_environment("NPT_SDK_B")
	var c := OS.get_environment("NPT_SDK_C")
	if a == "" or b == "" or c == "":
		_fails.append("NPT_SDK_A/B/C are not set - three SDK seats need three endpoints")
		_report()
		return
	var st = SettingsScript.new()
	st.seat_count = 4
	st.rng_seed = 20261019
	st.round_limit = 0            # the demo ends on the clock, not on the round limit
	st.turn_timer = 0             # the vendored window delays its force by the window value
	st.seat_assignments = [
		{"driver": "sdk:neuro", "name": "SDK 1", "sdk_endpoint": a},
		{"driver": "sdk:evil", "name": "SDK 2", "sdk_endpoint": b},
		{"driver": "sdk:neuro", "name": "SDK 3", "sdk_endpoint": c},
		{"driver": "AI", "name": "Bot"},
	]
	var seats: Array = SeatConfigScript.from_settings(st)
	var sdk := 0
	for s in seats:
		if str(s.input_driver) == "SDK":
			sdk += 1
	print("DEMO seats=%s (SDK=%d)" % [
		", ".join(seats.map(func(x): return "%s:%s:%s" % [x.name, x.input_driver,
			x.get("sdk_endpoint")])), sdk])
	if sdk != 3:
		_fails.append("expected 3 SDK seats, got %d" % sdk)
	_launcher.call("_build_game", st, seats)
	_launcher.get("_overlay").visible = false
	_launcher.set("_game_started", true)
	_launcher.get("_game_view").call("on_game_started")


## The demo script. Each step runs once, at its second.
func _timeline_step(t: float) -> void:
	_step(t, 8.0, "inspector", func() -> void:
		var board = _gv().find_child("stage", true, false)
		if board != null:
			board.emit_signal("tile_clicked", 6)
			_note("board: tile 6 clicked (inspector)"))
	_step(t, 16.0, "panels", func() -> void:
		_gv().call("set_panels_hidden", true)
		_note("top bar: panels hidden"))
	_step(t, 20.0, "panels-back", func() -> void:
		_gv().call("set_panels_hidden", false)
		_note("top bar: panels back"))
	_step(t, 24.0, "admin-open", func() -> void:
		var p = _launcher.get("_panel")
		if p == null:
			_fails.append("no admin panel (the demo must run as host)")
			return
		(p as Control).visible = true
		_note("admin: panel open"))
	_step(t, 30.0, "pause", func() -> void:
		var p = _launcher.get("_panel")
		if p != null and p.has_method("_quick_pause"):
			p.call("_quick_pause")
			_note("admin: PAUSE (global event)"))
	_step(t, 38.0, "resume", func() -> void:
		var p = _launcher.get("_panel")
		if p != null and p.has_method("_quick_resume"):
			p.call("_quick_resume")
			_note("admin: resume"))
	_step(t, 42.0, "admin-close", func() -> void:
		var p = _launcher.get("_panel")
		if p != null:
			(p as Control).visible = false
		_note("admin: panel closed"))


func _step(t: float, at: float, name: String, fn: Callable) -> void:
	if t < at or _marks.has(name):
		return
	_marks[name] = true
	fn.call()


func _note(msg: String) -> void:
	_timeline.append("%.0fs %s" % [float(Time.get_ticks_msec() - _start_ms) / 1000.0, msg])
	print("DEMO %s" % msg)


func _gv() -> Node:
	return _launcher.get("_game_view")


func _capture() -> void:
	# JPEG, not PNG: a 1600x1200 PNG costs ~40-60 ms per frame, which capped the recorder at ~3 fps
	# and made the video choppy. JPEG keeps ~8-10 fps on the same viewport readback.
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := "%s/f%05d.jpg" % [_outdir, _shot]
	var err := img.save_jpg(path, 0.86)
	if err == OK:
		_shot += 1


func _report() -> void:
	var eng = _launcher.get("_engine")
	var mgr = _launcher.get("_manager")
	if eng != null and mgr != null:
		var entries: Array = eng.log.entries()
		var ads = mgr.get("_sdk_adapters")
		var live := 0
		if ads is Dictionary:
			for pid in (ads as Dictionary).keys():
				var c = (ads as Dictionary)[pid].get("conn")
				if c != null and bool(c.websocket_is_connected):
					live += 1
			print("DEMO connections live=%d of %d" % [live, (ads as Dictionary).size()])
			if live < 3:
				_fails.append("only %d of 3 SDK connections were live" % live)
		var pause_events := 0
		for e in entries:
			var tp := str(e.get("type", ""))
			if tp == "pause" or tp == "resume":
				pause_events += 1
		print("DEMO events=%d pause/resume=%d frames=%d" % [entries.size(), pause_events, _shot])
		if pause_events < 2:
			_fails.append("the demo never logged pause AND resume (%d)" % pause_events)
		for s in mgr.get("seats"):
			var n := 0
			for e in entries:
				var d: Dictionary = e.get("data", {})
				if int(d.get("player", -1)) == int(s.pid) or int(d.get("from", -1)) == int(s.pid):
					n += 1
			print("DEMO seat %s driver=%s intents=%d" % [str(s.name), str(s.input_driver), n])
		print("DEMO turn=%d phase=%s" % [int(eng.turn_player), str(eng.phase)])
		for i in mini(8, entries.size()):
			var e: Dictionary = entries[i]
			print("DEMO log[%d] %s %s" % [i, str(e.get("type", "")),
				str(e.get("data", {})).left(64)])
		if ads is Dictionary:
			for pid in (ads as Dictionary).keys():
				var a = (ads as Dictionary)[pid]
				var ac = a.get("conn")
				print("DEMO adapter pid=%s awaiting=%s key=%s endpoint=%s conn=%s" % [str(pid),
					str(a.get("_awaiting_result")), str(a.get("_last_decision_key")),
					str(a.get("endpoint")), str(ac.name if ac != null else "null")])
	print("DEMO timeline: %s" % " | ".join(_timeline))
	if float(_shot) < DURATION * 2.0:
		_fails.append("only %d frame(s) in %.0fs - under 2 fps, the window was not rendering" % [
			_shot, DURATION])
	if _fails.is_empty():
		print("==> DEMO PASSED (%d frames, %d SDK connections)" % [_shot, 3])
		get_tree().quit(0)
		return
	print("==> DEMO FAILED: %s" % " | ".join(_fails))
	get_tree().quit(1)
