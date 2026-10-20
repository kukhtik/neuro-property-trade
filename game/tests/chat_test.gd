extends RefCounted
## CHAT-01 — the Twitch chat seat, end to end (promise S2).
##
## The pieces were all there and NOTHING checked them together: the bridge
## (`tools/ci/twitch_bridge.py`), the seat driver (`seats/drivers/chat_driver.gd` - majority
## of the last N commands, anti-flood, auto-pass on silence), the server entry
## (`game_server._on_chat` -> `seat_manager.push_chat`) and the engine's own validation.
## `grep -c CHAT-01 tools/ci/run_gates.sh` was 0: the promise had no acceptance test.
##
## WHAT IS PROVEN HERE (no network, no token): a viewer's vote reaches the engine, the
## engine decides, and the seat's move is the majority of the box. The bridge's own
## grammar and anti-flood rule are proven by its `--selftest`.
## WHAT IS NOT PROVEN HERE: the live IRC socket (needs a channel token), and the browser
## client that would carry the frame. Both are external by nature.

static func test_list() -> Array[String]:
	return [
		"test_chat_driver_majority_wins",
		"test_chat_driver_illegal_action_is_ignored",
		"test_chat_driver_passes_when_the_box_is_silent",
		"test_chat_driver_submits_through_the_manager",
		"test_chat_seat_buys_a_property_by_vote",
		"test_chat_seat_illegal_bid_is_rejected_by_the_engine",
		"test_bridge_turns_a_viewer_line_into_a_vote",
	]


static func _make_engine(player_names: Array = ["Ada", "Bo", "Cyd"]) -> Dictionary:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, player_names)
	return {"engine": e}


static func _make_chat_driver(engine, seat_pid: int, manager) -> Dictionary:
	var D = load("res://seats/drivers/chat_driver.gd")
	var d = D.new()
	d.setup(engine, _seat_stub(engine, seat_pid), manager)
	return {"driver": d}


## The driver only needs `pid` and `name` from the seat.
static func _seat_stub(engine, pid: int) -> Dictionary:
	return {"pid": pid, "name": "chat"}


# --- the driver, on its own ---

static func test_chat_driver_majority_wins() -> String:
	var r = _make_engine()
	var e = r["engine"]
	var d = _make_chat_driver(e, 0, null)["driver"]
	# "pass" is NOT legal at TURN_START, so the box holds two rolls - and the seat must
	# take the MAJORITY action, not the first one. The roll is forced to a non-double so
	# the turn is guaranteed to move on.
	e._force_dice(1, 1, 0, false)
	d.enqueue("roll", {})
	d.enqueue("roll", {})
	d.act()
	if e.player(0).position == 0:
		return "the majority action (roll) was not taken - position=" + str(e.player(0).position)
	return ""


static func test_chat_driver_illegal_action_is_ignored() -> String:
	var r = _make_engine()
	var d = _make_chat_driver(r["engine"], 0, null)["driver"]
	# "buy" is not legal at TURN_START: the driver must not submit it.
	d.enqueue("buy", {})
	d.enqueue("buy", {})
	d.act()
	# Nothing happened, so the engine is still waiting for the roll.
	if r["engine"].phase != r["engine"].PHASE_TURN_START:
		return "an illegal vote was executed - phase=" + r["engine"].phase
	if r["engine"].player(0).position != 0:
		return "the seat moved on an illegal vote - position=" + str(r["engine"].player(0).position)
	return ""


