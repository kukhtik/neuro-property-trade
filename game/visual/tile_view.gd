class_name TileView
extends Control
## A single board tile, assembled from CONTAINERS and skin slots
## (spec §4.2, §5.4) — the old absolute-positioning layout is gone.
##
## Structure (spec §5.4):
##   TileView (Control)
##   ├─ Bg            (slot tile.bg.*, else a token-coloured chamfer)
##   ├─ Root (MarginContainer)
##   │   └─ Row|Column            (orientation flips with band_side)
##   │      ├─ Band               (group/type colour; hosts the BuildingStrip)
##   │      └─ Body (VBox)
##   │         ├─ NameLabel
##   │         ├─ Icon
##   │         └─ Footer (HBox): PriceLabel, OwnerBadge
##   └─ StateOverlay  (current / selected / target / mortgaged)
##
## Orientation comes from BoardLayout's `band_side`, so the band always faces the
## board centre without an index formula here.
##
## EVERY visual value is a skin token or slot: colours, sizes, chamfer, band
## thickness, house size, motion durations. A skin swap restyles the tile with no
## code edit (the stage-1 requirement).
##
## Degradation (spec §1.4): the step follows the cell size, exactly as
## LayoutProfile.label_step describes — full / no price / smaller font / no name.

const SkinManager := preload("res://visual/skin_manager.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const PI := preload("res://core/player_identity.gd")
const HatchScript := preload("res://visual/tile_hatch.gd")
const BuildingStrip := preload("res://visual/building_strip.gd")

var _cell := 64
var _tile_count := 0        # set by build(); never assume 40 — the board is parametric
var _index := 0
var _band_side := "bottom"  # "top" | "bottom" | "left" | "right" (the INNER edge)
var _is_corner := false
var _skin: SkinManager
var _step := 0              # degradation step, 0 = best
var _pulse_phase := 0.0

# nodes
var _owner_stripe: ColorRect
var _sheen: ColorRect
var _bg: Chamfer
var _band: Chamfer
var _strip: Control
var _name: Label
## An icon may occupy at most this fraction of the cell (kept in step with the
## board probe's assertion so the art and the check cannot drift apart).
const ICON_MAX_FRAC := 0.35

var _icon: TextureRect
var _price: Label
var _badge: Chamfer
var _badge_label: Label
var _overlay: Control
var _row: BoxContainer

var _type := "property"
var _active := false


## Build the tile widget for `index`. `cell` is the tile size in px.
## Signature kept: the layout probes call this.
func build(index: int, tile_count: int, cell: int, skin: SkinManager = null) -> void:
	build_sized(index, tile_count, cell, cell, _band_side_for(index, tile_count), "",
		index % maxi(1, tile_count / 4) == 0, skin)


## Build with the EXACT geometry BoardLayout produced. The tile may be wider
## than tall (a corner is cr× larger along the edge), and `band_side` tells it
## which edge faces the centre, so no orientation formula lives here.
func build_sized(index: int, tile_count: int, w: float, h: float, band_side: String,
		_group: String, is_corner: bool, skin: SkinManager = null) -> void:
	_index = index
	_tile_count = tile_count
	_cell = int(minf(w, h))
	_band_side = band_side
	_is_corner = is_corner
	_skin = skin if skin != null else SkinManager.new()
	if _skin.skin_id() == "":
		_skin.load_skin()
	_step = _step_for(_cell)
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_nodes()


## The inner edge of the ring for a tile index (mirrors BoardLayout.band_side).
func _band_side_for(index: int, tile_count: int) -> String:
	var d: int = maxi(1, tile_count / 4)
	var s: int = index / d
	# 0=bottom row (inner edge up), 1=left column (inner edge right),
	# 2=top row (inner edge down), 3=right column (inner edge left)
	return ["top", "right", "bottom", "left"][s]


## Run the chase highlight across this tile, forever. Delayed by the tile index so the board
## shimmers as a wave instead of blinking in unison (the mockup's `--k*.16s`).
func _start_sheen() -> void:
	if _sheen == null or not is_instance_valid(_sheen):
		return
	if _sheen.get_meta("running", false):
		return
	_sheen.set_meta("running", true)
	var w: float = maxf(size.x, custom_minimum_size.x)
	if w <= 1.0:
		w = float(_cell)
	var t := create_tween()
	t.set_loops()
	# off to the left, sweep across, then rest before the next pass
	_sheen.position.x = -w * 0.35
	_sheen.size = Vector2(w * 0.35, maxf(size.y, custom_minimum_size.y))
	_sheen.visible = true
	var delay: float = 0.16 * float(_index % 40)
	t.tween_interval(delay)
	t.tween_property(_sheen, "position:x", w, 1.4).set_trans(Tween.TRANS_SINE)
	t.tween_interval(7.6 - delay)
	# a one-off nudge in case the tile is never laid out


func _step_for(cell: int) -> int:
	var c := float(cell)
	if c >= 78.0:
		return 0
	if c >= 60.0:
		return 1
	if c >= 44.0:
		return 2
	return 3


func _build_nodes() -> void:
	# --- Bg ----------------------------------------------------------------
	_bg = Chamfer.new()
	_bg.set_skin(_skin)
	_bg.fill_token = "surface.1"
	_bg.fill_shade = _skin.proportion("tile_shade", 0.22)
	_bg.border_token = "line"
	_bg.cut = "none"
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_full(_bg)
	add_child(_bg)

	# the owner's stripe: the mockup draws it INSET on the inner edge, so it must sit ABOVE
	# the face and BELOW the content
	_owner_stripe = ColorRect.new()
	_owner_stripe.name = "Owner"
	_owner_stripe.color = Color.TRANSPARENT
	_owner_stripe.visible = false
	_owner_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_owner_stripe.z_index = 1
	add_child(_owner_stripe)

	# the chase highlight: a diagonal sheen crossing the tile every 9s, delayed by the tile's
	# own index so the board shimmers as a wave. On a static board it is the only sign of life.
	_sheen = ColorRect.new()
	_sheen.name = "Sheen"
	_sheen.color = _skin.color("sheen")
	_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheen.z_index = 2
	_sheen.visible = false
	_sheen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sheen)
	# --- flow: a Row for vertical bands, a Column for horizontal ones -------
	var vertical: bool = _band_side == "left" or _band_side == "right"
	_row = HBoxContainer.new() if vertical else VBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 0)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad: int = maxi(1, int(_skin.space(1, 4) * 0.5))
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	margin.add_child(_row)
	_anchor_full(margin)
	add_child(margin)

	# --- Band with the building strip inside -------------------------------
	_band = Chamfer.new()
	_band.set_skin(_skin)
	_band.fill_token = "surface.3"
	# the mockup's band is `linear-gradient(180deg, lighter, base, darker)`: a flat stripe
	# reads as a sticker, a graded one as a solid chip catching light
	_band.fill_shade = _skin.proportion("band_shade", 0.5)
	_band.border_token = "line"
	_band.cut = "none"
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		_band.custom_minimum_size = Vector2(_band_thickness(), 0)
	else:
		_band.custom_minimum_size = Vector2(0, _band_thickness())
	_strip = BuildingStrip.new()
	(_strip as BuildingStrip).setup(_skin, _cell,
		_band_side == "left" or _band_side == "right")
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_full(_strip)
	_band.add_child(_strip)

	# --- Body --------------------------------------------------------------
	var body := VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", maxi(1, int(_skin.space(1, 4) * 0.5)))

	_name = Label.new()
	_name.name = "NameLabel"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.add_theme_font_size_override("font_size", _name_font())
	_name.add_theme_color_override("font_color", _skin.color("text"))
	_name.clip_text = true
	_name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_name)

	_icon = TextureRect.new()
	# A capped, centred icon. SHRINK_CENTER + no EXPAND_FILL keeps the size at
	# custom_minimum_size; EXPAND_FILL made it swallow the body and overlay the
	# tile's name/price at large cell sizes.
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	body.add_child(_icon)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_price = Label.new()
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.add_theme_font_size_override("font_size", _price_font())
	_price.add_theme_color_override("font_color", _skin.color("money"))
	_price.clip_text = true
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_price)

	var bpx: float = _badge_px()
	_badge = Chamfer.new()
	_badge.set_skin(_skin)
	_badge.fill_token = "accent"
	_badge.border_token = "line"
	_badge.cut = "tr"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.custom_minimum_size = Vector2(bpx, bpx)
	_badge.visible = false
	_badge_label = Label.new()
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", maxi(7, int(bpx * 0.7)))
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_full(_badge_label)
	_badge.add_child(_badge_label)
	footer.add_child(_badge)
	body.add_child(footer)

	# the band goes on the inner edge: first in the flow for top/left
	var band_first: bool = _band_side == "top" or _band_side == "left"
	if band_first:
		_row.add_child(_band)
		_row.add_child(body)
	else:
		_row.add_child(body)
		_row.add_child(_band)

	# --- StateOverlay: the mortgage hatch above the content -----------------
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_full(_overlay)
	var hatch := Control.new()
	hatch.set_script(HatchScript)
	hatch.name = "Hatch"
	hatch.visible = false
	hatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_full(hatch)
	_overlay.add_child(hatch)
	add_child(_overlay)


