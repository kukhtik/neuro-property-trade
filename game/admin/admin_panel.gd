extends PanelContainer
## Host-local admin panel (spec §8.2, P4). Dumb UI over admin_gate +
## admin_controller — no engine logic here. F12 toggle is handled in main.gd.
##
## Tabs (spec §8.2):
##   [Быстрые] force_roll / force_pass / rollback_decision / reset_seat_away
##   [Состояние] live state summary + copy JSON dump + snapshot save/load
##   [События] filtered event feed (type) + .jsonl export
##   [Правки] per-operation rows, each with ONLY its own fields + inline result
##
## Every mutation goes through gate.override → engine.admin_override (the
## engine-authoritative invariant is untouched). Destructive ops (redo_turn,
## reorder_players, snapshot load) ask for confirmation first. Results are
## shown INLINE (ok / reason) and in the admin log at the bottom — never only
## in stdout (spec problem 24).

signal game_rebuilt(engine)   # after a snapshot load (main rebuilds the view)

const UiTheme := preload("res://ui/theme.gd")
const Snapshot := preload("res://core/snapshot.gd")
const EventMessages := preload("res://visual/event_messages.gd")
const I18n := preload("res://i18n/i18n.gd")

const TAB_QUICK := 0
const TAB_STATE := 1
const TAB_EVENTS := 2
const TAB_EDITS := 3

const SNAPSHOT_PATH := "user://admin_snapshot.json"

var _controller
var _token: String = ""

# shared widgets
var _tabs: TabContainer
var _search: LineEdit
var _admin_log: RichTextLabel
var _admin_log_lines: Array[String] = []

# quick tab
var _b_force_roll: Button
var _b_force_pass: Button
var _b_rollback: Button
var _b_reset_away: Button
var _away_pid: SpinBox

# state tab
var _state: RichTextLabel
var _b_copy: Button
var _b_save_snap: Button
var _b_load_snap: Button

# events tab
var _ev_filter: OptionButton
var _ev_export: Button
var _ev_feed: RichTextLabel

# edits tab: rows built from EDIT_OPS (per-op fields, nothing more on screen)
var _edit_rows: Array = []   # {op, widgets: Dictionary, row: Control}
var _pid_options: Array = [] # OptionButtons that need the live pid list

## Operations for the Правки tab. Each row shows ONLY the fields the op needs;
## `confirm` marks destructive operations that ask before executing. Labels and
## tips are localized via I18n keys (`_op_label`/`_op_tip`).
const EDIT_OPS := [
	{"op": "set_balance", "label_key": "admin.op_set_balance", "fields": ["pid", "amount"]},
	{"op": "teleport", "label_key": "admin.op_teleport", "fields": ["pid", "tile"]},
	{"op": "force_dice", "label_key": "admin.op_force_dice", "fields": ["d1", "d2"]},
	{"op": "grant_property", "label_key": "admin.op_grant", "fields": ["pid", "tile"]},
	{"op": "revoke_property", "label_key": "admin.op_revoke", "fields": ["pid", "tile"]},
	{"op": "set_houses", "label_key": "admin.op_set_houses", "fields": ["tile", "count"]},
	{"op": "set_mortgage", "label_key": "admin.op_set_mortgage", "fields": ["tile", "flag"]},
	{"op": "tweak_tile", "label_key": "admin.op_tweak_tile", "fields": ["tile", "cost", "rent", "rent_set", "house_cost"]},
	{"op": "deck_insert", "label_key": "admin.op_deck_insert", "fields": ["deck", "card_name", "effect", "value"]},
	{"op": "deck_remove", "label_key": "admin.op_deck_remove", "fields": ["deck", "card_name"]},
	{"op": "set_go_jail", "label_key": "admin.op_set_go_jail", "fields": ["pid"]},
	{"op": "reorder_players", "label_key": "admin.op_reorder", "fields": ["order"], "confirm": true},
	{"op": "redo_turn", "label_key": "admin.op_redo_turn", "fields": ["seed"], "confirm": true},
]

static func _op_label(def: Dictionary) -> String:
	return I18n.t(str(def.get("label_key", def.get("op", ""))))

