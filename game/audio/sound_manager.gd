class_name SoundManager
extends Node
## THE PRODUCT'S AUDIO SURFACE — one node, one log, one switch.
##
## WHY IT EXISTS: measured on 20.10.2026 the repository had ZERO sound files, ZERO
## AudioStreamPlayer nodes and no `game_settings.sound` field at all, while the settings sheet
## shipped a "Звук" checkbox that wrote nothing. The row was the same kind of lie the program
## calls critical: the interface promised a thing the product did not have.
##
## WHAT IT IS: a static facade over one lazily created node in the tree root. Call sites read
## `SoundManager.play("buy")` and never hold a reference — the board, the shell and the tests all
## go through the same call. The node owns the `SFX` bus and a small pool of voices, so two
## events in the same frame do not cut each other off.
##
## THE COUNTER IS PART OF THE DESIGN, not a debugging leftover. `SOUND-EVENTS` proves the sounds
## are BOUND TO EVENTS rather than merely playable: a match runs, `counts()` is compared with the
## engine event stream the UI received, and an unbound sound shows up as a missing count. The
## counter only increments when a sound is really played (enabled, asset present), so "sound is
## off" is measured as zero rather than assumed.
##
## THE MASTER COSMETICS SWITCH: `SkinManager.animations_enabled` is the product's "анимации" row.
## Sound is cosmetics too, so turning animations off silences the game — one switch for the whole
## cosmetic layer, which is what the settings row always claimed to be.
##
## ASSETS: `game/assets/audio/*.wav`, synthesised by `tools/gen_sounds.py` (stdlib `wave`; the
## owner's decision B2). Files are loaded BY NAME, so dropping a real recording over any file
## changes the sound with no code change.