func _anchor_full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)


# --- skin-derived sizes -------------------------------------------------------

func _band_thickness() -> float:
	var t: float = float(_cell) * _skin.metric("band_ratio", 0.03) * 6.0
	return maxf(5.0, minf(t, float(_cell) * 0.24))

func _badge_px() -> float:
	return maxf(9.0, float(_cell) * 0.17)

func _name_font() -> int:
	# skin size tokens, one step smaller on a degraded tile
	return _skin.size("xs", 10) if _step >= 2 else _skin.size("s", 12)

func _price_font() -> int:
	return maxi(7, _skin.size("xs", 10) - 1)

func _money():
	return MoneyFmt.make("$", true)


# --- data ---------------------------------------------------------------------

## Which background the mockup prescribes for this tile.
##
## The mockup's CSS names don't match the engine's types one-to-one: `k-park` is
## `free_parking`, `k-cc` is `community`, `k-ch` is `chance`, `k-gj` is `go_to_jail`. This is
## the only place the two vocabularies meet.
func _face_kind(t: String, _entry: Dictionary) -> String:
	match t:
		"go":
			return "go"
		"jail":
			return "jail"
		"free_parking":
			return "parking"
		"go_to_jail":
			return "goto_jail"
		"chance":
			return "chance"
		"community":
			return "chest"
		"tax":
			return "tax"
		_:
			# property, railroad, utility: the group colour, faint
			return "property"