static func _op_tip(def: Dictionary) -> String:
	return I18n.t(str(def.get("label_key", def.get("op", ""))) + "_tip")

func setup(controller) -> void:
	_controller = controller
	# If the controller is an admin_gate, read its token for authenticated calls.
	if controller != null and controller.has_method("is_guarded"):
		_token = str(controller.get("_token")) if controller.get("_token") != null else ""
	if _tabs == null:
		_build()
	_refresh_all()

func _ready() -> void:
	# setup() may not have been called yet (panel created hidden at launch)
	if _tabs == null:
		_build()

# ---------------------------------------------------------------- build ----

func _build() -> void:
	custom_minimum_size = Vector2(620, 560)
	var margin = MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 10)
	add_child(margin)
	var v = VBoxContainer.new()
	margin.add_child(v)

	# header: title + search + close
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title = UiTheme.label(I18n.t("admin.title"), 16, UiTheme.COL().gold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = I18n.t("admin.search_ph")
	_search.custom_minimum_size.x = 170
	_search.tooltip_text = I18n.t("admin.search_tip")
	_search.connect("text_changed", Callable(self, "_on_search"))
	head.add_child(_search)
	v.add_child(head)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_build_quick_tab()
	_build_state_tab()
	_build_events_tab()
	_build_edits_tab()

	# admin log at the bottom (spec §8.2)
	var log_head := UiTheme.label(I18n.t("admin.log_head"), 11, UiTheme.COL().text_dim)
	v.add_child(log_head)
	_admin_log = RichTextLabel.new()
	_admin_log.bbcode_enabled = true
	_admin_log.scroll_following = true
	_admin_log.custom_minimum_size.y = 64
	v.add_child(_admin_log)

## One labeled spin row helper (label LEFT of the control).
func _labeled(lbl: String, ctl: Control, tip: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := UiTheme.label(lbl, 12)
	l.tooltip_text = tip
	h.add_child(l)
	h.add_child(ctl)
	return h

func _spin(minv: int, maxv: int, tip: String) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = minv
	sb.custom_minimum_size.x = 84
	sb.tooltip_text = tip
	return sb

# ----------------------------------------------------------- quick tab ----

func _build_quick_tab() -> void:
	var tab := UiTheme.vbox(10)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("admin.tab_quick"))

	var hint := UiTheme.label(I18n.t("admin.quick_hint"), 12, UiTheme.COL().text_dim)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(hint)

	_b_force_roll = UiTheme.button_accent(I18n.t("admin.quick_force_roll"), I18n.t("admin.quick_force_roll_tip"))
	_b_force_roll.custom_minimum_size.y = 32
	_b_force_roll.connect("pressed", Callable(self, "_quick_force_roll"))
	tab.add_child(_b_force_roll)
	_b_force_pass = UiTheme.button(I18n.t("admin.quick_force_pass"), I18n.t("admin.quick_force_pass_tip"))
	_b_force_pass.custom_minimum_size.y = 32
	_b_force_pass.connect("pressed", Callable(self, "_quick_force_pass"))
	tab.add_child(_b_force_pass)
	_b_rollback = UiTheme.button(I18n.t("admin.quick_rollback"), I18n.t("admin.quick_rollback_tip"))
	_b_rollback.custom_minimum_size.y = 32
	_b_rollback.connect("pressed", Callable(self, "_quick_rollback"))
	tab.add_child(_b_rollback)

	var away_row := HBoxContainer.new()
	away_row.add_theme_constant_override("separation", 8)
	_away_pid = _spin(0, 999, I18n.t("admin.away_pid_tip"))
	away_row.add_child(UiTheme.label(I18n.t("admin.away_pid_lbl"), 12))
	away_row.add_child(_away_pid)
	_b_reset_away = UiTheme.button(I18n.t("admin.reset_away"), I18n.t("admin.reset_away_tip"))
	_b_reset_away.connect("pressed", Callable(self, "_quick_reset_away"))
	away_row.add_child(_b_reset_away)
	tab.add_child(away_row)

	tab.add_child(_status_summary_label())

func _status_summary_label() -> Label:
	var l := UiTheme.label("", 12, UiTheme.COL().text_dim)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.name = "QuickSummary"
	return l

# ------------------------------------------------------------ state tab ----

func _build_state_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("admin.tab_state"))

	_state = RichTextLabel.new()
	_state.bbcode_enabled = true
	_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(_state)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_b_copy = UiTheme.button(I18n.t("admin.copy_dump"), I18n.t("admin.copy_dump_tip"))
	_b_copy.connect("pressed", Callable(self, "_copy_dump"))
	row.add_child(_b_copy)
	_b_save_snap = UiTheme.button(I18n.t("admin.save_snap"), I18n.t("admin.save_snap_tip"))
	_b_save_snap.connect("pressed", Callable(self, "_save_snapshot"))
	row.add_child(_b_save_snap)
	_b_load_snap = UiTheme.button(I18n.t("admin.load_snap"), I18n.t("admin.load_snap_tip"))
	_b_load_snap.connect("pressed", Callable(self, "_load_snapshot"))
	row.add_child(_b_load_snap)
	tab.add_child(row)

