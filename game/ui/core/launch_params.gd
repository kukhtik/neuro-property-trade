class_name LaunchParams
extends RefCounted
## Where a running instance learns how it was launched.
##
## WHY: a web build has NO command line and no environment, so the browser needs
## another way to be told which seat it owns and where the host is. The page URL
## carries it (`?seat=<token>&host=ws://...`), and this reads it.
##
## Every lookup degrades to "" rather than failing, and on desktop it reads the
## CLI so the SAME code path works in both worlds — that is what lets the smoke
## drive a native process and a browser identically.

const KEY_SEAT := "seat"
const KEY_HOST := "host"
const KEY_NAME := "name"


## One parameter by name: URL query in a browser, `--<name>=<value>` on desktop.
static func get_value(key: String) -> String:
	var v := _from_url(key)
	if v != "":
		return v
	return _from_cli(key)


static func seat_token() -> String:
	return get_value(KEY_SEAT)


static func host_url() -> String:
	return _normalise_host(get_value(KEY_HOST))


## Complete a bare `host:port` into a websocket URL; leave an explicit scheme
## alone. Split out so it is testable without any configuration present.
static func _normalise_host(v: String) -> String:
	if v == "":
		return ""
	if not v.begins_with("ws://") and not v.begins_with("wss://"):
		v = "ws://" + v
	return v


static func display_name() -> String:
	return get_value(KEY_NAME)


## True when this instance was given a seat to claim.
static func has_seat() -> bool:
	return seat_token() != "" and host_url() != ""


# --- sources ------------------------------------------------------------------

## The URL query, read through JavaScriptBridge. Empty on desktop.
static func _from_url(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	if not ClassDB.class_exists("JavaScriptBridge"):
		return ""
	var js := JavaScriptBridge
	var raw: Variant = js.eval("""
		(function () {
			try {
				var p = new URLSearchParams(window.location.search);
				return p.get('%s') || '';
			} catch (e) { return ''; }
		})()
	""" % key)
	if raw == null:
		return ""
	return str(raw)


## `--<key>=<value>` from the user args, which is how a native run is told.
static func _from_cli(key: String) -> String:
	var prefix := "--%s=" % key
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with(prefix):
			return s.substr(prefix.length())
	return ""