## The owner's mark: an inset stripe along the tile's INNER edge, exactly the direction the
## mockup uses per side (`.t.own.b` bottom, `.t.own.l` left, `.t.own.r` right, `.t.own.t2` top).
func _update_owner_stripe(entry: Dictionary) -> void:
	var owner := int(entry.get("owner", -1))
	if _owner_stripe == null:
		return
	if owner < 0:
		_owner_stripe.visible = false
		return
	var col: Color = _owner_color(owner)
	_owner_stripe.visible = true
	_owner_stripe.color = col
	# the stripe lies on the edge facing the CENTRE of the ring
	var t: float = 3.0
	match _band_side:
		"bottom":
			_owner_stripe.anchor_left = 0; _owner_stripe.anchor_right = 1
			_owner_stripe.anchor_top = 0; _owner_stripe.anchor_bottom = 0
			_owner_stripe.offset_left = 0; _owner_stripe.offset_right = 0
			_owner_stripe.offset_top = 0; _owner_stripe.offset_bottom = t
		"top":
			_owner_stripe.anchor_left = 0; _owner_stripe.anchor_right = 1
			_owner_stripe.anchor_top = 1; _owner_stripe.anchor_bottom = 1
			_owner_stripe.offset_left = 0; _owner_stripe.offset_right = 0
			_owner_stripe.offset_top = -t; _owner_stripe.offset_bottom = 0
		"left":
			_owner_stripe.anchor_left = 1; _owner_stripe.anchor_right = 1
			_owner_stripe.anchor_top = 0; _owner_stripe.anchor_bottom = 1
			_owner_stripe.offset_left = -t; _owner_stripe.offset_right = 0
			_owner_stripe.offset_top = 0; _owner_stripe.offset_bottom = 0
		_:
			_owner_stripe.anchor_left = 0; _owner_stripe.anchor_right = 0
			_owner_stripe.anchor_top = 0; _owner_stripe.anchor_bottom = 1
			_owner_stripe.offset_left = 0; _owner_stripe.offset_right = t
			_owner_stripe.offset_top = 0; _owner_stripe.offset_bottom = 0


