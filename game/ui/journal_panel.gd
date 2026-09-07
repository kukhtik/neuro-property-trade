class_name JournalPanel
extends PanelContainer
## Event journal (spec P4 / problem 15): replaces the raw 10-line label with a
## real panel — scrollable (auto-scroll pinned to the newest line), filterable
## (by player, by event type, money-only), with .jsonl export. Reads ONLY the
## engine event log entries (public fields) — spectator-safe.
##
## Observer layout: game_view widens this panel and the filters stay visible;
## nothing here depends on which seat is human.

signal exported(path: String)

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

var _log: RichTextLabel
var _player_filter: OptionButton
var _type_filter: OptionButton
var _money_only: CheckButton
var _export_btn: Button
var _count_lbl: Label
var _entries: Array = []          # full engine log (Array of Dictionary)
var _player_names: Array = []     # index == pid
var _rendered := 0                # how many entries are already in the label
var _filters_dirty := true

const EXPORT_PATH := "user://journal_export.jsonl"

## Event types that move money (the "деньги" quick filter).
const MONEY_TYPES := ["purchase", "pay", "rent", "tax", "go_bonus",
	"auction_win", "collect", "collect_from_all", "pay_each_player"]

func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel, UiTheme.COL.border, 1, 0))
	var outer := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(edge, 8)
	add_child(outer)
	var v := UiTheme.vbox(6)
	outer.add_child(v)

	# header: title + live count + export
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title := UiTheme.label(I18n.t("jrn.title"), 12, UiTheme.COL.accent)
	I18n.key_on(title, "jrn.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count_lbl = UiTheme.label("0", 11, UiTheme.COL.text_dim)
	_count_lbl.tooltip_text = I18n.t("jrn.count_tip")
	I18n.tip_on(_count_lbl, "jrn.count_tip")
	head.add_child(_count_lbl)
	_export_btn = UiTheme.button("⭳", I18n.t("jrn.export_tip"))
	I18n.tip_on(_export_btn, "jrn.export_tip")
	_export_btn.custom_minimum_size = Vector2(26, 22)
	_export_btn.connect("pressed", Callable(self, "_on_export"))
	head.add_child(_export_btn)
	v.add_child(head)

	# filter row: player | type | money-only
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	var plbl := UiTheme.label(I18n.t("jrn.player_lbl"), 11, UiTheme.COL.text_dim)
	I18n.key_on(plbl, "jrn.player_lbl")
	plbl.tooltip_text = I18n.t("jrn.player_tip")
	I18n.tip_on(plbl, "jrn.player_tip")
	filters.add_child(plbl)
	_player_filter = OptionButton.new()
	_player_filter.tooltip_text = I18n.t("jrn.player_filter_tip")
	I18n.tip_on(_player_filter, "jrn.player_filter_tip")
	_player_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_filter.clip_text = true
	_player_filter.connect("item_selected", Callable(self, "_on_filter_changed"))
	filters.add_child(_player_filter)
	var tlbl := UiTheme.label(I18n.t("jrn.type_lbl"), 11, UiTheme.COL.text_dim)
	I18n.key_on(tlbl, "jrn.type_lbl")
	tlbl.tooltip_text = I18n.t("jrn.type_tip")
	I18n.tip_on(tlbl, "jrn.type_tip")
	filters.add_child(tlbl)
	_type_filter = OptionButton.new()
	_type_filter.tooltip_text = I18n.t("jrn.type_filter_tip")
	I18n.tip_on(_type_filter, "jrn.type_filter_tip")
	_type_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_filter.clip_text = true
	_type_filter.connect("item_selected", Callable(self, "_on_filter_changed"))
	filters.add_child(_type_filter)
	_money_only = CheckButton.new()
	_money_only.text = "$"
	_money_only.tooltip_text = I18n.t("jrn.money_tip")
	I18n.tip_on(_money_only, "jrn.money_tip")
	_money_only.connect("toggled", Callable(self, "_on_filter_changed"))
	filters.add_child(_money_only)
	v.add_child(filters)

	# the log itself: rich text, auto-scroll pinned to the newest line
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.context_menu_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 120
	v.add_child(_log)

## Cold state: no engine yet.
func sync_cold() -> void:
	set_entries([], [])
	_filters_dirty = true

## P5: re-apply localized static labels after a locale change. Dynamic filter
## options are rebuilt (in the current locale) by a re-render.
func retranslate() -> void:
	I18n.relabel(self)
	if _entries.size() > 0 or _player_names.size() > 0:
		set_entries(_entries, _player_names)

## Full refresh: replace the entry list + player names, rebuild if needed.
## entries = engine.log.entries(); player_names[i] = display name of pid i.
func set_entries(entries: Array, player_names: Array) -> void:
	_entries = entries
	_player_names = player_names
	_sync_filter_options()
	_rebuild()

## Incremental feed: same as set_entries (kept for API symmetry with sync()).
func refresh(entries: Array, player_names: Array) -> void:
	set_entries(entries, player_names)

func _sync_filter_options() -> void:
	# index 0 is always the "all" display option (I18n.t("jrn.all")); the
	# comparison logic below relies on that position, not on the literal.
	var want: Array[String] = [I18n.t("jrn.all")]
	for i in _player_names.size():
		want.append("%d·%s" % [i, str(_player_names[i])])
	var cur_p: int = _player_filter.selected
	if _options_changed(_player_filter, want):
		_fill_options(_player_filter, want)
		_restore_selection(_player_filter, cur_p)
	# type filter: "all" + unique types present in the log
	var types: Array[String] = [I18n.t("jrn.all")]
	var seen := {}
	for e in _entries:
		var t: String = str(e.get("type", "?"))
		if not seen.has(t):
			seen[t] = true
			types.append(t)
	var cur_t := _selected_text(_type_filter)
	if _options_changed(_type_filter, types):
		_fill_type_options(_type_filter, types)
		_restore_text(_type_filter, cur_t)

func _fill_type_options(o: OptionButton, items: Array[String]) -> void:
	o.clear()
	for it in items:
		o.add_item(it)

func _options_changed(o: OptionButton, items: Array[String]) -> bool:
	if o.item_count != items.size():
		return true
	for i in items.size():
		if o.get_item_text(i) != items[i]:
			return true
	return false

func _fill_options(o: OptionButton, items: Array[String]) -> void:
	o.clear()
	for it in items:
		o.add_item(it)

func _restore_selection(o: OptionButton, idx: int) -> void:
	if idx >= 0 and idx < o.item_count:
		o.select(idx)
	else:
		o.select(0)

func _selected_text(o: OptionButton) -> String:
	if o.selected < 0 or o.selected >= o.item_count:
		return ""
	return o.get_item_text(o.selected)

func _restore_text(o: OptionButton, txt: String) -> void:
	for i in o.item_count:
		if o.get_item_text(i) == txt:
			o.select(i)
			return
	o.select(0)

func _selected_pid() -> int:
	# index 0 = "все"; option i corresponds to pid i-1
	if _player_filter.selected <= 0:
		return -1
	return _player_filter.selected - 1

func _selected_type() -> String:
	# index 0 is the "all" option — compare by position, not by the
	# locale-dependent display text.
	if _type_filter.selected <= 0:
		return ""
	return _selected_text(_type_filter)

func _money_only_on() -> bool:
	return _money_only.button_pressed

func _on_filter_changed(_idx: int = 0) -> void:
	_filters_dirty = true
	_rendered = 0
	if _log != null:
		_log.clear()
	_rebuild()

func _process(_delta: float) -> void:
	# rebuild lazily (new entries appended since last render, or filter change)
	if _filters_dirty or _rendered < _entries.size():
		_rebuild()

## Core: rebuild the visible text so it matches the current filters.
func _rebuild() -> void:
	if _log == null:
		return
	var vis := filter_entries(_entries, _selected_pid(), _selected_type(), _money_only.button_pressed)
	_log.clear()
	for e in vis:
		_log.append_text(_line_bbcode(e, _player_names))
	_rendered = _entries.size()
	_filters_dirty = false
	_count_lbl.text = "%d/%d" % [vis.size(), _entries.size()]

## PURE (headless-testable): filter log entries by player pid (-1 = all),
## event type ("" = all) and money-only.
static func filter_entries(entries: Array, pid: int, type: String, money_only: bool) -> Array:
	var out: Array = []
	for e in entries:
		var d: Dictionary = e.get("data", {})
		if pid >= 0 and not _mentions_player(d, pid):
			continue
		if type != "" and str(e.get("type", "")) != type:
			continue
		if money_only and not _is_money(e):
			continue
		out.append(e)
	return out

static func _mentions_player(d: Dictionary, pid: int) -> bool:
	for key in ["player", "from", "to", "proposer", "recipient", "winner"]:
		var v = d.get(key, null)
		if v == null:
			continue
		if v is int and int(v) == pid:
			return true
	return false

static func _is_money(e: Dictionary) -> bool:
	if MONEY_TYPES.has(str(e.get("type", ""))):
		return true
	var d: Dictionary = e.get("data", {})
	return d.has("amount") or d.has("cost") or d.has("price")

## PURE: serialize entries to .jsonl text (one JSON object per line).
static func to_jsonl(entries: Array) -> String:
	var lines: Array[String] = []
	for e in entries:
		lines.append(JSON.stringify(e))
	return "\n".join(lines) + "\n"

## One colored BBCode line for the log.
func _line_bbcode(e: Dictionary, names: Array) -> String:
	var idx := int(e.get("index", -1))
	var t: String = str(e.get("type", "?"))
	var txt: String = EventMessagesScript.describe(e)
	var col: Color = _kind_color(t)
	return "[color=#%s]#%d[/color] [color=#8b95a5][%s][/color] %s\n" % [
		col.to_html(false), idx, t, txt]

const EventMessagesScript := preload("res://visual/event_messages.gd")

static func _kind_color(t: String) -> Color:
	match t:
		"purchase", "auction_win", "go_bonus", "collect":
			return Color("5cb85c")
		"pay", "rent", "tax":
			return Color("c9a84c")
		"jail", "bankrupt":
			return Color("d9534f")
		"admin_override":
			return Color("9a86c9")
		_:
			return Color("e8edf3")

func _export() -> void:
	var f := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if f == null:
		exported.emit("")
		return
	f.store_string(to_jsonl(_entries))
	f.close()
	var global := ProjectSettings.globalize_path(EXPORT_PATH)
	exported.emit(global)