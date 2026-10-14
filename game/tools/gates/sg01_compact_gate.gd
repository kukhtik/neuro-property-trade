extends Node
## SG-01 gate — regions and reachability on every profile (docs/restoration/gates.md, SG-01).
##
## Grown out of the audit's `compact_probe.gd` (which only PRINTED visibility). The contract:
## for every profile, every region named by design/regions.json is either VISIBLE, or replaced
## by its compact counterpart (rail / drawer / console ticker). A region that is simply hidden
## is unreachable: the player cannot see the journal, cannot pick a tile, cannot manage
## property. The audit found exactly that at 1000x650 - `seats` and `rightcol` hidden with
## nothing in their place.
##
## Verdict: ==> SG-01 PASSED (4 profiles, 0 unreachable regions) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg01_compact_gate.tscn

const MainScript := preload("res://main.gd")

const PROFILES := [
	{"label": "1440x900", "size": Vector2i(1440, 900)},
	{"label": "1280x720", "size": Vector2i(1280, 720)},
	{"label": "1000x650", "size": Vector2i(1000, 650)},
	{"label": "880x600", "size": Vector2i(880, 600)},
]
## region -> [replacement candidates]. Empty = presence is enough (a transient overlay that is
## hidden between messages is not "unreachable"); non-empty = must be visible OR replaced.
const REGIONS := {
	"top": [],
	"stage": [],
	"act": [],
	"seats": ["rail-left", "drawer-seats"],
	"rightcol": ["rail-right"],
	"journal": ["rail-right", "drawer-journal"],
	"inspector": ["rail-right", "drawer-inspector"],
	"modal": [],
	"toast": [],
}
## Regions whose node may be hidden between messages (presence is the contract).
const PRESENCE_ONLY := ["modal"]

var _launcher = null
var _frame := 0
var _profile_idx := 0
var _fails: Array = []
var _checks := 0


func _ready() -> void:
	DisplayServer.window_set_size(PROFILES[0].size)
	get_tree().root.size = PROFILES[0].size
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 8:
		_launcher.call("_autostart")
		return
	if _frame < 12 or _frame % 12 != 0:
		return
	_check_profile(PROFILES[_profile_idx])
	_profile_idx += 1
	if _profile_idx >= PROFILES.size():
		_report()
		return
	get_tree().root.size = PROFILES[_profile_idx].size
	DisplayServer.window_set_size(PROFILES[_profile_idx].size)


func _check_profile(profile: Dictionary) -> void:
	var label: String = str(profile["label"])
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("%s: no game view" % label)
		return
	var unreachable: Array = []
	for region in REGIONS.keys():
		var node = gv.find_child(str(region), true, false)
		if node == null:
			_fail("%s: region `%s` is missing from the tree" % [label, region])
			continue
		if PRESENCE_ONLY.has(str(region)):
			_checks += 1
			continue
		# the toast host is the right dock when it shows and the one-line console ticker in
		# compact - the registry's own wording; both count as reachable.
		if str(region) == "toast":
			var rightcol_vis: bool = false
			var rc = gv.find_child("rightcol", true, false)
			if rc != null and (rc as Control).visible:
				rightcol_vis = true
			var console = gv.find_child("act", true, false)
			var ticker = console.get("_ticker") if console != null else null
			if rightcol_vis or ticker != null:
				_checks += 1
			else:
				unreachable.append("toast")
				_fail("%s: neither the right-dock toast host nor the compact console ticker is reachable" % label)
			continue
		var vis: bool = (node as Control).visible and (node as Control).size.x > 0.0 \
			and (node as Control).size.y > 0.0
		if vis:
			_checks += 1
			continue
		# hidden: acceptable ONLY when its compact counterpart exists
		var repl: Array = REGIONS[region]
		var found := ""
		for cand in repl:
			if gv.find_child(str(cand), true, false) != null:
				found = str(cand)
				break
		if found == "":
			unreachable.append(str(region))
			_fail("%s: region `%s` is hidden and has NO replacement (%s) - the player cannot reach it"
				% [label, region, ", ".join(repl) if repl.size() > 0 else "none declared"])
		else:
			_checks += 1
	print("SG-01 %s: %d/%d regions reachable%s" % [label, REGIONS.size() - unreachable.size(),
		REGIONS.size(), (" (hidden w/o replacement: %s)" % str(unreachable)) if not unreachable.is_empty() else ""])
	if label == "1440x900":
		_check_metrics(gv)


## The mockup's own metrics (design §3): header 56, docks 268/344, console 96+. This is the
## only profile where they must hold exactly; the others are allowed to collapse.
func _check_metrics(gv) -> void:
	var top = gv.find_child("top", true, false)
	var seats = gv.find_child("seats", true, false)
	var rightcol = gv.find_child("rightcol", true, false)
	var act = gv.find_child("act", true, false)
	if top != null and absf((top as Control).size.y - 56.0) > 2.0:
		_fail("1440x900: header height %s != 56" % str((top as Control).size.y))
	elif seats != null and absf((seats as Control).size.x - 268.0) > 2.0:
		_fail("1440x900: left dock %s != 268" % str((seats as Control).size.x))
	elif rightcol != null and absf((rightcol as Control).size.x - 344.0) > 2.0:
		_fail("1440x900: right dock %s != 344" % str((rightcol as Control).size.x))
	elif act != null and (act as Control).size.y < 90.0:
		_fail("1440x900: console height %s < 90" % str((act as Control).size.y))
	else:
		_checks += 1


func _report() -> void:
	print("SG-01: %d checks" % _checks)
	if _fails.is_empty():
		print("==> SG-01 PASSED (%d profiles, 0 unreachable regions, metrics hold at 1440x900)"
			% PROFILES.size())
		get_tree().quit(0)
	else:
		print("==> SG-01 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