## The seat colour for a player index. PlayerIdentity already owns that palette; a second
## copy here would drift from it.
func _owner_color(pid: int) -> Color:
	return PI.color_of(pid)


## Repaint from a projection tile entry (spec §5.4 render(tile_vm)).
func refresh(entry: Dictionary) -> void:
	_type = str(entry.get("type", "property"))

	# THE TILE'S OWN FACE: every type gets its background from the mockup's spec — GO is
	# accent-tinted, jail hatched, tax striped, chance and chest lean on accent and accent2,
	# and a property carries a hint of its GROUP colour. A single shared surface for all of
	# them is why our board read as a grid of identical rectangles.
	if _bg != null:
		var group: Color = _skin.tile_color(entry)
		var kind := _face_kind(_type, entry)
		# `size` is still zero on the first refresh — the container has not laid the tile out
		# yet — so the texture was built at 0x0 and never appeared. `custom_minimum_size` is
		# set at build time and is always correct here.
		var face_size := size
		if face_size.x <= 1.0 or face_size.y <= 1.0:
			face_size = custom_minimum_size
		if face_size.x <= 1.0 or face_size.y <= 1.0:
			face_size = Vector2(_cell, _cell)
		_bg.fill_texture = SkinPaint.tile_face(_skin, kind, group, face_size)
		_bg.fill_shade = 0.0   # the texture carries the shading now
		_bg.queue_redraw()

	# the mockup marks ownership with an INSET stripe on the inner edge (`inset 0 -3px 0`)
	_update_owner_stripe(entry)

	# band colour: the group colour for properties, the type colour otherwise
	_band.set_meta("fill_override", _skin.tile_color(entry))
	_band.queue_redraw()

	# name: full at steps 0-1, the short name at 2, hidden at 3
	var full := str(entry.get("name", ""))
	var short := str(entry.get("short", full))
	_name.text = full if _step <= 1 else (short if _step == 2 else "")
	_name.visible = _step <= 2 and not _is_corner

	var cost: int = int(entry.get("cost", 0))
	var amount: int = int(entry.get("amount", 0))
	if _is_corner:
		_name.visible = false
		_price.text = ""
		_show_icon("corner_icons." + _type)
	elif _type == "property":
		_price.text = _money().amount(cost)
		_icon.visible = false
	elif _type == "tax":
		_price.text = _money().amount(amount)
		_show_icon("type_icons." + _type)
	else:
		_price.text = _money().amount(cost) if cost > 0 else ""
		_show_icon("type_icons." + _type)
	# degradation: step >= 1 hides the price, step >= 2 hides the icon
	# The price is the most important number on a tile and the mockup shows it at almost any
	# size. It was gated at `_step == 0` (cell >= 78px), so a perfectly normal 66px tile
	# showed a name and NO price — the board looked empty of information while being full of
	# it. It now survives to step 2, alongside the name.
	_price.visible = _step <= 2 and _price.text != ""
	if _sheen != null and not _sheen.get_meta("running", false):
		_start_sheen()
	if _step >= 2:
		_icon.visible = false

	# owner badge + tile border, coloured from the SKIN palette
	var ow: int = int(entry.get("owner", -1))
	if ow >= 0:
		var col: Color = _skin.player_color(ow)
		_bg.set_meta("border_override", col)
		_badge.visible = true
		_badge_label.text = _initial_of(str(entry.get("owner_name", "")))
		_badge_label.add_theme_color_override("font_color", _contrast(col))
		_badge.set_meta("fill_override", col)
		_badge.queue_redraw()
	else:
		if _bg.has_meta("border_override"):
			_bg.remove_meta("border_override")
		_badge.visible = false
	_bg.queue_redraw()

	set_houses(int(entry.get("houses", 0)) if _type == "property" else 0)

	var mortgaged: bool = bool(entry.get("mortgaged", false))
	var hatch := _overlay.get_node_or_null("Hatch")
	if hatch != null:
		hatch.visible = mortgaged
	_band.modulate = _skin.color("mortgage.dim") if mortgaged else Color.WHITE
	pass


