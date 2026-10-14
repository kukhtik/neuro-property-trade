extends Node
## HG-09 gate — the i18n contract (docs/restoration/gates.md section 2, P0).
##
## Proves the user never sees a raw `{key}` on screen. Three layers:
##   1. STATIC: every `I18n.t("...")` / `I18n.has("...")` literal under game/ui, game/visual and
##      game/main.gd resolves in BOTH locales; the dynamic prefixes the code builds
##      (`"phase." + x`, `"event_type." + x`, `"event." + x`) are ENUMERATED from their real
##      sources (engine PHASE_* consts, engine log.append types, the adapter's TYPE_MAP spans)
##      and every member resolves too. Skin lookups (`"tokens." + p` style) are classified and
##      counted, not failed: they are data paths, not translations.
##   2. WIDGET: the v3 panels are built and fed crafted projections that reach labels the live
##      app only shows later (jail chip, purchase decision, auction hint, game-over modal).
##   3. LIVE: the real app boots, and the whole tree plus the game-over modal is scanned for
##      sentinel text and tooltips, in RU and EN.
## The scanner asserts its own COVERAGE (files read, prefixes classified, keys checked): a
## scanner that silently stops reading is a green light over a blind spot.
##
## Verdict: `==> HG-09 PASSED (...)` / `==> HG-09 FAILED: <reason>`.
## Run: godot --headless --path game res://tools/gates/hg09_i18n_gate.tscn

const I18n := preload("res://i18n/i18n.gd")
const TopBar := preload("res://ui/top_bar.gd")
const PlayersPanel := preload("res://ui/players_panel.gd")
const ActionPanel := preload("res://ui/action_panel.gd")
const ModalHost := preload("res://ui/modal_host.gd")
const MainScript := preload("res://main.gd")

const SCAN_DIRS := ["res://ui", "res://visual"]
const SCAN_FILES := ["res://main.gd"]
## Dynamic prefixes that MUST resolve (each has an enumeration rule below).
const I18N_DYNAMIC := ["phase.", "event_type.", "event.", "jrn.ev.", "settings.driver."]
## Dynamic prefixes that are DATA PATHS (SkinManager), not translations. Counted, not failed;
## a NEW one shows up in the log so the classification can be re-decided consciously.
const DATA_DYNAMIC := ["tokens.", "size.", "shape.", "metrics.", "proportions.", "motion.",
	"color.", "colors.", "slots.", "font.", "assets."]
## Coverage floors: a scan that reads fewer files / keys than this has gone blind.
const MIN_FILES := 12
const MIN_LITERAL_KEYS := 30
const MIN_ENGINE_TYPES := 30
const MIN_SPANS := 15

var _fails: Array = []
var _keys_checked := 0
var _files_read := 0

## A literal backslash, spelled without a double backslash on purpose (file-writing through
## this session's tooling collapses `\\`); in GDScript `\u005C` IS a backslash.
const BS := "\u005C"


func _ready() -> void:
	_run()

func _run() -> void:
	var files := _collect_files()
	for f in files:
		_scan_file_static(f)
	_scan_dynamic()
	_check_passed_widgets()
	await _check_live_app()
	_report()


func _collect_files() -> Array:
	var out: Array = []
	for d in SCAN_DIRS:
		_collect_dir(d, out)
	for f in SCAN_FILES:
		out.append(f)
	return out


