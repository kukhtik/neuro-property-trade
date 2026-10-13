extends Control
## The modal host (`#modal`): a dim scrim and one centred sheet. v3 rebuild — the shell
## uses it for rejection messages today; richer modals can land in it later.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

var _scrim: ColorRect
var _sheet: PanelContainer
var _title: Label
var _body: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	visible = false

	_scrim = ColorRect.new()
	_scrim.color = Color(UiTheme.COL().bg.r, UiTheme.COL().bg.g, UiTheme.COL().bg.b, 0.72)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	_sheet = PanelContainer.new()
	_sheet.custom_minimum_size = Vector2(0, 0)
	_sheet.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_sheet.anchor_left = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.offset_left = -280
	_sheet.offset_right = 280
	_sheet.offset_top = -120
	_sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_sheet)
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 16)
	_sheet.add_child(m)
	var v := UiTheme.vbox(10)
	m.add_child(v)
	var head := UiTheme.hbox(8)
	_title = UiTheme.label("", 16, UiTheme.COL().text)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := UiTheme.button("✕", "")
	x.custom_minimum_size = Vector2(26, 26)
	x.connect("pressed", Callable(self, "close"))
	head.add_child(x)
	v.add_child(head)
	_body = UiTheme.vbox(8)
	v.add_child(_body)


func show_message(title: String, text: String) -> void:
	_title.text = title
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_body.add_child(UiTheme.label_wrap(text, 13, UiTheme.COL().text))
	visible = true


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		accept_event()
