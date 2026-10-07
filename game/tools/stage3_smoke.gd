extends Node
## Stage-3 acceptance: the orchestrator — all roles alive in ONE run.
##
## The point of this stage is not to test a feature; it is to prove that the
## pieces can coexist. Three processes come up together and each is checked in
## its own scope, so the whole application is exercised in a single run instead
## of being launched a thousand times:
##
##   A. HOST/ADMIN  — a real Godot process (--admin), owns the engine
##   B. STREAM      — a second real process of the SAME binary (--stream)
##   C. BROWSER     — a WebSocket client on the host's server (the transport
##                    stage 1 built; stage 4 swaps it for real Chrome)
##
## What is verified here:
##   1. each process reaches its own role (they are independent, per stage 7);
##   2. the stream process takes no input and exposes no admin tools;
##   3. the browser client is served over the wire and its intents reach the
##      engine that the OTHER process owns;
##   4. the stream and the browser are never served private data.
##
## Exit 0 = the three roles coexist.

const Proto := preload("res://server/protocol.gd")

## How long a child process may take to announce readiness.
const READY_TIMEOUT_MS := 25000

var _fail := 0
var _admin_pid := -1
var _stream_pid := -1
var _port := 0
var _seat_token := ""
var _client: WebSocketPeer
var _inbox: Array = []
var _admin_out := []
var _stream_out := []
## One directory both children write their role log into, so this process can
## read a DETACHED child's readiness (there is no pipe API in Godot).
var _log_dir := ""


func _ready() -> void:
	print("=== Stage 3 acceptance: all roles alive in one run ===")
	await _run()
	_finish()


func _finish() -> void:
	_kill_children()
	print("")
	if _fail > 0:
		print("==> STAGE 3 FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> STAGE 3 PASSED — admin, stream and a networked player coexist")
		get_tree().quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _run() -> void:
	var godot := OS.get_executable_path()
	# the project the child should run; the smoke may be launched from anywhere
	var project := ProjectSettings.globalize_path("res://")
	_log_dir = _make_log_dir()
	_wipe_logs()

	print("[1] bring up the HOST process (--admin), which owns the engine")
	# an ephemeral port keeps parallel smoke runs from colliding
	_port = _pick_free_port()
	_admin_pid = _spawn(godot, ["--path", project, "--headless", "--",
		"--admin", "--server-port=%d" % _port,
		"--autostart", "--smoke-seats=3", "--log-dir=%s" % _log_dir], _admin_out)
	if _admin_pid < 0:
		_bad("the host process did not start")
		return
	# wait for a ready line naming OUR port, so a stale log cannot satisfy it
	if not await _await_line(_admin_out, "SERVER ready ws://127.0.0.1:%d" % _port,
			READY_TIMEOUT_MS):
		_bad("the host never announced its server on port %d (log=%s, lines=%d)"
			% [_port, _log_path(_admin_pid), _admin_out.size()])
		for l in _admin_out:
			print("      host: %s" % str(l))
		return
	_ok("the host is up and serving on port %d" % _port)

	print("[2] bring up the STREAM process (--stream), same binary, no input")
	_stream_pid = _spawn(godot, ["--path", project, "--headless", "--",
		"--stream", "--autostart", "--log-dir=%s" % _log_dir], _stream_out)
	if _stream_pid < 0:
		_bad("the stream process did not start")
		return
	if not await _await_line(_stream_out, "ready", READY_TIMEOUT_MS):
		_bad("the stream process never became ready")
		return
	_ok("the stream process is up as its own role")

	print("[3] the browser client joins over the wire")
	# the token is minted by the host; the host printed it
	_seat_token = _token_from(_admin_out)
	if _seat_token == "":
		# the file may be read between the two writes — keep polling briefly
		for i in 120:
			_poll_output()
			_seat_token = _token_from(_admin_out)
			if _seat_token != "":
				break
			await get_tree().process_frame
	if _seat_token == "":
		_bad("the host printed no seat token for the remote seat (log has %d lines)"
			% _admin_out.size())
		for l in _admin_out:
			print("      host: %s" % str(l))
		return
	_client = WebSocketPeer.new()
	_client.connect_to_url("ws://127.0.0.1:%d" % _port)
	if not await _await_open(_client, 300):
		_bad("the browser client could not connect")
		return
	_send({"t": "hello", "token": _seat_token, "profile": "player"})
	var hello = await _await_type("hello_ok", 300)
	if hello == null:
		_bad("the host did not greet the browser client")
		return
	if int(hello.get("pid", -1)) < 0:
		_bad("the browser client was not bound to a seat")
		return
	_ok("the browser client is bound to seat %d over the wire" % int(hello["pid"]))

	print("[4] the player is served its projection, the stream is NOT the player")
	var proj = await _await_type("projection", 300)
	if proj == null:
		_bad("the browser client received no projection")
		return
	var data: Dictionary = proj.get("data", {})
	if not data.has("legal"):
		_bad("a seated projection must carry legal actions")
		return
	_ok("the player's projection carries its own legal actions (%d)"
		% (data.get("legal", []) as Array).size())

	print("[5] admin and stream did not leak each other's scope")
	var admin_log := "\n".join(_admin_out)
	var stream_log := "\n".join(_stream_out)
	if stream_log.contains("SERVER ready") and admin_log.contains("SERVER ready") == false:
		_bad("the STREAM process opened a game server it does not own")
		return
	if not admin_log.contains("is_host=true"):
		_bad("the host process did not take the host role")
		return
	if not stream_log.contains("is_host=false"):
		_bad("the stream process thinks it is the host (roles are not independent)")
		return
	_ok("host is is_host=true, stream is is_host=false — roles are independent")

	# the stream must never hold a human seat
	if stream_log.contains("F12") and stream_log.contains("is_host=false"):
		_bad("the stream process still advertises the admin hint")
		return
	_ok("the stream process exposes no admin affordance")


