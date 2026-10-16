extends RefCounted
## READ-1 tests: the board cell is READABLE.
##
## The defect these exist for (master-fix-plan D1-D4): `tile_view` clamped the name font to
## 8px and the price to 7px, drew the name from `name` (never the `short` field the projection
## already carries), clipped text instead of ellipsising it, and called `LayoutProfile.label_step`
## nowhere while ui_core_test happily asserted the ladder's arithmetic. Result: measured on
## `turn-human_neuro.png`, 8 of 40 ring cells carried any text at all.
##
## Two layers, deliberately:
##   * pure assertions on `TileView.fonts_for()` - cheap, and they fail with a NUMBER;
##   * a built tree - because a constant can be right while the widget ignores it (the swap-era
##     factory bug in miniature), so the live Label must be READ BACK, not assumed.

const TileView := preload("res://visual/tile_view.gd")
const LayoutProfile := preload("res://ui/core/layout_profile.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

## The two cells the plan names: 63.6px ("при cell 63.6 это 11px") and 40px (step 3).
const CELL_LIVE := 63.64
const CELL_TINY := 40.0


static func test_list() -> Array[String]:
	return [
		"test_name_font_has_a_floor_of_11",
		"test_price_font_has_a_floor_of_9",
		"test_badge_is_at_least_12px",
		"test_fonts_never_shrink_below_floors_on_any_profile",
		"test_name_renders_short_not_long",
		"test_name_uses_ellipsis_not_clip",
		"test_step3_hides_name_but_keeps_band_and_badge",
		"test_house_counter_matches_houses",
		"test_live_label_carries_the_computed_font_size",
	]


## --- pure: the font ladder -----------------------------------------------------------------

static func test_name_font_has_a_floor_of_11() -> String:
	var f: Dictionary = TileView.fonts_for(CELL_LIVE)
	var n: int = int(f["name"])
	if n < 11:
		return "cell %.1f renders its name at %dpx; the READ-1 floor is 11px (was 8px in the clamp)" % [CELL_LIVE, n]
	# the plan's worked example: 63.6px cell -> 11px
	if n != 11:
		return "cell %.1f should give an 11px name, got %dpx" % [CELL_LIVE, n]
	return ""


static func test_price_font_has_a_floor_of_9() -> String:
	var f: Dictionary = TileView.fonts_for(CELL_LIVE)
	var p: int = int(f["price"])
	if p < 9:
		return "cell %.1f renders its price at %dpx; the READ-1 floor is 9px (was 7px)" % [CELL_LIVE, p]
	return ""


static func test_badge_is_at_least_12px() -> String:
	# the map measured the owner badge at ~10px on a 720p board - too small to read a letter in
	for cell in [40.0, 54.55, 63.64, 65.45, 81.82, 98.18]:
		var f: Dictionary = TileView.fonts_for(cell)
		if float(f["badge"]) < 12.0:
			return "cell %.2f gives a %.1fpx owner badge; the floor is 12px" % [cell, float(f["badge"])]
	return ""


static func test_fonts_never_shrink_below_floors_on_any_profile() -> String:
	# The regression this guards is a SIZE-dependent one: the old clamp was fine at 1440x900
	# (11px) and dead at 1280x720 (9px), so a single-profile check would have passed.
	# cell = min(w,h)/11 (board_scene._place_board)
	for screen in [Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(880, 600)]:
		var cell: float = float(mini(screen.x, screen.y)) / 11.0
		var f: Dictionary = TileView.fonts_for(cell)
		if int(f["name"]) < 11:
			return "on %dx%d (cell %.2f) the name would be %dpx" % [screen.x, screen.y, cell, int(f["name"])]
		if int(f["price"]) < 9:
			return "on %dx%d (cell %.2f) the price would be %dpx" % [screen.x, screen.y, cell, int(f["price"])]
	return ""


## --- live: the built widget must OBEY that ladder -------------------------------------------

static func _tile(cell: float, data: Dictionary) -> Control:
	var skin := SkinManager.new()
	skin.load_skin()
	var tv: Control = TileView.new()
	tv.setup(skin, int(data.get("index", 1)), data, cell, "b")
	return tv


static func _find(tv: Control, name_hint: String) -> Label:
	for c in tv.get_children():
		if c is Label:
			var l := c as Label
			# the tile's labels in build order: name, price, houses counter, badge, mortgaged
			if name_hint == "first" and l.tooltip_text != "":
				return l
			if name_hint == "muted_price" and l.text.begins_with("$"):
				return l
	return null


static func test_name_renders_short_not_long() -> String:
	# D3: `short` is in the projection for all 40 cells and the board rendered `name`.
	var data := {"index": 1, "name": "Harbor Station", "short": "Harbor Stn", "type": "railroad", "cost": 200}
	var tv := _tile(CELL_LIVE, data)
	var l := _find(tv, "first")
	if l == null:
		return "the built tile carries no named label"
	if l.text != "Harbor Stn":
		return "the cell renders %s; it must render the projection's `short` (Harbor Stn), not `name`" % l.text
	if l.tooltip_text != "Harbor Station":
		return "the full name must survive in the tooltip, got %s" % l.tooltip_text
	return ""


static func test_name_uses_ellipsis_not_clip() -> String:
	var data := {"index": 2, "name": "Community Chest Avenue", "short": "Community Chest", "type": "community"}
	var tv := _tile(CELL_LIVE, data)
	var l := _find(tv, "first")
	if l == null:
		return "the built tile carries no named label"
	if l.clip_text:
		return "the name still uses clip_text: its last letters vanish with no sign that text was cut"
	if l.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
		return "the name must trim with an ellipsis (OVERRUN_TRIM_ELLIPSIS), got %d" % l.text_overrun_behavior
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return "a value label must not wrap (AUTOWRAP_OFF); got mode %d" % l.autowrap_mode
	return ""


static func test_step3_hides_name_but_keeps_band_and_badge() -> String:
	# label_step(40) == 3 (see ui_core_test) and the plan requires: name hidden, but the group
	# band and the owner badge stay so the cell is still distinguishable from its neighbours.
	var data := {"index": 3, "name": "Sunset Blvd", "short": "Sunset Blvd", "type": "property", "group": "brown", "cost": 60}
	var tv := _tile(CELL_TINY, data)
	if LayoutProfile.label_step(CELL_TINY) != 3:
		return "precondition: label_step(%.0f) must be 3" % CELL_TINY
	var l := _find(tv, "first")
	if l == null:
		return "the built tile carries no named label"
	if l.visible:
		return "at cell %.0f (step 3) the name must be hidden - the ladder is still dead" % CELL_TINY
	# the band must still be painted (it is the cell's remaining identity)
	var band: ColorRect = null
	for c in tv.get_children():
		if c is ColorRect and (c as ColorRect).size.x > 0.0:
			band = c as ColorRect
	if band == null:
		return "step 3 left the cell with no group band: nothing identifies it"
	# and the owner badge must still be applied
	tv.apply({"owner": 2, "owner_name": "Neuro", "owner_color": Color(0.5, 0.5, 0.9)})
	var badge_visible := false
	for c in tv.get_children():
		if c is Label and (c as Label).text == "N" and (c as Label).visible:
			badge_visible = true
	if not badge_visible:
		return "step 3 dropped the owner badge: the cell has neither name nor owner"
	return ""


static func test_house_counter_matches_houses() -> String:
	# D4: houses were 5x5px squares only. The counter is the readable signal; it must agree
	# with `houses` exactly, including the hotel case (5).
	var data := {"index": 6, "name": "Palm Row", "short": "Palm Row", "type": "property", "group": "amber"}
	var tv := _tile(CELL_LIVE, data)
	for n in [1, 3, 4, 5]:
		tv.apply({"houses": n})
		var lbl: Label = null
		for c in tv.get_children():
			if c is Label and (c as Label).text.begins_with("×"):
				lbl = c
		if lbl == null:
			return "no house counter on the tile for houses=%d" % n
		if lbl.text != "×%d" % n:
			return "houses=%d rendered as %s" % [n, lbl.text]
		tv.apply({"houses": 0})
		var gone := true
		for c in tv.get_children():
			if c is Label and (c as Label).text.begins_with("×"):
				gone = false
		if not gone:
			return "the house counter survives houses=0"
	return ""


static func test_live_label_carries_the_computed_font_size() -> String:
	# The whole point: assert on the WIDGET, not on the constant. A constant can be correct
	# while _layout_children forgets to apply it - which is exactly how the 8px clamp survived
	# a passing `label_step` test.
	var data := {"index": 8, "name": "Chest", "short": "Chest", "type": "community"}
	var tv := _tile(CELL_LIVE, data)
	var l := _find(tv, "first")
	if l == null:
		return "the built tile carries no named label"
	var f: Dictionary = TileView.fonts_for(CELL_LIVE)
	var applied: int = l.get_theme_font_size("font_size")
	if applied != int(f["name"]):
		return "fonts_for() says %dpx but the live Label carries %dpx (the ladder is computed and ignored)" % [int(f["name"]), applied]
	if applied < 11:
		return "the live name label is %dpx, below the 11px floor" % applied
	return ""
