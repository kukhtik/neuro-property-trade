extends Node
## Phase 0 diagnostic probe — skinning/asset abstraction (TDD-first).
## Verifies the visual layer has NO hardcoded asset paths or Color(...) literals
## in the tile/panel/top-bar code — everything must go through a SkinManager /
## ThemeManager seam so art can swap by replacing assets + a skin.json config.
##   1. tile_view.gd: no `res://assets/...` literal paths, no `Color("...")` or
##      `Color(r,g,b)` literals for the tile's own look.
##   2. players_panel.gd / top_bar.gd: same.
##   3. A SkinManager exists and can resolve a skin.json config.
## Run: godot --headless --path game res://tools/skin_probe.tscn

var _had_fail := false
var _checks := 0

func _ready() -> void:
	await _check_no_hardcoded_paths("res://visual/tile_view.gd")
	await _check_no_hardcoded_paths("res://visual/board_view.gd")
	await _check_no_hardcoded_paths("res://ui/players_panel.gd")
	await _check_no_hardcoded_paths("res://ui/top_bar.gd")
	await _check_skin_manager_exists()

	if _had_fail:
		quit(1)
	else:
		print("SKIN_PROBE: ALL PASSED (%d checks)" % _checks)
		quit(0)

## A visual-layer file must not contain literal `res://assets/...` paths or
## `Color(...)` literals (the skin seam owns those).
func _check_no_hardcoded_paths(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("cannot read %s" % path)
		return
	var src: String = f.get_as_text()
	var bad_paths := 0
	var bad_colors := 0
	for line in src.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("#") or l.begins_with("##"):
			continue
		if l.contains("res://assets/") and not l.contains("SkinManager") and not l.contains("skin"):
			bad_paths += 1
		# Color("...") or Color(r, g, b) literals (not Color.TRANSPARENT/WHITE/BLACK
		# which are semantic, and not a call into a theme/skin manager)
		if l.contains("Color(") and not l.contains("Color.TRANSPARENT") and \
		   not l.contains("Color.WHITE") and not l.contains("Color.BLACK") and \
		   not l.contains("SkinManager") and not l.contains("ThemeManager") and \
		   not l.contains("skin") and not l.contains("theme"):
			bad_colors += 1
	if bad_paths > 0 or bad_colors > 0:
		_fail("%s: %d hardcoded asset paths, %d hardcoded Color() literals" % \
			[path, bad_paths, bad_colors])
		return
	_pass("%s: no hardcoded asset paths or Color() literals" % path)

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
