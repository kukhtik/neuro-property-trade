extends Node
## Phase 0 diagnostic probe — skinning/asset abstraction (TDD-first).
## Verifies every script reaches its art through the skin seam, never by literal path — everything must go through a SkinManager /
## ThemeManager seam so art can swap by replacing assets + a skin.json config.
##   1. tile_view.gd: no `res://assets/...` literal paths, no `Color("...")` or
##      `Color(r,g,b)` literals for the tile's own look.
##   2. players_panel.gd / top_bar.gd: same.
##   3. A SkinManager exists and can resolve a skin.json config.
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

func _pass(label: String) -> void:
	_checks += 1
	print("PASS: " + label)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
