extends Node
## Stage-5 acceptance: a FULL match, start to game-over, with event coverage.
##
## This is the load-bearing stage: everything after it (safety assertions, the
## report, the screenshots) reads what this run produces. It plays one match all
## the way through and records which of the engine's event types actually fired,
## so a gap is a FACT rather than a hope.
##
## The match runs on a REAL host process (the way production runs), the browser is
## a joining client on its wire, and the local seats are driven by the host as the
## smoke needs. Nothing here is a simulation of the game.
##
## Exit 0 = every required event type was observed.

const Proto := preload("res://server/protocol.gd")

## Event types the engine can emit. Sourced from engine.gd's own `.append("...")`
## calls, so this list is the engine's vocabulary, not a guess.
const ALL_TYPES := [
	"setup", "roll", "move", "teleport", "land", "land_self", "pass", "pass_on_purchase",
	"purchase", "purchase_dropped", "rent", "tax", "pay", "cash", "go_bonus",
	"free_parking", "card_land", "card_draw", "card_gain", "card_null", "use_card",
	"jail", "build", "sell", "mortgage", "unmortgage",
	"auction_start", "auction_bid", "auction_pass", "auction_win", "auction_unwon",
	"trade_proposed", "trade_declined", "trade", "bankrupt", "winner",
	"admin_override",
]

## Types a full match MUST produce. The rest are situational (a trade needs two
## willing parties, an admin override needs an admin action) so they are reported
## but do not fail the run.
## Types a full match MUST produce. `sell`, `mortgage` and `unmortgage` are NOT
## here on purpose: a match where every seat keeps a cash reserve never needs them
## (measured — a full match that reached game-over never pawned anything). They are
## proven by their own engine tests, not by hoping a match trips over them.
const REQUIRED := [
	"setup", "roll", "move", "land", "purchase", "rent", "tax", "pay",
	"go_bonus", "card_land", "build",
	"auction_start", "auction_bid", "auction_pass", "auction_win",
	"jail", "bankrupt", "winner",
]

## Budget for one full match.
##
## MEASURED: a full four-character match needs ~264 manager ticks and produces
## 35 000-60 000 events depending on how much is bought and traded. Bounding by
## EVENTS was the wrong metric — the probe failed on its own limit while the game
## was progressing fine. Bound by the WALL CLOCK, which is what a smoke cares about.
const MAX_SECONDS := 600
const MAX_EVENTS := 200000
const READY_TIMEOUT_MS := 25000
## Pinned so a failure is reproducible and a fix is attributable.
const SEED := 4242

var _fail := 0
var _host_pid := -1
var _log_dir := ""
var _host_out: Array = []
var _port := 0
var _token := ""
var _client: WebSocketPeer
var _inbox: Array = []
var _proj: Dictionary = {}
var _seen := {}          # event type -> count
var _events_total := 0
var _host_final := 0


