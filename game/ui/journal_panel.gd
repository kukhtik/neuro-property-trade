extends PanelContainer
## The right dock's journal (`#journal`) — SG-06.
##
## Contract (gates.md SG-06 + DESIGN §100): the feed explains the match.
##   · header: title · counter "показано N / M" · export (.jsonl)
##   · filters: by seat and by category (the 8 `ty.*` filters the design lists)
##   · rows: seat name in the seat's colour · text with tile NAMES in words · translated tag
##   · friendly empty states: no events yet / nothing matches the filter
## The panel stores the RAW engine events plus the rendering context and re-composes lines on
## filter or locale change (SG-08), so both stay live without a rebuild of the match.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const LinesScript := preload("res://ui/core/journal_lines.gd")

const CATS := ["roll", "money", "buy", "auction", "build", "card", "trade", "other"]
const EXPORT_PATH := "user://journal_export.jsonl"

var _title: Label
var _count: Label
var _export_btn: Button
var _pfilter: OptionButton
var _cfilter: OptionButton
var _list: VBoxContainer
var _empty: Label

var _lines = LinesScript.new()
var _rows: Array = []          # [{ev, ctx, line}] — raw + formatted, filtered at render time
var _seats: Array = []         # [{pid, name}] for the seat filter

var _f_pid := -1               # -1 = all seats
var _f_cat := ""               # "" = all kinds


func _init() -> void:
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var v := UiTheme.vbox(0)
	add_child(v)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 6)
	v.add_child(m)
	var col := UiTheme.vbox(6)
	m.add_child(col)
	# header: title · counter · export
	var head := UiTheme.hbox(8)
	_title = UiTheme.label(I18n.t("jrn.title"), 12, UiTheme.COL().text)
	head.add_child(_title)
	_count = UiTheme.label("", 10, UiTheme.COL().text_dim)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count)
	_export_btn = UiTheme.button(I18n.t("jrn.export"), I18n.t("jrn.export_tip"))
	_export_btn.add_theme_font_size_override("font_size", 10)
	_export_btn.pressed.connect(_on_export)
	head.add_child(_export_btn)
	col.add_child(head)
	# filters: seat · category
	var fil := UiTheme.hbox(8)
	_pfilter = OptionButton.new()
	_pfilter.add_theme_font_size_override("font_size", 10)
	_pfilter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pfilter.item_selected.connect(_on_pfilter)
	fil.add_child(_pfilter)
	_cfilter = OptionButton.new()
	_cfilter.add_theme_font_size_override("font_size", 10)
	# one grower per row (P-4): the seat filter takes the slack, the category filter sits at
	# its content width
	_cfilter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cfilter.item_selected.connect(_on_cfilter)
	fil.add_child(_cfilter)
	col.add_child(fil)

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
	# the friendly empty state lives INSIDE the scroll area, above the first row
	_empty = UiTheme.label_wrap("", 12, UiTheme.COL().text_dim)
	_empty.name = "jrn-empty"
	_empty.visible = false
	_list.add_child(_empty)
	_refill_filters()
	_update_counters()


## The seats known to the shell: [{pid, name}] - drives the seat filter's options.
## The shell hands over its own seat objects; normalise here so the panel never pokes at
## foreign classes (a Dictionary or a seat both work).
func set_seats(seat_list: Array) -> void:
	_seats.clear()
	for s in seat_list:
		if s is Dictionary:
			_seats.append({"pid": int(s.get("pid", -1)), "name": str(s.get("name", ""))})
		else:
			_seats.append({"pid": int(s.pid), "name": str(s.name)})
	_refill_filters()


## Keep one raw engine event; adapt + format it; render it when the filters let it through.
func append(ev: Dictionary, ctx: Dictionary) -> void:
	var line: Dictionary = _lines.line_for(ev, ctx)
	if line.is_empty():
		return
	_rows.append({"ev": ev, "ctx": ctx, "line": line})
	# cheap path: append only the new row when nothing is filtered away
	if _passes(line):
		_render_row(line)
	_update_counters()