# ----------------------------------------------------------- events tab ----

func _build_events_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("admin.tab_events"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.label(I18n.t("admin.ev_type_lbl"), 12))
	_ev_filter = OptionButton.new()
	_ev_filter.tooltip_text = I18n.t("admin.ev_filter_tip")
	_ev_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ev_filter.connect("item_selected", Callable(self, "_on_ev_filter"))
	row.add_child(_ev_filter)
	_ev_export = UiTheme.button(I18n.t("admin.ev_export"), I18n.t("admin.ev_export_tip"))
	_ev_export.connect("pressed", Callable(self, "_export_events"))
	row.add_child(_ev_export)
	tab.add_child(row)

	_ev_feed = RichTextLabel.new()
	_ev_feed.bbcode_enabled = true
	_ev_feed.scroll_following = true
	_ev_feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(_ev_feed)

# ------------------------------------------------------------ edits tab ----

func _build_edits_tab() -> void:
	var tab := VBoxContainer.new()
	tab.add_theme_constant_override("separation", 6)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("admin.tab_edits"))

	var note := UiTheme.label(I18n.t("admin.edits_note"), 11, UiTheme.COL().text_dim)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for def in EDIT_OPS:
		list.add_child(_build_edit_row(def))
	_filter_rows("")

func _build_edit_row(def: Dictionary) -> Control:
	var op: String = str(def["op"])
	var row := PanelContainer.new()
	row.name = "EditRow_" + op
	row.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	row.add_child(m)
	m.add_child(h)

	# op label with tooltip = the full "what it does / when to use" text
	var lbl := UiTheme.label(_op_label(def), 13)
	lbl.tooltip_text = _op_tip(def)
	lbl.custom_minimum_size.x = 120
	h.add_child(lbl)

	var widgets: Dictionary = {}
	for f in (def["fields"] as Array):
		var key: String = str(f)
		match key:
			"pid":
				var ob := OptionButton.new()
				ob.tooltip_text = I18n.t("admin.tip_pid")
				ob.custom_minimum_size.x = 110
				ob.clip_text = true
				widgets["pid"] = ob
				_pid_options.append(ob)
				h.add_child(ob)
			"tile":
				var ts := _spin(0, 39, I18n.t("admin.tip_tile"))
				widgets["tile"] = ts
				h.add_child(_labeled(I18n.t("admin.lbl_tile"), ts, ts.tooltip_text))
			"amount":
				var am := _spin(0, 1000000, I18n.t("admin.tip_amount"))
				am.value = 1500
				widgets["amount"] = am
				h.add_child(_labeled(I18n.t("admin.lbl_amount"), am, am.tooltip_text))
			"count":
				var cn := _spin(0, 5, I18n.t("admin.tip_count"))
				widgets["count"] = cn
				h.add_child(_labeled(I18n.t("admin.lbl_count"), cn, cn.tooltip_text))
			"flag":
				var fl := OptionButton.new()
				fl.add_item(I18n.t("admin.flag_mortgage"))
				fl.add_item(I18n.t("admin.flag_unmortgage"))
				fl.selected = 0
				fl.tooltip_text = I18n.t("admin.tip_flag")
				widgets["flag"] = fl
				h.add_child(fl)
			"d1", "d2":
				var dv := _spin(0, 6, I18n.t("admin.tip_die"))
				widgets[key] = dv
				h.add_child(_labeled(key, dv, dv.tooltip_text))
			"cost", "rent", "rent_set", "house_cost":
				var mv := _spin(0, 1000000, I18n.t("admin.tip_field"))
				mv.value = 0
				widgets[key] = mv
				h.add_child(_labeled(key, mv, mv.tooltip_text))
			"deck":
				var dk := OptionButton.new()
				# item VALUES are engine `kind` identifiers — must stay ASCII
				dk.add_item("community")
				dk.add_item("chance")
				dk.selected = 0
				dk.tooltip_text = I18n.t("admin.tip_deck")
				widgets["deck"] = dk
				h.add_child(dk)
			"card_name":
				var cn := LineEdit.new()
				cn.placeholder_text = I18n.t("admin.card_name_ph")
				cn.custom_minimum_size.x = 120
				cn.tooltip_text = I18n.t("admin.tip_card_name")
				widgets["card_name"] = cn
				h.add_child(cn)
			"effect":
				var ef := OptionButton.new()
				for e in ["collect", "pay", "advance", "move_to", "go_to_jail", "jail_card", "collect_from_all", "pay_each_player"]:
					ef.add_item(e)
				ef.selected = 0
				ef.tooltip_text = I18n.t("admin.tip_effect")
				widgets["effect"] = ef
				h.add_child(ef)
			"value":
				var vv := _spin(-1000, 1000000, I18n.t("admin.tip_value"))
				vv.value = 50
				widgets["value"] = vv
				h.add_child(_labeled(I18n.t("admin.lbl_value"), vv, vv.tooltip_text))
			"order":
				var od := LineEdit.new()
				od.placeholder_text = I18n.t("admin.order_ph")
				od.custom_minimum_size.x = 120
				od.tooltip_text = I18n.t("admin.tip_order")
				widgets["order"] = od
				h.add_child(od)
			"seed":
				var sd := _spin(1, 999999999, I18n.t("admin.tip_seed"))
				sd.value = 1
				widgets["seed"] = sd
				h.add_child(_labeled(I18n.t("admin.lbl_seed"), sd, sd.tooltip_text))

	var result := UiTheme.label("", 12, UiTheme.COL().text_dim)
	result.custom_minimum_size.x = 150
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	widgets["result"] = result
	h.add_child(result)

	var apply := UiTheme.button(I18n.t("admin.apply_btn"), _op_tip(def))
	apply.custom_minimum_size.y = 24
	apply.connect("pressed", Callable(self, "_on_edit_apply").bind(op))
	widgets["apply"] = apply
	h.add_child(apply)

	_edit_rows.append({"op": op, "widgets": widgets, "row": row})
	return row