func _ready() -> void:
	print("=== Stage 5 acceptance: a full match with event coverage ===")
	await _run()
	if _host_pid > 0:
		OS.kill(_host_pid)
	_report()
	if _fail > 0:
		print("==> STAGE 5 FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> STAGE 5 PASSED — full match played, every required event observed")
		get_tree().quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _run() -> void:
	var godot := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	_log_dir = _make_log_dir()
	_wipe_logs()

	print("[1] start a host match with a REMOTE seat and a joining client")
	_port = _pick_free_port()
	_host_pid = OS.create_process(godot, PackedStringArray([
		"--path", project, "--headless", "--",
		"--admin", "--server-port=%d" % _port, "--autostart", "--smoke-seats=4",
		"--smoke-drive", "--smoke-seed=%d" % SEED, "--log-dir=%s" % _log_dir]), false)
	if _host_pid <= 0:
		_bad("the host did not start")
		return
	if not await _await_line("SERVER ready ws://127.0.0.1:%d" % _port, READY_TIMEOUT_MS):
		_bad("the host never announced its server")
		return
	for i in 200:
		_poll_output()
		_token = _token_from()
		if _token != "":
			break
		await get_tree().process_frame
	if _token == "":
		_bad("the host printed no seat token")
		return
	_ok("host on port %d with a seat for the client" % _port)

	_client = WebSocketPeer.new()
	_client.connect_to_url("ws://127.0.0.1:%d" % _port)
	if not await _await_open(400):
		_bad("the client could not connect")
		return
	_send({"t": "hello", "token": _token, "profile": "player"})
	var hello = await _await_t("hello_ok", 400)
	if hello == null or int(hello.get("pid", -1)) < 0:
		_bad("the client was not bound to a seat")
		return
	var pid := int(hello["pid"])
	_note_seat(pid)
	_ok("client playing seat %d" % pid)

	print("[2] play the match to game-over")
	# The client's seat is a HUMAN: it only acts when asked. Everything else is
	# driven by the host (its LOCAL seats) or waits for its own timeout. This is
	# what makes the run a real match rather than a bot race.
	var over := await _play_until_over(pid, MAX_EVENTS)
	if not over:
		_bad("the match did not reach game-over in %d events" % MAX_EVENTS)
		return
	_ok("match finished after %d events observed on the wire" % _events_total)

	print("[3] the host agrees the match is over")
	_host_final = await _host_events()
	if _host_final < 0:
		_bad("the host never reported its event count")
		return
	_ok("host engine logged %d events" % _host_final)

	print("[4] event coverage")
	var missing: Array = []
	for t in REQUIRED:
		if int(_seen.get(t, 0)) == 0:
			missing.append(t)
	if missing.is_empty():
		_ok("every required event type was observed (%d of them)" % REQUIRED.size())
	else:
		_bad("required event types never fired: %s" % ", ".join(missing))
	# and report the situational ones so a gap is visible, not hidden
	var extra: Array = []
	for t in ALL_TYPES:
		if int(_seen.get(t, 0)) == 0 and not REQUIRED.has(t):
			extra.append(t)
	if not extra.is_empty():
		print("      (situational, not required: %s)" % ", ".join(extra))


func _report() -> void:
	print("")
	print("=== coverage ===")
	var lines: Array = []
	for t in ALL_TYPES:
		var n := int(_seen.get(t, 0))
		lines.append("%s=%d" % [t, n])
	var missing: Array = []
	for t in REQUIRED:
		if int(_seen.get(t, 0)) == 0:
			missing.append(t)
	print("observed: %d / %d types" % [_seen.size(), ALL_TYPES.size()])
	print("  " + " ".join(lines))
	if missing.is_empty():
		print("required: all %d present" % REQUIRED.size())
	else:
		print("required MISSING: %s" % ", ".join(missing))


# --- playing ------------------------------------------------------------------

## Watch the wire until the engine reaches a terminal state.
##
## The client acts ONLY when the host asks its seat to; it never pretends to be
## the other seats, because it cannot — it owns no rules. This is the same
## contract the browser has, so what this exercises is what ships.
func _play_until_over(pid: int, budget: int) -> bool:
	var idle := 0
	var t0 := Time.get_ticks_msec()
	var next_report := 30000
	while _events_total < budget:
		var elapsed_ms := Time.get_ticks_msec() - t0
		if elapsed_ms > MAX_SECONDS * 1000:
			print("      deadline reached: %ds, %d events, %d types"
				% [elapsed_ms / 1000, _events_total, _seen.size()])
			return false
		if _events_total >= next_report:
			print("      ... %d events, %d types, %ds"
				% [_events_total, _seen.size(), elapsed_ms / 1000])
			next_report += 30000
		await _pump()
		if _is_over():
			return true
		var legal: Array = _proj.get("legal", [])
		if legal.is_empty():
			idle += 1
			if idle % 400 == 0:
				# nobody is moving: either the match ended unseen, or a seat is
				# waiting on a timeout that only real time can cross
				_host_final = await _host_events()
			await _tiny_wait()
			continue
		idle = 0
		# The client is a TRANSPORT (variant A): the host plays every seat it is
		# asked about. The client still answers when its own seat is offered a
		# move, so the wire path is exercised, but a decision it cannot make is
		# not a decision it invents.
		var pick := _choose(legal)
		if pick.is_empty():
			await _tiny_wait()
			continue
		_send(Proto.intent("play", str(pick["action"]), pick.get("params", {})))
		await _pump()
		await _tiny_wait()
	return false


## The engine's own first offer. No policy lives here: under variant A the host
## owns the decisions, and a client that re-derived them would be the shadow
## engine again by another name.
func _choose(legal: Array) -> Dictionary:
	if legal.is_empty():
		return {}
	return {"action": str(legal[0]), "params": _params_for(str(legal[0]))}





