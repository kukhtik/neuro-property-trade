extends Node
## SOUND gate — the "Звук" row is a SETTING, not decoration (track 2, docs/tracks/2026-10-20-three-tracks.md §2).
##
## THE DEFECT THIS PINS (measured 20.10.2026):
##   *.ogg/*.wav/*.mp3 in the repo   -> 0
##   AudioStreamPlayer              -> 0
##   game_settings.sound            -> the field did not exist
##   settings_overlay`s toggle      -> built, shown, and wrote NOTHING
## So the interface promised a control the product did not have. This gate builds the REAL sheet
## (res://ui/settings_overlay.gd), reads its REAL checkbox, and demands that:
##   (a) the row exists and is tagged LIVE (it shipped as `settings.tag_inert`);
##   (b) toggling it changes the collected setting (false -> false, true -> true), which is what
##       "the toggle is saved" means;
##   (c) the toggle reaches the manager: OFF means SoundManager.play() refuses and the counter
##       stays 0; ON means it plays and is counted;
##   (d) the master cosmetics switch (`SkinManager.animations_enabled`) silences the sound too —
##       the track's own rule: sound is cosmetics;
##   (e) every registered sound name has a REAL WAV that loads as an AudioStream (12 names, the
##       assets are synthesised by tools/gen_sounds.py);
##   (f) `unused_symbols.py` no longer lists `sound` as UNAPPLIED — checked by the shell wrapper,
##       because that script is python and this scene is Godot.
##
## Verdict: ==> SOUND PASSED (...) / ==> SOUND FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sound_gate.tscn

