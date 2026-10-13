class_name BoardCenter
extends Control
## The board's centre panel (spec §5.7): logo, the two decks, the dice, the turn
## banner, the selected/current tile card and a mini-log of the last events.
##
## Shedding order when the centre gets small (spec §5.7): mini-log first, then
## the tile card, then the subtitle. Everything is container-built and every
## colour/size is a skin token, so a skin swap restyles it.
##
## Read-only: it renders what it is handed and never touches the engine.

const SkinManager := preload("res://visual/skin_manager.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const Layout := preload("res://ui/core/layout_profile.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")
const I18n := preload("res://i18n/i18n.gd")

var skin: SkinManager

var _root: VBoxContainer
var _logo: Label
var _sub: Label
var _banner: Label
var _doubles: Label
var _sum: Label
var _tojail: Label
var _card: Control
var _card_title: Label
var _card_owner: Label
var _mini: VBoxContainer
var _dice: HBoxContainer

# the tray tumble (mockup `.dicetray.rolling .die` → tumble 0.85s)
var _rolling := false
var _roll_t := 0.0
var _roll_swap := 0.0
var _roll_to := Vector2i(1, 1)

var _last_phase := ""
var _last_turn := -1
var _watermark := true   # cold-state mark; set_watermark() flips it when a match runs
var _fit_rect := Rect2()


func setup(p_skin: SkinManager) -> void:
	skin = p_skin
	if skin == null:
		skin = SkinManager.new()
		skin.load_skin()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	_root = VBoxContainer.new()
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", skin.space(2, 8))
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(_spacer())

	# --- watermark ----------------------------------------------------------
	# v3: `#center .watermark` — dim LINE-coloured brand, two lines, shown in the COLD
	# state only (proto.js renderCenter(): scn=="cold"; the warm centre is the dice tray).
	# It used to be a bright accent logo that stayed lit through the whole match.
	_logo = Label.new()
	_logo.text = "NEURO\nPROPERTY TRADE"
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_theme_font_size_override("font_size", skin.size("l", 18))
	_logo.add_theme_color_override("font_color", skin.color("line", skin.color("muted")))
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_logo)

	_sub = Label.new()
	var cold_txt: String = I18n.t("top.cold")
	if cold_txt.begins_with("{"):
		cold_txt = I18n.t("act.cold_status")
	_sub.text = cold_txt
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", skin.size("xs", 10))
	_sub.add_theme_color_override("font_color", skin.color("muted"))
	_sub.modulate = Color(1, 1, 1, 0.7)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sub)
	resized.connect(_apply_sizes)
	_apply_sizes()

	# --- dice tray ----------------------------------------------------------
	# v3 (proto.js diceHTML()): the centre dice ARE the tray — two pip dice at cell*0.62,
	# and the sum / doubles / to-jail marks sit in the SAME row. The old shape had a loose
	# HBox and a detached doubles label under it.
	_dice = HBoxContainer.new()
	_dice.name = "DiceTray"
	_dice.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice.add_theme_constant_override("separation", skin.space(3, 12))
	_dice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dice)
	for i in 2:
		var d := _make_die()
		d.name = "Die%d" % i
		_dice.add_child(d)

	# `.dice-sum` — the rolled total as a boxed number
	_sum = Label.new()
	_sum.name = "Sum"
	_sum.visible = false
	_sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sum.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dice.add_child(_sum)

	# `.dbl` — doubles are a real event (again / jail): the mockup marks them on the tray
	_doubles = Label.new()
	_doubles.name = "Doubles"
	_doubles.text = I18n.t("die.doubles")
	_doubles.visible = false
	_doubles.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_doubles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dice.add_child(_doubles)

	# `.tojail` — the third doubles roll walks straight to jail
	_tojail = Label.new()
	_tojail.name = "ToJail"
	_tojail.text = "→ " + I18n.t("phase.JAIL_DECISION")
	_tojail.visible = false
	_tojail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tojail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dice.add_child(_tojail)

	# --- turn banner --------------------------------------------------------
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", skin.size("m", 14))
	_banner.add_theme_color_override("font_color", skin.color("text"))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)

	# --- tile card ----------------------------------------------------------
	_card = Chamfer.new()
	(_card as Chamfer).set_skin(skin)
	(_card as Chamfer).fill_token = "surface.2"
	(_card as Chamfer).border_token = "line"
	(_card as Chamfer).cut = "tr"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	var card_box := VBoxContainer.new()
	card_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_card as Chamfer).add_child(card_box)
	_card_title = Label.new()
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.add_theme_font_size_override("font_size", skin.size("s", 12))
	_card_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.add_child(_card_title)
	_card_owner = Label.new()
	_card_owner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_owner.add_theme_font_size_override("font_size", skin.size("xs", 10))
	_card_owner.add_theme_color_override("font_color", skin.color("muted"))
	_card_owner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.add_child(_card_owner)
	_root.add_child(_card)

	# --- mini log -----------------------------------------------------------
	_mini = VBoxContainer.new()
	_mini.add_theme_constant_override("separation", 2)
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_mini)

	_root.add_child(_spacer())


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A die: a skin token square with pips drawn from tokens (no art needed).
func _make_die() -> Control:
	# v3 (proto.css `.die`): a plain square — background `dice-bg`, pips in a 3x3 grid in
	# `dice-ink`, and a 4px inset bottom shadow. It is NOT a chamfered chip, and it draws
	# itself in one `_draw` (the Chamfer-based holder painted nothing in-tree).
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var d: int = 28
	holder.custom_minimum_size = Vector2(d, d)
	holder.set_meta("value", 1)
	holder.draw.connect(_draw_die.bind(holder))
	return holder


