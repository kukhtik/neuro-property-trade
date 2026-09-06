class_name GameView
extends Control
## Full playable game screen: top bar + players panel (left) + board (center)
## + tile inspector + action panel (bottom) + modal host + journal (right).
## Wires the human LOCAL seat's clicks to seat_manager.push_intent. AI/CHAT
## seats self-drive in the manager. HUD reads the spectator projection;
## the human seat's legal actions come from engine.legal_actions. Shape-only
## UI (UiTheme) so art can replace shapes later without logic changes.

const UiTheme := preload("res://ui/theme.gd")
const BoardScene := preload("res://visual/board_scene.gd")
const TopBar := preload("res://ui/top_bar.gd")
const PlayersPanel := preload("res://ui/players_panel.gd")
const ActionPanel := preload("res://ui/action_panel.gd")
const TileInspector := preload("res://ui/tile_inspector.gd")
const ModalHost := preload("res://ui/modal_host.gd")
const ProjectionScript := preload("res://sdk/projection.gd")
const EventMessages := preload("res://visual/event_messages.gd")
const SeatManager := preload("res://seats/seat_manager.gd")

const _PANEL_W := 235
const _TOP_H := 34
const _JOURNAL_W := 300
const _ACTION_H := 84

var engine
var manager
var seats: Array = []
var settings

var _human_pid := -1
var _board_scene
var _top
var _players
var _actions
var _inspector
var _modals
var _journal

func setup(eng, mgr, seat_list: Array, s) -> void:
	engine = eng
	manager = mgr
	seats = seat_list
	settings = s
	for seat in seats:
		if str(seat.input_driver) in ["LOCAL", "ADMIN"]:
			_human_pid = int(seat.pid)
			break
	_build_layout()
	# board fills the center region (between left panel, top bar, journal, action bar)
	_board_scene.setup(engine, settings)
	var vp_rect := get_viewport().get_visible_rect()
	var board_rect := Rect2()
	board_rect.position = Vector2(_PANEL_W + 8, _TOP_H + 8)
	board_rect.size = Vector2(vp_rect.size.x - _PANEL_W - _JOURNAL_W - 16, vp_rect.size.y - _TOP_H - _ACTION_H - 16)
	_board_scene.set_frame(board_rect)
	var bs = _board_scene
	if bs.has_node("EventOverlay"):
		bs.get_node("EventOverlay").visible = false
	if _board_scene._board != null:
		_board_scene._board.tile_clicked.connect(_on_tile_clicked)
	# HUD refresh on every seat-manager tick
	manager.state_changed.connect(_on_state_changed)
	_top.settings_requested.connect(_on_settings_requested)
	_modals.sound_toggled.connect(_on_sound_toggled)
	_refresh_journal()
	_sync_all()

func _build_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_rect()

	# top bar (anchored top-wide)
	_top = TopBar.new()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.anchor_right = 1.0
	_top.offset_bottom = 34
	add_child(_top)

	# board (center), below the top bar
	_board_scene = BoardScene.new()
	_board_scene.name = "BoardScene"
	_board_scene.position = Vector2(0, 34)
	add_child(_board_scene)

	# left players panel
	_players = PlayersPanel.new()
	_players.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_players.offset_top = 34
	add_child(_players)

	# right journal panel
	var jpanel := UiTheme.panel()
	jpanel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	jpanel.anchor_left = 1.0
	jpanel.offset_left = -300
	jpanel.offset_top = 34
	jpanel.offset_bottom = -70
	jpanel.offset_right = 0
	jpanel.custom_minimum_size.x = 300
	add_child(jpanel)
	var jm := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		jm.add_theme_constant_override(edge, 8)
	jpanel.add_child(jm)
	var jv := UiTheme.vbox(4)
	jm.add_child(jv)
	jv.add_child(UiTheme.label("◆ ХОД СОБЫТИЙ", 12, UiTheme.COL.accent))
	_journal = UiTheme.label("", 12)
	_journal.custom_minimum_size.y = 0
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jv.add_child(_journal)

	# modal host (above everything)
	_modals = ModalHost.new()
	_modals.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modals.visible = false
	add_child(_modals)
	_connect_modals()

	# bottom action panel
	_actions = ActionPanel.new()
	_actions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_actions.anchor_top = 1.0
	_actions.offset_top = -84
	_actions.offset_bottom = 0
	_actions.anchor_right = 1.0
	_actions.offset_right = 0
	add_child(_actions)
	_actions.action_requested.connect(_on_action_requested)

	# tile inspector above the action panel (bottom-left), clear of the buttons
	_inspector = TileInspector.new()
	_inspector.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_inspector.offset_left = 8
	_inspector.offset_top = -(_ACTION_H + 8 + 90)   # above the action bar
	_inspector.offset_right = 360
	_inspector.offset_bottom = -(_ACTION_H + 8)
	add_child(_inspector)

func _apply_rect() -> void:
	var vp = get_viewport()
	var r := Rect2()
	if vp != null:
		r = vp.get_visible_rect()
	if r.size.x <= 0 or r.size.y <= 0:
		r = Rect2(0, 0, 1152, 648)
	position = r.position
	size = r.size

func _on_state_changed(_proj: Dictionary) -> void:
	_sync_all()
	_refresh_journal()

func _sync_all() -> void:
	var sp := ProjectionScript.new().for_spectator(engine)
	_sync_from_spectator(sp)

