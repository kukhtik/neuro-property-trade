extends Node
## SOUND-EVENTS gate — sound is BOUND TO EVENTS, not merely switched on (track 2).
##
## WHY A SECOND GATE. `SOUND` proves the row and the manager work when called. It cannot prove
## that anything calls them at the right moment: a product that plays a beep on a button and
## nothing on a purchase would pass it. So this gate runs a REAL match — a real engine, the real
## seat manager driving four AI seats, the real `game_view` (the same object the app builds) — and
## compares what the SOUND LOG counted against the events the UI actually received:
##
##     event, as the engine logged it   ->   sound, as it was heard   ->   count
##     roll (xN)                        ->   dice                      ->   N
##     purchase (xM)                    ->   buy                       ->   M
##     auction_bid, jail, card_*, mortgage, winner, bankrupt, rent ...   -> same rule
##
## The expectation table is DUPLICATED here on purpose. Reading it from SoundManager would make
## the gate agree with whatever the product does — the "harness that hard-codes the value it
## inspects" trap. A changed product map has to be a deliberate change here too.
##
## The sounds that do not come from an event (`turn`, `tick`) are subtracted out and checked
## separately: they follow the projection, and `SOUND` already measures them.
##
## THE NEGATIVE IS BUILT IN: the same events are replayed through the same handler with sound
## OFF (counter must be 0) and then ON (counter must be back). A gate that cannot go red proves
## nothing, so both directions run in every invocation.
##
## Verdict: ==> SOUND-EVENTS PASSED (...) / ==> SOUND-EVENTS FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sound_events_gate.tscn

const GameView := preload("res://ui/game_view.gd")
const EngineScript := preload("res://core/engine.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")
const SoundManager := preload("res://audio/sound_manager.gd")

## ENGINE EVENT -> the sound a player must hear. Independent of the product's own table.
const EXPECT := {
	"roll": "dice",
	# NOTE: "turn" is NOT here on purpose. The product plays it from the PROJECTION path
	# (the turn holder changed), not from an event - step 3 measures it on its own, and
	# step 2 subtracts it out of the totals.
	"purchase": "buy",
	"auction_win": "buy",
	"auction_bid": "bid",
	"jail": "jail",
	"card_draw": "card", "card_gain": "card", "card_land": "card", "card_null": "card",
	"mortgage": "mortgage",
	"winner": "game_over",
	"bankrupt": "error",
	"rent": "toast", "tax": "toast", "go_bonus": "toast", "build": "toast", "sell": "toast",
	"trade": "toast", "trade_proposed": "toast", "trade_declined": "toast",
	"free_parking": "toast", "pause": "toast", "resume": "toast",
}

## A match this gate accepts as "a match": a few turns, at least one purchase, several sounds.
const MIN_ROLLS := 4
const MIN_BUYS := 1
const MIN_SOUND_NAMES := 3
const DEADLINE_MS := 60000

var _engine
var _mgr
var _gv
var _seen: Array = []                  # every event the UI received, in order
var _expected: Dictionary = {}         # sound name -> number of events that asked for it
var _deadline := 0
var _fails: Array = []
var _finished := false


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	SoundManager.reset_log()
	SoundManager.set_enabled(true)
	_build()
	_deadline = Time.get_ticks_msec() + DEADLINE_MS


func _build() -> void:
	var st = SettingsScript.new()
	st.seat_count = 4
	st.rng_seed = 4242
	st.turn_timer = 0            # no auto-pass: the AI must act, not be timed out
	st.auction_timer = 0
	st.round_limit = 0
	var assigns: Array = []
	for i in 4:
		assigns.append({"driver": "AI", "name": "S%d" % i})
	st.seat_assignments = assigns
	var seats: Array = SeatConfigScript.from_settings(st)
	var names: Array = []
	for s in seats:
		names.append(str(s.name))
	_engine = EngineScript.new()
	_engine.setup(st, names)
	_mgr = SeatManager.new()
	_mgr.name = "SeatManager"
	add_child(_mgr)
	# MY counter listens BEFORE the view, so both see the same stream from the same instant
	_mgr.events_emitted.connect(Callable(self, "_on_events"))
	_mgr.setup(_engine, seats)
	_gv = GameView.new()
	_gv.name = "GameView"
	add_child(_gv)
	_gv.setup(_engine, _mgr, seats, st)
	print("=== sound events: 4 AI seats, seed %d, phase %s ===" % [int(st.rng_seed), str(_engine.phase)])


## The UI's own stream: every event is appended and priced in the expectation table.
func _on_events(events: Array) -> void:
	for ev in events:
		_seen.append(ev)
		var t: String = str((ev as Dictionary).get("type", ""))
		var want: String = str(EXPECT.get(t, ""))
		if want != "":
			_expected[want] = int(_expected.get(want, 0)) + 1


func _process(_dt: float) -> void:
	if _finished:
		return
	var rolls: int = int(_expected.get("dice", 0))
	var buys: int = int(_expected.get("buy", 0))
	var over: bool = str(_engine.phase) == "END_GAME"
	var timed_out: bool = Time.get_ticks_msec() >= _deadline
	if (rolls >= MIN_ROLLS and buys >= MIN_BUYS) or over or timed_out:
		_finished = true
		_judge(over, timed_out)