func _draw_die(holder: Control) -> void:
	var v: int = int(holder.get_meta("value", 1))
	var s: Vector2 = holder.size
	var side: float = maxf(4.0, minf(s.x, s.y))
	var base := Rect2((s - Vector2(side, side)) * 0.5, Vector2(side, side))
	holder.draw_rect(base, skin.color("dice_bg", Color(0.95, 0.96, 0.98)))
	# `.die { box-shadow: inset 0 -4px 0 0 color-mix(in srgb, var(--dice-ink) 20%, transparent) }`
	var col: Color = skin.color("dice_ink", skin.color("text"))
	var foot: Color = col
	foot.a = 0.2
	var fh: float = maxf(2.0, minf(4.0, side * 0.11))
	holder.draw_rect(Rect2(base.position + Vector2(0.0, base.size.y - fh), Vector2(side, fh)), foot)
	# pips: `padding: 12%` of the face, `i { width: 62% }` of a third
	var pad: float = maxf(2.0, side * 0.12)
	var cell: float = (side - pad * 2.0) / 3.0
	for p in _pip_positions(v):
		var c := base.position + Vector2(
			pad + (float(p[0]) + 0.5) * cell,
			pad + (float(p[1]) + 0.5) * cell)
		holder.draw_circle(c, maxf(1.5, cell * 0.31), col)


func _pip_positions(v: int) -> Array:
	match v:
		1: return [[1, 1]]
		2: return [[0, 0], [2, 2]]
		3: return [[0, 0], [1, 1], [2, 2]]
		4: return [[0, 0], [2, 0], [0, 2], [2, 2]]
		5: return [[0, 0], [2, 0], [1, 1], [0, 2], [2, 2]]
		6: return [[0, 0], [2, 0], [0, 1], [2, 1], [0, 2], [2, 2]]
	return []


## Show the dice. `third` marks the third-doubles roll (the tray's to-jail chip).
func set_dice(a: int, b: int, third: bool = false) -> void:
	var i := 0
	for c in _dice.get_children():
		if not str(c.name).begins_with("Die"):
			continue
		c.set_meta("value", a if i == 0 else b)
		c.queue_redraw()
		i += 1
	# v3 tray marks: sum, doubles (a>0 keeps an unrolled 0/0 dark), to-jail
	if _sum != null:
		_sum.visible = a > 0
		if a > 0:
			_sum.text = str(a + b)
	if _doubles != null:
		_doubles.visible = a > 0 and a == b and not third
		if _doubles.visible:
			_doubles.text = I18n.t("die.doubles")
	if _tojail != null:
		_tojail.visible = third


## v3 (mockup `.dicetray.rolling .die` → tumble 0.85s): the TRAY tumbles and settles on the
## decided faces. The engine's result is fixed before this runs — only the faces cycle.
func roll_tray(d1: int, d2: int) -> void:
	_roll_to = Vector2i(clampi(d1, 1, 6), clampi(d2, 1, 6))
	_roll_t = 0.0
	_roll_swap = 0.0
	_rolling = true
	if _sum != null:
		_sum.visible = false
	if _doubles != null:
		_doubles.visible = false
	if _tojail != null:
		_tojail.visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not _rolling:
		return
	var dur: float = skin.motion("dice_roll", 0.85)
	_roll_t += delta
	_roll_swap += delta
	if _roll_swap >= 0.085:
		_roll_swap = 0.0
		var i := 0
		for c in _dice.get_children():
			if not str(c.name).begins_with("Die"):
				continue
			# deterministic face cycling (cosmetic only — the result comes from the engine)
			c.set_meta("value", 1 + (i * 3 + int(_roll_t * 24.0)) % 6)
			c.queue_redraw()
			i += 1
	var p: float = clampf(_roll_t / maxf(0.01, dur), 0.0, 1.0)
	var j := 0
	for c in _dice.get_children():
		if not str(c.name).begins_with("Die"):
			continue
		var ctl := c as Control
		ctl.pivot_offset = ctl.size * 0.5
		ctl.rotation = sin(p * TAU * 2.4 + float(j) * 1.7) * 0.55 * (1.0 - p)
		ctl.scale = Vector2(1.0, 1.0 - 0.25 * sin(p * PI))
		j += 1
	if _roll_t >= dur:
		_rolling = false
		set_process(false)
		for c in _dice.get_children():
			if not str(c.name).begins_with("Die"):
				continue
			(c as Control).rotation = 0.0
			(c as Control).scale = Vector2.ONE
		set_dice(_roll_to.x, _roll_to.y)


