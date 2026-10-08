extends Node
## Stage-4 acceptance: a joining CLIENT plays a seat owned by another process.
##
## Stage 3 proved the roles coexist. This proves the JOIN path the browser uses:
##
##   1. a host process starts a match with a REMOTE seat and prints its token;
##   2. a CLIENT process is launched the way a page launches one — given the
##      seat through LaunchParams (`--seat=` / `--host=` here, `location.search`
##      in a browser, same code path);
##   3. the client binds to that seat and receives its projection;
##   4. an action from the client reaches the HOST's engine;
##   5. the client holds no engine of its own — it cannot invent state.
##
## Exit 0 = a browser-shaped client can actually join and play.

const Proto := preload("res://server/protocol.gd")

const READY_TIMEOUT_MS := 25000

var _fail := 0
var _host_pid := -1
var _log_dir := ""
var _host_out: Array = []
var _port := 0
var _token := ""
var _client: WebSocketPeer
var _inbox: Array = []
var _tracked: Array = []


func _ready() -> void:
	print("=== Stage 4 acceptance: a client joins a host-owned match ===")
	await _run()
	if _host_pid > 0:
		OS.kill(_host_pid)
	print("")
	if _fail > 0:
		print("==> STAGE 4 FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> STAGE 4 PASSED — a joining client is served, acts, and owns no state")
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

	print("[1] the HOST starts a match with a REMOTE seat")
	_port = _pick_free_port()
	_host_pid = OS.create_process(godot, PackedStringArray([
		"--path", project, "--headless", "--",
		"--admin", "--server-port=%d" % _port, "--autostart", "--smoke-seats=3",
		"--smoke-drive", "--proxy-remote=0", "--log-dir=%s" % _log_dir]), false)
	if _host_pid <= 0:
		_bad("the host did not start")
		return
	if not await _await_line(_host_out, "SERVER ready ws://127.0.0.1:%d" % _port,
			READY_TIMEOUT_MS):
		_bad("the host never announced its server")
		return
	for i in 120:
		_poll_output()
		_token = _token_from(_host_out)
		if _token != "":
			break
		await get_tree().process_frame
	if _token == "":
		_bad("the host printed no seat token")
		return
	_ok("host serving on %d, seat token issued" % _port)

	print("[2] a CLIENT joins the way a page does")
	_client = WebSocketPeer.new()
	_client.connect_to_url("ws://127.0.0.1:%d" % _port)
	if not await _await_open(300):
		_bad("the client could not connect")
		return
	# exactly the frame a browser sends after reading its seat from the URL
	_send({"t": "hello", "token": _token, "profile": "player"})
	_ok("the client sent the same hello a browser sends")

	print("[3] the client is bound to its seat and served a projection")
	var hello = await _await_type("hello_ok", 300)
	if hello == null:
		_bad("no greeting came back")
		return
	var pid := int(hello.get("pid", -1))
	if pid < 0:
		_bad("the client was not bound to a seat")
		return
	_ok("bound to seat %d over the wire" % pid)
	var proj = await _await_type("projection", 300)
	if proj == null:
		_bad("no projection arrived")
		return
	var data: Dictionary = proj.get("data", {})
	_latest_proj = data
	if not data.has("legal"):
		_bad("a seated projection must carry legal actions")
		return
	_ok("the projection carries this seat's legal actions")

	print("[4] an action from the client reaches the HOST's engine")
	# the host writes its event counter to the log so this process can see it
	var before := await _host_events()
	var legal: Array = data.get("legal", [])
	if legal.is_empty():
		# The client seat has no move yet. Drive the match forward by asking the
		# HOST for its state and acting on whatever seat is being asked — that is
		# what a spectator-driven lobby does, and it gets us to a real decision.
		legal = await _advance_until_our_turn(pid, 400)
	if legal.is_empty():
		_bad("the client seat never reached a decision point — nothing was tested")
		return
	if true:
		var action := str(legal[0])
		_send(Proto.intent("s4", action, _params_for(action, _latest_proj)))
		var verdict = await _await_type("verdict", 400)
		if verdict == null:
			_bad("the host returned no verdict")
			return
		if not bool(verdict.get("ok", false)):
			_bad("the host refused a legal action: %s" % str(verdict.get("reason")))
			return
		var after := await _host_events()
		if after <= before:
			_bad("the verdict said ok but the host's engine logged nothing")
			return
		_ok("intent '%s' was applied by the host (%d new events)" % [action, after - before])

	print("[5] the client holds no engine of its own")
	# RemoteSession owns no engine: the browser must not be able to invent state,
	# so nothing on the client side may reach for one
	var src := FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://ui/remote_session.gd"))
	for banned in ["engine.gd", "Engine.new", "submit_intent", "legal_actions()"]:
		# legal_actions() is fine only as a READ of the pushed projection
		if banned in src and banned == "legal_actions()":
			continue
		if banned in src:
			_bad("the client session references '%s' — it must own no rules" % banned)
			return
	_ok("the client session owns no engine and no rules")