# ------------------------------------------------------------- actions ----

func _gate_call(op: String, params: Dictionary) -> Dictionary:
	if _controller == null:
		return {"ok": false, "reason": "no controller"}
	if _controller.has_method("override") and _controller.has_method("is_guarded"):
		return _controller.override(op, params, _token)
	return _controller.override(op, params)

func _gate_reset_away(pid: int) -> Dictionary:
	if _controller == null:
		return {"ok": false, "reason": "no controller"}
	if _controller.has_method("reset_seat_away") and _controller.has_method("is_guarded"):
		return _controller.reset_seat_away(pid, _token)
	return _controller.reset_seat_away(pid)

func _quick_force_roll() -> void:
	_run_op("force_roll", {}, I18n.t("admin.quick_tag_roll"))

func _quick_force_pass() -> void:
	_run_op("force_pass", {}, I18n.t("admin.quick_tag_pass"))

func _quick_rollback() -> void:
	_run_op("rollback_decision", {}, I18n.t("admin.quick_tag_rollback"))

func _quick_reset_away() -> void:
	var pid := int(_away_pid.value)
	var res := _gate_reset_away(pid)
	_log_admin(I18n.t("admin.log_reset_away", [pid]), res)
	_refresh_all()

func _on_edit_apply(op: String) -> void:
	var def := _edit_def(op)
	var widgets: Dictionary = _edit_widgets(op)
	if def.is_empty() or widgets.is_empty():
		return
	# destructive ops ask for confirmation first (spec §8.2)
	if def.has("confirm") and bool(def["confirm"]):
		var ok: bool = await _confirm_dialog(I18n.t("admin.confirm_op", [_op_label(def)]))
		if not ok:
			_set_inline(op, I18n.t("admin.cancelled"), UiTheme.COL().text_dim)
			return
	var params := _params_from_widgets(op, widgets)
	var res := _gate_call(op, params)
	var col: Color = UiTheme.COL().success if bool(res.get("ok", false)) else UiTheme.COL().danger
	var txt: String = I18n.t("admin.ok") if bool(res.get("ok", false)) else I18n.t("admin.error", [str(res.get("reason", "?"))])
	_set_inline(op, txt, col)
	_log_admin(op, res)
	_refresh_all()