func _show_icon(slot_id: String) -> void:
	var tex: Texture2D = _skin.texture(slot_id)
	_icon.texture = tex
	_icon.visible = tex != null
	# Bound by the tile as well as the metric: an icon may never take more than a
	# third of the cell (the board probe enforces this at every tile_count).
	var want: float = float(_cell) * _skin.metric("icon_size", 0.036) * 7.0
	var cap: float = float(_cell) * ICON_MAX_FRAC
	var d: float = clampf(want, 8.0, cap)
	_icon.custom_minimum_size = Vector2(d, d)


## House/hotel count for the band strip (spec §5.5). The strip owns the drawing.
func set_houses(n: int) -> void:
	if _strip == null:
		return
	(_strip as BuildingStrip).set_count(n)


# --- highlight state (spec §4.2) ---------------------------------------------

func set_active(v: bool) -> void:
	_active = v
	if not v:
		if _bg.has_meta("state"):
			_bg.remove_meta("state")
	_bg.queue_redraw()


func set_selected(v: bool) -> void:
	if v:
		_bg.set_meta("state", "selected")
	else:
		_bg.remove_meta("state")
	_bg.queue_redraw()


func set_target(v: bool) -> void:
	if v:
		_bg.set_meta("target", true)
	else:
		_bg.remove_meta("target")
	_bg.queue_redraw()


# --- effects (spec §5.4 play_* methods; durations from motion tokens) ---------

func play_landing() -> void:
	var t := create_tween()
	var d: float = _skin.motion("pop", 0.5) * 0.4
	var boost: float = _skin.metric("flash_boost", 1.35)
	t.tween_property(self, "modulate", Color(boost, boost, boost), d)
	t.tween_property(self, "modulate", Color.WHITE, d)


func play_sold(_col: Color) -> void:
	play_landing()


func play_build() -> void:
	var t := create_tween()
	var d: float = _skin.motion("pop", 0.5) * 0.5
	t.tween_property(_band, "modulate", _skin.color("accent2"), d)
	t.tween_property(_band, "modulate", Color.WHITE, d)


func _process(delta: float) -> void:
	if not _active:
		return
	_pulse_phase += delta * TAU * 0.8
	var min_a: float = _skin.proportion("pulse_min_alpha", 0.5)
	var amp: float = _skin.proportion("pulse_amp", 0.4)
	_bg.set_meta("pulse", min_a + amp * (0.5 + 0.5 * sin(_pulse_phase)))
	_bg.queue_redraw()


func _initial_of(name: String) -> String:
	var n := name.strip_edges()
	return n.substr(0, 1).to_upper() if n.length() > 0 else "?"


## A readable text colour on a given background.
func _contrast(bg: Color) -> Color:
	var lum: float = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color.BLACK if lum > 0.6 else Color.WHITE
