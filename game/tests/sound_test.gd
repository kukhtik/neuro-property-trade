extends RefCounted
## Tests for the audio surface: `game_settings.sound`, `audio/sound_manager.gd` and the assets.
##
## WHY THIS MODULE EXISTS: until 21.10.2026 the repository had no sound files, no
## AudioStreamPlayer and no `sound` field — the settings sheet's "Звук" checkbox wrote NOTHING.
## These tests pin the three things that lie was made of: the FIELD round-trips, every SOUND NAME
## has a file behind it, and the SWITCH really gates playback (off means the log stays empty).

const Settings := preload("res://core/game_settings.gd")
const SoundManager := preload("res://audio/sound_manager.gd")
const SkinManager := preload("res://visual/skin_manager.gd")


static func test_list() -> Array[String]:
	return [
		"test_sound_field_default",
		"test_sound_field_round_trip",
		"test_every_name_has_an_asset",
		"test_off_plays_nothing",
		"test_on_counts_plays",
		"test_animations_master_switch_mutes",
		"test_event_binding",
		"test_pitch_variation_is_seeded",
	]


## The field the settings sheet writes. Absent, the "Звук" row is decoration.
static func test_sound_field_default() -> String:
	var s = Settings.new()
	if s.get("sound") == null:
		return "game_settings has no `sound` field - the settings toggle has nothing to write"
	if bool(s.sound) != true:
		return "sound must default to ON (the sheet ships the checkbox pressed), got %s" % str(s.sound)
	return ""


## field -> value -> value, and the same value through to_data/from_data (the settings sheet's
## own path: _collect_settings builds an object, the shell reads fields off it).
static func test_sound_field_round_trip() -> String:
	var s = Settings.new()
	s.sound = false
	if bool(s.sound) != false:
		return "writing sound=false read back %s" % str(s.sound)
	s.sound = true
	if bool(s.sound) != true:
		return "writing sound=true read back %s" % str(s.sound)
	var d: Dictionary = s.to_data()
	if not d.has("sound"):
		return "to_data() drops `sound` - a saved/preset sheet would forget the answer"
	s.sound = false
	s.from_data(d)
	if bool(s.sound) != true:
		return "from_data() did not restore sound=true from %s" % str(d.get("sound"))
	return ""


## A name with no file is a sound that silently does nothing: the same class of lie as the toggle.
static func test_every_name_has_an_asset() -> String:
	var names: Array = SoundManager.sound_names()
	if names.size() < 10:
		return "only %d sounds registered - the track asks for 10-15" % names.size()
	for n in names:
		var path: String = SoundManager.AUDIO_DIR + str(n) + ".wav"
		if not FileAccess.file_exists(path):
			return "sound '%s' has no asset at %s" % [str(n), path]
	return ""


## THE NEGATIVE: with the switch off nothing may be counted, and the call must say so.
static func test_off_plays_nothing() -> String:
	SoundManager.reset_log()
	SoundManager.set_enabled(false)
	var played: bool = SoundManager.play("buy")
	var total: int = int(SoundManager.total())
	var refused: int = int(SoundManager.suppressed())
	SoundManager.set_enabled(true)
	if not SoundManager.is_enabled():
		return "set_enabled(true) did not restore the manager"
	if played:
		return "play() reported success while sound was OFF"
	if total != 0:
		return "sound OFF still counted %d play(s)" % total
	if refused < 1:
		return "sound OFF did not record the refusal (suppressed=%d)" % refused
	return ""


## ... and THE POSITIVE, in the same log: on means it plays and it is counted.
static func test_on_counts_plays() -> String:
	SoundManager.reset_log()
	SoundManager.set_enabled(true)
	if not SoundManager.play("buy"):
		return "play('buy') failed with sound ON (missing asset?)"
	if int(SoundManager.count("buy")) != 1:
		return "count('buy') = %d after one play, expected 1" % int(SoundManager.count("buy"))
	if int(SoundManager.total()) != 1:
		return "total() = %d after one play, expected 1" % int(SoundManager.total())
	if not SoundManager.missing().is_empty():
		return "missing assets reported: %s" % str(SoundManager.missing())
	return ""


