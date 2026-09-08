class_name ToastStack
extends CanvasLayer
## Toast stack + banner host (P3). Shows transient messages with anti-spam
## deduplication (same message within 1.5s = suppressed, count badge grows).
## Banners are persistent until dismissed. Both are scene-free and
## spectator-safe (read event type only). Banner support is in ToastStack
## (spec listed ui/banner.gd as a separate file, but one CanvasLayer hosting
## both stacks avoids layering headaches).

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

signal dismissed(id: int)

var _toast_container: VBoxContainer
var _banner_container: VBoxContainer
var _next_id := 1
var _sfx = null   # optional Sfx for a soft pop on new toasts

# P6 CR-8: rent/pay anti-spam merge. Accumulates rent/pay events for the same
# player within a short window and flushes them as ONE merged toast (spec §6.2:
# "Neuro платит $48: рента Host ×2, налог $20"). Keyed by player id.
var _rent_pay_buffer: Dictionary = {}   # pid -> {name, amounts:Array, total:int, timer:float}
const _RENT_PAY_WINDOW := 1.2

## Provide the procedural Sfx node so new toasts play a soft pop sound.
func set_sfx(sfx) -> void:
	_sfx = sfx

func _init() -> void:
	# Toast stack: top-right, newest on top, auto-dismiss
	_toast_container = VBoxContainer.new()
	_toast_container.name = "ToastStack"
	_toast_container.add_theme_constant_override("separation", 6)
	_toast_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_container.offset_left = -420
	_toast_container.offset_top = 50
	_toast_container.offset_right = -20
	_toast_container.offset_bottom = -20
	_toast_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toast_container)

	# Banner host: centered near the top, persistent until dismissed
	_banner_container = VBoxContainer.new()
	_banner_container.name = "BannerStack"
	_banner_container.add_theme_constant_override("separation", 8)
	_banner_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_container.anchor_left = 0.5
	_banner_container.anchor_right = 0.5
	_banner_container.offset_left = -260
	_banner_container.offset_right = 260
	_banner_container.offset_top = 50
	_banner_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_banner_container)

## Show a transient toast (auto-dismiss after `duration` s). Anti-spam: the
## same text within _DEDUP_WINDOW seconds merges into the existing toast and
## increments its ×N count badge instead of adding a new one.
## `kind` = "info" | "success" | "warning" | "error"
func show_toast(text: String, kind: String = "info", duration: float = 4.0) -> int:
	var now := Time.get_ticks_msec() / 1000.0
	if text == _last_toast_text() and (now - _last_toast_time()) < ToastItem.DEDUP_WINDOW:
		for child in _toast_container.get_children():
			if child is ToastItem and child.text == text:
				child.increment_count()
				child.reset_timer(duration)
				return child.id
	var item := ToastItem.new()
	item.id = _next_id
	_next_id += 1
	item.setup(text, kind, duration)
	item.dismissed.connect(_on_toast_dismissed)
	_toast_container.add_child(item)
	_toast_container.move_child(item, 0)  # newest on top
	_remember_toast(text, now)
	if _sfx != null and _sfx.has_method("play_toast_pop"):
		_sfx.play_toast_pop()
	return item.id

## Show a persistent banner (stays until user clicks ✕ or dismiss_all()).
## `kind` = "info" | "success" | "warning" | "error" | "neutral"
## `actions` = [{"text": "РЕВАНШ", "action": "rematch"}, ...]
func show_banner(text: String, kind: String = "neutral", actions: Array = []) -> int:
	var item := BannerItem.new()
	item.id = _next_id
	_next_id += 1
	item.setup(text, kind, actions)
	item.dismissed.connect(_on_banner_dismissed)
	_banner_container.add_child(item)
	return item.id

func dismiss(id: int) -> void:
	for child in _toast_container.get_children():
		if child is ToastItem and child.id == id:
			child.dismiss()
			return
	for child in _banner_container.get_children():
		if child is BannerItem and child.id == id:
			child.dismiss()
			return

func dismiss_all() -> void:
	for child in _toast_container.get_children():
		if child is ToastItem:
			child.dismiss()
	for child in _banner_container.get_children():
		if child is BannerItem:
			child.dismiss()

func toast_count() -> int:
	return _toast_container.get_child_count()

func banner_count() -> int:
	return _banner_container.get_child_count()