## v3 watermarks show in the cold state only — proto.js renderCenter() draws them for
## scn=="cold" and nothing else. The match centre carries the dice tray and the cards.
func set_watermark(v: bool) -> void:
	if _watermark == v:
		return
	_watermark = v
	fit(_fit_rect)


## Cell-relative sizes straight from the mockup: dies at cell*0.62, `.dice-sum` at
## cell*0.5, watermark wm1/wm2 at cell*0.3 / cell*0.14, `.banner` at cell*0.26.
func _apply_sizes() -> void:
	var c := _cell()
	if _dice != null:
		var die_px: float = maxf(16.0, roundf(c * 0.62))
		for d in _dice.get_children():
			if str(d.name).begins_with("Die"):
				(d as Control).custom_minimum_size = Vector2(die_px, die_px)
	if _logo != null:
		_logo.add_theme_font_size_override("font_size", maxi(9, int(roundf(c * 0.30))))
	if _sub != null:
		_sub.add_theme_font_size_override("font_size", maxi(7, int(roundf(c * 0.14))))
	if _banner != null:
		_banner.add_theme_font_size_override("font_size", maxi(10, int(roundf(c * 0.26))))
	var chip_fs: int = maxi(8, int(roundf(c * 0.16)))
	if _sum != null:
		_sum.add_theme_font_size_override("font_size", maxi(12, int(roundf(c * 0.5))))
		_sum.add_theme_stylebox_override("normal", _chip_box(skin.color("line", Color(0.3, 0.3, 0.4)), int(c * 0.12), maxi(1, int(c * 0.06))))
	if _doubles != null:
		_doubles.add_theme_font_size_override("font_size", chip_fs)
		_doubles.add_theme_color_override("font_color", skin.color("warn", skin.color("accent")))
		_doubles.add_theme_stylebox_override("normal", _chip_box(skin.color("warn", skin.color("accent")), 6, 2))
	if _tojail != null:
		_tojail.add_theme_font_size_override("font_size", chip_fs)
		_tojail.add_theme_color_override("font_color", skin.color("bad", skin.color("danger", skin.color("accent"))))
		_tojail.add_theme_stylebox_override("normal", _chip_box(skin.color("bad", skin.color("danger", skin.color("accent"))), 6, 2))


func _cell() -> float:
	# the centre rect is 9 tiles wide (CSS `#center { width: 9/11 }`), so a tile is size/9
	var s := size
	return maxf(8.0, minf(s.x, s.y) / 9.0)


func _chip_box(border: Color, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = skin.color("surface.2", skin.color("panel_dark", Color(0.08, 0.06, 0.12)))
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## Show the turn banner: "Ada · Purchase · Sunset Blvd".
func set_turn(player_name: String, phase: String, tile_name: String) -> void:
	var parts: Array[String] = [player_name]
	if phase != "":
		parts.append(phase)
	if tile_name != "":
		parts.append(tile_name)
	_banner.text = " · ".join(parts)


## Show (or clear) the tile card.
func set_tile(entry: Dictionary, owner_name: String) -> void:
	if entry.is_empty():
		_card.visible = false
		return
	_card.visible = true
	var name := str(entry.get("name", ""))
	var cost: int = int(entry.get("cost", 0))
	_card_title.text = "%s  %s" % [name, MoneyFmt.make("$").amount(cost)] if cost > 0 else name
	_card_owner.text = owner_name if owner_name != "" else "—"


## Replace the mini-log with up to `count` already-formatted lines.
func set_mini_log(lines: Array, count: int = 4) -> void:
	for c in _mini.get_children():
		c.queue_free()
	var start: int = maxi(0, lines.size() - count)
	for i in range(start, lines.size()):
		var l := Label.new()
		l.text = str(lines[i])
		l.add_theme_font_size_override("font_size", skin.size("xs", 10))
		l.add_theme_color_override("font_color", skin.color("muted"))
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mini.add_child(l)


## Fit the centre to its rect: shed the mini-log, then the card, then the
## subtitle, exactly in the spec's order. The watermark items additionally
## require the cold state (v3).
func fit(centre: Rect2) -> void:
	_fit_rect = centre
	var w: float = centre.size.x
	var h: float = centre.size.y
	_mini.visible = h >= 200.0 and w >= 240.0
	_card.visible = h >= 150.0 and w >= 200.0
	_sub.visible = _watermark and h >= 120.0 and w >= 180.0
	_logo.visible = _watermark and h >= 80.0


func _money():
	return MoneyFmt.make("$")
