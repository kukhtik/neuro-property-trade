extends PanelContainer
## The right dock's journal (`#journal`): rows of "time · who · what · tag".
## v3 rebuild; the shell feeds it prepared rows.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

var _title: Label
var _count: Label
var _list: VBoxContainer
var _rows := 0


func _init() -> void:
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var v := UiTheme.vbox(0)
	add_child(v)
	var head := UiTheme.hbox(8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	m.add_child(head)
	_title = UiTheme.label(I18n.t("jrn.title"), 12, UiTheme.COL().text)
	head.add_child(_title)
	_count = UiTheme.label("", 10, UiTheme.COL().text_dim)
	head.add_child(_count)
	v.add_child(m)

	var list_margin := MarginContainer.new()
	list_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = UiTheme.vbox(0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	list_margin.add_child(scroll)
	v.add_child(list_margin)


## Append one row: {who, who_color, text, tag}.
func append(entry: Dictionary) -> void:
	if _rows == 0:
		pass
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark if _rows % 2 == 0 else UiTheme.COL().panel, Color(0, 0, 0, 0), 0, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	row.add_child(m)
	var line := UiTheme.hbox(8)
	m.add_child(line)
	var who := UiTheme.label(str(entry.get("who", "")), 11, entry.get("who_color", UiTheme.COL().text))
	who.custom_minimum_size.x = 60
	line.add_child(who)
	var txt := UiTheme.label_wrap(str(entry.get("text", "")), 12, UiTheme.COL().text)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(txt)
	var tag := UiTheme.label(str(entry.get("tag", "")), 9, UiTheme.COL().text_dim)
	line.add_child(tag)
	_list.add_child(row)
	_rows += 1
	_count.text = str(_rows)
	# autoscroll to the newest
	var scroll := _list.get_parent() as ScrollContainer
	if scroll != null:
		await get_tree().process_frame
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func clear_rows() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows = 0
	_count.text = "0"


func retranslate() -> void:
	_title.text = I18n.t("jrn.title")
