class_name UiStore
extends RefCounted
## The UI ViewModel: pure data, no node or engine references.
##
## Built from the authoritative projection (`resync`) and mutated by deltas
## while the presenter animates (`apply_delta`). The projection is the truth —
## `resync` always wins, and the presenter calls it once its queue drains, so an
## animation can never leave the view out of sync with the engine.
##
## Emits `changed(keys)` so components repaint by diff instead of rebuilding.
## Pure + headless-testable.

signal changed(keys: PackedStringArray)

## The view model. Keys mirror the spec §3.1 schema, adapted to real projection
## field names (see docs/ui_migration_notes.md).
var vm := {
	"started": false,
	"over": null,            # null | winner id | -1
	"round": 1,
	"turn": 0,
	"phase": "SETUP",        # engine phase string (SETUP/TURN_START/...)
	"dice": [0, 0],
	"pot": 0,                # Free Parking jackpot (public)
	"tile_count": 0,
	"tiles": [],             # [{index,name,type,group,cost,owner,houses,mortgaged}]
	"players": [],           # [{id,name,money,pos,in_jail,bankrupt}]
	"legal": [],             # engine.legal_actions for the local seat
	"pending": {},           # purchase/auction/trade decision context
	"selected_tile": -1,
	"follow_player": -1,
}


## Full replacement from a projection dictionary. This is authoritative.
func resync(proj: Dictionary) -> void:
	vm["started"] = true
	vm["phase"] = str(proj.get("phase", "SETUP"))
	vm["turn"] = int(proj.get("turn_player", 0))
	vm["pot"] = int(proj.get("parking_pot", 0))
	vm["pending"] = proj.get("pending", {})
	vm["legal"] = proj.get("legal", [])

	var players: Array = []
	for p in proj.get("players", []):
		players.append({
			"id": int(p.get("index", -1)),
			"name": str(p.get("name", "")),
			"money": int(p.get("money", 0)),
			"pos": int(p.get("position", 0)),
			"in_jail": bool(p.get("in_jail", false)),
			"jail_turns": int(p.get("jail_turns", 0)),
			"bankrupt": bool(p.get("bankrupt", false)),
			"tiles": p.get("tiles", []),
			"houses": int(p.get("houses", 0)),
			"mortgaged": int(p.get("mortgaged", 0)),
		})
	vm["players"] = players

	var tiles: Array = []
	for t in proj.get("board", []):
		tiles.append({
			"index": int(t.get("index", -1)),
			"name": str(t.get("name", "")),
			"short": str(t.get("short", t.get("name", ""))),
			"type": str(t.get("type", "property")),
			"group": str(t.get("group", "")),
			"cost": int(t.get("cost", 0)),
			"owner": int(t.get("owner", -1)),
			"houses": int(t.get("houses", 0)),
			"mortgaged": bool(t.get("mortgaged", false)),
		})
	vm["tile_count"] = tiles.size()
	vm["tiles"] = tiles

	changed.emit(PackedStringArray([
		"started", "phase", "turn", "pot", "pending", "legal",
		"players", "tiles", "tile_count",
	]))


## Apply a batch of deltas produced by EventAdapter.
## Each delta is an array: [kind, arg1, arg2?].
##   ["c", pid, delta]   cash change
##   ["cb", pid, abs]    cash set to an absolute balance (engine-logged truth)
##   ["pos", pid, idx]   position
##   ["o", tile, pid]    owner (null to clear)
##   ["h", tile, n]      house count
##   ["m", tile, bool]   mortgaged
##   ["out", pid]        bankruptcy
func apply_delta(deltas: Array) -> void:
	if deltas.is_empty():
		return
	var touched := {}
	for delta in deltas:
		if not (delta is Array) or (delta as Array).is_empty():
			continue
		var d: Array = delta
		match str(d[0]):
			"c":
				if d.size() >= 3 and _player_idx(int(d[1])) >= 0:
					var pi := _player_idx(int(d[1]))
					vm["players"][pi]["money"] += int(d[2])
					touched["players"] = true
			"cb":
				# absolute: the engine logged the resulting balance, which is
				# exact even where no cash event exists (card effects)
				if d.size() >= 3 and _player_idx(int(d[1])) >= 0:
					var pb := _player_idx(int(d[1]))
					vm["players"][pb]["money"] = int(d[2])
					touched["players"] = true
			"pos":
				if d.size() >= 3 and _player_idx(int(d[1])) >= 0:
					var pi2 := _player_idx(int(d[1]))
					vm["players"][pi2]["pos"] = int(d[2])
					touched["players"] = true
			"out":
				if d.size() >= 2 and _player_idx(int(d[1])) >= 0:
					var pi3 := _player_idx(int(d[1]))
					vm["players"][pi3]["bankrupt"] = true
					touched["players"] = true
			"o":
				if d.size() >= 3 and _tile_idx(int(d[1])) >= 0:
					var ti := _tile_idx(int(d[1]))
					var owner = d[2]
					vm["tiles"][ti]["owner"] = -1 if owner == null else int(owner)
					touched["tiles"] = true
			"h":
				if d.size() >= 3 and _tile_idx(int(d[1])) >= 0:
					var ti2 := _tile_idx(int(d[1]))
					vm["tiles"][ti2]["houses"] = int(d[2])
					touched["tiles"] = true
			"m":
				if d.size() >= 3 and _tile_idx(int(d[1])) >= 0:
					var ti3 := _tile_idx(int(d[1]))
					vm["tiles"][ti3]["mortgaged"] = bool(d[2])
					touched["tiles"] = true
	changed.emit(PackedStringArray(touched.keys()))


## Set the local selection (a UI concern, not engine state).
func select_tile(index: int) -> void:
	if vm["selected_tile"] == index:
		return
	vm["selected_tile"] = index
	changed.emit(PackedStringArray(["selected_tile"]))


## The viewer/observer follow target (UI concern).
func set_follow(pid: int) -> void:
	if vm["follow_player"] == pid:
		return
	vm["follow_player"] = pid
	changed.emit(PackedStringArray(["follow_player"]))


func mark_over(winner) -> void:
	vm["over"] = winner
	changed.emit(PackedStringArray(["over"]))


# --- lookups ------------------------------------------------------------------

func player(pid: int) -> Dictionary:
	var i := _player_idx(pid)
	return vm["players"][i] if i >= 0 else {}


func tile(index: int) -> Dictionary:
	var i := _tile_idx(index)
	return vm["tiles"][i] if i >= 0 else {}


func _player_idx(pid: int) -> int:
	var arr: Array = vm["players"]
	for i in arr.size():
		if int(arr[i].get("id", -1)) == pid:
			return i
	return -1


func _tile_idx(index: int) -> int:
	var arr: Array = vm["tiles"]
	for i in arr.size():
		if int(arr[i].get("index", -1)) == index:
			return i
	return -1