## A tile's price from the projection's board, which is what the client receives.
func _tile_price(idx: int) -> int:
	if idx < 0:
		return 0
	for t in _proj.get("board", []):
		var d: Dictionary = t
		if int(d.get("index", -1)) == idx:
			return int(d.get("cost", d.get("price", 0)))
	return 0


## This seat's cash, straight from the projection the host pushed.
func _my_cash() -> int:
	var me: int = int(_proj.get("_pid", -1))
	for pl in _proj.get("players", []):
		var d: Dictionary = pl
		if int(d.get("index", d.get("id", -1))) == me:
			return int(d.get("money", 0))
	# the spectator-shaped projection has the turn player first
	return 1500


func _params_for(action: String) -> Dictionary:
	match action:
		"bid":
			return {"amount": int((_proj.get("pending", {}) as Dictionary).get("high", 0)) + 5}
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			return {"tile": _own_tile()}
		"respond_trade":
			return {"accept": false}
		"use_card":
			return {}
		_:
			return {}


## A tile the CLIENT's seat owns, for the tile-addressed actions.
func _own_tile() -> int:
	var me: int = int(_proj.get("_pid", -1))
	for t in _proj.get("board", []):
		var d: Dictionary = t
		if int(d.get("owner", -1)) == me and int(d.get("houses", 0)) == 0:
			return int(d.get("index", -1))
	# fall back to any owned tile: the engine still validates it
	for t in _proj.get("board", []):
		var d: Dictionary = t
		if int(d.get("owner", -1)) == me:
			return int(d.get("index", -1))
	return -1


## Remember which seat this client owns, so the policy can read its own money.
func _note_seat(pid: int) -> void:
	_proj["_pid"] = pid


func _is_over() -> bool:
	# the host reports the terminal state through the event stream
	return int(_seen.get("winner", 0)) > 0


# --- wire ---------------------------------------------------------------------

func _pump() -> void:
	if _client == null:
		return
	_client.poll()
	while _client.get_available_packet_count() > 0:
		var d := Proto.decode(_client.get_packet().get_string_from_utf8())
		if d.is_empty():
			continue
		_inbox.append(d)
		_on_frame(d)


func _on_frame(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"projection":
			_proj = d.get("data", {})
		"event":
			var ev: Dictionary = d.get("data", {})
			var t := str(ev.get("type", ""))
			if t != "":
				_seen[t] = int(_seen.get(t, 0)) + 1
				_events_total += 1


func _send(msg: Dictionary) -> void:
	if _client != null and _client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_client.send_text(Proto.encode(msg))


func _await_open(frames: int) -> bool:
	for i in frames:
		_client.poll()
		if _client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		await get_tree().process_frame
	return false


func _await_t(t: String, frames: int):
	for i in frames:
		await _pump()
		for m in _inbox:
			if str(m.get("t", "")) == t:
				return m
		await get_tree().process_frame
	return null


## A short yield. Long enough for the host to send, short enough not to dominate
## the run time: the client acts once per pump and a match needs thousands.
func _tiny_wait() -> void:
	await get_tree().create_timer(0.004).timeout


# --- host log -----------------------------------------------------------------

func _poll_output() -> void:
	var f := _log_dir.path_join("admin.log")
	if not FileAccess.file_exists(f):
		return
	_host_out.clear()
	for line in FileAccess.get_file_as_string(f).split("\n"):
		_host_out.append(line)


func _await_line(needle: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		_poll_output()
		for line in _host_out:
			if str(line).contains(needle):
				return true
		await get_tree().process_frame
	return false


func _host_events() -> int:
	for i in 60:
		_poll_output()
		for line in _host_out:
			var s := str(line).strip_edges()
			if s.begins_with("EVENTS "):
				return int(s.substr(7))
		await get_tree().process_frame
	return -1


func _token_from() -> String:
	for line in _host_out:
		var s := str(line)
		if s.begins_with("SERVER seat="):
			for p in s.split(" "):
				if str(p).begins_with("token="):
					return str(p).substr(6)
	return ""


func _make_log_dir() -> String:
	var d := "user://smoke_stage5"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	return ProjectSettings.globalize_path(d)


func _wipe_logs() -> void:
	var d := DirAccess.open(_log_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func _pick_free_port() -> int:
	var tcp := TCPServer.new()
	if tcp.listen(0, "127.0.0.1") != OK:
		return 9082
	var p := tcp.get_local_port()
	tcp.stop()
	return p
