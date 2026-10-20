extends Control
## One board tile drawn the way the prototype draws it (`.tile`): a padded face, a group
## band on the INNER edge, the name, the price, the house marks on the band, the owner
## badge and the state frame (owned / active / selected / target / dimmed / mortgaged).
##
## v3 rebuild — replaces the archived tile. Everything is built from skin tokens; the
## board scene rebuilds tiles when the cell size changes, so fonts stay right.

signal pressed(index: int)

const UiTheme := preload("res://ui/theme.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const I18n := preload("res://i18n/i18n.gd")
const LayoutProfile := preload("res://ui/core/layout_profile.gd")

## Readability floors (READ-1). The old renderer clamped the name to 8px and the price to 7px,
## so on a 1280x720 board the cell name died in its own background and 32 of 40 cells carried
## no readable text at all (measured on turn-human_neuro.png). Text below ~10px is not text on
## a stream: it is texture. These floors are the contract, not a preference.
##
## THE FONT LADDER SCALES WITH THE CELL, so a board with room for readable text gets it. The old caps
## (name 13, price 11) were the reason the board still looked empty after every cell was given a
## name: whatever the board's size, the name could not exceed 13px. On the owner's 1310px stage the
## cells are 68px - room for ~15px - and the ceiling spent that room on nothing. The lower half of
## the ring measured as blank because its text was too small to see, not because it was missing.
## (The camera's double-centring bug produced the same symptom from the other direction; both had to
## be fixed for the cells to read.)
## Owner, 19.10: "поля бизнесов нужно немного переделать - увеличить шрифты". The ratios and the caps
## below are what makes a business cell readable at the B1 band: 0.20/0.16 of the SHORT side gives
## 17/14px on a 190x88 side cell and 21/17px on a 107x190 top cell - against 15/11 and 18/13 before.
const NAME_MIN := 12
const NAME_MAX := 26
const NAME_RATIO := 0.20
const PRICE_MIN := 10
const PRICE_MAX := 20
const PRICE_RATIO := 0.16
const BADGE_MIN := 12.0
const HOUSES_MIN := 10

var index := 0
var _skin: SkinManager
var _cell := 64.0
## B1 «кольцо во весь кадр»: a tile is NOT square any more. A side cell is band-wide and tall
## (190x88 at 1600x1200), a corner is 320x190. `_w`/`_h` carry the rect; `_cell` stays the SHORT
## side and keeps every existing metric (fonts, band, label step) anchored to it, so a square tile
## behaves exactly as before.
var _w := 64.0
var _h := 64.0
var _side := "b"           # which ring edge: "b" bottom, "l" left, "t" top, "r" right
var _type := "property"
var _group := ""
var _corner := false

var _face: Panel
## Text body inside the face: gives the face its lines and keeps tile-local coordinates.
var _body: Control
var _band: ColorRect
var _name: Label
var _price: Label
var _houses: HBoxContainer
var _badge: Label
var _houses_lbl: Label
var _state: Panel
var _mortgaged: Label
## Set by `_layout_children`: whether this cell is tall enough for the house counter. `apply()` used
## to decide it alone (`houses > 0 and _name.visible`), which is what pushed the counter out of a
## short B1 cell.
var _show_houses := true
## A corner is a SCREEN in B1: its face and border stay, its own price/houses/badge step aside for
## the glance line that BoardScene writes into it. THE NAME STAYS - it is the cell's identifier
## (READ-01) and R-12 forbids losing it; the screen line is what gets big.
var _plain := false
var _screen: Label
var _screen_text := ""


func setup(skin: SkinManager, idx: int, data: Dictionary, cell: float, side: String, h: float = 0.0) -> void:
	_skin = skin
	index = idx
	_w = cell
	_h = h if h > 0.0 else cell
	_cell = minf(_w, _h)
	_side = side
	_type = str(data.get("type", "property"))
	_group = str(data.get("group", ""))
	_corner = side == "corner"
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _face != null:
		return   # reuse: only re-layout below
	_build(data)
	_layout_children()


## Re-lay-out a BUILT tile for a new rect. `setup()` returns early when the widgets already exist
## (`if _face != null: return`), so a frame change used to leave every label at the previous frame's
## width. BoardScene calls this on every placement pass.
func resize(w: float, h: float) -> void:
	_w = w
	_h = h if h > 0.0 else w
	_cell = minf(_w, _h)
	if _face == null:
		return
	_layout_children()


## Every Label this cell renders, wherever it sits in the tree. The text moved INSIDE the face
## (PANEL-NOT-EMPTY counts a panel's own subtree), so callers - tests and the gates - ask the cell
## instead of walking `get_children()` and silently finding nothing.
func text_labels() -> Array:
	var out: Array = []
	_collect_labels(self, out)
	return out


func _collect_labels(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is Label:
			out.append(ch)
		_collect_labels(ch, out)


## Turn the cell into a plain SCREEN (no price, no houses, no owner badge).
func set_plain(on: bool) -> void:
	_plain = on
	if _face == null:
		return
	_layout_children()


## Write the glance line into a corner screen. `px` is the font BoardScene computed from the band.
func set_screen(text: String, px: int, kind: String = "") -> void:
	_screen_text = text
	if _screen == null:
		return
	if kind != "":
		_screen.name = "glance-" + kind     # the gate finds the role by name, not by position
	_screen.text = text
	_screen.add_theme_font_size_override("font_size", maxi(10, px))
	_layout_children()


func _build(data: Dictionary) -> void:
	_face = Panel.new()
	# THE FACE IS LAID OUT BY `_layout_children`, NOT BY ITS ANCHORS. This line used to also call
	# `set_anchors_preset(PRESET_FULL_RECT)`, which makes a Control fill its parent on its own - and
	# `_layout_children` then ALSO set `_face.position`/`_face.size` to the padded rect. The two
	# mechanisms fought: measured on the live tree every cell was 95x95 with a 186x186 face hanging
	# out of it, so all 40 cells drew a second panel twice their own size. That overlap is what the
	# owner saw as cells "по две". One owner for a rect: the layout.
	_face.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark if _corner else UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)
	# B1/PANEL-NOT-EMPTY: the cell's text lives INSIDE its face. As siblings the face carried 0 lines,
	# which the gate rightly calls an empty 40 000px^2 panel; and `_body` sits at -inner.position so
	# every position below keeps its tile-local coordinates.
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_child(_body)

	_band = ColorRect.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.color = _band_colour()
	add_child(_band)

	# READ-1/D3: the ring renders `short` (40/40 cells carry one in board.json) with `name` as the
	# fallback - the short form is what fits a cell, the long name lives in the tooltip/inspector.
	_name = UiTheme.label(str(data.get("short", data.get("name", ""))), 10, UiTheme.COL().text)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# WRAP, not cut: with the larger business-cell fonts (owner, 19.10) "Sunset Blvd" needs 118px in a
	# 98px box - the ellipsis hid the difference between a wide font and a narrow cell. Two lines fit
	# the 190px-tall cells; `clip_text` keeps the minimum from exploding (the screen-label trap).
	# FIT, don't cut (owner, 19.10: "никаких многоточий или неровных переносов, умещай и думай как
	# сделать красиво"). The name is ONE line whose FONT follows the word: `_fit_px` walks down from
	# the cap until the whole word fits the box, and never goes below the legibility floor. The
	# overrun behaviour stays NO_TRIMMING as a last resort - with the fit in place it never fires,
	# and if it ever did, a visible overflow would be a bug report instead of a silent ellipsis.
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_name.custom_minimum_size = Vector2.ZERO
	# OVERRUN_TRIM_ELLIPSIS rather than clip_text: a clipped label silently loses its last
	# letters (the reader sees "Harbor S"), an ellipsis says "there is more" and the tooltip
	# below carries the whole name.
	_name.name = "tile-name"
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var full_name := str(data.get("name", ""))
	if full_name != "":
		_name.tooltip_text = full_name
	_body.add_child(_name)

	var cost: int = int(data.get("cost", 0))
	_price = UiTheme.label(MoneyFmt.make("$").amount(cost) if cost > 0 else "", 8, UiTheme.COL().money)
	_price.name = "tile-price"
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_price)

	_houses = UiTheme.hbox(1)
	_houses.visible = false
	_houses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_houses)

	# READ-1/D4: the house squares are 5x5px (4.5px at 720p) - a 4.5px glyph is not a count. The
	# textual "xN" rides next to them and is the signal the gate reads; the squares stay as the
	# at-a-glance duplicate.
	_houses_lbl = UiTheme.label("", HOUSES_MIN, UiTheme.COL().success)
	_houses_lbl.name = "tile-houses"
	_houses_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_houses_lbl.visible = false
	_houses_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_houses_lbl)

	_badge = UiTheme.label("", 9, UiTheme.COL().text)
	_badge.name = "tile-badge"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.clip_text = true
	_badge.visible = false
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_badge)

	_mortgaged = UiTheme.label("M", 9, UiTheme.COL().danger)
	_mortgaged.name = "tile-mortgaged"
	_mortgaged.visible = false
	_mortgaged.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_mortgaged)

	_state = Panel.new()
	_state.set_anchors_preset(Control.PRESET_FULL_RECT)
	_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state.visible = false
	add_child(_state)

	# B1: the corner SCREEN. One big line, written by BoardScene from the projection.
	_screen = UiTheme.label("", 20, UiTheme.COL().text)
	_screen.name = "tile-screen"
	_screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_screen.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# CLIP, or the minimum size wins: a Label with wrapping computes its minimum HEIGHT from the
	# width it had at that moment. Measured on the live tree: the four screens reported 555..989px
	# tall inside 190px cells and covered the board, because their minimum had been computed while
	# the width was still small. `clip_text` collapses the minimum to one line and lets the assigned
	# rect rule.
	# Two lines MAX, and the break is written in the string itself (the phase key carries a
	# hard newline), so a corner never rag-wraps: the value sits on its own line under its label.
	_screen.max_lines_visible = 2
	_screen.custom_minimum_size = Vector2.ZERO
	_screen.visible = false
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_screen)


