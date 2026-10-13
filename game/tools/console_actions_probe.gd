extends Node
## Behavioral probe: do the CONSOLE buttons actually work?
## Boots a real 1-human-vs-AI match (autostart), waits for the human's TURN_START,
## then presses real buttons from the console row and records what the engine replies.
## Audit seed for gates HG-02/HG-03/HG-04 (docs/restoration/gates.md) — diagnostic today, gate next.
const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")
var _launcher = null
var _n := 0
var _phase_done := {}

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)

func _process(_dt: float) -> void:
	_n += 1
	if _n == 10:
		_launcher.call("_autostart")
	if _n >= 60 and _n % 30 == 0:
		_step()

func _find_button(console, key: String) -> Button:
	var row = console.get("_btn_row")
	if row == null:
		return null
	var want := I18n.t(key)
	for c in row.get_children():
		if c is Button and str((c as Button).text).begins_with(want):
			return c
	return null

func _modal_text(gv) -> String:
	var m = gv.find_child("modal", true, false)
	if m == null or not (m as Control).visible:
		return ""
	var body = m.get("_body")
	if body == null:
		return ""
	var out: Array = []
	for c in body.get_children():
		if c is Label:
			out.append(str((c as Label).text))
	return " ".join(out)

func _step() -> void:
	var gv = _launcher.get("_game_view")
	var engine = _launcher.get("_engine")
	if gv == null or engine == null:
		return
	var console = gv.find_child("act", true, false)
	var modal_before := _modal_text(gv)
	# --- build button: does an unaddressed console button work? ---
	if not _phase_done.has("build") and engine.phase == "TURN_START" and engine.turn_player == 0:
		var b := _find_button(console, "act.build")
		if b != null:
			print("PRESS build_house (console button, params={})")
			b.emit_signal("pressed")
			_phase_done["build"] = true
			await get_tree().process_frame
			print("  modal after build press:", _modal_text(gv))
	if not _phase_done.has("trade") and engine.phase == "TURN_START" and engine.turn_player == 0:
		var b2 := _find_button(console, "act.trade")
		if b2 != null:
			print("PRESS propose_trade (console button, params={})")
			b2.emit_signal("pressed")
			_phase_done["trade"] = true
			await get_tree().process_frame
			print("  modal:", _modal_text(gv))
	# --- positive control: roll works ---
	if not _phase_done.has("roll") and engine.phase == "TURN_START" and engine.turn_player == 0:
		var br := _find_button(console, "act.roll")
		if br != null:
			var before: int = engine.log.size()
			var phase_before: String = engine.phase
			br.emit_signal("pressed")
			_phase_done["roll"] = true
			await get_tree().process_frame
			print("ROLL pressed: phase %s -> %s, log %d -> %d" % [phase_before, engine.phase, before, engine.log.size()])
	if _phase_done.has("build") and _phase_done.has("trade") and _phase_done.has("roll"):
		var modal = _modal_text(gv)
		print("== final modal text: %s" % modal)
		get_tree().quit(0)
