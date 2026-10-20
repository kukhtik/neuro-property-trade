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
		"test_smallest_step_keeps_the_name_band_and_badge",
		"test_no_cell_is_ever_blank_across_sizes",
		"test_house_counter_matches_houses",
		"test_live_label_carries_the_computed_font_size",
		"test_rectangular_cell_keeps_every_child_inside",
		"test_ring_fills_the_frame_with_legal_cells",
		"test_corner_screens_carry_the_glance_layer",
		"test_business_cell_fonts_are_large_enough",
	]


## --- pure: the font ladder -----------------------------------------------------------------

static func test_name_font_has_a_floor_of_11() -> String:
	var f: Dictionary = TileView.fonts_for(CELL_LIVE)
	var n: int = int(f["name"])
	if n < 11:
		return "cell %.1f renders its name at %dpx; the READ-1 floor is 11px (was 8px in the clamp)" % [CELL_LIVE, n]
	# The worked example used to demand EXACTLY 11px at a 63.6px cell. That was the floor, not the
	# intent: the owner asked for larger business-cell fonts (19.10), so the assertion is now the
	# floor itself - and the exact value is pinned by test_business_cell_fonts_are_large_enough.
	if n > TileView.NAME_MAX or n < TileView.NAME_MIN:
		return "cell %.1f renders its name at %dpx, outside the %d..%d band" % [
			CELL_LIVE, n, TileView.NAME_MIN, TileView.NAME_MAX]
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
	for c in tv.text_labels():
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


static func test_smallest_step_keeps_the_name_band_and_badge() -> String:
	# THE OLD CONTRACT WAS THE DEFECT. This test used to require the name to be HIDDEN at step 3,
	# because `label_step` had a "hide the name" rung and the plan trusted the group band to identify
	# the cell. The owner's report ("клетки почему-то пустые вообще") is exactly what that produced on
	# a real board: at 1440x900 the console starved the board to 796x449, every cell fell to 41px =
	# step 3, and the 12 non-property cells (no price either) rendered as EMPTY squares.
	#
	# The contract now: a cell is NEVER blank. At the smallest step the name must still be VISIBLE,
	# and the band and the owner badge stay as well - identity does not give way to size.
	var data := {"index": 3, "name": "Sunset Blvd", "short": "Sunset Blvd", "type": "property", "group": "brown", "cost": 60}
	var tv := _tile(CELL_TINY, data)
	if LayoutProfile.label_step(CELL_TINY) != 3:
		return "precondition: label_step(%.0f) must be 3" % CELL_TINY
	var l := _find(tv, "first")
	if l == null:
		return "the built tile carries no named label"
	if not l.visible:
		return "at cell %.0f (step 3) the name is HIDDEN - a nameless square is the owner's 'empty cell' defect" % CELL_TINY
	if l.text.strip_edges() == "":
		return "at cell %.0f the name label is visible but empty" % CELL_TINY
	# the band must still be painted (the group colour)
	var band: ColorRect = null
	for c in _all_controls(tv):
		if c is ColorRect and (c as ColorRect).size.x > 0.0:
			band = c as ColorRect
	if band == null:
		return "step 3 left the cell with no group band: nothing identifies it"
	# and the owner badge must still be applied
	tv.apply({"owner": 2, "owner_name": "Neuro", "owner_color": Color(0.5, 0.5, 0.9)})
	var badge_visible := false
	for c in tv.text_labels():
		if c is Label and (c as Label).text == "N" and (c as Label).visible:
			badge_visible = true
	if not badge_visible:
		return "step 3 dropped the owner badge"
	return ""


static func test_no_cell_is_ever_blank_across_sizes() -> String:
	# The regression this guards is the one the owner hit: a board small enough that EVERY cell lost
	# its name. Walk the sizes a real window can produce and require a visible name on each.
	for cell in [24.0, 32.0, 41.0, 53.0, 70.0, 86.0]:
		var data := {"index": 0, "name": "Start", "short": "Start", "type": "go"}
		var tv := _tile(cell, data)
		var l := _find(tv, "first")
		if l == null or not l.visible or (l as Label).text.strip_edges() == "":
			return "a %.0fpx cell renders with no visible name - a blank square (the owner's defect)" % cell
	return ""