func _process(delta: float) -> void:
	# P6 CR-8: flush the rent/pay merge buffer when its window elapses.
	if _rent_pay_buffer.is_empty():
		return
	var expired: Array = []
	for pid in _rent_pay_buffer:
		var e: Dictionary = _rent_pay_buffer[pid]
		e["timer"] = float(e.get("timer", 0.0)) - delta
		if float(e.get("timer", 0.0)) <= 0.0:
			expired.append(pid)
	for pid in expired:
		_flush_rent_pay(pid)

## P6 CR-8: accumulate a rent/pay event for a player; flush as one merged toast
## when the window elapses (or immediately if it's the only one).
func _buffer_rent_pay(pid: int, name: String, amount: int) -> void:
	if not _rent_pay_buffer.has(pid):
		_rent_pay_buffer[pid] = {"name": name, "amounts": [], "total": 0, "timer": _RENT_PAY_WINDOW}
	var e: Dictionary = _rent_pay_buffer[pid]
	e["amounts"].append(amount)
	e["total"] = int(e.get("total", 0)) + amount
	e["timer"] = _RENT_PAY_WINDOW

func _flush_rent_pay(pid: int) -> void:
	if not _rent_pay_buffer.has(pid):
		return
	var e: Dictionary = _rent_pay_buffer[pid]
	_rent_pay_buffer.erase(pid)
	var amounts: Array = e.get("amounts", [])
	var total: int = int(e.get("total", 0))
	var name: String = str(e.get("name", "?"))
	if amounts.size() > 1:
		show_toast(I18n.t("toast.rent_merged", [name, total, amounts.size()]), "warning")
	else:
		show_toast(I18n.t("toast.pay", [name, total]), "warning")

func _on_toast_dismissed(id: int) -> void:
	dismissed.emit(id)

func _on_banner_dismissed(id: int) -> void:
	dismissed.emit(id)

var _last_text := ""
var _last_time := 0.0

func _remember_toast(text: String, now: float) -> void:
	_last_text = text
	_last_time = now

func _last_toast_text() -> String:
	return _last_text

func _last_toast_time() -> float:
	return _last_time

## Convenience: show a toast/banner from an engine event entry (spectator-safe;
## reads only type + data, never engine internals). Uses the same wording as
## the journal (EventMessages) so the two stay consistent. P5: localized.
func show_event_toast(entry: Dictionary) -> void:
	var t: String = entry.get("type", "")
	var d: Dictionary = entry.get("data", {})
	match t:
		"purchase":
			show_toast(I18n.t("toast.purchase", [_who(d, "player"), _tile_name(d), int(d.get("cost", 0))]), "success")
		"pass":
			show_toast(I18n.t("toast.pass", [_who(d, "player"), _tile_name(d)]), "info")
		"pay":
			# P6 CR-8: buffer rent/pay so multiple payments in one turn merge.
			_buffer_rent_pay(_pid_of(d, "from"), _who(d, "from"), int(d.get("amount", 0)))
		"rent":
			# rent has no amount in the event data; buffer with 0 so it merges
			# with a following pay for the same player.
			_buffer_rent_pay(_pid_of(d, "from"), _who(d, "from"), 0)
		"build":
			show_toast(I18n.t("toast.build", [_who(d, "player"), _tile_name(d)]), "success")
		"sell":
			show_toast(I18n.t("toast.sell", [_who(d, "player"), _tile_name(d)]), "info")
		"mortgage":
			show_toast(I18n.t("toast.mortgage", [_who(d, "player"), _tile_name(d)]), "warning")
		"bankrupt":
			show_banner(I18n.t("toast.bankrupt", [_who(d, "player")]), "error")
		"jail":
			show_toast(I18n.t("toast.jail", [_who(d, "player")]), "warning")
		"go_bonus":
			show_toast(I18n.t("toast.go_bonus", [_who(d, "player")]), "success")
		"tax":
			show_toast(I18n.t("toast.tax", [_who(d, "from")]), "warning")
		"winner":
			show_banner(I18n.t("toast.winner", [_who(d, "player")]), "success", [{"text": I18n.t("toast.rematch"), "action": "rematch"}])
		"trade":
			show_toast(I18n.t("toast.trade"), "info")
		"auction_win":
			show_toast(I18n.t("toast.auction_win", [_who(d, "player"), _tile_name(d)]), "success")
		"auction_start":
			show_banner(I18n.t("toast.auction_start", [_tile_name(d)]), "neutral")
		"admin_override":
			show_toast(I18n.t("toast.admin_override", [_who(d, "op")]), "neutral")
		_:
			pass  # unknown event types stay silent (journal still shows them)

