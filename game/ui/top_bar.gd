class_name TopBar
extends PanelContainer
## Fixed top bar: game title + current turn (player) + phase + F12 hint.
## Reads a spectator-safe projection dict. Shape-only for future art swap.

const UiTheme := preload("res://ui/theme.gd")

signal settings_requested

var _title: Label
var _turn: Label
var _phase: Label
var _hint: Label

func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel_dark, UiTheme.COL.border, 1, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	add_child(m)
	m.add_child(h)

	_title = UiTheme.label("● NEURO PROPERTY TRADE", 15, UiTheme.COL.gold)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title)
	_turn = UiTheme.label("", 15)
	h.add_child(_turn)
	_phase = UiTheme.label("", 13, UiTheme.COL.text_dim)
	h.add_child(_phase)
	var settings_btn := UiTheme.button("⚙")
	settings_btn.custom_minimum_size = Vector2(30, 24)
	settings_btn.connect("pressed", Callable(self, "_on_settings"))
	h.add_child(settings_btn)
	_hint = UiTheme.label("F12 — админ", 12, UiTheme.COL.text_dim)
	h.add_child(_hint)

func _on_settings() -> void:
	settings_requested.emit()

func sync(proj: Dictionary, players: Array) -> void:
	# proj = for_spectator(engine); players = the seat list (to resolve names+colors)
	var tp: int = int(proj.get("turn_player", -1))
	if tp >= 0 and tp < players.size():
		var s = players[tp]
		_turn.text = "ХОД: " + str(s.name)
		_turn.add_theme_color_override("font_color", s.color)
	else:
		_turn.text = ""
	_phase.text = "ФАЗА: " + str(proj.get("phase", ""))
