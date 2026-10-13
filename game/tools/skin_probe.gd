extends Node
## Phase 0 diagnostic probe — skinning/asset abstraction (TDD-first).
## Verifies every script reaches its art through the skin seam, never by literal path — everything must go through a SkinManager /
## ThemeManager seam so art can swap by replacing assets + a skin.json config.
##   1. tile_view.gd: no `res://assets/...` literal paths, no `Color("...")` or
##      `Color(r,g,b)` literals for the tile's own look.
##   2. players_panel.gd / top_bar.gd: same.
##   3. A SkinManager exists and can resolve a skin.json config.
##   4. Every skin a player can WEAR resolves a complete token set (effective config) —
##      a skin that renders its chrome from SkinManager's built-in FALLBACK_COLORS is a
##      defect, not a theme (classic used to do exactly that).
## Run: godot --headless --path game res://tools/skin_probe.tscn

var _had_fail := false
var _checks := 0

func _ready() -> void:
	# EVERY script, not four hand-picked ones. The old list (`tile_view`, `board_view`,
	# `players_panel`, `top_bar`) meant this probe reported PASS while the rest of the UI was
	# never read — and its Colour test skipped any line containing the word "skin", which is most
	# lines that legitimately mention a skin and also most lines that would hide a literal.
	# Colours are `stage8_contrast`'s job now (it scans the same tree, recursively, for both
	# `#rrggbb` and `Color(...)`); this probe guards ASSET PATHS, which nothing else checks.
	for d in ["res://ui", "res://visual", "res://admin", "res://seats", "res://i18n", "res://core"]:
		_scan_dir(d)
	await _check_skin_manager_exists()
	_check_skins_complete()

	if _had_fail:
		quit(1)
	else:
		print("SKIN_PROBE: ALL PASSED (%d files, %d checks)" % [_files, _checks])
		quit(0)


var _files := 0


func _scan_dir(d: String) -> void:
	var dir := DirAccess.open(d)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var path: String = d.path_join(f)
		if path.ends_with("skin_manager.gd"):
			continue   # the one place an asset path is ALLOWED to appear
		_check_no_hardcoded_paths(path)
	for sub in dir.get_directories():
		_scan_dir(d.path_join(sub))


## A script must not open an asset by literal path — art swaps by replacing files, and a literal
## path is what stops a skin from being able to redirect it.
func _check_no_hardcoded_paths(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("cannot read %s" % path)
		return
	_files += 1
	var bad := 0
	for line in f.get_as_text().split("
"):
		var code := _strip_comment(line).strip_edges()
		if code.contains("res://assets/") or code.contains("res://assets\\"):
			# a `const SKIN_DIR := "res://assets/skins"` style declaration is a SEAM, not a bake
			if code.begins_with("const ") or code.begins_with("@"):
				continue
			bad += 1
	if bad > 0:
		_fail("%s: %d hardcoded asset paths" % [path, bad])


## Comments are prose: they cite paths as evidence and must not be counted as code.
func _strip_comment(line: String) -> String:
	var in_s := false
	var in_d := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"" and not in_d:
			in_s = not in_s
		elif ch == "'" and not in_s:
			in_d = not in_d
		elif ch == "#" and not in_s and not in_d:
			return line.substr(0, i)
	return line


## A SkinManager class must exist and load a skin.json config.
func _check_skin_manager_exists() -> void:
	var sm_path := "res://visual/skin_manager.gd"
	if not ResourceLoader.exists(sm_path):
		_fail("SkinManager not found at %s" % sm_path)
		return
	var sm = load(sm_path).new()
	if sm == null:
		_fail("SkinManager failed to instantiate")
		return
	# must expose a way to load a skin config
	if not sm.has_method("load_skin"):
		_fail("SkinManager has no load_skin()")
		return
	_pass("SkinManager exists with load_skin()")


## Every skin a player can wear must resolve a COMPLETE token set on its EFFECTIVE config —
## `extends` inheritance is legitimate skin design (see `evil`: a single colour block over
## `neuro`, and its own note says so), so the check runs on the merged view the app reads.
##
## Required: the chrome tokens the panels resolve (hardcoded here, so it cannot be lowered by
## editing one file) plus every colour the BASELINE skin ships, plus the five size steps.
## A skin that falls through to FALLBACK_COLORS wears ANOTHER theme's values baked into code:
## that is what "рисует интерфейс фолбэками" means, and classic did exactly that (its own
## legacy `colors` block was never read by the token lookups; the chrome came from the
## built-in defaults, which are `default`'s values).
##
## Fixtures are exempt by the `_` prefix convention (`_stress`: deliberately extreme).
## The picker list is read from the LIVE top_bar script, so dropping a partial skin into the
## switcher fails here instead of on a player's screen.
func _check_skins_complete() -> void:
	var sm = load("res://visual/skin_manager.gd").new()
	var want_colors := {}
	for k in ["bg", "surface.1", "surface.2", "surface.3", "line", "text", "muted", "accent",
			"on_accent", "on_panel", "money", "danger", "warn", "ink", "dice_bg", "dice_ink",
			"board.bg2", "board.bg3",
			# design v3 additions (design/coverage.md §2): chrome the new layout needs
			"scrim", "glow", "good", "ring_bg", "group"]:
		want_colors[k] = true
	sm.load_skin("default")
	var base: Variant = sm._lookup("tokens.color")
	if base is Dictionary:
		for k in (base as Dictionary).keys():
			want_colors[k] = true
	var want_sizes := ["xs", "s", "m", "l", "xl"]

	var picker: Array = []
	var tb = load("res://ui/top_bar.gd")
	if tb != null:
		picker = tb.SKINS

	var ids := {}
	for id in sm.available():
		var s := str(id)
		if not s.begins_with("_"):
			ids[s] = true
	for id in picker:
		ids[str(id)] = true

	var bad: Array = []
	var keys: Array = ids.keys()
	keys.sort()
	for id in keys:
		if not sm.load_skin(id):
			bad.append("%s: не загружается" % id)
			continue
		var col: Variant = sm._lookup("tokens.color")
		var siz: Variant = sm._lookup("tokens.size")
		var parent := ""
		var pe: Variant = sm._lookup("extends")
		if pe != null:
			parent = str(pe)
		var miss: Array = []
		for k in want_colors.keys():
			if not (col is Dictionary and (col as Dictionary).has(k)):
				miss.append("color." + str(k))
		if siz is Dictionary:
			for s in want_sizes:
				if not (siz as Dictionary).has(s):
					miss.append("size." + s)
		else:
			miss.append("size.*")
		var pl: Variant = sm._lookup("tokens.color.player")
		if not (pl is Array) or (pl as Array).size() < 8:
			miss.append("color.player >= 8 (seats 2..8)")
		if miss.is_empty():
			var have: int = (col as Dictionary).size() if col is Dictionary else 0
			var from := (" (наследует от %s)" % parent) if parent != "" else ""
			print("  skin %s: %d цветов, 5 размеров%s — полон" % [id, have, from])
		else:
			bad.append("%s: нет %s" % [id, ", ".join(miss)])
	for b in bad:
		print("  incomplete skin: " + str(b))
	if bad.is_empty():
		_pass("skins complete: %d shipping skin(s)" % keys.size())
	else:
		_fail("%d incomplete skin(s) — the player would see fallbacks: %s" % [bad.size(), bad[0]])

func _pass(label: String) -> void:
	_checks += 1
	print("PASS: " + label)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
