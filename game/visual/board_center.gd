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

var skin: SkinManager

var _root: VBoxContainer
var _logo: Label
var _sub: Label
var _banner: Label
var _card: Control
var _card_title: Label
var _card_owner: Label
var _mini: VBoxContainer
var _dice: HBoxContainer

var _last_phase := ""
var _last_turn := -1


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

	# --- logo ---------------------------------------------------------------
	_logo = Label.new()
	_logo.text = "NEURO PROPERTY TRADE"
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_theme_font_size_override("font_size", skin.size("l", 18))
	_logo.add_theme_color_override("font_color", skin.color("accent"))
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_logo)

	_sub = Label.new()
	_sub.text = "PROPERTY TRADING · LIVE"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", skin.size("xs", 10))
	_sub.add_theme_color_override("font_color", skin.color("muted"))
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sub)

	# --- dice ---------------------------------------------------------------
	_dice = HBoxContainer.new()
	_dice.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice.add_theme_constant_override("separation", skin.space(2, 8))
	_dice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dice)
	for i in 2:
		var d := _make_die()
		d.name = "Die%d" % i
		_dice.add_child(d)

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
	var holder := Chamfer.new()
	(holder as Chamfer).set_skin(skin)
	(holder as Chamfer).fill_token = "surface.1"
	(holder as Chamfer).border_token = "text"
	(holder as Chamfer).cut = "none"
	var d: int = maxi(16, skin.size("xl", 28))
	(holder as Chamfer).custom_minimum_size = Vector2(d, d)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta("value", 1)
	holder.draw.connect(_draw_die.bind(holder))
	return holder


func _draw_die(holder: Control) -> void:
	var v: int = int(holder.get_meta("value", 1))
	var s: Vector2 = holder.size
	var pad: float = maxf(2.0, minf(s.x, s.y) * 0.18)
	var cell: float = (minf(s.x, s.y) - pad * 2.0) / 3.0
	var col: Color = skin.color("text")
	var pips := _pip_positions(v)
	for p in pips:
		var c := Vector2(pad + (float(p[0]) + 0.5) * cell, pad + (float(p[1]) + 0.5) * cell)
		holder.draw_circle(c, maxf(1.5, cell * 0.32), col)


func _pip_positions(v: int) -> Array:
	match v:
		1: return [[1, 1]]
		2: return [[0, 0], [2, 2]]
		3: return [[0, 0], [1, 1], [2, 2]]
		4: return [[0, 0], [2, 0], [0, 2], [2, 2]]
		5: return [[0, 0], [2, 0], [1, 1], [0, 2], [2, 2]]
		6: return [[0, 0], [2, 0], [0, 1], [2, 1], [0, 2], [2, 2]]
	return []


## Show the dice.
func set_dice(a: int, b: int) -> void:
	for i in _dice.get_child_count():
		var d := _dice.get_child(i)
		d.set_meta("value", a if i == 0 else b)
		d.queue_redraw()


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
## subtitle, exactly in the spec's order.
func fit(centre: Rect2) -> void:
	var w: float = centre.size.x
	var h: float = centre.size.y
	_mini.visible = h >= 200.0 and w >= 240.0
	_card.visible = h >= 150.0 and w >= 200.0
	_sub.visible = h >= 120.0 and w >= 180.0
	_logo.visible = h >= 80.0


func _money():
	return MoneyFmt.make("$")