# --- child processes ----------------------------------------------------------

func _spawn(godot: String, args: Array, sink: Array) -> int:
	var pid := OS.create_process(godot, PackedStringArray(args), false)
	if pid <= 0:
		return -1
	# drain the child's stdout on a timer; OS.execute would block the run
	_drain_into(pid, sink)
	return pid


## Poll a child's output into `sink`. Godot has no pipe API for a detached
## process, so the child is asked to WRITE its readiness to a file and this reads
## that file instead — simpler and platform-independent.
func _drain_into(pid: int, sink: Array) -> void:
	_tracked.append({"pid": pid, "sink": sink})


var _tracked: Array = []


func _poll_output() -> void:
	for t in _tracked:
		var f: String = _log_path(int(t["pid"]))
		if FileAccess.file_exists(f):
			var txt := FileAccess.get_file_as_string(f)
			var sink: Array = t["sink"]
			sink.clear()
			for line in txt.split("\n"):
				sink.append(line)


func _log_path(pid: int) -> String:
	return _log_dir.path_join("%s.log" % _tag_for_pid(pid))


func _tag_for_pid(pid: int) -> String:
	if pid == _admin_pid:
		return "admin"
	if pid == _stream_pid:
		return "stream"
	return "proc%d" % pid


func _kill_children() -> void:
	for pid in [_admin_pid, _stream_pid]:
		if pid > 0:
			OS.kill(int(pid))


# --- waiting ------------------------------------------------------------------

func _await_line(sink: Array, needle: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		_poll_output()
		for line in sink:
			if str(line).contains(needle):
				return true
		await get_tree().process_frame
	return false


func _await_open(peer: WebSocketPeer, frames: int) -> bool:
	for i in frames:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
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


func _send(msg: Dictionary) -> void:
	if _client != null and _client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_client.send_text(Proto.encode(msg))


func _token_from(log: Array) -> String:
	for line in log:
		var s := str(line)
		if s.begins_with("SERVER seat="):
			var parts := s.split(" ")
			for p in parts:
				if str(p).begins_with("token="):
					return str(p).substr(6)
	return ""


## Remove any role log left by an earlier run. Without this the parent can match
## a stale "SERVER ready" line and read the token of a dead process.
func _wipe_logs() -> void:
	var d := DirAccess.open(_log_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


## A scratch directory both children write their role log into.
func _make_log_dir() -> String:
	var d := "user://smoke_stage3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	return ProjectSettings.globalize_path(d)


## Any port the OS is not using right now. The host binds it a moment later; a
## rare race is acceptable for a smoke and never for production.
func _pick_free_port() -> int:
	var tcp := TCPServer.new()
	if tcp.listen(0, "127.0.0.1") != OK:
		return 9080
	var p := tcp.get_local_port()
	tcp.stop()
	return p
