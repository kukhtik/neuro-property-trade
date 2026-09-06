extends PanelContainer
## Thin host-local admin panel (spec §4). Dumb UI over admin_controller — no
## engine logic here. F12 toggle is handled in main.gd.

var _controller
var _op: OptionButton
var _param_pid: SpinBox
var _param_tile: SpinBox
var _param_amount: SpinBox
var _param_flag: OptionButton   # on/off for set_mortgage
var _param_d1: SpinBox
var _param_d2: SpinBox
var _apply: Button
var _reset_away: Button
var _state: RichTextLabel
var _log: RichTextLabel
var _refresh_timer: float = 0.0

const OPS := ["set_balance", "teleport", "force_dice", "grant_property",
	"revoke_property", "set_houses", "set_mortgage", "set_go_jail",
	"force_roll", "force_pass", "rollback_decision"]

func setup(controller) -> void:
	_controller = controller
	_build()
	_refresh_all()

func _build() -> void:
	custom_minimum_size = Vector2(560, 460)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var v = VBoxContainer.new()
	margin.add_child(v)

	var header = Label.new()
	header.text = "Admin Console (host-local)"
	header.add_theme_font_size_override("font_size", 18)
	v.add_child(header)

	# Operation selector + Apply/Reset buttons.
	var oprow = HBoxContainer.new()
	oprow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	v.add_child(oprow)
	_op = OptionButton.new()
	for op in OPS:
		_op.add_item(op)
	_op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oprow.add_child(_op)
	_apply = Button.new(); _apply.text = "Apply"
	_apply.pressed.connect(_apply_op)
	oprow.add_child(_apply)

	# Params grid: pid | tile | amount/count | on/off | d1 | d2.
	var grid = GridContainer.new()
	grid.columns = 6
	v.add_child(grid)
	_param_pid = _spin(0, 999, "pid", grid)
	_param_tile = _spin(0, 39, "tile", grid)
	_param_amount = _spin(0, 99999, "amount/count", grid)
	var flag_label = Label.new(); flag_label.text = "on:"
	grid.add_child(flag_label)
	_param_flag = OptionButton.new()
	_param_flag.add_item("on"); _param_flag.add_item("off")
	_param_flag.selected = 0
	grid.add_child(_param_flag)
	_param_d1 = _spin(0, 6, "d1", grid)
	_param_d2 = _spin(0, 6, "d2", grid)

	_reset_away = Button.new(); _reset_away.text = "Reset 'away' for pid"
	_reset_away.pressed.connect(_reset_away_pressed)
	v.add_child(_reset_away)

	var state_label = Label.new(); state_label.text = "Live state:"
	v.add_child(state_label)
	_state = RichTextLabel.new()
	_state.bbcode_enabled = true
	_state.custom_minimum_size.y = 130
	_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_state)

	var log_label = Label.new(); log_label.text = "Event log (last 30):"
	v.add_child(log_label)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.custom_minimum_size.y = 130
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_log)

func _spin(minv: int, maxv: int, label_text: String, parent: Control) -> SpinBox:
	var sb = SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = minv
	sb.editable = true
	var wrap = HBoxContainer.new()
	var lab = Label.new()
	lab.text = label_text + ":"
	wrap.add_child(lab)
	wrap.add_child(sb)
	parent.add_child(wrap)
	return sb

## Read only the params that make sense for the selected op; ignore the rest.
func _params_for_op(op: String) -> Dictionary:
	var params := {}
	match op:
		"set_balance":
			params["pid"] = int(_param_pid.value)
			params["amount"] = int(_param_amount.value)
		"teleport":
			params["pid"] = int(_param_pid.value)
			params["tile"] = int(_param_tile.value)
		"force_dice":
			params["d1"] = int(_param_d1.value)
			params["d2"] = int(_param_d2.value)
		"grant_property":
			params["pid"] = int(_param_pid.value)
			params["tile"] = int(_param_tile.value)
		"revoke_property":
			params["pid"] = int(_param_pid.value)
			params["tile"] = int(_param_tile.value)
		"set_houses":
			params["tile"] = int(_param_tile.value)
			params["count"] = int(_param_amount.value)
		"set_mortgage":
			params["tile"] = int(_param_tile.value)
			params["on"] = (_param_flag.selected == 0)
		"set_go_jail":
			params["pid"] = int(_param_pid.value)
		# force_roll / force_pass / rollback_decision take no params
	return params

func _apply_op() -> void:
	if _controller == null: return
	var op: String = _op.get_item_text(_op.selected)
	var params := _params_for_op(op)
	var res: Dictionary = _controller.override(op, params)
	_refresh_all()
	print("[admin] %s -> ok=%s reason=%s" % [op, str(res.get("ok")), str(res.get("reason", ""))])

func _reset_away_pressed() -> void:
	if _controller == null: return
	var pid: int = int(_param_pid.value)
	var res: Dictionary = _controller.reset_seat_away(pid)
	print("[admin] reset_seat_away %d -> %s" % [pid, str(res)])
	_refresh_all()

func _refresh_all() -> void:
	if _controller == null: return
	var dump = _controller.dump_state()
	_state.bbcode_text = "[code]%s[/code]" % _dump_to_text(dump)
	var ev: Array = _controller.list_events("")
	var start: int = maxi(0, ev.size() - 30)
	var tail: Array = ev.slice(start)
	_log.bbcode_text = "[code]%s[/code]" % _events_to_text(tail)

func _dump_to_text(d: Dictionary) -> String:
	var lines: Array[String] = ["phase %s | turn %s" % [d.get("phase", ""), str(d.get("turn_player", ""))]]
	for p in (d.get("players", []) as Array):
		lines.append("p%d %-8s $%-6d @%-2d jail:%s away:%s tiles:%s" % [
			int(p.get("pid", 0)), str(p.get("name", "")), int(p.get("money", 0)),
			int(p.get("position", 0)), str(p.get("in_jail", false)),
			str(p.get("away", false)), str(p.get("tiles", []))])
	return "\n".join(lines)

func _events_to_text(ev: Array) -> String:
	var lines: Array[String] = []
	for entry in ev:
		lines.append("%d:%s %s" % [int(entry.get("index", 0)), str(entry.get("type", "")), str(entry.get("data", {}))])
	return "\n".join(lines)

func _process(delta: float) -> void:
	_refresh_timer += delta
	if visible and _refresh_timer >= 1.0:
		_refresh_timer = 0.0
		_refresh_all()