func _params_from_widgets(op: String, w: Dictionary) -> Dictionary:
	var params := {}
	match op:
		"set_balance":
			params["pid"] = _opt_pid(w["pid"])
			params["amount"] = int((w["amount"] as SpinBox).value)
		"teleport":
			params["pid"] = _opt_pid(w["pid"])
			params["tile"] = int((w["tile"] as SpinBox).value)
		"force_dice":
			params["d1"] = int((w["d1"] as SpinBox).value)
			params["d2"] = int((w["d2"] as SpinBox).value)
		"grant_property", "revoke_property":
			params["pid"] = _opt_pid(w["pid"])
			params["tile"] = int((w["tile"] as SpinBox).value)
		"set_houses":
			params["tile"] = int((w["tile"] as SpinBox).value)
			params["count"] = int((w["count"] as SpinBox).value)
		"set_mortgage":
			params["tile"] = int((w["tile"] as SpinBox).value)
			params["on"] = (w["flag"] as OptionButton).selected == 0
		"tweak_tile":
			params["tile"] = int((w["tile"] as SpinBox).value)
			for key in ["cost", "rent", "rent_set", "house_cost"]:
				if (w[key] as SpinBox).value > 0:
					params[key] = int((w[key] as SpinBox).value)
		"deck_insert":
			params["kind"] = (w["deck"] as OptionButton).get_item_text((w["deck"] as OptionButton).selected)
			params["card"] = {
				"name": str((w["card_name"] as LineEdit).text),
				"effect": (w["effect"] as OptionButton).get_item_text((w["effect"] as OptionButton).selected),
				"value": int((w["value"] as SpinBox).value),
			}
		"deck_remove":
			params["kind"] = (w["deck"] as OptionButton).get_item_text((w["deck"] as OptionButton).selected)
			var nm: String = str((w["card_name"] as LineEdit).text).strip_edges()
			if nm != "":
				params["name"] = nm
		"set_go_jail":
			params["pid"] = _opt_pid(w["pid"])
		"reorder_players":
			var order: Array = []
			for part in str((w["order"] as LineEdit).text).split(","):
				var t := part.strip_edges()
				if t.is_valid_int():
					order.append(int(t))
			params["order"] = order
		"redo_turn":
			params["seed"] = int((w["seed"] as SpinBox).value)
	return params

func _opt_pid(ob: OptionButton) -> int:
	# item index == pid (options are rebuilt in pid order)
	return ob.selected if ob.selected >= 0 else 0

func _edit_def(op: String) -> Dictionary:
	for def in EDIT_OPS:
		if str(def["op"]) == op:
			return def
	return {}

func _edit_widgets(op: String) -> Dictionary:
	for r in _edit_rows:
		if str(r["op"]) == op:
			return r["widgets"]
	return {}

func _set_inline(op: String, txt: String, col: Color) -> void:
	var w: Dictionary = _edit_widgets(op)
	if w.has("result"):
		var l: Label = w["result"]
		l.text = txt
		l.add_theme_color_override("font_color", col)

func _run_op(op: String, params: Dictionary, tag: String) -> void:
	var res := _gate_call(op, params)
	_log_admin(tag, res)
	_refresh_all()

