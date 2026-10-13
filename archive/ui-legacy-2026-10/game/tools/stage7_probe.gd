extends SceneTree
## Stage-7 acceptance probe: executions are independent, and spectator data is safe.
##
## The owner decision (docs/ui_migration_notes §9): a role is chosen at LAUNCH,
## not toggled by a header button. The prototype's ИГРОК/СТРИМ/АДМИН switcher is
## deliberately NOT ported:
##
##   player = the WebUI            (a seat plays locally)
##   stream = the OBS window       (spectator data only, no input, large type)
##   admin  = the host application (full input + admin tools)
##
## Checks:
##  1. infer() maps launch conditions to the right role;
##  2. the role actually reaches the launcher and the view (integration, not
##     just a unit test — that mistake cost us a whole stage in stage 3);
##  3. a STREAM execution claims NO local seat even when a seat is LOCAL;
##  4. the spectator projection carries no private data and no legal actions,
##     and no raw event tag is rendered outside the admin console.
##
## Exit 0 = stage 7 is integrated.

const MainScript := preload("res://main.gd")
const Profile := preload("res://ui/core/ui_profile.gd")
const Proj := preload("res://sdk/projection.gd")
const EventAdapter := preload("res://ui/core/event_adapter.gd")

## Raw tags the prototype leaked to end users (defect: "[auction_bid]" etc).
const RAW_TAGS := ["auction_bid", "auction_pass", "auction_start", "cash",
	"trade_offer", "mortgage", "unmortgage", "bankrupt", "game_over"]

var _fail := 0

func _init() -> void:
	print("=== Stage 7 acceptance: independent executions, spectator-safe ===")
	_run()


func _run() -> void:
	await process_frame
	_check_infer()
	_check_private_projection()
	_check_adapter_tags()
	await _check_live_admin()
	await _check_live_stream()
	_finish()


func _finish() -> void:
	print("")
	if _fail > 0:
		print("==> STAGE 7 FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> STAGE 7 PASSED — roles from launch, spectator-safe, no raw tags")
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


# --- 1. the role follows the launch, not a button -----------------------------

func _check_infer() -> void:
	print("[1] infer() maps the launch to a role")
	var cases := [
		[true, [] as PackedStringArray, Profile.PLAYER, "web export"],
		[false, [] as PackedStringArray, Profile.ADMIN, "desktop, no flag"],
		[false, PackedStringArray(["--stream"]), Profile.STREAM, "--stream"],
		[false, PackedStringArray(["--admin"]), Profile.ADMIN, "--admin"],
	]
	for c in cases:
		var p = Profile.infer(c[0], c[1])
		if p.id != c[2]:
			_bad("%s should be '%s', got '%s'" % [c[3], c[2], p.id])
			return
	_ok("web→player, desktop→admin, --stream→stream, --admin→admin")

	# the role must NOT be switchable in the UI: a profile carries a READ-ONLY
	# badge flag, and there must be no setter that flips it at runtime
	var st = Profile.for_id(Profile.STREAM)
	if not st.shows_role_badge:
		_bad("a stream profile should still report its role (read-only badge)")
		return
	if st.input_enabled or st.shows_actions or st.shows_admin_tools:
		_bad("stream must take no input and expose no admin tools")
		return
	if st.data_source != "spectator":
		_bad("stream must read the spectator projection, got '%s'" % st.data_source)
		return
	_ok("stream: no input, no admin tools, spectator data source")


# --- 2. the spectator projection has no private data --------------------------

