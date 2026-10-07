extends RefCounted
## Tests for the network transport (stage 1 of the full smoke).
##
## The wire contract is pure, so it is tested WITHOUT opening a port: framing,
## token minting, channel routing and the safety property that private data has
## no shared channel to leak into.

const Proto := preload("res://server/protocol.gd")
const Server := preload("res://server/game_server.gd")


static func test_list() -> Array[String]:
	return [
		"test_encode_decode_roundtrip", "test_numeric_params_survive_as_numbers",
		"test_decode_rejects_garbage",
		"test_decode_requires_type",
		"test_client_msg_whitelist",
		"test_token_is_stable_for_a_seed",
		"test_token_differs_per_seat",
		"test_token_changes_with_seed",
		"test_channel_spectator_when_unseated",
		"test_channel_per_seat",
		"test_intent_frame_shape",
		"test_hello_frame_shape",
		"test_spectator_projection_has_no_private",
		"test_seated_projection_carries_private",
		"test_server_binds_and_reports_port",
	]


## JSON has ONE number type, so an int parameter comes back as a float. That is
## a real property of the wire, not a bug — it is pinned here because the engine
## receives every intent through this path and must tolerate it.
static func test_encode_decode_roundtrip() -> String:
	var msg := {"t": "intent", "id": "a1", "action": "roll", "params": {"amount": 5}}
	var back := Proto.decode(Proto.encode(msg))
	if str(back.get("t", "")) != "intent" or str(back.get("action", "")) != "roll":
		return "roundtrip changed the frame: %s" % str(back)
	if str(back.get("id", "")) != "a1":
		return "roundtrip lost the intent id"
	# the value survives; only its numeric representation is unified to float
	if int(back["params"]["amount"]) != 5:
		return "roundtrip lost the parameter value"
	return ""


## A tile index written as an int must still reach the engine as an index.
static func test_numeric_params_survive_as_numbers() -> String:
	var f := Proto.decode(Proto.encode(Proto.intent("n1", "buy", {"tile": 7})))
	var tile: Variant = f["params"]["tile"]
	if not (tile is int or tile is float):
		return "a numeric parameter came back as %s" % typeof(tile)
	if int(tile) != 7:
		return "a numeric parameter changed value: %s" % str(tile)
	return ""


static func test_decode_rejects_garbage() -> String:
	for raw in ["", "not json", "{broken", "[1,2,3]", "\"text\"", "42"]:
		var d := Proto.decode(raw)
		if not d.is_empty():
			return "garbage %s decoded to %s" % [raw, str(d)]
	return ""


static func test_decode_requires_type() -> String:
	# an object without `t` is not a frame — a crash-free host must ignore it
	var d := Proto.decode('{"action":"roll"}')
	if not d.is_empty():
		return "a frame without a type should be dropped, got %s" % str(d)
	return ""


static func test_client_msg_whitelist() -> String:
	for t in ["hello", "intent", "ping"]:
		if not Proto.is_valid_client_msg({"t": t}):
			return "'%s' should be a valid client message" % t
	# a server-only type must NOT be accepted from a client
	for t in ["projection", "verdict", "hello_ok", "reject"]:
		if Proto.is_valid_client_msg({"t": t}):
			return "'%s' must not be accepted from a client" % t
	return ""


static func test_token_is_stable_for_a_seed() -> String:
	# reproducibility: the same seed and seat must mint the same token, which is
	# what lets a reconnect test replay exactly
	var a := Proto.new_token(2, _fake_engine(1234))
	var b := Proto.new_token(2, _fake_engine(1234))
	if a != b:
		return "token is not deterministic: %s vs %s" % [a, b]
	if a.length() != 16:
		return "token should be 16 chars, got %d" % a.length()
	return ""


static func test_token_differs_per_seat() -> String:
	var e = _fake_engine(7)
	if Proto.new_token(0, e) == Proto.new_token(1, e):
		return "two seats must not share a token"
	return ""


static func test_token_changes_with_seed() -> String:
	var a := Proto.new_token(0, _fake_engine(1))
	var b := Proto.new_token(0, _fake_engine(2))
	if a == b:
		return "a different seed should mint a different token"
	return ""


static func test_channel_spectator_when_unseated() -> String:
	if Proto.channel_for(-1, "") != "spectator":
		return "an unknown socket must sit on the spectator channel"
	return ""


static func test_channel_per_seat() -> String:
	var c := Proto.channel_for(3, "abc123")
	if c != "seat/abc123":
		return "a seated socket needs its own channel, got %s" % c
	return ""


static func test_intent_frame_shape() -> String:
	var f := Proto.intent("x9", "buy", {"tile": 4})
	if f["t"] != "intent" or f["id"] != "x9" or f["action"] != "buy":
		return "intent frame is malformed: %s" % str(f)
	if int(f["params"]["tile"]) != 4:
		return "intent parameters were lost"
	return ""


static func test_hello_frame_shape() -> String:
	var f := Proto.hello("tok", "stream")
	if f["t"] != "hello" or f["token"] != "tok" or f["profile"] != "stream":
		return "hello frame is malformed: %s" % str(f)
	return ""


## The core safety property of the two-channel design.
static func test_spectator_projection_has_no_private() -> String:
	var proj := _projection_pair()
	for key in ["private", "legal"]:
		if proj["spec"].has(key):
			return "the spectator projection exposes '%s'" % key
	return ""


static func test_seated_projection_carries_private() -> String:
	var proj := _projection_pair()
	if not proj["own"].has("private"):
		return "a seat's own projection must carry its private section"
	if not proj["own"].has("legal"):
		return "a seat's own projection must carry its legal actions"
	return ""


static func test_server_binds_and_reports_port() -> String:
	# port 0 -> the OS picks a free one, so parallel smoke runs never collide
	var s := Server.new()
	if not s.listen(0, "127.0.0.1"):
		return "the server could not bind to an ephemeral port"
	var p: int = s.port()
	s.close_all()
	if p <= 0:
		return "the server reported port %d after binding" % p
	return ""


# --- helpers ------------------------------------------------------------------

static func _fake_engine(seed_value: int):
	return {"settings": {"rng_seed": seed_value}}


## A real engine projection pair: the seated/spectator split must be the engine's
## own doing, not something this test simulates.
static func _projection_pair() -> Dictionary:
	var EngineScript := load("res://core/engine.gd")
	var SettingsScript := load("res://core/game_settings.gd")
	var Proj := load("res://sdk/projection.gd")
	var st = SettingsScript.new()
	st.rng_seed = 11
	var eng = EngineScript.new()
	eng.setup(st, ["A", "B"])
	return {
		"spec": Proj.new().for_spectator(eng),
		"own": Proj.new().for_player(eng, 0),
	}