func _judge(over: bool, timed_out: bool) -> void:
	var rolls: int = int(_expected.get("dice", 0))
	var buys: int = int(_expected.get("buy", 0))
	print("=== sound events: %d events, %d rolls, %d purchases, end_game=%s timed_out=%s ==="
		% [_seen.size(), rolls, buys, str(over), str(timed_out)])
	if rolls < MIN_ROLLS:
		_fail("only %d rolls in the match - too little happened to judge the binding" % rolls)
	if buys < MIN_BUYS:
		_fail("no purchase happened in %d events - the buy sound cannot be judged" % _seen.size())

	# --- 1. what the log says versus what the events asked for ------------------------------- #
	# "turn" HAS TWO SOURCES in the product: the match-start EVENT (setup/start in the
	# event map) and the PROJECTION path (the turn holder changed). Comparing the total
	# against the event count called a correct product wrong ("turn played 5 times, the
	# events asked for 3"). So the PROJECTION sounds are subtracted out of the totals
	# before the comparison, and checked on their own in step 3.
	var fired: Dictionary = SoundManager.counts()
	var names_hit := 0
	for name in _expected:
		var want: int = int(_expected[name])
		var got: int = int(fired.get(str(name), 0))
		if got > 0:
			names_hit += 1
		print("    %-10s expected %3d  heard %3d" % [str(name), want, got])
		if want != got:
			_fail("sound '%s' played %d time(s), the events asked for %d (sound is not bound to the event)" % [str(name), got, want])
	if names_hit < MIN_SOUND_NAMES:
		_fail("only %d distinct event sounds fired (expected at least %d)" % [names_hit, MIN_SOUND_NAMES])

	# --- 2. no sound may exist that no event asked for --------------------------------------- #
	var projection_sounds: int = int(SoundManager.count("turn")) + int(SoundManager.count("tick"))
	var event_sounds: int = int(SoundManager.total()) - projection_sounds
	var expected_total := 0
	for name in _expected:
		expected_total += int(_expected[name])
	if event_sounds != expected_total:
		_fail("%d event sounds were played but the events account for %d" % [event_sounds, expected_total])

	# --- 3. the projection sounds also fired (the shell's other sound path) ------------------ #
	if int(SoundManager.count("turn")) < 1:
		_fail("no turn sound during the match (apply_projection is not feeding the manager)")
	print("    %-10s %3d (projection)  %-10s %3d (projection)"
		% ["turn", int(SoundManager.count("turn")), "tick", int(SoundManager.count("tick"))])

	# --- 4. THE NEGATIVE + its positive twin, through the SAME handler ---------------------- #
	# FREEZE THE MATCH FIRST. The seat manager keeps driving AI seats on its own clock, and every
	# projection it pushes makes the shell play a turn sound - the first version of this replay
	# counted 3 phantom "turn" sounds that had nothing to do with the events it was replaying.
	_mgr.set_process(false)
	var off_total := _replay(false)
	var off_suppressed := int(SoundManager.suppressed())
	var on_total := _replay(true)
	print("    replay: sound OFF -> %d played (%d refused), sound ON -> %d played, %d events replayed"
		% [off_total, off_suppressed, on_total, _seen.size()])
	if off_total != 0:
		_fail("replaying %d events with sound OFF still produced %d sound(s)" % [_seen.size(), off_total])
	if off_suppressed < 1:
		_fail("sound OFF recorded no refusals - is the switch even reaching play()?")
	if on_total < 1:
		_fail("replaying the same events with sound ON produced no sound at all")
	if on_total != expected_total:
		_fail("replay with sound ON produced %d sound(s), the events account for %d" % [on_total, expected_total])

	if _fails.is_empty():
		print("==> SOUND-EVENTS PASSED (%d events, %d event sounds over %d names, both switch directions, rolls=%d buys=%d)"
			% [_seen.size(), event_sounds, names_hit, rolls, buys])
		get_tree().quit(0)
	else:
		print("==> SOUND-EVENTS FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


## Push the whole recorded stream through the product's own event handler with sound off/on.
func _replay(enabled: bool) -> int:
	SoundManager.reset_log()
	SoundManager.set_enabled(enabled)
	for ev in _seen:
		_gv.call("_on_events", [ev])
	var counts: Dictionary = SoundManager.counts()
	# The EVENT sounds, the same rule step 2 uses on the live match: the total minus the
	# projection sounds. The replay drives the shell's event handler, and the shell also
	# plays the projection sound ("turn") for every projection it applies - counting it
	# as an event sound is what made the first version fail ("produced 11 sound(s), the
	# events account for 8").
	var projection_sounds: int = int(counts.get("turn", 0)) + int(counts.get("tick", 0))
	var total: int = int(SoundManager.total()) - projection_sounds
	print("    replay(counts, sound %s): %s" % [str(enabled), str(counts)])
	SoundManager.set_enabled(true)
	return total


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