## Sound is cosmetics: the master "Анимации" switch must silence it too (the track's rule).
static func test_animations_master_switch_mutes() -> String:
	SoundManager.reset_log()
	SoundManager.set_enabled(true)
	var was: bool = bool(SkinManager.animations_enabled)
	SkinManager.set_animations(false)
	var enabled_after: bool = SoundManager.is_enabled()
	var played: bool = SoundManager.play("toast")
	var total: int = int(SoundManager.total())
	SkinManager.set_animations(was)
	if enabled_after:
		return "animations OFF left sound enabled - the cosmetics master switch does not reach audio"
	if played or total != 0:
		return "animations OFF still played %d sound(s)" % total
	if not SoundManager.is_enabled():
		return "restoring animations did not restore sound"
	return ""


## The ENGINE EVENT -> sound map: the binding SOUND-EVENTS relies on. `roll` is silent here on
## purpose (the dice belongs to the tray in board_scene.play_event, or a roll would play twice).
static func test_event_binding() -> String:
	var cases := {
		"purchase": "buy", "auction_win": "buy",
		"auction_bid": "bid",
		"jail": "jail",
		"card_draw": "card",
		"mortgage": "mortgage",
		"winner": "game_over",
		"bankrupt": "error",
	}
	for ev in cases:
		if SoundManager.event_sound(str(ev)) != str(cases[ev]):
			return "event '%s' maps to '%s', expected '%s'" % [str(ev), SoundManager.event_sound(str(ev)), str(cases[ev])]
	for silent in ["roll", "move", "cash", "tax", "land"]:
		if SoundManager.event_sound(str(silent)) != "":
			return "event '%s' should be silent, maps to '%s'" % [str(silent), SoundManager.event_sound(str(silent))]
	# a mapped name that is not a shipped sound would play nothing at all
	for ev in SoundManager.EVENT_SOUND:
		var n: String = str(SoundManager.EVENT_SOUND[ev])
		if not SoundManager.sound_names().has(n):
			return "event '%s' points at unregistered sound '%s'" % [str(ev), n]
	# the call, not just the map: play_event must reach the log
	SoundManager.reset_log()
	SoundManager.set_enabled(true)
	if not SoundManager.play_event("purchase"):
		return "play_event('purchase') played nothing"
	if int(SoundManager.count("buy")) != 1:
		return "play_event('purchase') counted %d buys, expected 1" % int(SoundManager.count("buy"))
	if SoundManager.play_event("cash"):
		return "play_event('cash') is not silent"
	return ""


## Determinism: pitch jitter comes from a seeded Rng, so the same call sequence gives the same
## detune - the same rule the engine's dice follow.
static func test_pitch_variation_is_seeded() -> String:
	# The seed must be the CONSTANT, not the clock. A timing-based check cannot prove it:
	# two sequences drawn in the same millisecond agree even with a wall-clock seed - that
	# is how the first two versions of this test passed a non-deterministic product.
	# So the check asks the generator DIRECTLY: it must report the seed it will use.
	SoundManager._reset_pitch_rng()
	var seed: int = SoundManager._pitch_seed()
	if seed != SoundManager.PITCH_SEED:
		return "the pitch seed is %d, not the fixed %d - the same match would not sound the same twice" % [seed, SoundManager.PITCH_SEED]
	# and the sequence must be reproducible through the production path
	var first: Array = []
	SoundManager._reset_pitch_rng()
	for i in 4:
		first.append(SoundManager._pitch(0.05))
	var second: Array = []
	SoundManager._reset_pitch_rng()
	for i in 4:
		second.append(SoundManager._pitch(0.05))
	for i in first.size():
		if absf(float(first[i]) - float(second[i])) > 0.000001:
			return "the pitch sequence is not reproducible: draw %d was %.5f and then %.5f" % [i, float(first[i]), float(second[i])]
	if first[0] == first[1]:
		return "the pitch never varies - a constant is not a variation"
	for v in first:
		if float(v) < 0.95 or float(v) > 1.05:
			return "pitch %.3f is outside +-5%% of 1.0" % float(v)
	if float(SoundManager._pitch(0.0)) != 1.0:
		return "zero variation must be exactly 1.0"
	return ""

