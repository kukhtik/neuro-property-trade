extends VBoxContainer
## Toasts docked at the top of the right column (`#toast`): one row per event, a coloured
## bar, a title, the text and a close button. v3 rebuild.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
## E-1/D9: the toast builds a trade's line through the SAME renderer the journal uses, so the two
## surfaces cannot drift apart about what a deal contained.
const JournalLines := preload("res://ui/core/journal_lines.gd")

const MAX_TOASTS := 3

## The line renderer holds round-tracking state, so the toast keeps its own instance rather than
## calling the class statically. Its own instance (not the journal's) on purpose: two consumers
## sharing one adapter's round tracker would each advance the other's round counter.
var _lines = JournalLines.new()


func _init() -> void:
	add_theme_constant_override("separation", 6)


func toast_count() -> int:
	return get_child_count()


func dismiss_all() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()


## One event as a toast: {type, data}. Titles come from the i18n `event_type.*` keys.
## The toast line for an event. Most events carry a ready human message from the engine; a TRADE
## does not, and used to show only the proposer's name - so the notification said "сделка" over a
## player name and nothing about the deal (E-1/D9). It now renders the SAME composition the journal
## and the modal render, through the same renderer, so all three agree.
##
## `ctx` is the journal context (tile names + seat names); when it is absent the toast degrades to
## the engine's message rather than fabricating a composition from indices it cannot resolve.
func show_event_toast(ev: Dictionary, ctx: Dictionary = {}) -> void:
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
	# E-1/D9: a trade notification must carry the DEAL, not just a name. The line is built by the
	# same renderer the journal uses (JournalLines), so the toast, the journal and the modal cannot
	# tell the player three different things about one trade. The engine sends no `message` for a
	# trade, which is why the toast used to fall through to the bare proposer name.
	if kind in ["trade", "trade_proposed", "trade_declined"]:
		var line: Dictionary = _lines.line_for(ev, ctx)
		var composed := str(line.get("text", ""))
		if composed != "":
			text = composed
	var lbl := UiTheme.label_wrap(text, 12, UiTheme.COL().text)
	v.add_child(lbl)
	row.add_child(v)
	var x := UiTheme.button("✕", "")
	x.custom_minimum_size = Vector2(20, 20)
	x.connect("pressed", func() -> void:
		card.queue_free())
	row.add_child(x)
	add_child(card)