static func test_house_counter_matches_houses() -> String:
	# D4: houses were 5x5px squares only. The counter is the readable signal; it must agree
	# with `houses` exactly, including the hotel case (5).
	var data := {"index": 6, "name": "Palm Row", "short": "Palm Row", "type": "property", "group": "amber"}
	var tv := _tile(CELL_LIVE, data)
	for n in [1, 3, 4, 5]:
		tv.apply({"houses": n})
		var lbl: Label = null
		for c in tv.text_labels():
			if c is Label and (c as Label).text.begins_with("×"):
				lbl = c
		if lbl == null:
			return "no house counter on the tile for houses=%d" % n
		if lbl.text != "×%d" % n:
			return "houses=%d rendered as %s" % [n, lbl.text]
		tv.apply({"houses": 0})
		var gone := true
		for c in tv.text_labels():
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


static func test_rectangular_cell_keeps_every_child_inside() -> String:
	# B1 «кольцо во весь кадр»: a tile is no longer square - a side cell is band-wide and tall
	# (190x88 at 1600x1200) and a corner is 320x190. Every child must stay inside the rect, or the
	# board leaks: the name would hang over the neighbouring cell and the band would sit outside.
	var skin := SkinManager.new()
	skin.load_skin()
	var cases := [
		{"w": 190.0, "h": 88.0, "side": "l", "label": "left cell 190x88"},
		{"w": 104.0, "h": 190.0, "side": "b", "label": "bottom cell 104x190"},
		{"w": 320.0, "h": 190.0, "side": "corner", "label": "corner 320x190"},
	]
	for cse in cases:
		var w := float(cse["w"])
		var h := float(cse["h"])
		var tv: Control = TileView.new()
		tv.setup(skin, 6, {"index": 6, "name": "Palm Row", "short": "Palm Row", "type": "property",
			"group": "amber", "cost": 120}, w, str(cse["side"]), h)
		tv.size = Vector2(w, h)
		tv.apply({"owner": 1, "owner_name": "Хост", "houses": 2})
		for ch in _all_controls(tv):
			var ctl := ch as Control
			if ctl == null or not ctl.visible:
				continue
			var r := _rect_in(ctl, tv)
			if r.position.x < -0.5 or r.position.y < -0.5 \
					or r.end.x > w + 0.5 or r.end.y > h + 0.5:
				return "%s: a visible child occupies %s, outside the %sx%s cell" % [
					str(cse["label"]), str(r), str(w), str(h)]
	return ""


