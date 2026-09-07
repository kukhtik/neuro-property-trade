class_name ToastStack
extends CanvasLayer
## Toast stack + banner host (P3). Shows transient messages with anti-spam
## deduplication (same message within 1.5s = suppressed, count badge grows).
## Banners are persistent until dismissed. Both are scene-free and
## spectator-safe (read event type only). Banner support is in ToastStack
## (spec listed ui/banner.gd as a separate file, but one CanvasLayer hosting
## both stacks avoids layering headaches).

const UiTheme := preload("res://ui/theme.gd")

signal dismissed(id: int)

var _toast_container: VBoxContainer
var _banner_container: VBoxContainer
var _next_id := 1

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
## the journal (EventMessages) so the two stay consistent.
func show_event_toast(entry: Dictionary) -> void:
	var t: String = entry.get("type", "")
	var d: Dictionary = entry.get("data", {})
	match t:
		"purchase":
			show_toast("%s купил «%s» за $%d" % [_who(d, "player"), _tile_name(d), int(d.get("cost", 0))], "success")
		"pass":
			show_toast("%s не купил «%s»" % [_who(d, "player"), _tile_name(d)], "info")
		"pay":
			show_toast("%s заплатил $%d" % [_who(d, "from"), int(d.get("amount", 0))], "warning")
		"rent":
			show_toast("%s заплатил аренду" % _who(d, "from"), "warning")
		"build":
			show_toast("%s построил на «%s»" % [_who(d, "player"), _tile_name(d)], "success")
		"sell":
			show_toast("%s продал с «%s»" % [_who(d, "player"), _tile_name(d)], "info")
		"mortgage":
			show_toast("%s заложил «%s»" % [_who(d, "player"), _tile_name(d)], "warning")
		"bankrupt":
			show_banner("%s обанкротился!" % _who(d, "player"), "error")
		"jail":
			show_toast("%s попал в тюрьму" % _who(d, "player"), "warning")
		"go_bonus":
			show_toast("%s получает бонус GO" % _who(d, "player"), "success")
		"tax":
			show_toast("%s заплатил налог" % _who(d, "from"), "warning")
		"winner":
			show_banner("%s ПОБЕДИЛ!" % _who(d, "player"), "success", [{"text": "РЕВАНШ", "action": "rematch"}])
		"trade":
			show_toast("Сделка завершена", "info")
		"auction_win":
			show_toast("%s выиграл аукцион «%s»" % [_who(d, "player"), _tile_name(d)], "success")
		"auction_start":
			show_banner("Аукцион: «%s»" % _tile_name(d), "neutral")
		"admin_override":
			show_toast("Админ: %s" % _who(d, "op"), "neutral")
		_:
			pass  # unknown event types stay silent (journal still shows them)

func _who(d: Dictionary, key: String) -> String:
	var v = d.get(key, "?")
	if v is String: return str(v)
	return "p%s" % str(v)

func _tile_name(d: Dictionary) -> String:
	var tile := int(d.get("tile", -1))
	return "тайл %d" % tile if tile >= 0 else "?"


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
		var close = UiTheme.button("✕", "Закрыть")
		close.custom_minimum_size = Vector2(28, 28)
		close.connect("pressed", Callable(self, "dismiss"))
		head.add_child(close)
		v.add_child(head)

		if actions.size() > 0:
			var act_row = HBoxContainer.new()
			act_row.add_theme_constant_override("separation", 8)
			for a in actions:
				var btn = UiTheme.button_accent(str(a.get("text", "?")), "Действие баннера")
				btn.connect("pressed", Callable(self, "_on_action").bind(str(a.get("action", ""))))
				act_row.add_child(btn)
			act_row.add_child(Control.new())  # spacer
			v.add_child(act_row)

	func _on_action(action: String) -> void:
		dismissed.emit(id)
		# Action handling is external (see dismissed signal consumers)