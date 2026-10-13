extends Node
## UI Contract Runner — verifies the 6 defects from the glm53 HTML prototype
## are NOT carried into Godot (per docs/superpowers/references/opendesign-glm53-bugs.md).
## Each check is a behavioral probe on the REAL launcher (main.gd), not a
## screenshot. Run: godot --headless --path game res://tests/ui_contract_runner.tscn
##
## The 6 contracts:
##   1. Right side of the board has real data (no empty green tiles).
##   2. Tile text + icon are separated (VBox-style) — they never overlap.
##   3. Toasts sit BELOW the top row of board tiles (don't cover them).
##   4. Secondary actions (trade/build/mortgage) are real buttons, not micro-links.
##   5. Open modals fully re-render on EN locale switch (100% i18n).
##   6. Board center is an interactive scene (dice centered on the BOARD, not viewport).

const MainScript := preload("res://main.gd")
const I := preload("res://i18n/i18n.gd")

var _launcher
var _had_fail := 0
var _checks := 0

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame
	_run_tests()

func _run_tests() -> void:
	_pass("=== UI Contract Runner: glm53 prototype defects ===")
	# start the game so the board has real engine data
	var overlay: Node = _launcher.get("_overlay")
	if overlay == null:
		_fail("setup: no settings overlay"); _finish(); return
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	var gv: Node = _launcher.get("_game_view")
	if gv == null:
		_fail("setup: no game_view after START"); _finish(); return

	await _test_tiles_complete(gv)
	await _test_tile_no_overlap(gv)
	await _test_toast_position(gv)
	await _test_secondary_buttons(gv)
	await _test_modal_relabel(gv)
	await _test_dice_centered(gv)

	_finish()

func _finish() -> void:
	if _had_fail:
		print("UI CONTRACT RUNNER: FAILED (%d checks, %d failed)" % [_checks, _had_fail])
		get_tree().quit(1)
	else:
		print("UI CONTRACT RUNNER: ALL PASSED (%d checks)" % _checks)
		get_tree().quit(0)

## CONTRACT 1: every tile has a name; priced tiles have a price; icon tiles have an icon.
func _test_tiles_complete(gv: Node) -> void:
	var board: Node = gv.get("_board_scene").get("_board")
	if board == null:
		_fail("C1 setup: no board"); return
	var empty_name := 0
	var empty_price := 0
	var empty_icon := 0
	var priced := 0
	for tv in board.get("_tile_nodes"):
		var nm: String = str(tv.get("_name").get("text"))
		if nm == "":
			empty_name += 1
		# priced tile types (property/railroad/utility/tax) must show a price
		var typ: String = str(tv.get("_type"))
		if typ in ["property", "railroad", "utility", "tax"]:
			priced += 1
			var price: String = str(tv.get("_price").get("text"))
			if price == "":
				empty_price += 1
		# icon tiles (chance/community/railroad/utility/tax/corners) must have a texture
		if tv.get("_icon").get("visible") and tv.get("_icon").get("texture") == null:
			empty_icon += 1
	if empty_name > 0:
		_fail("C1: %d tiles have empty name (right side empty-green bug)" % empty_name)
	else:
		_pass("C1: all %d tiles have a name" % board.get("_tile_nodes").size())
	if empty_price > 0:
		_fail("C1: %d of %d priced tiles have empty price" % [empty_price, priced])
	else:
		_pass("C1: all %d priced tiles show a price" % priced)
	if empty_icon > 0:
		_fail("C1: %d icon tiles have no texture" % empty_icon)
	else:
		_pass("C1: all icon tiles have a texture")

## CONTRACT 2: name/price/icon rects never overlap on any tile (only VISIBLE elements).
func _test_tile_no_overlap(gv: Node) -> void:
	var board: Node = gv.get("_board_scene").get("_board")
	if board == null:
		_fail("C2 setup: no board"); return
	var overlaps := 0
	var overlap_detail := ""
	for tv in board.get("_tile_nodes"):
		var name_rect := Rect2(tv.get("_name").get("position"), tv.get("_name").get("size"))
		var price_rect := Rect2(tv.get("_price").get("position"), tv.get("_price").get("size"))
		var icon_rect := Rect2(tv.get("_icon").get("position"), tv.get("_icon").get("size"))
		var name_vis: bool = tv.get("_name").get("visible")
		var price_vis: bool = tv.get("_price").get("visible")
		var icon_vis: bool = tv.get("_icon").get("visible")
		if icon_vis:
			# strict overlap: require > 1px of real intersection (adjacent/touching
			# rects are fine — the icon sits beside the name, not on it)
			if name_vis and _strict_overlap(name_rect, icon_rect):
				overlaps += 1
				overlap_detail += " tile%d(name×icon)" % int(tv.get("_index"))
			if price_vis and _strict_overlap(price_rect, icon_rect):
				overlaps += 1
				overlap_detail += " tile%d(price×icon)" % int(tv.get("_index"))
			if overlaps > 0 and overlap_detail.length() < 200:
				overlap_detail += " [name=%s icon=%s price=%s]" % [name_rect, icon_rect, price_rect]
	if overlaps > 0:
		_fail("C2: %d name/price/icon rect overlaps (text on icon):%s" % [overlaps, overlap_detail])
	else:
		_pass("C2: no name/price/icon overlap on any tile")