# ----------------------------------------------------------- state tab ----

func _dump_text(d: Dictionary) -> String:
	var lines: Array[String] = [I18n.t("admin.dump_header", [
		str(d.get("phase", "?")), str(d.get("turn_player", "?"))])]
	for p in (d.get("players", []) as Array):
		lines.append(I18n.t("admin.dump_row", [
			int(p.get("pid", 0)), str(p.get("name", "")), int(p.get("money", 0)),
			int(p.get("position", 0)), int(p.get("houses", 0)), int(p.get("mortgaged", 0)),
			str(p.get("in_jail", false)), str(p.get("bankrupt", false)), str(p.get("tiles", []))]))
	return "\n".join(lines)

func _copy_dump() -> void:
	var d: Dictionary = _controller.dump_state() if _controller != null else {}
	DisplayServer.clipboard_set(JSON.stringify(d, "	"))
	_log_admin(I18n.t("admin.log_copy"), {"ok": true, "reason": "clipboard"})

func _save_snapshot() -> void:
	if _controller == null:
		return
	var engine = _controller.engine
	var ok: bool = Snapshot.save("user://admin_snapshot.json", engine)
	_log_admin(I18n.t("admin.log_save_snap"), {"ok": ok, "reason": "" if ok else I18n.t("admin.reason_write_fail")})
	_refresh_all()

func _load_snapshot() -> void:
	var ok: bool = await _confirm_dialog(I18n.t("admin.confirm_snap"))
	if not ok:
		return
	var eng = Snapshot.load("user://admin_snapshot.json")
	if eng == null:
		_log_admin(I18n.t("admin.log_export"), {"ok": false, "reason": I18n.t("admin.reason_load_fail")})
		_refresh_all()
		return
	# hot-swap: hand the restored engine to the controller + notify main
	_controller.engine = eng
	game_rebuilt.emit(eng)
	_log_admin(I18n.t("admin.log_export"), {"ok": true, "reason": I18n.t("admin.load_snap_done")})
	_refresh_all()

# ---------------------------------------------------------- events tab ----

func _on_ev_filter(_idx: int = 0) -> void:
	_refresh_events()

func _export_events() -> void:
	if _controller == null:
		return
	var entries: Array = _controller.list_events("")
	var f := FileAccess.open("user://admin_events_export.jsonl", FileAccess.WRITE)
	if f == null:
		_log_admin(I18n.t("admin.log_export"), {"ok": false, "reason": I18n.t("admin.export_fail")})
		return
	for e in entries:
		f.store_line(JSON.stringify(e))
	f.close()
	_log_admin(I18n.t("admin.log_export"), {"ok": true, "reason": ProjectSettings.globalize_path("user://admin_events_export.jsonl")})
	_refresh_all()

func _refresh_events() -> void:
	if _controller == null or _ev_feed == null:
		return
	var flt := ""
	if _ev_filter.selected > 0:
		flt = _ev_filter.get_item_text(_ev_filter.selected)
	var entries: Array = _controller.list_events(flt)
	# rebuild the type options (once per refresh is cheap at 40 ops scale)
	var types: Array[String] = [I18n.t("admin.ev_all_types")]
	var seen := {}
	for e in ( _controller.list_events("") as Array):
		var t: String = str(e.get("type", "?"))
		if not seen.has(t):
			seen[t] = true
			types.append(t)
	if _ev_filter.item_count != types.size():
		var keep := flt
		_ev_filter.clear()
		for t in types:
			_ev_filter.add_item(t)
		for i in _ev_filter.item_count:
			if _ev_filter.get_item_text(i) == (keep if keep != "" else I18n.t("admin.ev_all_types")):
				_ev_filter.select(i)
				break
	# feed: newest last, colored, human-readable (EventMessages wording)
	_ev_feed.clear()
	var start: int = maxi(0, entries.size() - 60)
	for i in range(start, entries.size()):
		var e: Dictionary = entries[i]
		var col: Color = _kind_color(str(e.get("type", "")))
		# the dim tag comes from the THEME, not from markup: a baked colour ignores the skin
		_ev_feed.append_text("[color=#%s]#%d[/color] [color=#%s][%s][/color] %s\n" % [
			col.to_html(false), int(e.get("index", -1)), UiTheme.COL().text_dim.to_html(false),
			str(e.get("type", "?")), EventMessages.describe(e)])