## E-3: the hover tooltip - name, group, price and the rent the tile charges RIGHT NOW.
##
## Only the parts that exist are shown, so a corner cell ("Start") does not advertise a rent of $0,
## and an unowned plot still tells a viewer what it would cost them to land on it later.
func _tip_update(entry: Dictionary) -> void:
	var parts: Array = []
	if _group != "":
		# The group as the repo already renders it elsewhere (the inspector shows the raw token).
		# Introducing a `group.*` key family here would be a half-built translation: the keys do not
		# exist, and I18n.t would print the sentinel `{group.brown}` - the exact defect HG-09 exists to
		# catch. If groups get localised, they get localised everywhere, in one change.
		parts.append(_group)
	var cost: int = int(entry.get("cost", 0))
	if cost > 0:
		parts.append(I18n.t("tip.cost", [cost]))
	var rent_now: int = int(entry.get("rent_now", 0))
	if rent_now > 0:
		var houses: int = int(entry.get("houses", 0))
		parts.append(I18n.t("tip.rent_hotel", [rent_now]) if houses >= 5
			else I18n.t("tip.rent_houses", [rent_now, houses]) if houses > 0
			else I18n.t("tip.rent", [rent_now]))
	if bool(entry.get("mortgaged", false)):
		parts.append(I18n.t("ins.mortgaged"))
	var head: String = _name.tooltip_text if _name.tooltip_text != "" else str(entry.get("name", ""))
	tooltip_text = head if parts.is_empty() else "%s\n%s" % [head, " · ".join(parts)]


