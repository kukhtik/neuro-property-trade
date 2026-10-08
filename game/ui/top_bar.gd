class_name TopBar
extends PanelContainer
## Fixed top bar: game title + current turn (player) + phase + timer ring +
## settings/restart buttons + F12 hint (host-only). Reads a spectator-safe
## projection dict. Shape-only for future art swap.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
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
## The execution role. Drives what the header shows — the role is NOT switchable
## here (owner decision, docs/ui_migration_notes §9), only reported.
var _profile = null
var _role_badge: Label = null
var _eye_btn: Button
var _sfx = null   # optional Sfx for the per-second timer tick

## Provide the procedural Sfx node so the timer ring can play a tick each second.
func set_sfx(sfx) -> void:
	_sfx = sfx
	if _timer_ring != null:
		_timer_ring.set_tick_callback(_timer_tick)

## P5 SFX: one tick per elapsed decision-timer second (routed by TimerRing).
func _timer_tick() -> void:
	if _sfx != null and _sfx.has_method("play_timer_tick"):
		_sfx.play_timer_tick()

func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	add_child(m)
	m.add_child(h)

	_title = UiTheme.label(I18n.t("top.title"), 15, UiTheme.COL().gold)
	I18n.key_on(_title, "top.title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title)
	_turn = UiTheme.label("", 15)
	h.add_child(_turn)
	_phase = UiTheme.label("", 13, UiTheme.COL().text_dim)
	h.add_child(_phase)
	
	# P3: Timer ring next to phase
	_timer_ring = TimerRing.new()
	h.add_child(_timer_ring)
	
	_settings_btn = UiTheme.button("⚙", I18n.t("top.settings_tip"))
	_settings_btn.custom_minimum_size = Vector2(30, 24)
	_settings_btn.connect("pressed", Callable(self, "_on_settings"))
	h.add_child(_settings_btn)
	_restart_btn = UiTheme.button("↻", I18n.t("top.restart_tip"))
	_restart_btn.custom_minimum_size = Vector2(30, 24)
	_restart_btn.connect("pressed", Callable(self, "_on_restart"))
	h.add_child(_restart_btn)
	# P4 §7: observer button — shown only when the match has no LOCAL seat
	# (otherwise it would "disconnect" the live human player).
	_eye_btn = UiTheme.button("👁", I18n.t("top.eye_tip"))
	_eye_btn.custom_minimum_size = Vector2(30, 24)
	_eye_btn.visible = false
	_eye_btn.connect("pressed", Callable(self, "_on_eye"))
	h.add_child(_eye_btn)
	_hint = UiTheme.label(I18n.t("top.admin_hint"), 12, UiTheme.COL().text_dim)
	h.add_child(_hint)

## Host-only gate: hide the F12 hint on non-host (WebGL / spectator).
func set_host(v: bool) -> void:
	_is_host = v
	_hint.visible = v


## Apply the execution role. Stream runs get a compact header, a "LIVE" marker
## and NO admin hint; player/admin keep the full one.
func set_profile(pr) -> void:
	if pr == null:
		return
	_profile = pr
	_is_host = pr.shows_admin_tools
	if _hint != null:
		_hint.visible = pr.shows_admin_tools
	if _role_badge != null:
		_role_badge.visible = pr.shows_role_badge
		_role_badge.text = I18n.t("mode." + str(pr.id))

## P5: re-apply static localized labels after a locale change.
func retranslate() -> void:
	if _settings_btn != null:
		_settings_btn.tooltip_text = I18n.t("top.settings_tip")
	if _restart_btn != null:
		_restart_btn.tooltip_text = I18n.t("top.restart_tip")
	if _eye_btn != null:
		_eye_btn.tooltip_text = I18n.t("top.eye_tip")
	if _hint != null:
		_hint.text = I18n.t("top.admin_hint")

## Enlarge the bar's own type for a role that is read from a distance (the OBS window).
func scale_text(factor: float) -> void:
	if factor <= 0.0 or is_equal_approx(factor, 1.0):
		return
	for lbl in [_turn, _phase, _hint, _role_badge]:
		if lbl == null:
			continue
		var base: int = int(lbl.get_meta("base_size", 0))
		if base == 0:
			base = lbl.get_theme_font_size("font_size")
			if base <= 0:
				base = 13
			lbl.set_meta("base_size", base)
		lbl.add_theme_font_size_override("font_size", int(round(base * factor)))


func set_cold(v: bool) -> void:
	_turn.text = ""
	_phase.text = I18n.t("top.cold")
	_restart_btn.visible = false

func sync_cold() -> void:
	_turn.text = ""
	_phase.text = I18n.t("top.cold")
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
		_turn.text = I18n.t("top.turn") + str(s.name)
		_turn.add_theme_color_override("font_color", s.color)
	else:
		_turn.text = ""
	# CS-1: localize the phase name (phase.* keys), fall back to the raw enum.
	var ph: String = str(proj.get("phase", ""))
	var ph_lbl: String = I18n.t("phase." + ph)
	if ph_lbl.begins_with("{phase."):
		ph_lbl = ph
	_phase.text = I18n.t("top.phase") + ph_lbl
	_restart_btn.visible = true
	
	# P3: Update timer ring
	if _timer_ring != null:
		var window: float = float(proj.get("timer_window", 0.0))
		var elapsed: float = float(proj.get("timer_elapsed", 0.0))
		var active: bool = bool(proj.get("timer_active", false))
		_timer_ring.set_state(window, elapsed, active)