## New match: forget everything, the round tracker too.
func clear_rows() -> void:
	_rows.clear()
	_lines.reset()
	_rebuild()


func total() -> int:
	return _rows.size()


func shown() -> int:
	var n := 0
	for r in _rows:
		if _passes(r["line"]):
			n += 1
	return n


## Export the WHOLE feed (filters ignored - an export is a record, not a view) as .jsonl.
func export_jsonl() -> String:
	var f := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if f == null:
		return ""
	for r in _rows:
		f.store_line(JSON.stringify({
			"round": int(r["line"].get("round", 1)),
			"seat": str(r["line"].get("who", "")),
			"cat": str(r["line"].get("cat", "")),
			"text": str(r["line"].get("text", "")),
		}))
	f.close()
	return EXPORT_PATH


func retranslate() -> void:
	_title.text = I18n.t("jrn.title")
	_export_btn.text = I18n.t("jrn.export")
	_export_btn.tooltip_text = I18n.t("jrn.export_tip")
	# rows are re-COMPOSED, not merely re-rendered: the stored line was formatted in the OLD
	# language, and a row must not keep the old tongue after the switch (SG-08)
	for r in _rows:
		r["line"] = _lines.line_for(r["ev"], r["ctx"])
	_refill_filters()
	_rebuild()


func _passes(line: Dictionary) -> bool:
	if _f_pid >= 0 and int(line.get("pid", -1)) != _f_pid:
		return false
	if _f_cat != "" and str(line.get("cat", "")) != _f_cat:
		return false
	return true


func _rebuild() -> void:
	for c in _list.get_children():
		if str(c.name) != "jrn-empty":
			_list.remove_child(c)
			c.queue_free()
	for r in _rows:
		if _passes(r["line"]):
			_render_row(r["line"])
	_update_counters()


func _render_row(line: Dictionary) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark if _list.get_child_count() % 2 == 0 else UiTheme.COL().panel,
			Color(0, 0, 0, 0), 0, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	row.add_child(m)
	var ln := UiTheme.hbox(8)
	m.add_child(ln)
	var who := UiTheme.label(str(line.get("who", "")), 11, line.get("who_color", UiTheme.COL().text))
	who.custom_minimum_size.x = 60
	ln.add_child(who)
	var txt := UiTheme.label_wrap(str(line.get("text", "")), 12, UiTheme.COL().text)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ln.add_child(txt)
	var tag := UiTheme.label(str(line.get("tag", "")), 9, UiTheme.COL().text_dim)
	ln.add_child(tag)
	_list.add_child(row)
	# autoscroll to the newest
	var scroll := _list.get_parent() as ScrollContainer
	if scroll != null:
		await get_tree().process_frame
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _update_counters() -> void:
	_count.text = I18n.t("jrn.shown", [shown(), total()])
	# the empty label is a child of _list; it is the ONLY child when nothing shows
	_empty.visible = _list.get_child_count() <= 1
	_empty.text = I18n.t("jrn.empty") if total() == 0 else I18n.t("jrn.no_match")


func _refill_filters() -> void:
	_pfilter.clear()
	_pfilter.add_item(I18n.t("jrn.filter_all"))
	for s in _seats:
		_pfilter.add_item(str(s.get("name", "")))
	_pfilter.selected = 0
	_cfilter.clear()
	_cfilter.add_item(I18n.t("jrn.filter_allcats"))
	for c in CATS:
		_cfilter.add_item(I18n.t("ty." + c))
	_cfilter.selected = 0


func _on_pfilter(idx: int) -> void:
	_f_pid = -1 if idx <= 0 or idx > _seats.size() else int(_seats[idx - 1].get("pid", -1))
	_rebuild()


func _on_cfilter(idx: int) -> void:
	_f_cat = "" if idx <= 0 or idx > CATS.size() else str(CATS[idx - 1])
	_rebuild()


func _on_export() -> void:
	export_jsonl()