static func test_ring_fills_the_frame_with_legal_cells() -> String:
	# B1 «кольцо во весь кадр»: the ring is the frame, not a centred square. Four invariants, each a
	# requirement rather than a preference:
	#   R-17  every cell's short side >= 77px on every profile;
	#   edges the ring touches all four sides of the frame (this is what R-1 "no empty frame" means);
	#   cover no gaps between neighbouring cells and no cell outside the frame;
	#   corner the four corners are WIDER than the band (they carry the glance layer).
	var BoardScene := preload("res://visual/board_scene.gd")
	for frame in [Vector2(1600, 1200), Vector2(1920, 1080), Vector2(1440, 900), Vector2(1280, 720)]:
		var m: Dictionary = BoardScene.ring_metrics(frame)
		var band: float = m["band"]
		var corner: float = m["corner"]
		var o0: Vector2 = m["origin"]
		var ring0 := Vector2(float(m["ring_w"]), float(m["ring_h"]))
		var rects: Array = []
		for i in 40:
			rects.append(BoardScene.tile_rect(i, m, frame))
		var min_side := 1e9
		var min_x := 1e9
		var min_y := 1e9
		var max_x := -1e9
		var max_y := -1e9
		for i in 40:
			var r: Rect2 = rects[i]
			min_side = minf(min_side, minf(r.size.x, r.size.y))
			min_x = minf(min_x, r.position.x)
			min_y = minf(min_y, r.position.y)
			max_x = maxf(max_x, r.end.x)
			max_y = maxf(max_y, r.end.y)
			if r.position.x < o0.x - 0.5 or r.position.y < o0.y - 0.5 \
					or r.end.x > o0.x + ring0.x + 0.5 or r.end.y > o0.y + ring0.y + 0.5:
				return "on %s cell %d sits outside the ring rect: %s" % [str(frame), i, str(r)]
		if min_side < BoardScene.MIN_CELL - 0.5:
			return "on %s the smallest cell side is %.2fpx, below the %.0fpx floor" % [
				str(frame), min_side, BoardScene.MIN_CELL]
		# The ring fills ITS OWN rect. When the frame is too small for legal cells the ring is bigger
		# than the frame and sits centred (R-18: the frame grows, the board never shrinks), so the
		# comparison is against the ring rect, not against the frame.
		var o: Vector2 = m["origin"]
		var ring_w: float = m["ring_w"]
		var ring_h: float = m["ring_h"]
		if min_x > o.x + 0.5 or min_y > o.y + 0.5 \
				or max_x < o.x + ring_w - 0.5 or max_y < o.y + ring_h - 0.5:
			return "on %s the ring does not fill its rect: x %.1f..%.1f, y %.1f..%.1f (rect %.1f..%.1f, %.1f..%.1f)" % [
				str(frame), min_x, max_x, min_y, max_y, o.x, o.x + ring_w, o.y, o.y + ring_h]
		if ring_w <= frame.x + 0.5 and absf(o.x) > 0.5:
			return "on %s the ring fits but is not flush with the frame (origin x %.1f)" % [str(frame), o.x]
		if ring_h <= frame.y + 0.5 and absf(o.y) > 0.5:
			return "on %s the ring fits but is not flush with the frame (origin y %.1f)" % [str(frame), o.y]
		if corner <= band:
			return "on %s the corner (%.1f) is not wider than the band (%.1f)" % [
				str(frame), corner, band]
		for i in 40:
			for j in range(i + 1, 40):
				var a: Rect2 = rects[i]
				var b: Rect2 = rects[j]
				var overlap := a.intersection(b)
				if overlap.size.x > 1.0 and overlap.size.y > 1.0:
					return "on %s cells %d and %d overlap by %.1fx%.1f" % [
						str(frame), i, j, overlap.size.x, overlap.size.y]
	return ""


