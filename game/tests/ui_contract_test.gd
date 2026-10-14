extends RefCounted
## HG-10 — the projection contract (docs/restoration/gates.md).
##
## The UI reads the projection by STRING keys, so a renamed key fails nowhere: the read yields
## null and the widget paints a zero. That is exactly what happened to the parking bank — the
## projection says `parking_pot`, two panels asked for `pot`, and the "БАНК ПАРКОВКИ" chip
## showed $0 for a whole match while the pot filled up inside the engine.
##
## This module (a) pins the keys BOTH projections really output, (b) scans game/ui and the
## server for projection reads and refuses any key outside the contract below, and (c) carries
## the direct regression case: `pot` must neither exist in the projection nor be read anywhere.
## A new projection key enters `CONTRACT` in the same commit that introduces it.

const EngineScript := preload("res://core/engine.gd")
const SettingsScript := preload("res://core/game_settings.gd")
## `Projection` collides with a Godot builtin type name - the repo calls it ProjScript.
const ProjScript := preload("res://sdk/projection.gd")

## Top-level keys a UI/server file may read. `legal`/`private` are wire-only (for_player).
const CONTRACT := ["phase", "turn_player", "turn", "round", "board", "players", "pending",
	"legal", "holder", "parking_pot", "timer_window", "timer_elapsed", "timer_active", "private"]


static func test_list() -> Array[String]:
	return ["test_projection_outputs_pinned", "test_ui_reads_only_contract_keys",
		"test_parking_pot_not_pot"]


## (a) what the projections actually output, pinned with types.
static func test_projection_outputs_pinned() -> String:
	var eng = _engine()
	var p = ProjScript.new()
	var spec: Dictionary = p.for_spectator(eng)
	var player: Dictionary = p.for_player(eng, 0)
	for key in ["phase", "turn_player", "round", "board", "players", "pending", "parking_pot"]:
		if not spec.has(key):
			return "spectator projection lost key `%s`" % key
	if spec.has("legal") or spec.has("private"):
		return "spectator projection leaked `legal`/`private` - a spectator holds no decision"
	for key in ["phase", "turn_player", "round", "board", "players", "pending", "parking_pot",
			"legal", "private"]:
		if not player.has(key):
			return "player projection lost key `%s`" % key
	if typeof(spec["parking_pot"]) != TYPE_INT or typeof(player["round"]) != TYPE_INT:
		return "projection types drifted (parking_pot/round must be int)"
	if typeof(player["board"]) != TYPE_ARRAY or typeof(player["players"]) != TYPE_ARRAY:
		return "board/players must be arrays"
	if typeof(player["pending"]) != TYPE_DICTIONARY or typeof(player["legal"]) != TYPE_ARRAY:
		return "pending must be a dictionary, legal an array"
	return ""


## (b) every projection read in game/ui (and the server) names a contract key.
static func test_ui_reads_only_contract_keys() -> String:
	var reads := _scan_projection_reads()
	if reads.size() < 3:
		return "the scan found only %d projection read(s) - it cannot be proving anything" % reads.size()
	var files := {}
	for r in reads:
		files[str(r["file"])] = true
	if files.size() < 3:
		return "the scan read projection calls in only %d file(s) - coverage lost" % files.size()
	for r in reads:
		var key := str(r["key"])
		if not CONTRACT.has(key):
			return "%s:%d reads `%s`, which is not in the projection contract" % [r["file"], r["line"], key]
	return ""


## (c) the direct regression case: one bank, one name, and the UI uses it.
static func test_parking_pot_not_pot() -> String:
	var eng = _engine()
	var p = ProjScript.new()
	var spec: Dictionary = p.for_spectator(eng)
	if not spec.has("parking_pot"):
		return "the projection stopped carrying `parking_pot`"
	if spec.has("pot"):
		return "the projection grew a second name for the same thing (`pot`)"
	for r in _scan_projection_reads():
		if str(r["key"]) == "pot":
			return "%s:%d reads `pot` - the chip would show $0 forever" % [r["file"], r["line"]]
	return ""


static func _engine():
	var st = SettingsScript.new()
	st.seat_count = 2
	st.seat_assignments = [{"driver": "LOCAL", "name": "A"}, {"driver": "AI", "name": "B"}]
	var eng = EngineScript.new()
	eng.setup(st, ["A", "B"])
	return eng


## Every `proj.get("key")` / `_proj.get("key")` / `spec.get("key")` in the UI and the server.
static func _scan_projection_reads() -> Array:
	var out: Array = []
	var files: Array = []
	_collect("res://ui", files)
	files.append("res://server/game_server.gd")
	for f in files:
		var txt := FileAccess.get_file_as_string(str(f))
		if txt == "":
			continue
		var lines := txt.split("\n")
		for i in lines.size():
			var line := str(lines[i])
			for probe in ["proj.get(\"", "spec.get(\""]:
				var at := line.find(probe)
				while at >= 0:
					var rest := line.substr(at + probe.length())
					var endp := rest.find("\"")
					if endp > 0:
						out.append({"file": str(f), "line": i + 1, "key": rest.substr(0, endp)})
					at = line.find(probe, at + probe.length())
	return out


static func _collect(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		if str(f).ends_with(".gd"):
			out.append(path + "/" + str(f))
	for sub in dir.get_directories():
		_collect(path + "/" + str(sub), out)