func _sync_from_spectator(proj: Dictionary) -> void:
	_top.sync(proj, seats)
	_players.sync(proj, seats)
	_inspector.sync(proj, seats)
	var holder: int = SeatManager.find_decision_holder(engine, engine.player_count())
	var is_human: bool = (holder == _human_pid)
	var legal: Array = []
	if holder >= 0:
		legal = engine.legal_actions(holder)
	_actions.sync(holder, legal, is_human, proj, seats)

func _refresh_journal() -> void:
	if engine == null or _journal == null:
		return
	var entries: Array = engine.log.entries()
	var start: int = maxi(0, entries.size() - 10)
	var lines: Array[String] = []
	for i in range(start, entries.size()):
		lines.append(EventMessages.describe(entries[i]))
	_journal.text = "\n".join(lines)

func _on_tile_clicked(idx: int) -> void:
	_inspector.select(idx)
	var sp := ProjectionScript.new().for_spectator(engine)
	_inspector.sync(sp, seats)

func _connect_modals() -> void:
	_modals.build_requested.connect(_on_build)
	_modals.trade_proposed.connect(_on_trade_proposed)
	_modals.trade_responded.connect(_on_trade_responded)
	_modals.auction_bid.connect(_on_auction_bid)
	_modals.auction_pass.connect(_on_auction_pass)

func _on_action_requested(act: String, _params: Dictionary) -> void:
	match act:
		"roll", "buy", "pass", "pay", "use_card":
			_submit(_human_pid, act, {})
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			if _inspector.selected >= 0:
				var sp := ProjectionScript.new().for_spectator(engine)
				_modals.open_build(_inspector.selected, sp, "")
			else:
				_modals.show_message("Выберите тайл", "Кликните по тайлу на доске, который хотите изменить.")
		"propose_trade":
			var sp2 := ProjectionScript.new().for_spectator(engine)
			_modals.open_trade(sp2, seats, _human_pid)
		"respond_trade":
			var sp3 := ProjectionScript.new().for_spectator(engine)
			_modals.open_trade_response(sp3, seats)
		"bid":
			var sp4 := ProjectionScript.new().for_spectator(engine)
			_modals.open_auction(sp4, seats)

func _on_build(tile: int, op: String) -> void:
	_submit(_human_pid, op, {"tile": tile})
	_modals.close()

func _on_trade_proposed(to: int, give: Array, gcash: int, want: Array, wcash: int) -> void:
	_submit(_human_pid, "propose_trade", {
		"to": to, "give_tiles": give, "give_cash": gcash,
		"want_tiles": want, "want_cash": wcash,
	})
	_modals.close()

func _on_trade_responded(accept: bool) -> void:
	_submit(_human_pid, "respond_trade", {"accept": accept})
	_modals.close()

func _on_auction_bid(amount: int) -> void:
	_submit(_human_pid, "bid", {"amount": amount})
	_modals.close()

func _on_auction_pass() -> void:
	_submit(_human_pid, "pass", {})
	_modals.close()

func _on_settings_requested() -> void:
	var cats: Array = [
		{"key": "sfx", "label": "Звуковые эффекты", "on": _sfx_enabled},
	]
	_modals.open_settings(cats, _rules_text())

func _on_sound_toggled(key: String, on: bool) -> void:
	if key == "sfx":
		_sfx_enabled = on
		if _board_scene != null and _board_scene._sfx != null:
			_board_scene._sfx.set_enabled(on)

var _sfx_enabled := true

func _rules_text() -> String:
	var s = settings
	var lines: Array[String] = []
	lines.append("ПРАВИЛА (по текущим настройкам)")
	lines.append("")
	lines.append("Стартовый капитал: $%d" % s.starting_cash)
	lines.append("Бонус за GO: $%d" % s.go_bonus)
	lines.append("Тюрьма: %s (штраф $%d)" % [s.jail_rule, s.jail_fine])
	lines.append("Бесплатная стоянка: %s" % ("вкл" if s.free_parking else "выкл"))
	lines.append("Дубли: %s" % ("вкл" if s.doubles else "выкл"))
	lines.append("Тройные дубли → тюрьма: %s" % ("вкл" if s.triple_doubles_to_jail else "выкл"))
	lines.append("Аукционы при отказе: %s" % ("вкл" if s.auctions_on_refusal else "выкл"))
	lines.append("Строительство: %s" % ("вкл" if s.housing else "выкл"))
	lines.append("Равномерная застройка: %s" % ("вкл" if s.even_build else "выкл"))
	lines.append("Монополия ×2 аренда: %s" % ("вкл" if s.monopoly_rent_x2 else "выкл"))
	lines.append("Залог: %s (%d%% / %d%%)" % [("вкл" if s.mortgage else "выкл"), s.mortgage_loan_pct, s.mortgage_repay_pct])
	lines.append("Торги: %s" % ("вкл" if s.trades else "выкл"))
	lines.append("Таймер хода: %dс" % s.turn_timer)
	lines.append("Таймер аукциона: %dс" % s.auction_timer)
	return "\n".join(lines)

func _submit(pid: int, action: String, params: Dictionary) -> void:
	if manager == null:
		return
	var res: Dictionary = manager.push_intent(pid, action, params)
	if not res.get("ok", false):
		_modals.show_message("Действие отклонено", "Причина: " + str(res.get("reason", "?")))
