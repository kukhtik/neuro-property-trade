class_name PlayersPanel
extends PanelContainer
## Left panel listing every player's current state: money, position, tile
## count, jail/away badges. Active turn highlighted. Reads spectator projection
## + the seat list (names/colors). Shape-only (theme) for future art swap.

const UiTheme := preload("res://ui/theme.gd")

var _rows: Array = []   # per pid: {name, money, pos, tiles, badges}

func _init() -> void:
	custom_minimum_size.x = 235
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel, UiTheme.COL.border, 1, 0))
	var outer := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(edge, 10)
	add_child(outer)
	_v = UiTheme.vbox(8)
	outer.add_child(_v)

	var head := UiTheme.label("ИГРОКИ", 14, UiTheme.COL.accent)
	_v.add_child(head)
	_list = UiTheme.vbox(6)
	_v.add_child(_list)

var _v: VBoxContainer
var _list: VBoxContainer

## Cold state (pre-game): show a placeholder list (no engine yet).
func sync_cold() -> void:
	for c in _list.get_children():
		_list.remove_child(c); c.queue_free()
	_rows.clear()
	var ph := UiTheme.label("Партия ещё не начата", 13, UiTheme.COL.text_dim)
	_list.add_child(ph)

func sync(proj: Dictionary, seats: Array) -> void:
	# rebuild rows each sync (simple, deterministic for MVP shell)
	for c in _list.get_children():
		_list.remove_child(c); c.queue_free()
	_rows.clear()
	var players: Array = proj.get("players", [])
	var tp: int = int(proj.get("turn_player", -1))
	for p in players:
		var pid: int = int(p.get("index", 0))
		var row := _build_row(p, seats, pid, pid == tp, proj)
		_list.add_child(row)

func _build_row(p: Dictionary, seats: Array, pid: int, active: bool, proj: Dictionary) -> Control:
	var seat = null
	for s in seats:
		if int(s.pid) == pid:
			seat = s
	var name: String = str(p.get("name", "P%d" % pid))
	var col: Color = seat.color if seat != null else Color.WHITE

	var out := PanelContainer.new()
	var bord: Color = UiTheme.COL.border_accent if active else UiTheme.COL.border
	var w := 2 if active else 1
	out.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel_dark, bord, w, 6))

	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 8)
	out.add_child(m)
	var v := UiTheme.vbox(2)
	m.add_child(v)

	# name + badges
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var nm := UiTheme.label(name, 14, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	if bool(p.get("bankrupt", false)):
		var bk := UiTheme.label("БАНКРОТ", 11, UiTheme.COL.danger)
		name_row.add_child(bk)
	if bool(p.get("in_jail", false)):
		var jl := UiTheme.label("⚖ В ТЮРЬМЕ", 11, UiTheme.COL.jail)
		name_row.add_child(jl)
	for s in seats:
		if int(s.pid) == pid and bool(s.away):
			var aw := UiTheme.label("⤚ away", 11, UiTheme.COL.text_dim)
			name_row.add_child(aw)
	v.add_child(name_row)

	# money + position + tiles
	var info := UiTheme.label("$%d   @%s   нед.:%d" % [
		int(p.get("money", 0)), str(p.get("position", 0)), int(p.get("tiles", []).size())],
		13, UiTheme.COL.text_dim)
	v.add_child(info)
	return out