func _collect_dir(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		_fail("cannot open %s for the scan" % path)
		print("FAIL: cannot open %s for the scan" % path)
		return
	for f in dir.get_files():
		if str(f).ends_with(".gd") and not str(f).ends_with(".uid"):
			out.append(path + "/" + str(f))
	for sub in dir.get_directories():
		_collect_dir(path + "/" + str(sub), out)


## Layer 1a: literal keys, resolved in both locales.
func _scan_file_static(path: String) -> void:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		_fail("%s unreadable (empty)" % path)
		print("FAIL: %s unreadable (empty)" % path)
		return
	_files_read += 1
	# regex escapes are built from BS (a literal backslash); see the note at the const.
	var rx := RegEx.new()
	rx.compile("I18n" + BS + ".(?:t|has)" + BS + "(" + BS + "s*" + BS + "\"([^" + BS + "\"]+)" + BS + "\"")
	for m in rx.search_all(txt):
		# a literal directly followed by `+` is the HEAD OF A DYNAMIC KEY (`"phase." + x`),
		# not a key: it is enumerated by the dynamic pass below, not resolved as-is.
		if txt.substr(m.get_end(), 8).strip_edges().begins_with("+"):
			continue
		var key := m.get_string(1)
		var line := txt.substr(0, m.get_start()).count("\n") + 1
		_check_key(key, "%s:%d" % [path, line])
	var rx2 := RegEx.new()
	rx2.compile("I18n" + BS + ".(?:key_on|tip_on)" + BS + "([^,]+," + BS + "s*" + BS + "\"([^" + BS + "\"]+)" + BS + "\"")
	for m in rx2.search_all(txt):
		var key := m.get_string(1)
		var line := txt.substr(0, m.get_start()).count("\n") + 1
		_check_key(key, "%s:%d" % [path, line])


## Resolve one key in RU and EN. A missing key prints `{key}` in both - that is the failure.
func _check_key(key: String, where: String) -> void:
	_keys_checked += 1
	for loc in ["ru", "en"]:
		I18n.set_locale(loc)
		var v: String = I18n.t(key)
		if v.begins_with("{") and v.ends_with("}"):
			_fail("%s: key `%s` does not resolve in %s" % [where, key, loc.to_upper()])
			print("FAIL: %s: key `%s` does not resolve in %s" % [where, key, loc.to_upper()])
			return


## Layer 1b: dynamic prefixes. Each i18n prefix has an enumeration rule; every member must
## resolve. `event.` is special: it is only reachable through `EventAdapter.text_key`, and if
## that helper has no caller the prefix is dead - the gate then checks that it STAYS dead
## instead of demanding templates nobody renders.
func _scan_dynamic() -> void:
	var prefixes := {}
	var files := _collect_files()
	for path in files:
		var txt := FileAccess.get_file_as_string(path)
		var rx := RegEx.new()
		# one or more dot-separated segments inside the quotes: `"phase."`, `"event_type."`,
		# and the two-dot `"settings.driver."` (the first version only allowed a single dot
		# and silently missed the settings prefix).
		rx.compile("\"([a-z_]+[a-z_.]*)\"" + BS + "s*" + BS + "+")
		for m in rx.search_all(txt):
			var pre := m.get_string(1)
			if not prefixes.has(pre):
				prefixes[pre] = "%s" % path
	var eng_types := _engine_event_types()
	var spans := _adapter_spans()
	print("HG-09 scan: %d files, %d literal keys checked, %d dynamic prefixes" % [_files_read, _keys_checked, prefixes.size()])
	if _files_read < MIN_FILES:
		_fail("scan coverage lost: only %d files read (expected >= %d)" % [_files_read, MIN_FILES])
		print("FAIL: scan coverage lost: only %d files read (expected >= %d)" % [_files_read, MIN_FILES])
	if _keys_checked < MIN_LITERAL_KEYS:
		_fail("scan coverage lost: only %d literal keys found (expected >= %d)" % [_keys_checked, MIN_LITERAL_KEYS])
		print("FAIL: scan coverage lost: only %d literal keys found (expected >= %d)" % [_keys_checked, MIN_LITERAL_KEYS])
	if eng_types.size() < MIN_ENGINE_TYPES:
		_fail("engine event-type enumeration lost: %d types (expected >= %d)" % [eng_types.size(), MIN_ENGINE_TYPES])
		print("FAIL: engine event-type enumeration lost: %d types (expected >= %d)" % [eng_types.size(), MIN_ENGINE_TYPES])
	if spans.size() < MIN_SPANS:
		_fail("adapter span enumeration lost: %d spans (expected >= %d)" % [spans.size(), MIN_SPANS])
		print("FAIL: adapter span enumeration lost: %d spans (expected >= %d)" % [spans.size(), MIN_SPANS])
	var seen_i18n := {}
	for pre in prefixes:
		var where: String = prefixes[pre]
		if pre == "phase.":
			seen_i18n[pre] = true
			for ph in _engine_phases():
				_check_key("phase." + ph, where)
		elif pre == "event_type.":
			seen_i18n[pre] = true
			for t in eng_types:
				_check_key("event_type." + t, where)
			for sp in spans:
				_check_key("event_type." + sp, where)
		elif pre == "event.":
			seen_i18n[pre] = true
			# only reachable via EventAdapter.text_key - verify that stays true
			var callers := _text_key_callers()
			if callers.size() == 0:
				print("HG-09 note: prefix `event.` is defined (EventAdapter.text_key) with no caller - treated as dead code, not a contract")
			else:
				for sp in spans:
					_check_key("event." + sp, callers[0])
		elif pre == "settings.driver.":
			seen_i18n[pre] = true
			# the settings sheet builds driver labels as "settings.driver." + id.lower() with
			# ':' -> '_' (sdk:neuro -> sdk_neuro). Enumerate the DRIVERS list itself.
			for d in _driver_ids():
				_check_key("settings.driver." + d.to_lower().replace(":", "_"), where)
		elif pre == "jrn.ev.":
			seen_i18n[pre] = true
			# SG-06 journal lines: ui/core/journal_lines.gd builds "jrn.ev." + span for every
			# span the journal RENDERS (VISIBLE). Non-visible spans (move/cash/pay) never ask
			# for a line key - enumerating the VISIBLE list keeps this from demanding dead keys.
			var vis := _adapter_visible_spans()
			if vis.size() < MIN_SPANS:
				_fail("journal-line span enumeration lost: %d visible spans (expected >= %d)" % [vis.size(), MIN_SPANS])
			for sp in vis:
				_check_key("jrn.ev." + str(sp), where)
		else:
			# a data-path prefix may have several segments (`tokens.metrics.`, `colors.group.`) -
			# classify by its ROOT, not by a full-string match.
			var is_data := false
			for root in DATA_DYNAMIC:
				if pre.begins_with(str(root)):
					is_data = true
					break
			if not is_data:
				print("HG-09 warn: dynamic prefix `%s` (%s) is not classified as i18n or data-path" % [pre, where])
	for pre in I18N_DYNAMIC:
		if not seen_i18n.has(pre):
			print("HG-09 note: i18n prefix `%s` not found in the scan (no live use)" % pre)


## Engine phase names, straight from the consts - the same strings `phase.*` is asked for.
func _engine_phases() -> Array:
	var phases: Array = []
	var txt := FileAccess.get_file_as_string("res://core/engine.gd")
	var rx := RegEx.new()
	rx.compile("const PHASE_[A-Z_]+" + BS + "s*:=" + BS + "s*" + BS + "\"([A-Z_]+)" + BS + "\"")
	for m in rx.search_all(txt):
		phases.append(m.get_string(1))
	return phases


## Every event type the engine logs, from the core sources themselves.
func _engine_event_types() -> Array:
	var types := {}
	var dir := DirAccess.open("res://core")
	if dir != null:
		for f in dir.get_files():
			if not str(f).ends_with(".gd"):
				continue
			var txt := FileAccess.get_file_as_string("res://core/" + str(f))
			var rx := RegEx.new()
			rx.compile("log" + BS + ".append" + BS + "(" + BS + "\"([a-z_]+)" + BS + "\"")
			for m in rx.search_all(txt):
				types[m.get_string(1)] = true
	return types.keys()


## The adapter's span names: TYPE_MAP values only. The CATEGORY block next to it maps spans to
## filter categories (money/auction/...) - those are NOT display titles and must not be
## enumerated here, or the gate fails on keys that never belong on a label.
func _adapter_spans() -> Array:
	var spans := {}
	var txt := FileAccess.get_file_as_string("res://ui/core/event_adapter.gd")
	var start := txt.find("const TYPE_MAP")
	var endp := txt.find("}", start)
	if start < 0 or endp < 0:
		return []
	var block := txt.substr(start, endp - start)
	var rx := RegEx.new()
	rx.compile(BS + "\"([a-z_]+)" + BS + "\"" + BS + "s*:" + BS + "s*" + BS + "\"([a-z_]+)" + BS + "\"")
	for m in rx.search_all(block):
		spans[m.get_string(2)] = true
	return spans.keys()


## The spans the journal can RENDER: the adapter's VISIBLE list. `jrn.ev.` keys exist exactly
## for these (move/cash/pay are adapted but never shown -> no line keys by design).
func _adapter_visible_spans() -> Array:
	var spans: Array = []
	var txt := FileAccess.get_file_as_string("res://ui/core/event_adapter.gd")
	var start := txt.find("const VISIBLE")
	var endp := txt.find("]", start)
	if start < 0 or endp < 0:
		return spans
	var block := txt.substr(start, endp - start)
	var rx := RegEx.new()
	rx.compile(BS + "\"([a-z_]+)\"")
	for m in rx.search_all(block):
		spans.append(m.get_string(1))
	return spans


func _text_key_callers() -> Array:
	var out: Array = []
	for path in _collect_files():
		var txt := FileAccess.get_file_as_string(path)
		if txt.contains("text_key(") and not path.ends_with("event_adapter.gd"):
			out.append(path)
	return out


## The driver ids the settings sheet offers, straight from its DRIVERS const - the source the
## "settings.driver.<id>" keys are built from.
func _driver_ids() -> Array:
	var ids: Array = []
	var txt := FileAccess.get_file_as_string("res://ui/settings_overlay.gd")
	var start := txt.find("const DRIVERS")
	var endp := txt.find("]", start)
	if start < 0 or endp < 0:
		return []
	var block := txt.substr(start, endp - start)
	var rx := RegEx.new()
	rx.compile(BS + "\"([a-zA-Z:]+)" + BS + "\"")
	for m in rx.search_all(block):
		ids.append(m.get_string(1))
	return ids


## A seat stand-in for the crafted projections (the panels read pid/name/color/driver).
class FakeSeat:
	var pid := 0
	var name := "Tester"
	var color := Color(0.8, 0.7, 0.4)
	var input_driver := "LOCAL"


## Layer 2: crafted projections through the real v3 widgets, in both locales. The live app
## reaches some of these labels only late (a jail chip needs a jail, the decision chip needs a
## pending purchase, the title needs a game over) - here they are reached now.
func _check_passed_widgets() -> void:
	var seat := FakeSeat.new()
	for loc in ["ru", "en"]:
		I18n.set_locale(loc)
		var top = TopBar.new()
		add_child(top)
		top.sync({
			"turn_player": 0, "phase": "PURCHASE_WAIT", "round": 2, "parking_pot": 140,
			"pending": {"type": "purchase", "tile": 5}, "legal": [],
			"players": [{"index": 0, "position": 4}],
			"board": [{"index": 5, "name": "Nova Terrace", "cost": 120}],
		}, [seat])
		_walk_sentinels(top, "TopBar[%s] purchase" % loc)
		# auction pending: the decision area must be silent, not sentinel
		top.sync({
			"turn_player": 0, "phase": "AUCTION", "round": 2, "parking_pot": 140,
			"pending": {"type": "auction", "tile": 5, "high": 120}, "legal": [],
			"players": [{"index": 0, "position": 4}],
			"board": [{"index": 5, "name": "Nova Terrace"}],
		}, [seat])
		_walk_sentinels(top, "TopBar[%s] auction" % loc)
		top.queue_free()

		var pp = PlayersPanel.new()
		add_child(pp)
		pp.sync({
			"round": 3, "parking_pot": 90,
			"players": [
				{"index": 0, "name": "Tester", "money": 400, "position": 5,
					"in_jail": true, "bankrupt": false, "tiles": [1, 2]},
				{"index": 1, "name": "Bot", "money": 90, "position": 0,
					"in_jail": false, "bankrupt": true, "tiles": []},
			],
			"board": [{"index": 5, "name": "Nova Terrace"}],
		}, [seat])
		_walk_sentinels(pp, "PlayersPanel[%s] jail+bankrupt+stats" % loc)
		pp.queue_free()

		var act = ActionPanel.new()
		add_child(act)
		act.set_cold(false)
		act.sync(0, ["roll", "build_house", "propose_trade"], true, {
			"phase": "TURN_START", "pending": {},
		}, [seat])
		_walk_sentinels(act, "ActionPanel[%s] turn actions" % loc)
		act.sync(0, ["bid", "pass"], true, {
			"phase": "AUCTION", "pending": {"type": "auction", "tile": 5, "high": 120},
			"board": [{"index": 5, "name": "Nova Terrace"}],
		}, [seat])
		_walk_sentinels(act, "ActionPanel[%s] auction" % loc)
		act.queue_free()

		var mod = ModalHost.new()
		add_child(mod)
		mod.show_message(I18n.t("modal.game_over"), I18n.t("modal.winner", ["Tester"]))
		_walk_sentinels(mod, "ModalHost[%s] game over" % loc)
		mod.queue_free()
	print("HG-09 widget pass: crafted projections through TopBar/PlayersPanel/ActionPanel/ModalHost")


## Layer 3: the real app. Boot it, autostart, wait for the first projection, scan the whole
## tree; then raise the game-over modal and scan that too.
func _check_live_app() -> void:
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 20:
		await get_tree().process_frame
	launcher.call("_autostart")
	var gv = launcher.get("_game_view")
	if gv == null:
		_fail("live app: no GameView after autostart")
		print("FAIL: live app: no GameView after autostart")
		return
	# wait for the projection to arrive (the panels paint from it)
	var waited := 0
	while waited < 200:
		var proj = gv.get("_proj")
		if proj is Dictionary and not (proj as Dictionary).is_empty():
			break
		await get_tree().process_frame
		waited += 1
	if waited >= 200:
		_fail("live app: no projection arrived in 200 frames - nothing was painted, nothing was checked")
		print("FAIL: live app: no projection arrived in 200 frames - nothing was painted, nothing was checked")
		return
	for loc in ["ru", "en"]:
		I18n.set_locale(loc)
		for _i in 5:
			await get_tree().process_frame
		_walk_sentinels(gv, "live app [%s]" % loc)
	# the inspector's body only exists with a tile selected - a blind spot that hid the
	# `{ins.price}:` sentinel until SG-08 walked in: select a tile, repaint, scan again
	var insp = gv.find_child("inspector", true, false)
	if insp != null and insp.has_method("select"):
		insp.call("select", 1)
		gv.call("_sync_all")
		for _i in 5:
			await get_tree().process_frame
		_walk_sentinels(gv, "live app [inspector selected]")
	gv.call("show_game_over", "Tester")
	for _i in 5:
		await get_tree().process_frame
	_walk_sentinels(gv, "live app game over")
	if launcher != null and is_instance_valid(launcher):
		launcher.queue_free()
	for _i in 2:
		await get_tree().process_frame
	print("HG-09 live pass: full tree + game-over modal scanned in RU/EN")


## Any visible text or tooltip carrying a `{key}` sentinel is a bug: the user is looking at a
## key. The old pass demanded the WHOLE string be a sentinel, so `{ins.price}:` sailed through
## for as long as `ins.price` was missing (SG-08 found it in the live walk).
func _walk_sentinels(root: Node, where: String) -> void:
	var rx := RegEx.new()
	rx.compile(BS + "{[A-Za-z0-9_.]+" + BS + "}")
	var found := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var c = stack.pop_back()
		if c is Control:
			var ctl := c as Control
			for prop in ["text", "tooltip_text"]:
				if prop in ctl:
					var t := str(ctl.get(prop)).strip_edges()
					if rx.search(t) != null:
						found += 1
						if found <= 5:
							_fail("%s: %s on %s shows `%s`" % [where, prop, _node_path(ctl, root), t])
							print("FAIL: %s: %s on %s shows `%s`" % [where, prop, _node_path(ctl, root), t])
			for i in ctl.get_child_count():
				stack.append(ctl.get_child(i))
		elif c is Node:
			for i in (c as Node).get_child_count():
				stack.append((c as Node).get_child(i))


func _node_path(n: Node, root: Node) -> String:
	var parts: Array = []
	var cur := n
	while cur != null and cur != root:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
	return ("/" + "/".join(parts)) if not parts.is_empty() else "/"


func _report() -> void:
	if _fails.is_empty():
		print("==> HG-09 PASSED (%d files, %d literal refs, 0 sentinels, ru+en)" % [_files_read, _keys_checked])
		get_tree().quit(0)
	else:
		print("==> HG-09 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