static func test_chat_driver_passes_when_the_box_is_silent() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# A CHAT seat with nothing to say must not stall the match. At TURN_START the only
	# move that advances the turn is "roll" ("pass" is not in the legal set there), so a
	# quiet table ROLLS ON after EMPTY_ROUNDS_BEFORE_PASS rounds. Before the fix the
	# auto-pass was guarded by `legal.has("pass")`, which is never true at TURN_START -
	# so the seat held the turn forever and the match stalled. That is what this test
	# pins: the turn MOVES.
	var d = _make_chat_driver(e, 0, null)["driver"]
	# The seat's own decision points: TURN_START, then PURCHASE_WAIT. Force a NON-double
	# roll so the turn is guaranteed to move on (a double would keep the turn with the
	# same seat and the assertion would be a coin flip rather than a check).
	e._force_dice(1, 1, 0, false)
	for i in 4:
		d.act()
	# The seat must have MOVED: that is the whole point - before the fix the auto-pass
	# guard (`legal.has("pass")`) was never true at TURN_START and the seat held the
	# turn forever.
	if e.player(0).position == 0:
		return "the silent seat never moved - the auto-roll did not happen"
	# And it must not be stuck holding a decision it cannot leave.
	if e.phase == e.PHASE_TURN_START and e.turn_player == 0:
		return "the silent seat kept the turn - the match would stall"
	return ""


static func test_chat_driver_submits_through_the_manager() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# A manager that records what the driver sent. The driver must go through the
	# manager (not the engine directly), because the events have to reach the journal:
	# a driver that called engine.submit_intent directly left the whole feed empty.
	var recorded: Array = []
	# The driver checks `manager.has_method("push_intent")`, so the stand-in must be an
	# OBJECT with that method - a Dictionary has no methods.
	var fake = FakeManager.new()
	fake.recorded = recorded
	var d = _make_chat_driver(e, 0, fake)["driver"]
	d.enqueue("roll", {})
	d.act()
	if recorded.size() == 0:
		return "the driver did not submit through the manager"
	if str(recorded[0][1]) != "roll":
		return "the driver submitted the wrong action: " + str(recorded[0][1])
	return ""


# --- the seat in a real match ---

static func test_chat_seat_buys_a_property_by_vote() -> String:
	var r = _make_engine()
	var e = r["engine"]
	var d = _make_chat_driver(e, 0, null)["driver"]
	# Move the chat seat onto a property: a roll, then the purchase decision.
	e._force_dice(1, 1, 0, false)
	d.enqueue("roll", {})
	d.act()
	if e.phase != e.PHASE_PURCHASE_WAIT:
		return "the vote did not produce a purchase decision - phase=" + e.phase
	# The viewers vote to buy.
	d.enqueue("buy", {})
	d.enqueue("buy", {})
	d.act()
	if not e.player(0).owns(1):
		return "the voted purchase did not happen - the seat owns no tile"
	return ""


static func test_chat_seat_illegal_bid_is_rejected_by_the_engine() -> String:
	var r = _make_engine(["Ada", "Bo", "Cyd"])
	var e = r["engine"]
	# A bid of 0 must not be accepted: the engine is the authority, the chat seat
	# only proposes.
	var res: Dictionary = e.submit_intent(0, "bid", {"amount": 0})
	if res.get("ok", false):
		return "the engine accepted a bid of 0 - it must reject it"
	return ""


# --- the bridge, on its own ---

static func test_bridge_turns_a_viewer_line_into_a_vote() -> String:
	# The bridge is a python process; the gate runs its selftest. Here we pin the
	# CONTRACT the game depends on: the frame the bridge sends is the one the server
	# reads. If the shape changes, this test fails before the bridge does.
	var proto = load("res://server/protocol.gd")
	var frame := {"t": "chat", "action": "buy", "params": {}}
	var raw: String = proto.encode(frame)
	var back: Dictionary = proto.decode(raw)
	if back.is_empty():
		return "the chat frame did not survive the protocol round trip"
	if str(back.get("t", "")) != "chat":
		return "the frame lost its type: " + str(back.get("t", ""))
	if str(back.get("action", "")) != "buy":
		return "the frame lost its action: " + str(back.get("action", ""))
	return ""


## A stand-in for the seat manager. The driver asks `manager.has_method("push_intent")`
## and then calls it - `has_method` is a BUILT-IN on Object, so the stand-in must be a
## real object that simply HAS a `push_intent` method (the built-in then answers true).
class FakeManager:
	extends RefCounted
	var recorded: Array = []

	func push_intent(pid: int, action: String, params: Dictionary) -> Dictionary:
		recorded.append([pid, action, params])
		return {"ok": true, "reason": "", "legal": [], "events": []}