func _band_colour() -> Color:
	if _type == "property" and _group != "":
		return UiTheme.skin().group_color(_group)
	match _type:
		"go":
			return UiTheme.COL().success
		"chance", "community":
			return UiTheme.COL().accent2
		"tax", "go_to_jail":
			return UiTheme.COL().danger
		"railroad", "utility":
			return UiTheme.COL().text_dim
	return UiTheme.COL().border


## READ-1 font contract, extracted so `tile_view_test` pins the FLOORS and not a screenshot.
## The bug this exists to prevent: `clampi(c*0.145, 8, 13)` on a 65px cell gave 9px, and the
## same cell at 60px gave 8px - a 40-cell ring where 32 names were unreadable.
static func fonts_for(cell: float) -> Dictionary:
	return {
		"name": clampi(int(round(cell * NAME_RATIO)), NAME_MIN, NAME_MAX),
		"price": clampi(int(round(cell * PRICE_RATIO)), PRICE_MIN, PRICE_MAX),
		"badge": maxf(BADGE_MIN, cell * 0.20),
		"houses": HOUSES_MIN,
	}


## The largest font size in [lo, hi] at which `text` fits `w` x `h` on one line.
## Used instead of ellipsis/wrapping: a cell must show its whole word, and the type must be as large
## as that word allows. Returns `lo` when even the floor does not fit - the caller then has a real
## problem worth seeing (an overflow), not one hidden behind three dots.
func _fit_px(text: String, w: float, h: float, lo: int, hi: int) -> int:
	if text.strip_edges() == "" or w <= 1.0 or h <= 1.0:
		return hi
	var font: Font = _name.get_theme_font("font")
	var px: int = hi
	while px > lo:
		var need := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		if need.x <= w and need.y <= h:
			return px
		px -= 1
	return lo


