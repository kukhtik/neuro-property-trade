class_name TimerRing
extends Control
## Visual timer ring (P3) — draws a circular progress ring that counts down
## the decision window. Hidden when timer_window == 0 (no limit).
## Positioned in TopBar next to the phase label.

var _timer_window: float = 0.0
var _timer_elapsed: float = 0.0
var _timer_active: bool = false
var _size: int = 28
var _thickness: int = 3
var _last_second := -1
var _on_tick: Callable = Callable()   # optional: called each second boundary

## Set a callback invoked on each whole-second countdown change (for SFX ticks).
func set_tick_callback(cb: Callable) -> void:
	_on_tick = cb

func _init() -> void:
	custom_minimum_size = Vector2(_size, _size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_state(window: float, elapsed: float, active: bool) -> void:
	_timer_window = window
	_timer_elapsed = elapsed
	_timer_active = active
	visible = active and window > 0.0
	if active and window > 0.0:
		var sec := maxi(0, int(ceil(window - elapsed)))
		if sec != _last_second:
			if _last_second > 0 and sec < _last_second and _on_tick.is_valid():
				_on_tick.call()
			_last_second = sec
	else:
		_last_second = -1
	queue_redraw()

func _draw() -> void:
	if not _timer_active or _timer_window <= 0.0:
		return
	var center: float = size.x * 0.5
	var radius: float = center - _thickness * 0.5
	# Background ring (dim)
	var bg_col := Color(0.2, 0.25, 0.35, 0.6)
	draw_arc(Vector2(center, center), radius, 0, 2 * PI, 16, bg_col, _thickness)
	# Progress ring (accent) — counts DOWN from full to empty
	var progress := 1.0 - clampf(_timer_elapsed / _timer_window, 0.0, 1.0)
	var end_angle := -PI / 2.0 + progress * 2 * PI
	var fg_col := UiTheme.skin().color("money")
	if progress < 0.25:
		fg_col = UiTheme.skin().color("ev.danger")
	elif progress < 0.5:
		fg_col = UiTheme.skin().color("ev.build")
	draw_arc(Vector2(center, center), radius, -PI / 2.0, end_angle, 16, fg_col, _thickness)
	# Center time text
	var remaining := maxi(0, int(ceil(_timer_window - _timer_elapsed)))
	var fs: float = _size * 0.4
	draw_string(get_theme_font("font"), Vector2(center, center + fs * 0.35),
		str(remaining), HORIZONTAL_ALIGNMENT_CENTER, _size, fs, UiTheme.skin().color("dice_bg"))