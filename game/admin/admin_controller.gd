extends RefCounted
## Phase 4 admin policy layer (pure, headless-testable). Wraps
## engine.admin_override plus seat-level housekeeping. A future full panel or
## token-guarded remote panel is a thin consumer of this class.

var engine
var seats: Array = []

func setup(eng, seat_list: Array = []) -> void:
	engine = eng
	seats = seat_list

## Forward an admin state-edit / unblocking intent to the authoritative engine.
func override(op: String, params: Dictionary) -> Dictionary:
	return engine.admin_override(op, params)

## Seat flag (not engine state — lives on the Seat objects in the manager).
func reset_seat_away(pid: int) -> Dictionary:
	for s in seats:
		if s.pid == pid:
			s.away = false
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "no seat with pid %d" % pid}

## Flattened live state table for diagnostics (spec §4.C).
func dump_state() -> Dictionary:
	var players_d: Array = []
	for i in engine.player_count():
		var p = engine.player(i)
		players_d.append({
			"pid": i,
			"name": p.name,
			"money": p.money,
			"position": p.position,
			"in_jail": p.in_jail,
			"bankrupt": p.bankrupt,
			"tiles": p.owned_tiles(),
			"away": _seat_away(i),
		})
	return {"phase": engine.phase, "turn_player": engine.turn_player, "players": players_d}

## Event list, optionally filtered by type. spec §4.C diagnostics.
func list_events(type_filter: String = "") -> Array:
	var entries: Array = engine.log.entries()
	if type_filter == "":
		return entries
	var out: Array = []
	for entry in entries:
		if str(entry.get("type", "")) == type_filter:
			out.append(entry)
	return out

func _seat_away(pid: int) -> bool:
	for s in seats:
		if s.pid == pid:
			return s.away
	return false
