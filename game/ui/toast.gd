extends VBoxContainer
## Toasts docked at the top of the right column (`#toast`): one row per event, a coloured
## bar, a title, the text and a close button. v3 rebuild.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

const MAX_TOASTS := 3


func _init() -> void:
	add_theme_constant_override("separation", 6)


func toast_count() -> int:
	return get_child_count()


func dismiss_all() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()


## One event as a toast: {type, data}. Titles come from the i18n `event_type.*` keys.
func show_event_toast(ev: Dictionary) -> void:
	while get_child_count() >= MAX_TOASTS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var kind: String = str(ev.get("type", ""))
	var data: Dictionary = ev.get("data", {})
	var card := PanelContainer.new()
	var bar_col: Color = UiTheme.COL().accent
	match kind:
		"rent", "tax", "pay":
			bar_col = UiTheme.COL().money
		"purchase", "auction_win":
			bar_col = UiTheme.COL().success
		"bankrupt", "send_to_jail":
			bar_col = UiTheme.COL().danger
	card.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark, bar_col, 1, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	card.add_child(m)
	var row := UiTheme.hbox(8)
	m.add_child(row)
	var v := UiTheme.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_key := "event_type." + kind
	var title := UiTheme.label(I18n.t(title_key) if I18n.has(title_key) else kind, 12, bar_col)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(title)
	var text := str(data.get("message", ""))
	if text == "":
		var who := str(data.get("player", ""))
		if who != "":
			text = who
	var line := UiTheme.label_wrap(text, 12, UiTheme.COL().text)
	v.add_child(line)
	row.add_child(v)
	var x := UiTheme.button("✕", "")
	x.custom_minimum_size = Vector2(20, 20)
	x.connect("pressed", func() -> void:
		card.queue_free())
	row.add_child(x)
	add_child(card)