const SettingsOverlay := preload("res://ui/settings_overlay.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SoundManager := preload("res://audio/sound_manager.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

var _fails: Array = []


func _ready() -> void:
	await _run()
	if _fails.is_empty():
		print("==> SOUND PASSED (row builds and is live, toggle reaches game_settings.sound, OFF plays 0 / ON plays >0, animations mutes, %d assets load)" % SoundManager.sound_names().size())
		get_tree().quit(0)
	else:
		print("==> SOUND FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _run() -> void:
	SoundManager.reset_log()
	SoundManager.set_enabled(true)
	await _check_sheet()
	_check_assets()
	# MUST be awaited: the tick measurement waits for real time, and an un-awaited coroutine
	# returns at its first `await` - the gate would print its verdict having skipped the check
	# (that is how a check that measures nothing stays green).
	await _check_projection_sounds()


## (a) + (b) + (c): the sheet's own checkbox, toggled through the widget the player presses.
func _check_sheet() -> void:
	var ov = SettingsOverlay.new()
	add_child(ov)
	await get_tree().process_frame
	var box = ov.get("_sound")
	if box == null or not (box is CheckButton):
		_fail("the settings sheet has no 'Звук' checkbox (_sound missing or not a CheckButton)")
		ov.queue_free()
		return
	# (a) the tag: the row must CLAIM to be live, because it now is (it shipped as tag_inert)
	var row: Node = box.get_parent()
	var tag_key := ""
	if row != null:
		for c in row.get_children():
			if str(c.name) == "Tag":
				tag_key = str(c.get_meta("i18n_key", ""))
	if tag_key != "settings.tag_live":
		_fail("the 'Звук' row is tagged '%s', expected 'settings.tag_live' (sound applies immediately)" % tag_key)
	else:
		print("PASS: the 'Звук' row exists and is tagged live")
	# (b) OFF through the widget -> the collected setting
	box.button_pressed = false
	var off = ov.call("_collect_settings")
	if bool(off.sound) != false:
		_fail("toggling 'Звук' OFF collected sound=%s — the checkbox writes nothing (the 20.10 defect)"
			% str(off.sound))
	else:
		print("PASS: toggle OFF -> game_settings.sound=false")
	# (c) ... and it really silences the manager, which the toggled handler must have told
	if SoundManager.is_enabled():
		_fail("'Звук' OFF left SoundManager enabled — the switch does not reach the audio")
	var played_off: bool = SoundManager.play("buy")
	if played_off:
		_fail("SoundManager.play() reported success with 'Звук' OFF")
	elif int(SoundManager.total()) != 0:
		_fail("with 'Звук' OFF the counter still recorded %d play(s)" % int(SoundManager.total()))
	else:
		print("PASS: 'Звук' OFF -> play() refused, 0 counted (suppressed=%d)" % int(SoundManager.suppressed()))
	# ON again -> the field, the manager and the counter
	SoundManager.reset_log()
	box.button_pressed = true
	var on = ov.call("_collect_settings")
	if bool(on.sound) != true:
		_fail("toggling 'Звук' ON collected sound=%s" % str(on.sound))
	elif not SoundManager.is_enabled():
		_fail("'Звук' ON left SoundManager disabled")
	else:
		SoundManager.reset_log()   # the ON confirmation beep is not part of this measurement
		if not SoundManager.play("buy"):
			_fail("SoundManager.play('buy') failed with 'Звук' ON — the WAV did not load")
		elif int(SoundManager.count("buy")) != 1:
			_fail("'Звук' ON played 'buy' %d time(s), expected 1" % int(SoundManager.count("buy")))
		else:
			print("PASS: 'Звук' ON -> game_settings.sound=true, 1 play counted")
	# the collected setting survives the sheet's own to_data/from_data path
	var data: Dictionary = on.to_data()
	if not data.has("sound"):
		_fail("collected settings have no `sound` key in to_data() — a restart would forget it")
	ov.queue_free()
	await get_tree().process_frame


## (e) a name with no file is a sound that silently does nothing.
func _check_assets() -> void:
	var names: Array = SoundManager.sound_names()
	if names.size() < 10 or names.size() > 15:
		_fail("%d sounds registered, the track asks for 10-15" % names.size())
		return
	var loaded := 0
	for n in names:
		var path: String = SoundManager.AUDIO_DIR + str(n) + ".wav"
		if not FileAccess.file_exists(path):
			_fail("sound '%s' has no asset (%s)" % [str(n), path])
			continue
		var st: Resource = load(path)
		if st == null or not (st is AudioStream):
			_fail("%s did not load as an AudioStream" % path)
			continue
		loaded += 1
	if loaded == names.size():
		print("PASS: %d/%d sound assets load as AudioStream" % [loaded, names.size()])
	# and the manager agrees: playing every name leaves nothing in `missing()`
	SoundManager.reset_log()
	SoundManager.set_enabled(true)
	var played := 0
	for n in names:
		if SoundManager.play(str(n)):
			played += 1
	if played != names.size():
		_fail("only %d/%d registered sounds actually play (missing: %s)"
			% [played, names.size(), str(SoundManager.missing())])
	else:
		print("PASS: all %d sounds play through SoundManager (log=%d)" % [played, int(SoundManager.total())])


## The master cosmetics switch and the projection-driven sounds (turn + clock tick).
func _check_projection_sounds() -> void:
	# (d) animations OFF is the product's master cosmetics switch: it must silence audio too.
	SoundManager.reset_log()
	SoundManager.set_enabled(true)
	var was_anim: bool = bool(SkinManager.animations_enabled)
	SkinManager.set_animations(false)
	var muted: bool = not SoundManager.is_enabled()
	var played: bool = SoundManager.play("toast")
	var total: int = int(SoundManager.total())
	SkinManager.set_animations(was_anim)
	if not muted or played or total != 0:
		_fail("animations OFF did not mute sound (enabled=%s played=%s counted=%d)"
			% [str(not muted), str(played), total])
	else:
		print("PASS: animations OFF mutes sound (cosmetics master switch)")
	# the turn sound: a new turn player on TURN_START
	SoundManager.reset_log()
	SoundManager.on_projection({"phase": "TURN_START", "turn_player": 0,
		"timer_window": 0.0, "timer_elapsed": 0.0, "timer_active": false})
	var turns: int = int(SoundManager.count("turn"))
	# the clock: last seconds -> ticks; the manager counts them down on its own clock
	SoundManager.reset_log()
	SoundManager.on_projection({"phase": "TURN_START", "turn_player": 0,
		"timer_window": 3.0, "timer_elapsed": 0.0, "timer_active": true})
	await get_tree().create_timer(1.5).timeout
	var ticks: int = int(SoundManager.count("tick"))
	SoundManager.on_projection({"phase": "TURN_START", "turn_player": 0,
		"timer_window": 0.0, "timer_elapsed": 0.0, "timer_active": false})
	if turns < 1:
		_fail("a TURN_START projection played no turn sound")
	elif ticks < 1:
		_fail("a clock with 3s left produced no tick in 1.5s")
	else:
		print("PASS: projection sounds (turn=%d, tick=%d)" % [turns, ticks])


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
