extends RefCounted
## Tests for the REMOTE seat driver (stage 2 of the full smoke).
##
## A REMOTE seat is a TRANSPORT, not a brain: it must never pick a move of its
## own, must forward exactly what the browser sent, and must keep the match alive
## when the socket is gone. Those three properties are what the browser client
## depends on, so they are pinned here.

const SeatConfig := preload("res://seats/seat_config.gd")
const Remote := preload("res://seats/drivers/remote_driver.gd")
const Proto := preload("res://server/protocol.gd")


static func test_list() -> Array[String]:
	return [
		"test_remote_label_resolves",
		"test_remote_variants_resolve",
		"test_other_labels_unchanged",
		"test_driver_is_not_a_decider",
		"test_submit_is_idempotent_when_offline",
		"test_legal_actions_come_from_the_host",
		"test_projection_starts_empty",
		"test_verdict_is_not_a_decision",
	]


## The label had nowhere to go before the transport existed.
static func test_remote_label_resolves() -> String:
	var r := SeatConfig.resolve_driver("REMOTE", false)
	if r != "REMOTE":
		return "a 'REMOTE' seat should resolve to the REMOTE driver, got '%s'" % r
	return ""


static func test_remote_variants_resolve() -> String:
	# case-insensitive, and a `remote:<x>` form so a host can name the channel
	for label in ["remote", "Remote", "remote:laptop"]:
		var r := SeatConfig.resolve_driver(label, false)
		if r != "REMOTE":
			return "'%s' should resolve to REMOTE, got '%s'" % [label, r]
	return ""


static func test_other_labels_unchanged() -> String:
	# adding REMOTE must not disturb the existing assignments
	var cases := {"LOCAL": "LOCAL", "CHAT": "CHAT", "ADMIN": "ADMIN", "AI": "AI",
		"sdk:neuro": "SDK", "": "AI", "nonsense": "AI"}
	for label in cases:
		var r := SeatConfig.resolve_driver(str(label), false)
		if r != cases[label]:
			return "'%s' should still resolve to '%s', got '%s'" % [label, cases[label], r]
	# and the single-SDK rule still holds
	if SeatConfig.resolve_driver("sdk:evil", true) != "AI":
		return "a second SDK seat must still fall back to AI"
	return ""


## The defining property: with no socket, the driver decides NOTHING. It has no
## act() at all, so the seat manager's AI/CHAT auto-advance cannot touch it.
static func test_driver_is_not_a_decider() -> String:
	var d := Remote.new()
	if d.has_method("act"):
		return "a REMOTE driver must not expose act() — it is a transport, not a brain"
	if d.has_method("enqueue"):
		return "a REMOTE driver must not accept chat-style enqueue()"
	return ""


static func test_submit_is_idempotent_when_offline() -> String:
	var d := Remote.new()
	# never connected: submitting must fail quietly, not crash and not queue
	var id := d.submit("roll", {})
	if id != "":
		return "an offline driver returned an intent id '%s'" % id
	if d.is_connected_to_host():
		return "a fresh driver claims to be connected"
	# and a disconnect on a never-connected driver is safe
	d.disconnect_from_host()
	return ""


static func test_legal_actions_come_from_the_host() -> String:
	var d := Remote.new()
	# before any projection there are no legal actions — the client must not
	# invent them, or the UI would offer buttons the engine will refuse
	if not (d.legal_actions() as Array).is_empty():
		return "legal actions appeared before the host sent a projection"
	# with a host projection they are exactly what the host said
	d._last_projection = {"legal": ["roll", "buy"]}
	var legal := d.legal_actions()
	if legal.size() != 2 or not legal.has("roll"):
		return "the driver did not report the host's legal actions: %s" % str(legal)
	# and it must NOT add a guess of its own
	if legal.has("end"):
		return "the driver invented a legal action the host did not send"
	return ""


static func test_projection_starts_empty() -> String:
	var d := Remote.new()
	if not d.projection().is_empty():
		return "a fresh driver already holds a projection"
	return ""


static func test_verdict_is_not_a_decision() -> String:
	# a verdict arriving from the host must not be interpreted by the driver —
	# the engine already applied (or refused) it
	var d := Remote.new()
	d._handle({"t": "verdict", "id": "i1", "ok": false, "reason": "nope"})
	if not d.projection().is_empty():
		return "a verdict must not populate the projection"
	d._handle({"t": "projection", "data": {"legal": ["roll"]}})
	if (d.legal_actions() as Array).size() != 1:
		return "a projection frame should update the local copy"
	return ""