static func test_corner_screens_carry_the_glance_layer() -> String:
	# B1: the four corners are SCREENS, and the screen lives INSIDE the cell. Two gates taught this:
	# READ-01 wants every ring cell to keep an identifier, PANEL-NOT-EMPTY wants a big panel to carry
	# text - an overlay label satisfied neither. So: the name stays (small), the glance line is big.
	var BoardScene := preload("res://visual/board_scene.gd")
	var m: Dictionary = BoardScene.ring_metrics(Vector2(1600, 1200))
	var band: float = m["band"]
	var fs_wanted: int = int(maxf(14.0, band * BoardScene.GLANCE_F))
	var eff: float = float(fs_wanted) * 390.0 / 1600.0
	if eff < 12.0:
		return "the corner glance font at a %.0fpx band is %dpx = %.2fpx on a 390 frame (floor 12)" % [
			band, fs_wanted, eff]
	var skin := SkinManager.new()
	skin.load_skin()
	var tv: Control = TileView.new()
	tv.setup(skin, 0, {"index": 0, "name": "Старт", "short": "Старт", "type": "corner"}, 320.0, "corner", 190.0)
	tv.size = Vector2(320.0, 190.0)
	tv.set_plain(true)
	tv.set_screen("ХОД: Хост", fs_wanted)
	var screen: Label = null
	var name_lbl: Label = null
	for c in tv.text_labels():
		if not (c is Label):
			continue
		var l := c as Label
		if l.name == "tile-screen":
			screen = l
		elif l.tooltip_text != "":
			name_lbl = l
	if screen == null:
		return "the corner cell carries no tile-screen label"
	if not screen.visible:
		return "the corner screen exists but is hidden"
	if screen.text != "ХОД: Хост":
		return "the screen reads %s" % screen.text
	if screen.get_theme_font_size("font_size") != fs_wanted:
		return "the screen carries %dpx, the formula says %dpx" % [
			screen.get_theme_font_size("font_size"), fs_wanted]
	var sr := Rect2(screen.position, screen.size)
	if sr.end.x > 320.5 or sr.end.y > 190.5 or sr.position.x < -0.5 or sr.position.y < -0.5:
		return "the screen %s is not inside the 320x190 cell" % str(sr)
	if name_lbl == null or not name_lbl.visible:
		return "the corner's NAME disappeared - READ-01 and R-12 both require it"
	if name_lbl.get_theme_font_size("font_size") < BoardScene.MIN_CELL / 7.0:
		return "the corner name is %dpx, too small to identify the cell" % name_lbl.get_theme_font_size("font_size")
	tv.free()
	return ""


## Every Control under a node, at any depth: after the text moved inside the cell's face, checking
## only direct children would silently skip every label.
static func _all_controls(root: Node) -> Array:
	var out: Array = []
	for ch in root.get_children():
		if ch is Control:
			out.append(ch)
		out.append_array(_all_controls(ch))
	return out


## A Control's rect expressed in `root`'s coordinates: children of the cell's text body live at
## negative local positions by design (the body cancels the face's padding), so their own
## `position` is not comparable with the cell's size.
static func _rect_in(node: Control, root: Control) -> Rect2:
	var pos := node.position
	var n := node.get_parent()
	while n != null and n != root:
		if n is Control:
			pos += (n as Control).position
		n = n.get_parent()
	return Rect2(pos, node.size)


static func test_business_cell_fonts_are_large_enough() -> String:
	# Owner, 19.10: "поля бизнесов нужно немного переделать - увеличить шрифты". Written as a floor on
	# the BUILT cell's font, not on the ratio: the ratios can be right while the cap or the step ladder
	# still hands the label a small size.
	var cases := [
		{"w": 190.0, "h": 88.0, "side": "l", "label": "side cell 190x88"},
		{"w": 107.0, "h": 190.0, "side": "b", "label": "top cell 107x190"},
	]
	var skin := SkinManager.new()
	skin.load_skin()
	for cse in cases:
		var w := float(cse["w"])
		var h := float(cse["h"])
		var tv: Control = TileView.new()
		tv.setup(skin, 6, {"index": 6, "name": "Palm Row", "short": "Palm Row", "type": "property",
			"group": "amber", "cost": 120}, w, str(cse["side"]), h)
		tv.size = Vector2(w, h)
		var name_lbl: Label = null
		var price_lbl: Label = null
		for c in tv.text_labels():
			var l := c as Label
			if l.name == "tile-name":
				name_lbl = l
			elif l.name == "tile-price":
				price_lbl = l
		if name_lbl == null or price_lbl == null:
			return "%s: the cell lost its name or price label" % str(cse["label"])
		if name_lbl.get_theme_font_size("font_size") < 16:
			return "%s: the name is %dpx; business cells need at least 16px (owner's request)" % [
				str(cse["label"]), name_lbl.get_theme_font_size("font_size")]
		if price_lbl.get_theme_font_size("font_size") < 12:
			return "%s: the price is %dpx; business cells need at least 12px (owner's request)" % [
				str(cse["label"]), price_lbl.get_theme_font_size("font_size")]
		tv.free()
	return ""