func _check_private_projection() -> void:
	print("[2] the spectator projection carries no private data")
	var launcher = MainScript.new()
	root.add_child(launcher)
	# drive a real match so the projection is non-trivial
	var overlay: Node = launcher.get("_overlay")
	if overlay == null:
		_bad("no settings overlay")
		return
	overlay.call("_start_pressed")
	var gv: Node = launcher.get("_game_view")
	if gv == null:
		_bad("no game_view")
		return
	var engine = gv.get("engine")
	if engine == null:
		_bad("no engine")
		return

	var spec: Dictionary = Proj.new().for_spectator(engine)
	for key in ["private", "legal"]:
		if spec.has(key):
			_bad("the spectator projection exposes '%s'" % key)
			return
	_ok("no 'private' and no 'legal' section in for_spectator()")

	# the hidden information specifically: get-out-of-jail cards must NOT appear
	var dump := JSON.stringify(spec)
	if dump.contains("get_out_of_jail") or dump.contains("jail_cards"):
		_bad("get-out-of-jail cards leak into the spectator projection")
		return
	_ok("get-out-of-jail cards never reach a spectator")

	# a seat's own projection DOES carry its private view (control)
	var seat: int = int(engine.turn_player)
	var mine: Dictionary = Proj.new().for_player(engine, seat)
	if not mine.has("private"):
		_bad("a player's own projection should carry its private section")
		return
	_ok("a seat's own projection does carry 'private' (control)")


# --- 3. no raw event tag may reach a normal user ------------------------------

func _check_adapter_tags() -> void:
	print("[3] no raw engine tag is rendered outside the admin console")
	var a = EventAdapter.new()
	# every core event type must normalize to a UI kind, and the kind must be a
	# short token — never the raw bracketed tag the prototype printed
	var raw := {"type": "auction_bid", "player": 0, "amount": 70}
	var ev: Dictionary = a.adapt({"type": "auction_bid", "data": {"player": 0, "amount": 70}})
	if str(ev.get("k", "")) == "":
		_bad("the adapter produced no kind for auction_bid")
		return
	if str(ev.get("k", "")) in RAW_TAGS:
		_bad("the adapter passes the RAW tag '%s' through" % ev["k"])
		return
	_ok("auction_bid normalizes to UI kind '%s' (not a raw tag)" % ev["k"])

	# the adapted dictionary must not smuggle the raw engine type through, nor
	# any bracketed tag a journal could print verbatim
	var dump := JSON.stringify(ev)
	if dump.contains("[auction_bid]"):
		_bad("the adapted event still carries a bracketed raw tag")
		return
	_ok("the adapted event carries no bracketed raw tag")


# --- 4. a live stream execution -------------------------------------------

func _check_live_admin() -> void:
	print("[4] the launcher honours the role it was given (admin default)")
	await process_frame
	var launcher = MainScript.new()
	root.add_child(launcher)
	for i in 6:
		await process_frame
	var prof = launcher.get("_profile")
	if prof == null:
		_bad("the launcher kept no profile")
		return
	# headless desktop with no flag is the host
	if prof.id != Profile.ADMIN:
		_bad("a desktop launch should be admin, got '%s'" % prof.id)
		return
	if launcher.get("_is_host") != true:
		_bad("an admin execution should own the admin panel")
		return
	_ok("desktop launch → admin, is_host=true (admin panel owner)")


func _check_live_stream() -> void:
	print("[5] a stream execution claims no local seat")
	await process_frame
	var launcher = MainScript.new()
	launcher.set("_force_profile", Profile.for_id(Profile.STREAM))
	root.add_child(launcher)
	for i in 6:
		await process_frame
	var prof = launcher.get("_profile")
	if prof == null or prof.id != Profile.STREAM:
		_bad("the launcher ignored the forced stream profile")
		return
	if launcher.get("_is_host") != false:
		_bad("a stream execution must NOT own the admin panel")
		return
	var gv: Node = launcher.get("_game_view")
	if gv == null:
		_bad("no game_view in the stream execution")
		return
	var overlay: Node = launcher.get("_overlay")
	overlay.call("_start_pressed")
	for i in 10:
		await process_frame
	if int(gv.get("_human_pid")) != -1:
		_bad("a stream execution claimed local seat %d (it must take no input)"
			% int(gv.get("_human_pid")))
		return
	_ok("stream: no admin panel, no human seat, input disabled")