## Resolve a player id from a data field (int pid or string name). Used to
## key the rent/pay merge buffer.
func _pid_of(d: Dictionary, key: String) -> int:
	var v = d.get(key, -1)
	if v is int:
		return v
	return -1

func _who(d: Dictionary, key: String) -> String:
	var v = d.get(key, "?")
	if v is String: return str(v)
	return "p%s" % str(v)

func _tile_name(d: Dictionary) -> String:
	var tile := int(d.get("tile", -1))
	return I18n.t("event.tile_name", [tile]) if tile >= 0 else "?"


class ToastItem extends PanelContainer:
	## Dedup window for anti-spam merging (same text within this window merges).
	const DEDUP_WINDOW := 1.5

	var id: int
	var text: String
	var _label: Label
	var _count_label: Label
	var _count := 1
	var _timer := 0.0
	var _duration := 4.0
	signal dismissed(id: int)

	static func _kind_color(kind: String) -> Color:
		match kind:
			"success": return UiTheme.COL.success
			"warning": return Color("#c9a84c")
			"error": return UiTheme.COL.danger
			"info": return UiTheme.COL.accent
			"neutral": return UiTheme.COL.panel_dark
		return UiTheme.COL.accent

	func setup(t: String, kind: String, duration: float) -> void:
		text = t
		_duration = duration
		add_theme_stylebox_override("panel", UiTheme.box(
			_kind_color(kind), UiTheme.COL.border_accent, 1, 6))
		var m = MarginContainer.new()
		for e in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			m.add_theme_constant_override(e, 10)
		add_child(m)
		var h = HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		m.add_child(h)
		_label = UiTheme.label(text, 13, Color("#0c1218"))
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(_label)
		_count_label = Label.new()
		_count_label.text = ""
		_count_label.add_theme_font_size_override("font_size", 11)
		_count_label.add_theme_color_override("font_color", Color("#0c1218"))
		_count_label.visible = false
		h.add_child(_count_label)
		custom_minimum_size = Vector2(380, 0)

	func _process(delta: float) -> void:
		_timer += delta
		if _timer >= _duration:
			dismiss()

	func increment_count() -> void:
		_count += 1
		if _count_label != null:
			_count_label.text = "×%d" % _count
			_count_label.visible = true

	func reset_timer(duration: float) -> void:
		_timer = 0.0
		_duration = duration

	func dismiss() -> void:
		dismissed.emit(id)
		queue_free()


class BannerItem extends PanelContainer:
	var id: int
	var _actions: Array = []
	signal dismissed(id: int)

	static func _kind_color(kind: String) -> Color:
		match kind:
			"success": return UiTheme.COL.success
			"warning": return Color("#c9a84c")
			"error": return UiTheme.COL.danger
			"info": return UiTheme.COL.accent
			"neutral": return UiTheme.COL.panel
		return UiTheme.COL.accent

	func setup(text: String, kind: String, actions: Array) -> void:
		_actions = actions
		add_theme_stylebox_override("panel", UiTheme.box(
			_kind_color(kind), UiTheme.COL.border_accent, 2, 8))
		var m = MarginContainer.new()
		for e in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			m.add_theme_constant_override(e, 16)
		add_child(m)
		var v = VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		m.add_child(v)

		var head = HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		var lbl = UiTheme.label(text, 15, Color("#f2f6fa"))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(lbl)
		var close = UiTheme.button("✕", I18n.t("toast.dismiss_tip"))
		I18n.tip_on(close, "toast.dismiss_tip")   # re-localize on locale change
		close.custom_minimum_size = Vector2(28, 28)
		close.connect("pressed", Callable(self, "dismiss"))
		head.add_child(close)
		v.add_child(head)

		if actions.size() > 0:
			var act_row = HBoxContainer.new()
			act_row.add_theme_constant_override("separation", 8)
			for a in actions:
				var btn = UiTheme.button_accent(str(a.get("text", "?")), I18n.t("modal.banner_action_tip"))
				btn.connect("pressed", Callable(self, "_on_action").bind(str(a.get("action", ""))))
				act_row.add_child(btn)
			act_row.add_child(Control.new())  # spacer
			v.add_child(act_row)

	func _on_action(action: String) -> void:
		dismissed.emit(id)
		# Action handling is external (see dismissed signal consumers)