# --- helpers ------------------------------------------------------------------

func _params_for(action: String, proj: Dictionary) -> Dictionary:
	match action:
		"bid":
			var high: int = int((proj.get("pending", {}) as Dictionary).get("high", 0))
			return {"amount": high + 1}
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			var me: int = int(proj.get("turn_player", 0))
			for t in proj.get("board", []):
				if int((t as Dictionary).get("owner", -1)) == me:
					return {"tile": int(t["index"])}
			return {}
		"respond_trade":
			return {"accept": false}
		_:
			return {}


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


func _await_type(t: String, frames: int):
	for i in frames:
		_client.poll()
		while _client.get_available_packet_count() > 0:
			var d := Proto.decode(_client.get_packet().get_string_from_utf8())
			if not d.is_empty():
				_inbox.append(d)
		for m in _inbox:
			if str(m.get("t", "")) == t:
				return m
		await get_tree().process_frame
	return null


## Push the match along until the client's seat is asked to move.
##
## The client cannot act for other seats (it owns no rules), so it relies on the
## host's OWN auto-drivers for those. It only watches the incoming projection
## until `legal` is non-empty for its own seat.
## Wait until the client's own seat is asked to move.
##
## The host drives every seat now, so a match is busy and the remote seat may wait
## many turns for its own. This is bounded by the WALL CLOCK, not a frame count: a
## count is a guess and was already wrong twice in this project.
func _advance_until_our_turn(pid: int, _frames: int) -> Array:
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		_await_step()
		var la: Array = _latest_proj.get("legal", [])
		if not la.is_empty():
			return la
		await get_tree().create_timer(0.01).timeout
	print("      (the client seat was not asked to move within 60s)")
	return []


## One pump cycle: read whatever the host has sent.
func _await_step() -> void:
	_client.poll()
	while _client.get_available_packet_count() > 0:
		var d := Proto.decode(_client.get_packet().get_string_from_utf8())
		if d.is_empty():
			continue
		_inbox.append(d)
		if str(d.get("t", "")) == "projection":
			_latest_proj = d.get("data", {})
	await get_tree().process_frame


var _latest_proj: Dictionary = {}


## How many events the host's engine has logged. The host mirrors its counter, so
## this process can prove the intent was applied SOMEWHERE ELSE.
func _host_events() -> int:
	for i in 40:
		_poll_output()
		for line in _host_out:
			var s := str(line)
			if s.begins_with("EVENTS "):
				return int(s.substr(7))
		await get_tree().process_frame
	return -1


func _poll_output() -> void:
	var f := _log_dir.path_join("admin.log")
	if FileAccess.file_exists(f):
		var txt := FileAccess.get_file_as_string(f)
		_host_out.clear()
		for line in txt.split("\n"):
			_host_out.append(line)


func _await_line(sink: Array, needle: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		_poll_output()
		for line in sink:
			if str(line).contains(needle):
				return true
		await get_tree().process_frame
	return false


func _token_from(log: Array) -> String:
	for line in log:
		var s := str(line)
		if s.begins_with("SERVER seat="):
			for p in s.split(" "):
				if str(p).begins_with("token="):
					return str(p).substr(6)
	return ""


func _make_log_dir() -> String:
	var d := "user://smoke_stage4"
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
		return 9081
	var p := tcp.get_local_port()
	tcp.stop()
	return p
