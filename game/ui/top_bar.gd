class_name TopBar
extends PanelContainer
## Fixed top bar: game title + current turn (player) + phase + timer ring +
## settings/restart buttons + F12 hint (host-only). Reads a spectator-safe
## projection dict. Shape-only for future art swap.

const UiTheme := preload("res://ui/theme.gd")
const TimerRing := preload("res://ui/timer_ring.gd")

signal settings_requested
signal restart_requested
signal observer_toggle_requested

var _title: Label
var _turn: Label
var _phase: Label
var _hint: Label
var _restart_btn: Button
var _settings_btn: Button
var _timer_ring: TimerRing
var _is_host := true
var _eye_btn: Button

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
	
	# P3: Timer ring next to phase
	_timer_ring = TimerRing.new()
	h.add_child(_timer_ring)
	
	_settings_btn = UiTheme.button("⚙", "Открыть настройки и правила игры")
	_settings_btn.custom_minimum_size = Vector2(30, 24)
	_settings_btn.connect("pressed", Callable(self, "_on_settings"))
	h.add_child(_settings_btn)
	_restart_btn = UiTheme.button("↻", "Пересобрать партию с новым сидом (рестарт)")
	_restart_btn.custom_minimum_size = Vector2(30, 24)
	_restart_btn.connect("pressed", Callable(self, "_on_restart"))
	h.add_child(_restart_btn)
	# P4 §7: observer button — shown only when the match has no LOCAL seat
	# (otherwise it would "disconnect" the live human player).
	_eye_btn = UiTheme.button("👁", "Режим наблюдателя: вернуться к настройкам матча (места без LOCAL играют сами)")
	_eye_btn.custom_minimum_size = Vector2(30, 24)
	_eye_btn.visible = false
	_eye_btn.connect("pressed", Callable(self, "_on_eye"))
	h.add_child(_eye_btn)
	_hint = UiTheme.label("F12 — админ", 12, UiTheme.COL.text_dim)
	h.add_child(_hint)

## Host-only gate: hide the F12 hint on non-host (WebGL / spectator).
func set_host(v: bool) -> void:
	_is_host = v
	_hint.visible = v

func set_cold(v: bool) -> void:
	_turn.text = ""
	_phase.text = "до старта"
	_restart_btn.visible = false

func sync_cold() -> void:
	_turn.text = ""
	_phase.text = "до старта"
	_restart_btn.visible = false

func _on_settings() -> void:
	settings_requested.emit()

func _on_restart() -> void:
	restart_requested.emit()

func _on_eye() -> void:
	observer_toggle_requested.emit()

## P4 §7: the 👁 button exists only in a match WITHOUT a LOCAL seat (host is a
## pure spectator) — clicking it returns to the settings overlay.
func set_observer(v: bool) -> void:
	if _eye_btn != null:
		_eye_btn.visible = v

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
	_restart_btn.visible = true
	
	# P3: Update timer ring
	if _timer_ring != null:
		var window: float = float(proj.get("timer_window", 0.0))
		var elapsed: float = float(proj.get("timer_elapsed", 0.0))
		var active: bool = bool(proj.get("timer_active", false))
		_timer_ring.set_state(window, elapsed, active)
