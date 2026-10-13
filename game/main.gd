extends Node
## Entry point / single launcher (v2 one-screen). Builds GameView immediately
## (the board is always the root visual layer). The engine is created lazily on
## START. The SettingsOverlay (ex-lobby) opens on first run and via ⚙/F1.
## F12 toggles the host-local admin panel (engine-authoritative, token-guarded);
## on WebGL / --spectator the panel is NOT created at all (is_host gate).

const EngineScript := preload("res://core/engine.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
const LaunchParams := preload("res://ui/core/launch_params.gd")
const RemoteSession := preload("res://ui/remote_session.gd")
const GameServer := preload("res://server/game_server.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")
const AdminController := preload("res://admin/admin_controller.gd")
const AdminGate := preload("res://admin/admin_gate.gd")
const AdminPanel := preload("res://admin/admin_panel.gd")
const SettingsOverlay := preload("res://ui/settings_overlay.gd")
const GameView := preload("res://ui/game_view.gd")
# v3 swap: JoinLobby / HostInvite / PerfOverlay were archived with the old interface.
const SkinManager := preload("res://visual/skin_manager.gd")

var _engine
var _manager
var _controller
var _gate
var _panel
var _game_view
var _overlay
var _is_host := true
## kept so the view can be rebuilt (a skin change re-creates it) without losing the match
var _seats_cache: Array = []
var _settings_cache = null
var _profile
## Test/embedding hook: force the role instead of inferring it from argv. Must be
## set BEFORE the node enters the tree (i.e. before _ready).
var _force_profile = null
var _game_started := false
## The network host for REMOTE seats. Started only when a match actually has one
## (or when the port is requested explicitly), so a normal local game opens no
## socket. The token for each remote seat is printed to stdout on start, which is
## how a browser — or the smoke — learns where to connect.
var _server
var _server_port := 0
var _seat_tokens := {}   # pid -> token
var _join_lobby = null    # the screen a friend sees while joining
var _host_invite = null   # the invitation screen the host sees after creating a match
## Test/embedding hook: a fixed port instead of an ephemeral one.
var _force_port := 0
## Set when this instance joined a match over the wire instead of owning one.
var _remote_session

func _ready() -> void:
	# set window size for the playable shell (1440x900 gives the board room to
	# render larger, more readable tiles; the layout adapts to any size)
	var vp = get_viewport()
	if vp != null:
		DisplayServer.window_set_size(Vector2i(1440, 900))

	# The execution role is chosen at LAUNCH, never toggled in the UI
	# (docs/ui_migration_notes §9). UiProfile is the single source of that.
	#   --admin   : the host application (admin tools available; default on desktop)
	#   --stream  : the OBS window (spectator data, no input, large type)
	#   web       : the player WebUI
	_profile = _force_profile if _force_profile != null 		else UiProfileScript.infer(OS.has_feature("web"), OS.get_cmdline_user_args())
	_is_host = _profile.shows_admin_tools

	# the seat palette follows the skin from the first frame (P-2): seed the
	# identity colours before any seat or token is built
	SkinManager.sync_identity_palette()

	# one screen: build the game view immediately (cold board, no engine yet)
	_game_view = GameView.new()
	add_child(_game_view)
	_game_view.set_profile(_profile)
	_game_view.setup_cold(self)
	_game_view.restart_requested.connect(_on_restart_requested)
	_game_view.settings_requested.connect(_open_overlay)
	_game_view.skin_requested.connect(_on_skin_requested)

	# settings overlay (ex-lobby) opens on first run, pre-game mode. It lives
	# on its own top CanvasLayer (layer 50) so it is cleanly separated from the
	# GameView tree — no white-frame/collapse artifacts from being a sibling of
	# the board (P6 Phase 3).
	var _overlay_layer := CanvasLayer.new()
	_overlay_layer.name = "OverlayLayer"
	_overlay_layer.layer = 50
	add_child(_overlay_layer)
	_overlay = SettingsOverlay.new()
	_overlay_layer.add_child(_overlay)
	_overlay.set_mode(true)
	_overlay.started.connect(_on_started)
	_overlay.apply_requested.connect(_on_apply)
	_overlay.closed.connect(_on_overlay_closed)

	# host-only admin panel (created only when is_host)
	if _is_host:
		_panel = AdminPanel.new()
		_panel.name = "AdminPanel"
		add_child(_panel)
		_panel.visible = false
		_panel.game_rebuilt.connect(_on_admin_rebuilt)

	print("Neuro Property Trade — ready. is_host=%s" % str(_is_host))
	_mirror_log("ready is_host=%s" % str(_is_host))

	# --autostart: build a match immediately, no lobby click. Used by the smoke so
	# a role can be exercised without a human at the keyboard.
	if _has_cli_flag("--autostart"):
		call_deferred("_autostart")
	# A seat was handed to us (by the page URL or the CLI): join the host's match
	# over the wire rather than playing a local one.
	if LaunchParams.has_seat():
		# v3 swap: the join lobby went to the archive with the old interface; the seat link is
		# still parseable but the screen for it is yet to be rebuilt.
		push_warning("join-by-link is not wired in the v3 interface yet")
	# --perf: the perf overlay went to the archive with the old interface (its replacement
	# comes with the v3 pass).
	# --server-port=<n>: bind the game server on a FIXED port (0 = ephemeral)
	var port := _cli_value("--server-port=")
	if port != "":
		_force_port = int(port)


## The directory this process's logs go to: --log-dir=<dir>, else user://. The role log and
## perf.log share it, so one directory holds one run.
func _log_dir() -> String:
	var dir: String = _cli_value("--log-dir=")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	return dir


## Append a line to this process's role log so a parent can observe it.
func _mirror_log(line: String) -> void:
	var role := "player"
	if _profile != null:
		role = str(_profile.id)
	# an ABSOLUTE path, optionally redirected by --log-dir, so a parent process
	# (the smoke) can read a detached child's readiness
	var dir: String = _log_dir()
	var path := dir.path_join("%s.log" % role)
	if not FileAccess.file_exists(path):
		# touch it first: READ_WRITE will not create a missing file
		var c := FileAccess.open(path, FileAccess.WRITE)
		if c != null:
			c.close()
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()


## Mirror the engine's event counter so another process can see progress. Called
## on every manager tick while a server is running.
func _mirror_events(_spec: Dictionary = {}) -> void:
	if _engine == null:
		return
	_rewrite_counter("EVENTS", str(int(_engine.log.size())))


## Replace the single "<tag> <value>" line in this process's role log. Used for a
## value that updates constantly, which must not grow the file.
func _rewrite_counter(tag: String, value: String) -> void:
	var role := "player"
	if _profile != null:
		role = str(_profile.id)
	var dir: String = _log_dir()
	var path := dir.path_join("%s.log" % role)
	var kept: Array = []
	if FileAccess.file_exists(path):
		# split on the CHARACTER \n, not an escaped one: the file may use CRLF
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var s := str(line).strip_edges()
			if s != "" and not s.begins_with(tag + " "):
				kept.append(s)
	kept.append("%s %s" % [tag, value])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		for line in kept:
			f.store_line(str(line))
		f.close()


## Join a running match as a REMOTE seat. The host owns the engine; this instance
## only renders and sends intents, so it needs no local engine at all.
func _join_as_remote() -> void:
	var url := LaunchParams.host_url()
	var tok := LaunchParams.seat_token()
	print("JOIN host=%s seat=%s..." % [url, tok.substr(0, 6)])
	_mirror_log("JOIN host=%s seat=%s" % [url, tok.substr(0, 6)])
	_remote_session = RemoteSession.new()
	_remote_session.name = "RemoteSession"
	add_child(_remote_session)
	_remote_session.joined.connect(_on_remote_joined)
	_remote_session.event_received.connect(_on_remote_event)
	_remote_session.state_received.connect(_on_remote_state)
	_remote_session.verdict_received.connect(_on_remote_verdict)
	_remote_session.connection_lost.connect(_on_remote_lost)
	_remote_session.verbose = _has_cli_flag("--verbose-join")
	_remote_session.join(url, tok)


## The host accepted this seat. Logged so a probe (or a player) can see it happened.
func _on_remote_joined(pid: int) -> void:
	print("JOINED pid=%d" % pid)
	_mirror_log("JOINED pid=%d" % pid)


## The host pushed the state. When this seat is the one being asked, answer — that is
## the whole job of a client: the host decides, the player only chooses from what it is
## offered.
func _on_remote_state(proj: Dictionary) -> void:
	# paint first: this client has no engine, so the wire is its only source of truth
	if _game_view != null and _game_view.has_method("apply_projection"):
		_game_view.apply_projection(proj)
	var legal: Array = proj.get("legal", [])
	# Nothing to answer: either the seat is simply not the one being asked, or the host is gone.
	# This path used to write an IDLE line per idle state — hundreds of lines per match, and both
	# cases read the same. The connection state tells them apart (a lost host logs DISCONNECTED),
	# so the idle case stays silent.
	if legal.is_empty():
		return
	var action := str(legal[0])
	var params := {}
	# a bid and a tile-addressed action need parameters, which come from the state
	var pending: Dictionary = proj.get("pending", {})
	match action:
		"bid":
			params = {"amount": int(pending.get("high", 0)) + 5}
		"buy", "pass":
			pass
	_remote_session.act(action, params)
	print("PLAYED action=%s params=%s" % [action, str(params)])
	_mirror_log("PLAYED action=%s" % action)


func _on_remote_verdict(id: String, ok: bool, reason: String) -> void:
	print("VERDICT %s ok=%s reason=%s" % [id, str(ok), reason])
	_mirror_log("VERDICT %s ok=%s reason=%s" % [id, str(ok), reason])


func _on_remote_lost() -> void:
	print("DISCONNECTED from the host")
	_mirror_log("DISCONNECTED")


func _cli_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(prefix):
			return str(a).substr(prefix.length())
	return ""


## Build a default match without the lobby. Deliberately minimal: the smoke wants
## a running engine, not a curated one.
func _autostart() -> void:
	var st = SettingsScript.new()
	# --smoke-seats=N: the fixture the full smoke drives — a host seat, a REMOTE
	# seat for the browser, and AI for the rest.
	var n := int(_cli_value("--smoke-seats="))
	if n >= 2:
		st.seat_count = n
		st.starting_order = "manual"
		# `--smoke-seats=N` used to make exactly ONE remote seat and fill the rest with bots, which
		# is what the browser smoke needed. A host inviting friends needs N-1 remote seats, so
		# `--remote-seats=` says how many; without it the old shape is kept so the smoke fixtures
		# and their recorded expectations do not move.
		var remote := int(_cli_value("--remote-seats="))
		var a: Array = [{"driver": "LOCAL", "name": "Host"}]
		if remote <= 0:
			a.append({"driver": "REMOTE", "name": "Browser"})
			remote = 1
		else:
			for i in remote:
				a.append({"driver": "REMOTE", "name": "Player %d" % (i + 2)})
		while a.size() < n:
			a.append({"driver": "AI", "name": "Bot %d" % (a.size() + 1)})
		st.seat_assignments = a
	# a smoke must be REPRODUCIBLE: without this every run played a different match
	var seed_arg := _cli_value("--smoke-seed=")
	if seed_arg != "":
		st.rng_seed = int(seed_arg)
	# --round-limit=N closes the match at a finite round count (0 = off). Needed for a full-cycle
	# run, because without it a match can be unbounded — no colour group, no houses, the bank pays
	# out and nobody can go bankrupt. 60 covers every healthy match (measured: 19-45 rounds).
	var lim := _cli_value("--round-limit=")
	if lim != "":
		st.round_limit = int(lim)
	var seats: Array = SeatConfigScript.from_settings(st)
	var names: Array = []
	for s in seats:
		names.append(str(s.name))
	_build_game(st, seats)
	# STARTING A MATCH MUST MEAN THE SAME THING ON BOTH PATHS.
	#
	# `_on_started` (the button) hides the settings overlay and tells the view the game began.
	# `_autostart` did neither, so every probe and every smoke frame taken through it photographed
	# the screen with the SETTINGS MENU still open over the board — the centre of the frame was a
	# settings dialog, and metrics were read from it. Found by the owner, not by me: the suite was
	# green because the assertions looked at colours that happen to sit outside the dialog.
	_overlay.visible = false
	_game_started = true
	_game_view.on_game_started()

func _has_cli_flag(flag: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == flag:
			return true
	return false

## Pre-game START: build engine + seats + manager, then start the game.
func _on_started(settings, seats: Array) -> void:
	_build_game(settings, seats)
	_overlay.visible = false
	_game_started = true
	_game_view.on_game_started()

## In-game restart (ПРИМЕНИТЬ): rebuild the engine with a new seed.
func _on_apply(settings, seats: Array) -> void:
	_build_game(settings, seats)
	_overlay.visible = false
	_game_started = true
	_game_view.on_game_started()

func _build_game(settings, seats: Array) -> void:
	# tear down any previous engine/manager
	if _manager != null and is_instance_valid(_manager):
		_manager.queue_free()
	# the engine is a RefCounted (not a Node) — dropping the reference lets GC
	# reclaim it; do NOT call .free() on it.
	_engine = null

	_engine = EngineScript.new()
	var names: Array = []
	for s in seats:
		names.append(str(s.name))
	_engine.setup(settings, names)

	_manager = SeatManager.new()
	_manager.name = "SeatManager"
	add_child(_manager)
	_manager.setup(_engine, seats)

	# admin (host-local, token-guarded) wired after seats exist
	_controller = AdminController.new()
	_controller.setup(_engine, seats)
	_gate = AdminGate.new()
	_gate.setup(_controller, settings.admin_token)
	if _panel != null:
		_panel.setup(_gate)
		_panel.visible = false

	_seats_cache = seats
	_settings_cache = settings
	_start_server_if_needed(seats)

	_game_view.setup(_engine, _manager, seats, settings)
	# game-over banner: seat_manager emits game_over when the engine reaches END_GAME
	if _manager.game_over.is_connected(_on_game_over):
		_manager.game_over.disconnect(_on_game_over)
	_manager.game_over.connect(_on_game_over)
	# --smoke-drive: let the host play its own LOCAL seats so an automated run can get past
	# turn one.
	#
	# THIS MUST NOT DEPEND ON `_server`. It used to sit inside `if _server != null`, so an
	# offline autostart never enabled auto-play: the engine was built, the board was placed,
	# and the match then sat at player 0 forever. Every screenshot of the offline app was of a
	# game that had not started — which is why the board looked empty while its data was
	# complete. Remote seats are still left to the wire unless proxy play is asked for.
	if _has_cli_flag("--smoke-drive"):
		_manager.set_autoplay_local(true)
		_manager.set_proxy_remote(_cli_value("--proxy-remote=") == "1")
	if _server != null:
		# a remote player's progress has to be observable from its own process
		if not _manager.state_changed.is_connected(_mirror_events):
			_manager.state_changed.connect(_mirror_events)

## Bring up the network host when the match has a REMOTE seat (or when a port
## was forced for testing). Prints the connection line a browser/ smoke reads.
func _start_server_if_needed(seats: Array) -> void:
	if _server != null and is_instance_valid(_server):
		_server.queue_free()
		_server = null
	_seat_tokens.clear()
	var wants := _force_port > 0
	var remote_pids: Array = []
	for s in seats:
		if str(s.input_driver) == "REMOTE":
			remote_pids.append(int(s.pid))
			wants = true
	if not wants:
		return
	_server = GameServer.new()
	_server.name = "GameServer"
	add_child(_server)
	# A LAN GAME NEEDS A REACHABLE BIND. This was hardcoded to the loopback address, so the host
	# could only ever serve itself — fine for the smoke, useless for playing with other people.
	# `--server-bind=` opens it up (`0.0.0.0`); the default stays loopback so nothing on a shared
	# network is exposed unless asked for.
	var bind := _cli_value("--server-bind=")
	if bind == "":
		bind = "127.0.0.1"
	if not _server.listen(_force_port, bind):
		push_error("main: the game server failed to bind")
		_server = null
		return
	_server.bind_game(_engine, _manager)
	# A friend who opens an invitation must TAKE the seat, not share it: without this the host's
	# proxy keeps answering for the same place, so the friend's moves are accepted and then
	# overwritten a tick later. `set_proxy_remote(false)` is not enough per-seat, so the host drops
	# the whole proxy the moment one client identifies itself.
	_server.seat_claimed.connect(_on_seat_claimed)
	_server_port = int(_server.port())
	for pid in remote_pids:
		var tok: String = _server.mint_token(int(pid))
		_seat_tokens[int(pid)] = tok
		print("SERVER seat=%d token=%s" % [int(pid), tok])
		_mirror_log("SERVER seat=%d token=%s" % [int(pid), tok])
	var shown := bind
	if shown == "0.0.0.0" or shown == "*":
		shown = _lan_address()
	print("SERVER ready ws://%s:%d" % [shown, _server_port])
	_mirror_log("SERVER ready ws://%s:%d" % [shown, _server_port])


## Connection details for tests and tooling.
func server_port() -> int:
	return _server_port


func seat_token(pid: int) -> String:
	return str(_seat_tokens.get(int(pid), ""))


func _on_game_over(winner_name: String) -> void:
	_game_view.show_game_over(winner_name)

## P4: admin snapshot load — the panel hot-swapped the engine in the
## controller; re-wire the seat manager + game view to the restored engine.
func _on_admin_rebuilt(eng) -> void:
	_engine = eng
	if _manager != null and is_instance_valid(_manager):
		_manager.queue_free()
	_manager = SeatManager.new()
	_manager.name = "SeatManager"
	add_child(_manager)
	_manager.setup(_engine, _controller.seats)
	_game_view.setup(_engine, _manager, _controller.seats, _engine.settings)
	if _manager.game_over.is_connected(_on_game_over):
		_manager.game_over.disconnect(_on_game_over)
	_manager.game_over.connect(_on_game_over)
	if _server != null:
		# a remote player's progress has to be observable from its own process
		if not _manager.state_changed.is_connected(_mirror_events):
			_manager.state_changed.connect(_mirror_events)
		# --smoke-drive: let the host play its own LOCAL seats so an automated run
		# can get past turn one. REMOTE seats are left waiting for their player — a
		# probe that TESTS the wire needs exactly that, or the host would answer
		# before the client ever sees the question.
		if _has_cli_flag("--smoke-drive"):
			_manager.set_autoplay_local(true)
			_manager.set_proxy_remote(_cli_value("--proxy-remote=") == "1")

func _on_overlay_closed() -> void:
	# ESC closes the overlay without starting: the board stays "cold" with a
	# single START button in the action panel.
	_overlay.visible = false
	_game_view.on_overlay_closed()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			if _panel != null:
				_panel.visible = not _panel.visible
				if _panel.visible:
					_panel.move_to_front()
		elif event.keycode == KEY_F1:
			_open_overlay()
		elif event.keycode == KEY_ESCAPE:
			if _overlay.visible:
				_on_overlay_closed()

func _open_overlay() -> void:
	_overlay.set_mode(not _game_started)
	_overlay.visible = true
	_overlay.move_to_front()

## Game-over "РЕВАНШ" or TopBar "↻": reopen the settings overlay in apply mode
## so the host can restart with a new seed.
func _on_restart_requested() -> void:
	_open_overlay()


## THE SKIN SWITCH. A widget's colours are decided when it is built (`UiTheme.box(skin.color(...))`,
## `_init` fetching tokens), so nothing already on screen can be repainted — changing the skin
## means building the view again. The engine and the seat manager live on THIS node, not on the
## view, so the match survives the rebuild: `setup()` is handed the same objects back.
func _on_skin_requested(skin_id: String) -> void:
	if skin_id == "" or skin_id == SkinManager.chosen:
		return
	# `available()` is an instance method (it lists what is on disk), so ask a throwaway one.
	if not SkinManager.new().available().has(skin_id):
		return
	SkinManager.chosen = skin_id
	# the palette follows the skin; seats that never got an explicit pick recolour
	# with it (custom picks stay — they are the seat's own colour, not the palette's)
	SkinManager.sync_identity_palette()
	for s in _seats_cache:
		if not s.color_custom:
			s.color = SkinManager.PI.color_of(int(s.pid))
	var old = _game_view
	_game_view = GameView.new()
	add_child(_game_view)
	_game_view.set_profile(_profile)
	_game_view.setup_cold(self)
	_game_view.restart_requested.connect(_on_restart_requested)
	_game_view.settings_requested.connect(_open_overlay)
	_game_view.skin_requested.connect(_on_skin_requested)
	if _overlay != null and _overlay.has_signal("host_invite_requested"):
		_overlay.host_invite_requested.connect(_on_host_invite)
	if old != null and is_instance_valid(old):
		old.queue_free()
	if _engine != null and _settings_cache != null:
		_game_view.setup(_engine, _manager, _seats_cache, _settings_cache)
		_game_view.on_game_started()


## The address another machine should use to reach this host. `0.0.0.0` is a bind instruction,
## not an address anyone can connect TO, so the host prints a real LAN address instead of the one
## it happens to be listening on.
func _lan_address() -> String:
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.begins_with("127.") or s.contains(":"):
			continue
		if s.begins_with("169.254."):
			continue   # link-local: not routable
		return s
	return "127.0.0.1"


## Show the join screen for a seat handed to us by an invitation link…
## v3 swap: archived with the old interface — rebuilt after the shell.
func _open_join_lobby() -> void:
	push_warning("_open_join_lobby: the v3 join screen is not built yet")


func _on_lobby_joined(pid: int) -> void:
	print("JOINED pid=%d" % pid)
	_mirror_log("JOINED pid=%d" % pid)
	# the lobby's session becomes the game's: hand it over instead of opening a second one
	if _join_lobby != null and is_instance_valid(_join_lobby):
		var sess = _join_lobby.get("_session")
		if sess != null and is_instance_valid(sess):
			_remote_session = sess
			sess.event_received.connect(_on_remote_event)
			sess.state_received.connect(_on_remote_state)
			sess.verdict_received.connect(_on_remote_verdict)
			sess.connection_lost.connect(_on_remote_lost)
			_join_lobby.remove_child(sess)
			add_child(sess)
		_join_lobby.queue_free()
		_join_lobby = null
	if _game_view != null:
		_game_view.on_game_started()


func _on_lobby_gave_up(_reason: String) -> void:
	pass   # the lobby keeps showing the problem and a retry button


## "Создать партию для друзей" — v3 swap: archived with the old interface, rebuilt later.
func _on_host_invite() -> void:
	push_warning("host invite: the v3 invite screen is not built yet")


## The invitation screen, filled from what the server actually bound.
## v3 swap: archived with the old interface.
func _show_invite() -> void:
	push_warning("_show_invite: the v3 invite screen is not built yet")


func _add_perf_overlay() -> void:
	push_warning("_add_perf_overlay: the v3 perf overlay is not built yet")


## A real client identified itself with a valid seat token. Hand the seat over: the host stops
## proxying REMOTE seats so the friend's own intents are the ones executed.
func _on_seat_claimed(pid: int) -> void:
	if _manager == null:
		return
	_manager.set_proxy_remote(false)
	print("SEAT CLAIMED pid=%d — host no longer plays it" % pid)
	_mirror_log("SEAT_CLAIMED pid=%d" % pid)


## An engine event arrived over the wire. `winner` is the one that matters: it is the only way a
## client — which has no engine of its own — can learn the match ended and who won it.
func _on_remote_event(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	var kind := str(ev.get("type", ev.get("k", "")))
	var data: Dictionary = ev.get("data", {})
	if kind != "winner" and kind != "round_limit":
		return
	var who := str(data.get("name", ""))
	if who == "":
		who = str(data.get("player", "?"))
	print("EVENT %s winner=%s" % [kind, who])
	_mirror_log("EVENT %s winner=%s" % [kind, who])
	if _game_view != null and _game_view.has_method("show_game_over"):
		_game_view.show_game_over(who)