const RngScript := preload("res://core/rng.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

const SFX_BUS := "SFX"
const AUDIO_DIR := "res://assets/audio/"
## How many sounds may overlap. More than four never happens in this game (a roll, a toast and a
## purchase land in the same frame at most), and each voice is an AudioStreamPlayer node.
const VOICES := 6
## The pitch generator's seed. Fixed, so the same match sounds the same every time.
const PITCH_SEED := 0x5EED
## The clock starts ticking when this many seconds remain — a warning, not a metronome.
const TICK_WINDOW := 5.0

## Every sound the product ships. Kept as a list so a gate can demand "no file without a name".
const SOUNDS := [
	"dice", "toast", "tick", "buy", "bid", "mortgage", "jail", "card",
	"turn", "game_over", "error", "skin",
]

## ENGINE EVENT TYPE (and UI kind) -> sound name.
##
## `roll` is DELIBERATELY absent: the dice sound belongs to the tray tumble in
## `board_scene.play_event`, and mapping it here as well would play it twice per roll (the toast
## feed sees every event). `move` is silent — a token hop is a picture, not a sound.
const EVENT_SOUND := {
	"purchase": "buy", "buy": "buy",
	"auction_win": "buy", "aucwin": "buy",
	"auction_bid": "bid", "bid": "bid",
	"jail": "jail", "send_to_jail": "jail",
	"card_draw": "card", "card_gain": "card", "card_land": "card",
	"card_null": "card", "card": "card",
	"mortgage": "mortgage", "mort": "mortgage",
	"setup": "turn", "start": "turn",
	"winner": "game_over", "over": "game_over",
	"bankrupt": "error", "refused": "error", "rejected": "error",
}

## Events with no sound of their own still deserve a notification sound: the neutral "toast" is
## the sound of a line appearing in the feed. Kept separate from EVENT_SOUND so "which sound is
## this event" stays one lookup and the fallback is one list.
const NOTIFY := [
	"rent", "tax", "pay", "go_bonus", "go", "build", "sell",
	"trade", "trade_proposed", "trade_declined", "free_parking", "pause", "resume",
]

# --- shared state (static on purpose: every call site and the node read ONE log) ---------------- #
static var _inst: Node = null
static var _setting_enabled := true          # `game_settings.sound`
static var _counts: Dictionary = {}          # sound name -> times actually played
static var _suppressed := 0                  # calls refused because the switch was off
static var _missing: Dictionary = {}         # sound names whose asset failed to load
static var _streams: Dictionary = {}         # sound name -> AudioStream (loaded once)
## The seed the pitch generator was actually given. Read by the test, so the check
## and the behaviour cannot disagree.
static var _pitch_seed_used: int = 0
## The pitch generator. STATIC, because `play()` is static and uses it: as an instance
## member the file did not parse, and a file that does not parse takes the whole test
## module with it - the oracle said "444 tests, 0 failed" while the sound tests never ran.
static var _rng: RefCounted = null      # seeded: pitch jitter must be reproducible
static var _last_turn_holder := -2
static var _timer_left := -1.0               # seconds left on the clock, -1 = no clock

# --- node state --------------------------------------------------------------------------------- #
var _voices: Array = []
var _next := 0
var _tick_acc := 0.0


# ================================================================================================= #
# Public API — the only names call sites use.
# ================================================================================================= #

## Play one sound. `pitch_variation` is the maximum relative detune (0.05 = ±5 %), drawn from the
## seeded Rng so two runs of the same match sound — and COUNT — the same.
## Returns true only when the sound was really started (enabled + asset present).
static func play(sound_name: String, pitch_variation: float = 0.0) -> bool:
	if not is_enabled():
		_suppressed += 1
		return false
	var stream := _stream_for(sound_name)
	if stream == null:
		return false
	_counts[sound_name] = int(_counts.get(sound_name, 0)) + 1
	var node := instance()
	if node != null:
		node.call("_emit", stream, _pitch(pitch_variation))
	return true


## Play the sound an engine event maps to. Returns false for events that are silent by design.
static func play_event(engine_type: String) -> bool:
	var name := event_sound(engine_type)
	if name == "" and NOTIFY.has(engine_type):
		name = "toast"
	if name == "":
		return false
	return play(name)


## The sound bound to an engine event type / UI kind, or "" when the event is silent.
static func event_sound(engine_type: String) -> String:
	return str(EVENT_SOUND.get(engine_type, ""))


## The `game_settings.sound` answer. Off stops the voices that are still ringing.
static func set_enabled(on: bool) -> void:
	_setting_enabled = on
	if on:
		return
	var node := instance()
	if node != null:
		node.call("stop_all")


## Sound is cosmetics: it needs BOTH the player's switch and the master cosmetics switch.
static func is_enabled() -> bool:
	return _setting_enabled and bool(SkinManager.animations_enabled)


static func setting_enabled() -> bool:
	return _setting_enabled


## One projection is all the turn/clock sounds need. Called from the shell's `apply_projection`
## with the same dictionary the panels paint, so the sounds cannot describe a different turn than
## the screen does. All of its state lives here, not in the shell.
static func on_projection(proj: Dictionary) -> void:
	# TURN START: the turn player changed on a fresh turn. Auctions and purchase waits keep the
	# same holder, so this fires once per turn and not once per click.
	if str(proj.get("phase", "")) == "TURN_START":
		var holder := int(proj.get("turn_player", -1))
		if holder != _last_turn_holder:
			_last_turn_holder = holder
			play("turn")
	# THE CLOCK: the node counts the last seconds down itself (a per-frame timer), this only
	# hands it the remaining time of the window the screen is showing.
	var window := float(proj.get("timer_window", 0.0))
	var elapsed := float(proj.get("timer_elapsed", 0.0))
	if bool(proj.get("timer_active", false)) and window > 0.0:
		_timer_left = maxf(0.0, window - elapsed)
	else:
		_timer_left = -1.0


# --- the log (SOUND-EVENTS reads this) --------------------------------------------------------- #
static func counts() -> Dictionary:
	return _counts.duplicate()


static func count(sound_name: String) -> int:
	return int(_counts.get(sound_name, 0))


static func total() -> int:
	var n := 0
	for k in _counts:
		n += int(_counts[k])
	return n


## Calls refused because sound was off. Present so a gate can tell "silent by switch" from
## "nothing ever asked".
static func suppressed() -> int:
	return _suppressed


## Sounds whose WAV did not load. Non-empty = the build is missing its assets.
static func missing() -> Array:
	return _missing.keys()


static func reset_log() -> void:
	_counts.clear()
	_suppressed = 0
	_missing.clear()
	_last_turn_holder = -2
	_timer_left = -1.0


static func sound_names() -> Array:
	return SOUNDS.duplicate()


## The shared node, created on first use under the tree root. Null when there is no tree at all
## (a pure-data test): the log still works, there is simply nothing to hear.
static func instance() -> Node:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Node = (loop as SceneTree).root
	if root == null:
		return null
	var node: Node = load("res://audio/sound_manager.gd").new()
	node.name = "SoundManager"
	root.add_child(node)
	_inst = node
	return _inst


# ================================================================================================= #
# Node side
# ================================================================================================= #

func _ready() -> void:
	_ensure_sfx_bus()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "voice_%d" % i
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)
	set_process(true)


