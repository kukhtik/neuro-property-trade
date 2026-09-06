class_name TileInspector
extends PanelContainer
## Bottom-left inspector showing the currently selected tile: name, type,
## cost, rent, houses, owner. Reads a spectator projection. `selected` holds
## the last clicked tile index (set via select()).

const UiTheme := preload("res://ui/theme.gd")

var selected := -1
var _text: Label
var _close: Button
var _hide_timer := 0.0
const _HIDE_AFTER := 3.0

func _init() -> void:
	custom_minimum_size = Vector2(320, 90)
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel, UiTheme.COL.border, 1, 8))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 10)
	add_child(m)
	var v := UiTheme.vbox(4)
	m.add_child(v)
	var head := HBoxContainer.new()
	var lbl := UiTheme.label("КЛЕТКА", 12, UiTheme.COL.accent)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lbl)
	_close = UiTheme.button("✕", "Закрыть справку по клетке")
	_close.custom_minimum_size = Vector2(24, 20)
	_close.connect("pressed", Callable(self, "clear"))
	head.add_child(_close)
	v.add_child(head)
	_text = UiTheme.label("Кликните по тайлу доски", 13, UiTheme.COL.text_dim)
	v.add_child(_text)

func _process(delta: float) -> void:
	# A3: auto-hide the inspector a few seconds after the last selection.
	if selected >= 0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			clear()

func select(idx: int) -> void:
	selected = idx
	_hide_timer = _HIDE_AFTER   # reset the auto-hide countdown

func clear() -> void:
	selected = -1
	_hide_timer = 0.0
	_text.text = "Кликните по тайлу доски"
	_text.add_theme_color_override("font_color", UiTheme.COL.text_dim)

func sync(proj: Dictionary, seats: Array) -> void:
	if selected < 0:
		return
	for t in (proj.get("board", []) as Array):
		if int(t.get("index", -1)) != selected:
			continue
		var nm: String = str(t.get("name", ""))
		var typ: String = str(t.get("type", "property"))
		var cost: int = int(t.get("cost", 0))
		var houses: int = int(t.get("houses", 0))
		var mortgaged: bool = bool(t.get("mortgaged", false))
		var owner: int = int(t.get("owner", -1))
		var base_rent: int = _base_rent(t)
		var owner_txt := "— свободен"
		var owner_col: Color = UiTheme.COL.success
		if owner >= 0:
			for s in seats:
				if int(s.pid) == owner:
					owner_txt = "владелец: " + str(s.name)
					owner_col = s.color
		var house_txt := ""
		if typ == "property":
			house_txt = " · дом: %s" % ("HOTEL" if houses >= 5 else str(houses))
		var mort := " · ЗАЛОЖЕН" if mortgaged else ""
		_text.text = "«%s»  %s%s\nцена $%d · аренда $%d · %s%s" % [
			nm, typ, mort, cost, base_rent, owner_txt, house_txt]
		_text.add_theme_color_override("font_color", owner_col if owner >= 0 else UiTheme.COL.text)
		return

func _base_rent(t: Dictionary) -> int:
	var group: String = str(t.get("group", ""))
	if group != "":
		return int(t.get("rent_set", t.get("rent", 0)))
	return int(t.get("rent", 0))