## CONTRACT 3: toast stack top sits BELOW the top row of board tiles.
func _test_toast_position(gv: Node) -> void:
	var toast: Node = gv.get("_toast_stack")
	if toast == null:
		_fail("C3 setup: no toast stack"); return
	var top: float = float(toast.get("_toast_container").get("offset_top"))
	var board_scene: Node = gv.get("_board_scene")
	var board_top: float = board_scene.get("position").y
	var cell: float = float(board_scene.get("_cell"))
	# toasts must start below the top row of tiles (board_top + one cell)
	var required: float = board_top + cell
	if top < required:
		_fail("C3: toast top=%.0f < required %.0f (covers top row of board)" % [top, required])
	else:
		_pass("C3: toast top=%.0f sits below top row (>= %.0f)" % [top, required])

## CONTRACT 4: secondary actions are real Buttons (not micro-links).
func _test_secondary_buttons(gv: Node) -> void:
	var actions: Node = gv.get("_actions")
	if actions == null:
		_fail("C4 setup: no action panel"); return
	var missing := 0
	for act in ["build_house", "sell_house", "mortgage_property", "unmortgage_property", "propose_trade"]:
		var btn = actions.call("_make_button", act, {}, 0)
		if btn == null or not (btn is Button):
			missing += 1
			_fail("C4: action '%s' is not a Button (micro-link bug)" % act)
	if missing == 0:
		_pass("C4: all secondary actions are real Buttons")

## CONTRACT 5: an open modal fully re-renders on EN locale switch.
func _test_modal_relabel(gv: Node) -> void:
	var modals: Node = gv.get("_modals")
	if modals == null:
		_fail("C5 setup: no modal host"); return
	I.set_locale("ru")
	modals.call("show_game_over", "Host", 5, 1500, 4)
	await get_tree().process_frame
	var ru_found: bool = _find_label_text(modals, "ПАРТИЯ ОКОНЧЕНА") or _find_label_text(modals, "MATCH OVER")
	I.set_locale("en")
	# game_view._on_locale_changed fires; modal must re-render to EN
	await get_tree().process_frame
	await get_tree().process_frame
	var en_found: bool = _find_label_text(modals, "MATCH OVER")
	if not en_found:
		_fail("C5: open game-over modal did not re-render to EN (stuck RU)")
	else:
		_pass("C5: open modal re-renders to EN on locale switch")
	modals.call("close")

## CONTRACT 6: dice are centered on the BOARD, not the viewport.
func _test_dice_centered(gv: Node) -> void:
	var bs: Node = gv.get("_board_scene")
	var dice: Node = bs.get("_dice_stage")
	if dice == null:
		_fail("C6 setup: no dice stage"); return
	# In headless the HBox doesn't lay out children (board_scene.size.x=0), so
	# simulate a real laid-out board region before rolling. The dice must center
	# on THIS rect, not the viewport center.
	var board_rect := Rect2(0, 0, 600, 600)
	bs.set("size", board_rect.size)
	dice.set("size", board_rect.size)
	dice.call("set_animations", false)
	dice.call("roll", 3, 4)
	await get_tree().process_frame
	var nodes: Array = dice.get("_dice_nodes")
	if nodes.is_empty():
		_fail("C6: no dice nodes after roll"); return
	# The pair of dice is symmetric around the board center — check the midpoint
	# of the two dice, not the first die alone.
	var pair_center: Vector2 = Vector2.ZERO
	for n in nodes:
		pair_center += (n.get("position") + n.get("size") * 0.5)
	pair_center /= float(nodes.size())
	var board_center: Vector2 = board_rect.size * 0.5
	var dist: float = (pair_center - board_center).length()
	print("  C6 debug: pair_center=%s board_center=%s" % [pair_center, board_center])
	if dist > 20.0:
		_fail("C6: dice pair center %s is %.0fpx from board center %s (viewport-centered bug)" % [pair_center, dist, board_center])
	else:
		_pass("C6: dice pair centered on board (%.0fpx off)" % dist)

## Recursively find a Label whose text contains `substr`.
func _find_label_text(root: Node, substr: String) -> bool:
	if root is Label and str(root.get("text")).contains(substr):
		return true
	for ch in root.get_children():
		if _find_label_text(ch, substr):
			return true
	return false

## True only if two rects overlap by more than 1px in BOTH axes (touching edges
## are not an overlap — the icon sits beside the name, not on it).
func _strict_overlap(a: Rect2, b: Rect2) -> bool:
	var ix: float = minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var iy: float = minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	return ix > 1.0 and iy > 1.0

func _pass(msg: String) -> void:
	_checks += 1
	print("PASS: " + msg)

func _fail(msg: String) -> void:
	_had_fail += 1
	_checks += 1
	print("FAIL: " + msg)
