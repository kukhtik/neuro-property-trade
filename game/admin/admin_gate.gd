extends RefCounted
## Token-guarded admin gate (spec §4 "later possible" — built 2026-09-06).
##
## Establishes the remote-admin authentication invariant BEFORE any network
## transport exists (REMOTE is post-MVP). A future remote panel authenticates
## with a token and calls through this gate; the host-local F12 panel can pass
## the token directly (or bypass via `allow_local`). Every authorized override
## still flows through engine.admin_override (engine-authoritative, same event
## log) — the gate only adds an auth layer, never engine logic.
##
## Pure + headless-testable: no scene tree, no network.

var _controller
var _token: String = ""

## controller = an admin_controller instance; token = the shared secret.
func setup(controller, token: String) -> void:
	_controller = controller
	_token = token

## True when the gate is configured with a non-empty token (i.e. auth is on).
func is_guarded() -> bool:
	return _token != ""

## Authorize a presented token. Constant-time-ish compare to avoid trivial
## timing leaks; empty presented token never matches a guarded gate.
func authorize(presented: String) -> bool:
	if not is_guarded():
		return true   # no token configured -> open (host-local default)
	if presented == "":
		return false
	return _constant_time_eq(presented, _token)

## Run an admin override through the gate. Returns the engine result on
## success, or a fail-closed {ok:false, reason:"unauthorized"} with no mutation.
func override(op: String, params: Dictionary, presented: String) -> Dictionary:
	if not authorize(presented):
		return {"ok": false, "reason": "unauthorized", "legal": [], "events": []}
	if _controller == null:
		return {"ok": false, "reason": "no controller", "legal": [], "events": []}
	return _controller.override(op, params)

## Seat-level housekeeping, also gated.
func reset_seat_away(pid: int, presented: String) -> Dictionary:
	if not authorize(presented):
		return {"ok": false, "reason": "unauthorized"}
	if _controller == null:
		return {"ok": false, "reason": "no controller"}
	return _controller.reset_seat_away(pid)

## Diagnostics are read-only and NOT gated (a remote panel may view state
## without a token; only mutations require auth).
func dump_state() -> Dictionary:
	if _controller == null:
		return {}
	return _controller.dump_state()

func list_events(type_filter: String = "") -> Array:
	if _controller == null:
		return []
	return _controller.list_events(type_filter)

## Constant-time string comparison (length-independent early-exit avoided).
static func _constant_time_eq(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	var diff := 0
	for i in a.length():
		diff |= (a.unicode_at(i) ^ b.unicode_at(i))
	return diff == 0