func _kind_color(t: String) -> Color:
	match t:
		"purchase", "auction_win", "go_bonus":
			return UiTheme.COL().money
		"pay", "rent", "tax":
			return Color("c9a84c")
		"jail", "bankrupt":
			return UiTheme.COL().danger
		"admin_override":
			return Color("9a86c9")
		_:
			return Color("e8edf3")

# -------------------------------------------------------- admin log ----

func _log_admin(op: String, res: Dictionary) -> void:
	var stamp := Time.get_time_string_from_system()
	var ok: bool = bool(res.get("ok", false))
	var reason: String = str(res.get("reason", ""))
	var col: String = UiTheme.COL().money.to_html(false) if ok else UiTheme.COL().danger.to_html(false)
	var line := "[color=#%s]%s[/color] [color=#%s]%s → %s[/color]" % [
		UiTheme.COL().text_dim.to_html(false), stamp, col, op, "ok" if ok else reason]
	_admin_log_lines.append(line)
	if _admin_log_lines.size() > 60:
		_admin_log_lines = _admin_log_lines.slice(_admin_log_lines.size() - 60)
	_admin_log.clear()
	for l in _admin_log_lines:
		_admin_log.append_text(l + "\n")

# --------------------------------------------------- search + refresh ----

func _on_search(_txt: String = "") -> void:
	_filter_rows(_search.text)

func _filter_rows(query: String) -> void:
	var q := query.to_lower().strip_edges()
	# match against op id, label text, and tooltip description
	for r in _edit_rows:
		var row: Control = r["row"]
		var def := _edit_def(str(r["op"]))
		var haystack := (str(r["op"]) + " " + _op_label(def) + " " + _op_tip(def)).to_lower()
		row.visible = (q == "") or haystack.contains(q)

func _refresh_all() -> void:
	if _controller == null:
		return
	# pid options live everywhere (quick away + every edits-row pid selector)
	var names: Array = []
	var dump: Dictionary = _controller.dump_state()
	for p in (dump.get("players", []) as Array):
		names.append("p%d·%s" % [int(p.get("pid", 0)), str(p.get("name", ""))])
	for ob in _pid_options:
		var keep: int = ob.selected
		ob.clear()
		if names.is_empty():
			ob.add_item(I18n.t("admin.no_players"))
			ob.selected = 0
		else:
			for i in names.size():
				ob.add_item(str(names[i]))
			ob.select(clampi(keep, 0, names.size() - 1))
	# state tab
	_state.bbcode_text = "[code]%s[/code]" % _dump_text(dump)
	# quick tab summary
	var qs := _tabs.get_tab_control(TAB_QUICK).get_node_or_null("QuickSummary")
	if qs != null:
		qs.text = I18n.t("admin.quick_summary", [str(dump.get("phase", "?")), str(dump.get("turn_player", "?"))])
	_refresh_events()

# -------------------------------------------------- confirmation modal ----

## When true (probe/testing hook), _confirm_dialog returns true without UI.
var auto_confirm := false

func _confirm_dialog(text: String) -> bool:
	if auto_confirm:
		return true
	# modal confirmation via ConfirmationDialog (works in windowed runs too)
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = text
	dlg.ok_button_text = I18n.t("admin.confirm_yes")
	dlg.cancel_button_text = I18n.t("admin.confirm_no")
	dlg.title = I18n.t("admin.confirm_dlg")
	var done := [false, false]   # [answered, accepted]
	dlg.confirmed.connect(func() -> void:
		done[0] = true
		done[1] = true)
	dlg.canceled.connect(func() -> void:
		done[0] = true
		done[1] = false)
	add_child(dlg)
	dlg.popup_centered()
	while not done[0]:
		await get_tree().process_frame
	dlg.queue_free()
	return done[1]

func _process(delta: float) -> void:
	_refresh_timer += delta
	if visible and _refresh_timer >= 1.0:
		_refresh_timer = 0.0
		_refresh_all()

var _refresh_timer: float = 0.0