func _layout_children() -> void:
	var c := _cell                      # the SHORT side drives every metric below
	var pad := 2.0
	var inner := Rect2(pad, pad, _w - pad * 2.0, _h - pad * 2.0)
	# band thickness: full strip along the INNER edge
	var bt: float = maxf(4.0, minf(c * 0.16, 13.0))
	if _side == "corner":
		bt = 0.0
	# face occupies the padded rect
	_face.position = inner.position
	_face.size = inner.size
	if _body != null:
		_body.position = -inner.position
		_body.size = inner.size
	var band := Rect2()
	match _side:
		"b":   # bottom row → band on top (facing centre)
			band = Rect2(inner.position, Vector2(inner.size.x, bt))
		"t":
			band = Rect2(inner.position + Vector2(0, inner.size.y - bt), Vector2(inner.size.x, bt))
		"l":
			band = Rect2(inner.position + Vector2(inner.size.x - maxf(4.0, c * 0.10), 0),
				Vector2(maxf(4.0, c * 0.10), inner.size.y))
		"r":
			band = Rect2(inner.position, Vector2(maxf(4.0, c * 0.10), inner.size.y))
	_band.position = band.position
	_band.size = band.size
	# text block: the inner rect minus the band
	var text_rect := inner
	if _side == "b":
		text_rect.position.y += bt
		text_rect.size.y -= bt
	elif _side == "t":
		text_rect.size.y -= bt
	elif _side == "l":
		text_rect.size.x -= band.size.x
	else:
		text_rect.position.x += band.size.x
		text_rect.size.x -= band.size.x
	var f := fonts_for(c)
	var fname: int = int(f["name"])
	var fprice: int = int(f["price"])
	_name.add_theme_font_size_override("font_size", fname)
	_price.add_theme_font_size_override("font_size", fprice)
	# THE NAME IS NEVER HIDDEN (owner's rule, 16.10 evening): a cell without its word is an empty
	# square - which is exactly what he saw, 12 of them. The ladder sheds SECONDARY detail as the
	# cell tightens (the price hides at step 2, the house squares at step 1); identity stays.
	# `label_step` no longer has a "hide the name" rung, and this line is what consumes that promise.
	var step: int = LayoutProfile.label_step(c)
	# SCREEN MODE (a B1 corner): the name stays as the cell's identifier (READ-01, R-12) and the
	# glance line takes the rest at the big font BoardScene asked for.
	if _screen_text != "":
		var name_h: float = clampf(float(NAME_MIN) + 8.0, 0.0, text_rect.size.y * 0.32)
		_name.visible = true
		_name.position = text_rect.position
		_name.size = Vector2(text_rect.size.x, name_h)
		_price.visible = false
		_houses_lbl.visible = false
		_show_houses = false
		_screen.visible = true
		_screen.position = text_rect.position + Vector2(0, name_h)
		_screen.size = Vector2(maxf(1.0, text_rect.size.x), maxf(1.0, text_rect.size.y - name_h))
		_badge.position = Vector2(inner.position.x + 1, inner.position.y + 1)
		_badge.size = Vector2(maxf(BADGE_MIN, c * 0.16), maxf(BADGE_MIN, _badge.get_combined_minimum_size().y))
		return
	_screen.visible = false
	_name.visible = not _plain
	if step >= 2 or _plain:
		# the tightest legible ring: no price, the name still carries the cell
		_price.visible = false
	else:
		_price.visible = true
	# the house counter rides the band as a value, so a 4.5px square is never the only signal.
	# B1: on a SHORT cell (a side band cell is 190x88 at 1600x1200) the counter used to be placed at
	# a fixed offset from the bottom and its own minimum height pushed it past the cell edge
	# (measured: y 75 + 23 = 98 in an 88px cell). So: reserve a strip only when it FITS, and let the
	# name/price share what is left.
	_houses_lbl.add_theme_font_size_override("font_size", HOUSES_MIN)
	var houses_h: float = _houses_lbl.get_combined_minimum_size().y
	var strip: float = minf(houses_h, text_rect.size.y * 0.35)
	_show_houses = (not _plain) and step < 3 and strip >= 8.0
	if not _show_houses:
		strip = 0.0
	var body := Rect2(text_rect.position, Vector2(text_rect.size.x, maxf(0.0, text_rect.size.y - strip)))
	var name_h2: float = body.size.y if _price.visible == false else body.size.y * 0.62
	_name.position = body.position
	_name.size = Vector2(body.size.x, name_h2)
	_price.position = body.position + Vector2(0, name_h2)
	_price.size = Vector2(body.size.x, body.size.y - name_h2)
	# the type follows the word (and the box), never the other way round
	var f2 := fonts_for(c)
	_name.add_theme_font_size_override("font_size",
		_fit_px(_name.text, body.size.x, name_h2, NAME_MIN, int(f2["name"])))
	_price.add_theme_font_size_override("font_size",
		_fit_px(_price.text, body.size.x, maxf(4.0, body.size.y - name_h2), PRICE_MIN, int(f2["price"])))
	_houses_lbl.position = body.position + Vector2(0, body.size.y)
	_houses_lbl.size = Vector2(body.size.x, strip)
	# houses ride the band centre
	var house_w: float = minf(band.size.x - 4.0, 5.0 * 6.0 + 5.0)
	_houses.position = band.position + Vector2((band.size.x - house_w) * 0.5, maxf(0.0, (band.size.y - 6.0) * 0.5))
	# owner badge: bottom-left of the face, floor 12px (was 10 - "the badge is ~10px" in the map).
	# B1: a Label's height is clamped up to its font's minimum, so a 12px badge in an 88px cell
	# reported 23px tall and hung 2px past the edge. Measure it, then anchor it to the bottom.
	var bs: float = maxf(BADGE_MIN, c * 0.20)
	var bh: float = maxf(bs, _badge.get_combined_minimum_size().y)
	_badge.position = Vector2(inner.position.x + 1, inner.end.y - bh - 1)
	_badge.size = Vector2(bs, bh)
	_mortgaged.position = inner.position + Vector2(1, 1)