## Master + SFX. `Master` always exists; `SFX` is created once per process, so the SFX level can be
## mixed without touching anything else (music would be a second bus).
func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index(SFX_BUS) >= 0:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, SFX_BUS)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, -3.0)


func _emit(stream: AudioStream, pitch: float) -> void:
	if _voices.is_empty():
		return
	var p: AudioStreamPlayer = _voices[_next % _voices.size()]
	_next += 1
	p.stream = stream
	p.pitch_scale = pitch
	p.play()


func stop_all() -> void:
	for v in _voices:
		if v != null and (v as AudioStreamPlayer).playing:
			(v as AudioStreamPlayer).stop()
	_tick_acc = 0.0


## The countdown: one tick per whole second while the clock is inside its last TICK_WINDOW.
func _process(delta: float) -> void:
	if _timer_left < 0.0:
		return
	_timer_left = maxf(0.0, _timer_left - delta)
	if _timer_left > TICK_WINDOW or _timer_left <= 0.0:
		_tick_acc = 0.0
		return
	_tick_acc += delta
	if _tick_acc >= 1.0:
		_tick_acc -= 1.0
		SoundManager.play("tick")


# ================================================================================================= #
# Helpers
# ================================================================================================= #

## Load one WAV once. A missing asset is reported ONCE per name and never counted as played —
## silently substituting a sound would make SOUND-EVENTS green over a broken build.
static func _stream_for(sound_name: String) -> AudioStream:
	if _streams.has(sound_name):
		return _streams[sound_name]
	if not SOUNDS.has(sound_name):
		if not _missing.has(sound_name):
			_missing[sound_name] = true
			push_warning("SoundManager: '%s' is not a known sound" % sound_name)
		return null
	var path: String = AUDIO_DIR + sound_name + ".wav"
	if not ResourceLoader.exists(path):
		if not _missing.has(sound_name):
			_missing[sound_name] = true
			push_warning("SoundManager: missing asset %s" % path)
		return null
	var stream: Resource = load(path) as AudioStream
	if stream == null:
		if not _missing.has(sound_name):
			_missing[sound_name] = true
			push_warning("SoundManager: %s did not load as an AudioStream" % path)
		return null
	_streams[sound_name] = stream
	return stream


## CLEAR the pitch generator, so the next draw seeds it through the PRODUCTION path.
## The pitch sequence must be REPRODUCIBLE: the same match has to sound the same every
## time, or a replay would not match the recording. A test clears it and draws again.
##
## It clears rather than seeds ON PURPOSE: a reset that seeded the generator itself
## would hide a defect in the seeding - which is exactly how the first version of the
## determinism test passed a wall-clock seed.
static func _reset_pitch_rng() -> void:
	_rng = null
	_pitch_seed_used = 0


## The seed the pitch generator WILL use, read from the same place the product takes
## it. A test asks this instead of comparing two draws: two draws in the same
## millisecond agree even with a clock seed, so the comparison proved nothing.
static func _pitch_seed() -> int:
	_ensure_rng()
	return _pitch_seed_used


## The ONE place the pitch generator is seeded. Both the product and the test read the
## seed from here, so a report cannot disagree with the behaviour.
static func _ensure_rng() -> void:
	if _rng != null:
		return
	_rng = RngScript.new()
	_rng.seed_rng(PITCH_SEED)
	_pitch_seed_used = PITCH_SEED


static func _pitch(variation: float) -> float:
	if variation <= 0.0:
		return 1.0
	_ensure_rng()
	var unit: float = float(_rng.unit())
	return clampf(1.0 + (unit * 2.0 - 1.0) * variation, 0.1, 4.0)
