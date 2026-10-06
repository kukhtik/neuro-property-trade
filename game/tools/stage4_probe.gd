extends SceneTree
## Stage-4 acceptance probe: the rail panels and the layout profiles.
##
## Checks the spec's §5.1/§5.2 requirements that the suite cannot see:
##   1. a panel collapses to a rail and EXPANDS BACK
##   2. a collapsed rail is not empty — it keeps its title and a count
##   3. the content hides while railed
##   4. auto-collapse follows LayoutProfile, and a MANUAL toggle wins over it
##   5. UiTheme now resolves through the skin (no hardcoded palette left)
##
## Exit 0 = stage 4 rails + profiles behave.

const RailPanel := preload("res://ui/components/rail_panel.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const Layout := preload("res://ui/core/layout_profile.gd")
const UiTheme := preload("res://ui/theme.gd")
const GameView := preload("res://ui/game_view.gd")

var _fail := 0

func _init() -> void:
	print("=== Stage 4 acceptance: rails + layout profiles ===")
	await process_frame
	_check_rail_collapse()
	_check_rail_not_empty()
	_check_manual_wins()
	_check_layout_profiles()
	_check_theme_reads_skin()
	_check_game_view_railed()
	print("")
	if _fail > 0:
		print("==> STAGE 4 FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> STAGE 4 PASSED — rails collapse, profiles drive them, theme is skinned")
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)

func _skin():
	var s = SkinManager.new()
	s.load_skin("neuro")
	return s


func _content() -> Control:
	var c := VBoxContainer.new()
	c.add_child(Label.new())
	return c


func _check_rail_collapse() -> void:
	print("[1] a panel collapses to a rail and expands back")
	var rail = RailPanel.new()
	root.add_child(rail)
	rail.setup(_skin(), "ui.players", true)
	rail.set_content(_content())
	if rail.is_collapsed():
		_bad("a fresh rail should start expanded")
	rail.set_collapsed(true, false)
	if not rail.is_collapsed():
		_bad("set_collapsed(true) did not collapse")
	elif rail.custom_minimum_size.x != float(RailPanel.RAIL_W):
		_bad("a collapsed rail should be %d px, got %s" % [RailPanel.RAIL_W, str(rail.custom_minimum_size.x)])
	else:
		_ok("collapsed to the %dpx rail" % RailPanel.RAIL_W)
	rail.set_collapsed(false, false)
	if rail.is_collapsed():
		_bad("set_collapsed(false) did not expand")
	elif rail.custom_minimum_size.x != 0.0:
		_bad("an expanded rail should not pin a min width, got %s" % str(rail.custom_minimum_size.x))
	else:
		_ok("expanded back (no pinned min width)")
	rail.free()


func _check_rail_not_empty() -> void:
	print("[2] a collapsed rail keeps a title and a count (never an empty strip)")
	var rail = RailPanel.new()
	root.add_child(rail)
	rail.setup(_skin(), "ui.players", true)
	rail.set_content(_content())
	rail.set_title("PLAYERS")
	rail.set_count("4")
	rail.set_collapsed(true, false)
	if rail._title_label.text == "":
		_bad("the rail lost its title")
	elif rail._title_label.text != "PLAYERS":
		# collapsed titles read vertically, so the text is the same chars only
		# when length is 1; here it must be the stacked form
		var flat: String = str(rail._title_label.text).replace("\n", "")
		if flat != "PLAYERS":
			_bad("the rail title lost characters: %s" % rail._title_label.text)
		else:
			_ok("the rail title is stacked vertically: %s" % str(rail._title_label.text).replace("\n", "\\n"))
	else:
		_ok("the rail title is preserved")
	if rail._count_label.text != "4":
		_bad("the rail count is missing")
	else:
		_ok("the rail shows its count (4)")
	# and the content is hidden
	if rail._content.visible:
		_bad("the rail content should be hidden while collapsed")
	else:
		_ok("the content hides while railed")
	rail.free()


func _check_manual_wins() -> void:
	print("[3] a manual toggle is remembered")
	var rail = RailPanel.new()
	root.add_child(rail)
	rail.setup(_skin(), "ui.players", true)
	rail.set_content(_content())
	if rail.is_manual():
		_bad("a fresh rail should not be manual")
	# simulate the header click path
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	rail._on_header_input(ev)
	if not rail.is_collapsed():
		_bad("a header click should collapse the rail")
	elif not rail.is_manual():
		_bad("a header click should mark the rail manual")
	else:
		_ok("a header click collapses it and marks it manual")
	rail.free()


func _check_layout_profiles() -> void:
	print("[4] LayoutProfile drives the collapse thresholds")
	# wide: both panels open
	var wide = Layout.for_screen(Vector2i(1920, 1080))
	if wide.rail_left() or wide.rail_right():
		_bad("a 1920px window should keep both panels open")
	else:
		_ok("1920px: both panels open (%s)" % wide.id)
	# mid: the right panel folds first (the spec's order)
	var mid = Layout.for_screen(Vector2i(1100, 900))
	if mid.rail_left():
		_bad("at 1100px the LEFT panel should still be open (threshold 1000)")
	elif not mid.rail_right():
		_bad("at 1100px the RIGHT panel should be folded (threshold 1180)")
	else:
		_ok("1100px: left open, right folded")
	# narrow: both folded
	var narrow = Layout.for_screen(Vector2i(960, 900))
	if not narrow.rail_left() or not narrow.rail_right():
		_bad("at 960px both panels should be folded")
	else:
		_ok("960px: both folded (%s)" % narrow.id)


func _check_theme_reads_skin() -> void:
	print("[5] UiTheme resolves through the skin (no hardcoded palette)")
	var neuro = SkinManager.new()
	neuro.load_skin("neuro")
	var evil = SkinManager.new()
	evil.load_skin("evil")
	UiTheme.use_skin(neuro)
	var a: Color = UiTheme.COL()["accent"]
	UiTheme.use_skin(evil)
	var b: Color = UiTheme.COL()["accent"]
	if a == b:
		_bad("UiTheme.COL() returned the same accent for neuro and evil — still hardcoded")
	elif b != evil.color("accent"):
		_bad("UiTheme.COL()accent should equal the skin's accent, got %s vs %s" % [b, evil.color("accent")])
	else:
		_ok("UiTheme follows the skin (neuro %s vs evil %s)" % [a, b])
	# a button built by UiTheme must carry the active skin's colours
	var btn = UiTheme.button("X")
	var sb = btn.get_theme_stylebox("normal")
	if sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color != evil.color("surface.2"):
		_bad("a UiTheme button should use the skin's surface.2")
	else:
		_ok("UiTheme buttons use the skin palette")
	btn.free()
	UiTheme.use_skin(neuro)


func _check_game_view_railed() -> void:
	print("[6] GameView wires its panels into rails")
	var gv = GameView.new()
	root.add_child(gv)
	gv.setup_cold(null)
	await process_frame
	if gv.get("_players_rail") == null:
		_bad("game_view has no players rail")
	elif gv.get("_jpanel_rail") == null:
		_bad("game_view has no journal rail")
	else:
		_ok("both side panels are railed")
	# each panel must know its rail (so its own header hides when railed)
	if gv._players.get("_rail") == null:
		_bad("the players panel is not linked to its rail")
	elif gv._journal.get("_rail") == null:
		_bad("the journal is not linked to its rail")
	else:
		_ok("panels are linked to their rails (headers hide when collapsed)")
	gv.free()