## Paint the dynamic state: ownership, houses, mortgage and the highlight frame.
func apply(entry: Dictionary) -> void:
	var owner: int = int(entry.get("owner", -1))
	var owner_col: Color = entry.get("owner_color", UiTheme.COL().accent)
	if owner >= 0 and not _plain:
		_badge.visible = true
		var nm := str(entry.get("owner_name", ""))
		_badge.text = nm.substr(0, 1).to_upper() if nm != "" else str(owner)
		_badge.add_theme_stylebox_override("normal", UiTheme.box(owner_col, UiTheme.COL().border, 1, 0))
		_badge.add_theme_color_override("font_color", Color.BLACK if owner_col.get_luminance() > 0.5 else Color.WHITE)
	else:
		_badge.visible = false
	var houses: int = int(entry.get("houses", 0))
	for c in _houses.get_children():
		_houses.remove_child(c)
		c.queue_free()
	_houses.visible = houses > 0 and not _plain
	_houses_lbl.visible = houses > 0 and _show_houses
	_houses_lbl.text = ("×%d" % houses) if houses > 0 else ""
	if houses > 0:
		var n: int = 1 if houses >= 5 else mini(houses, 4)
		for i in n:
			var sq := ColorRect.new()
			sq.color = UiTheme.COL().success
			sq.custom_minimum_size = Vector2(8, 6) if houses >= 5 else Vector2(5, 5)
			_houses.add_child(sq)
	var mortgaged: bool = bool(entry.get("mortgaged", false))
	_mortgaged.visible = mortgaged
	_face.modulate = Color(1, 1, 1, 0.45) if mortgaged else Color.WHITE
	# E-3/D11: the cell's TOOLTIP carries what the cell is worth right now. Rent lived nowhere but
	# the inspector, and the tooltip - the one surface a viewer hovers without a click - said only
	# the name. Now it names the group, the price and the CURRENT rent (with houses and monopoly
	# applied), which is the number a bid in an auction is actually about.
	_tip_update(entry)
	# the state frame: target tint · active ring (glow) · selected marker · owner border
	var ac: Color = UiTheme.COL().accent
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	var show := false
	# E-2: the event flash. A transient ring in the event's own colour draws the eye to WHERE
	# something happened (a purchase here, a bankruptcy there) while the banner in the centre says
	# WHAT happened. It outranks the owner border but not the active-turn ring: the turn ring is
	# the state a player acts on, the flash is news.
	if bool(entry.get("flash", false)):
		sb.set_border_width_all(3)
		sb.border_color = UiTheme.COL().warn
		sb.shadow_color = sb.border_color
		sb.shadow_size = 10
		show = true
	if bool(entry.get("target", false)):
		sb.bg_color = Color(ac.r, ac.g, ac.b, 0.12)
		sb.draw_center = true
		show = true
	if bool(entry.get("active", false)):
		sb.set_border_width_all(2)
		sb.border_color = ac
		sb.shadow_color = UiTheme.COL().accent
		sb.shadow_size = 8
		show = true
	elif bool(entry.get("selected", false)):
		sb.set_border_width_all(1)
		sb.border_color = UiTheme.COL().text
		sb.expand_margin_left = -3.0
		sb.expand_margin_right = -3.0
		sb.expand_margin_top = -3.0
		sb.expand_margin_bottom = -3.0
		show = true
	elif owner >= 0:
		sb.set_border_width_all(2)
		sb.border_color = owner_col
		show = true
	_state.add_theme_stylebox_override("panel", sb)
	_state.visible = show
	modulate = Color(1, 1, 1, 0.5) if bool(entry.get("dimmed", false)) else Color.WHITE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(index)
