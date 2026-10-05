class_name SettingsOverlay
extends Control
## Pre-game / in-game settings overlay (replaces the old lobby). One screen:
## this overlay sits on top of the live board. Pre-game it opens on first run
## with focus on START; in-game ⚙ reopens the same overlay. Tabs per spec 5.1:
## Игроки / Правила / Темп / Интерфейс / Данные. Emits `started(settings, seats)`
## on pre-game START and `apply_requested(settings, seats)` on in-game restart.
## Pure UI over GameSettings + SeatConfig — no engine here.

signal started(settings, seats)
signal apply_requested(settings, seats)
signal closed

const UiTheme := preload("res://ui/theme.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const PI := preload("res://core/player_identity.gd")
const I18n := preload("res://i18n/i18n.gd")

const DRIVERS := ["LOCAL", "AI", "CHAT", "sdk:neuro", "sdk:evil"]
const NAMES := ["Host", "AI-2", "AI-3", "AI-4", "AI-5", "AI-6", "AI-7", "AI-8"]
## Fallback board size when no settings object exists yet. The engine's default
## lives in game_settings.gd; this is only the pre-settings placeholder, never a
## layout assumption (geometry is parametric — see BoardLayout).
const DEF_TILE_COUNT := 40
const COLORS := PI.COLORS
const TOKENS := PI.TOKENS

var _rows: Array = []            # per-player: {driver, name, color, token, remove_btn, row}
var _pre_game := true            # true => main button is СТАРТ; false => ПРИМЕНИТЬ (restart)

# control refs
var _root: PanelContainer
var _tabs: TabContainer
var _players_list: VBoxContainer
var _host_role: OptionButton
var _starting_order: OptionButton
var _start_btn: Button
var _apply_btn: Button
var _rules_btn: Button
var _status_lbl: Label

# rules tab
var _starting_cash: SpinBox
var _go_bonus: SpinBox
var _jail_rule: OptionButton
var _jail_fine: SpinBox
var _free_parking: OptionButton
var _doubles: CheckButton
var _triple_doubles: CheckButton
var _auctions: OptionButton
var _housing: CheckButton
var _even_build: CheckButton
var _monopoly_x2: CheckButton
var _mortgage: CheckButton
var _loan_pct: SpinBox
var _repay_pct: SpinBox
var _trades: CheckButton
var _ai_aggression: SpinBox

# tempo tab
var _turn_timer: OptionButton
var _auction_timer: OptionButton
var _timeout_action: OptionButton

# interface tab
var _animations: CheckButton
var _event_overlay: CheckButton
var _spectacle: CheckButton
var _language: OptionButton
var _sound: CheckButton

# data tab
var _rng_seed: SpinBox
var _tile_count: SpinBox

# preset buttons (CR-4: retranslated on locale change)
var _p_classic: Button
var _p_fast: Button
var _p_hard: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# P5: language switch → retranslate in place (no scene rebuild). OptionButton
	# items that carry data (driver/token/dice/deck) keep their stable values; we
	# only re-apply text labels collected via i18n_key/i18n_tip metadata.
	I18n.inst().locale_changed.connect(_on_locale_changed)

## Pre-game (START button) vs in-game (ПРИМЕНИТЬ / restart) mode.
func set_mode(pre_game: bool) -> void:
	_pre_game = pre_game
	_refresh_buttons()

## P5: retranslate in place when the locale changes (no scene rebuild). Any
## Control carrying i18n_key/i18n_tip metadata is re-labelled; localized
## OptionButton items are rebuilt with current-locale text, preserving the
## selected index so the user's choice doesn't jump.
func _retranslate() -> void:
	I18n.relabel(self)
	# CR-3: tab titles must be re-applied on locale change (set_tab_title is
	# only called in _build_*_tab, so re-apply here).
	if _tabs != null:
		var tab_keys := ["settings.tab_players", "settings.tab_rules",
			"settings.tab_tempo", "settings.tab_interface", "settings.tab_data"]
		for i in mini(_tabs.get_tab_count(), tab_keys.size()):
			_tabs.set_tab_title(i, I18n.t(tab_keys[i]))
	# CR-2: driver items are localized — rebuild them in the current locale,
	# preserving each row's selected index.
	for r in _rows:
		_rebuild_driver_items(r["driver"])
	# host role (option texts localized; values derived from selected index)
	_host_role.clear()
	_host_role.add_item(I18n.t("settings.host_playing"))
	_host_role.add_item(I18n.t("settings.host_obs"))
	# starting order
	_starting_order.clear()
	_starting_order.add_item(I18n.t("settings.order_random"))
	_starting_order.add_item(I18n.t("settings.order_manual"))
	# jail rule — values fixed by index (both/fine/card), labels localized
	_jail_rule.clear()
	_jail_rule.add_item(I18n.t("settings.jail_both"))
	_jail_rule.add_item(I18n.t("settings.jail_fine_only"))
	_jail_rule.add_item(I18n.t("settings.jail_card_only"))
	# free parking on/off
	_free_parking.clear()
	_free_parking.add_item(I18n.t("settings.fp_on"))
	_free_parking.add_item(I18n.t("settings.fp_off"))
	# auctions on/off  (index 0 = on, index 1 = off, matching _collect_settings)
	_auctions.clear()
	_auctions.add_item(I18n.t("settings.auctions_on"))
	_auctions.add_item(I18n.t("settings.auctions_off"))
	# turn/auction timer options — re-add with localized suffix + no-limit label
	_rebuild_seconds(_turn_timer, [0, 5, 10, 15, 20, 30, 45, 60], 30)
	_rebuild_seconds(_auction_timer, [0, 5, 8, 10, 12, 15, 20], 15)
	_turn_timer.tooltip_text = I18n.t("settings.turn_timer_tip")
	_auction_timer.tooltip_text = I18n.t("settings.auction_timer_tip")
	# timeout action
	_timeout_action.clear()
	_timeout_action.add_item(I18n.t("settings.timeout_auto_pass"))
	_timeout_action.add_item(I18n.t("settings.timeout_away"))
	_timeout_action.tooltip_text = I18n.t("settings.timeout_tip")
	# static tooltips that aren't metadata-tagged
	_doubles.tooltip_text = I18n.t("settings.doubles_tip")
	_triple_doubles.tooltip_text = I18n.t("settings.triple_doubles_tip")
	_housing.tooltip_text = I18n.t("settings.housing_tip")
	_even_build.tooltip_text = I18n.t("settings.even_build_tip")
	_monopoly_x2.tooltip_text = I18n.t("settings.monopoly_x2_tip")
	_mortgage.tooltip_text = I18n.t("settings.mortgage_tip")
	_trades.tooltip_text = I18n.t("settings.trades_tip")
	_animations.tooltip_text = I18n.t("settings.animations_tip")
	_event_overlay.tooltip_text = I18n.t("settings.event_overlay_tip")
	_spectacle.tooltip_text = I18n.t("settings.spectacle_tip")
	_sound.tooltip_text = I18n.t("settings.sound_tip")
	_language.tooltip_text = I18n.t("settings.language_tip")
	_rng_seed.tooltip_text = I18n.t("settings.rng_seed_tip")
	_start_btn.tooltip_text = I18n.t("settings.start_tip")
	_apply_btn.tooltip_text = I18n.t("settings.apply_tip")
	_rules_btn.tooltip_text = I18n.t("settings.rules_tip")
	_refresh_buttons()

func _rebuild_seconds(o: OptionButton, vals: Array, def: int) -> void:
	var keep: int = _selected_seconds(o)
	o.clear()
	o.add_item(I18n.t("settings.no_limit"), 0)
	for value in vals:
		if value == 0:
			continue
		o.add_item(str(value) + sec_suffix(), value)
	# restore the previously selected seconds value
	for i in o.item_count:
		if o.get_item_id(i) == keep:
			o.selected = i
			return
	o.selected = 0

func _on_locale_changed(_locale: String) -> void:
	_retranslate()

func _build() -> void:
	# dim background under the overlay
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_root = UiTheme.panel()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.custom_minimum_size = Vector2(860, 600)
	_root.reset_size()
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.position = (get_viewport().get_visible_rect().size - _root.size) * 0.5
	add_child(_root)

	var margin := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 16)
	_root.add_child(margin)
	var v := UiTheme.vbox(10)
	margin.add_child(v)

	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var title := UiTheme.label(I18n.t("settings.title"), 20, UiTheme.COL.gold)
	I18n.key_on(title, "settings.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset_btn := UiTheme.button(I18n.t("settings.reset_btn"), I18n.t("settings.reset_tip"))
	I18n.key_on(reset_btn, "settings.reset_btn")
	I18n.tip_on(reset_btn, "settings.reset_tip")
	reset_btn.connect("pressed", Callable(self, "_reset_all"))
	head.add_child(reset_btn)
	var close_btn := UiTheme.button(I18n.t("settings.close_btn"), I18n.t("settings.close_tip"))
	I18n.key_on(close_btn, "settings.close_btn")
	I18n.tip_on(close_btn, "settings.close_tip")
	close_btn.connect("pressed", Callable(self, "_on_close"))
	head.add_child(close_btn)
	v.add_child(head)

	# presets row
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	var presets_lbl := UiTheme.label(I18n.t("settings.presets_lbl"), 13, UiTheme.COL.text_dim)
	I18n.key_on(presets_lbl, "settings.presets_lbl")
	presets.add_child(presets_lbl)
	_p_classic = UiTheme.button(I18n.t("settings.preset_classic"), I18n.t("settings.preset_classic_tip"))
	I18n.key_on(_p_classic, "settings.preset_classic"); I18n.tip_on(_p_classic, "settings.preset_classic_tip")
	_p_classic.connect("pressed", Callable(self, "_preset_classic"))
	presets.add_child(_p_classic)
	_p_fast = UiTheme.button(I18n.t("settings.preset_fast"), I18n.t("settings.preset_fast_tip"))
	I18n.key_on(_p_fast, "settings.preset_fast"); I18n.tip_on(_p_fast, "settings.preset_fast_tip")
	_p_fast.connect("pressed", Callable(self, "_preset_fast"))
	presets.add_child(_p_fast)
	_p_hard = UiTheme.button(I18n.t("settings.preset_hard"), I18n.t("settings.preset_hard_tip"))
	I18n.key_on(_p_hard, "settings.preset_hard"); I18n.tip_on(_p_hard, "settings.preset_hard_tip")
	_p_hard.connect("pressed", Callable(self, "_preset_hard"))
	presets.add_child(_p_hard)
	v.add_child(presets)

	# tabs
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_build_players_tab()
	_build_rules_tab()
	_build_tempo_tab()
	_build_interface_tab()
	_build_data_tab()

	# status + action row
	_status_lbl = UiTheme.label("", 12, UiTheme.COL.text_dim)
	v.add_child(_status_lbl)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_start_btn = UiTheme.button_accent(I18n.t("settings.start_btn"), I18n.t("settings.start_tip"))
	_start_btn.custom_minimum_size.y = 40
	_start_btn.connect("pressed", Callable(self, "_start_pressed"))
	actions.add_child(_start_btn)
	_apply_btn = UiTheme.button_accent(I18n.t("settings.apply_btn"), I18n.t("settings.apply_tip"))
	_apply_btn.custom_minimum_size.y = 40
	_apply_btn.connect("pressed", Callable(self, "_apply_pressed"))
	actions.add_child(_apply_btn)
	_rules_btn = UiTheme.button(I18n.t("settings.rules_btn"), I18n.t("settings.rules_tip"))
	_rules_btn.connect("pressed", Callable(self, "_show_rules"))
	actions.add_child(_rules_btn)
	v.add_child(actions)

	# default rows
	for i in 4:
		_add_row(i)
	_refresh_buttons()

func _build_players_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("settings.tab_players"))

	var players_box := UiTheme.panel()
	tab.add_child(players_box)
	_players_list = UiTheme.vbox(6)
	var pm := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pm.add_theme_constant_override(edge, 10)
	players_box.add_child(pm)
	pm.add_child(_players_list)

	var add_row := UiTheme.button(I18n.t("settings.add_player"), I18n.t("settings.add_player_tip"))
	add_row.connect("pressed", Callable(self, "_add_row"))
	add_row.custom_minimum_size.y = 28
	tab.add_child(add_row)

	# host role + starting order
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 20)
	opts.add_child(UiTheme.label(I18n.t("ui.host_role"), 13))
	_host_role = OptionButton.new()
	_host_role.add_item(I18n.t("settings.host_playing")); _host_role.add_item(I18n.t("settings.host_obs"))
	_host_role.selected = 0
	_host_role.tooltip_text = I18n.t("settings.host_role_tip")
	opts.add_child(_host_role)
	opts.add_child(UiTheme.label(I18n.t("ui.starting_order"), 13))
	_starting_order = OptionButton.new()
	_starting_order.add_item(I18n.t("settings.order_random")); _starting_order.add_item(I18n.t("settings.order_manual"))
	_starting_order.selected = 0
	_starting_order.tooltip_text = I18n.t("settings.starting_order_tip")
	opts.add_child(_starting_order)
	tab.add_child(opts)

func _build_rules_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("settings.tab_rules"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_starting_cash = _spin(100, 100000, 1500, I18n.t("settings.starting_cash"), I18n.t("settings.starting_cash_tip"))
	grid.add_child(_h("settings.starting_cash", _starting_cash))
	_go_bonus = _spin(0, 10000, 200, I18n.t("settings.go_bonus"), I18n.t("settings.go_bonus_tip"))
	grid.add_child(_h("settings.go_bonus", _go_bonus))

	_jail_rule = OptionButton.new()
	_jail_rule.add_item(I18n.t("settings.jail_both")); _jail_rule.add_item(I18n.t("settings.jail_fine_only")); _jail_rule.add_item(I18n.t("settings.jail_card_only"))
	_jail_rule.selected = 0
	_jail_rule.tooltip_text = I18n.t("settings.jail_rule_tip")
	grid.add_child(_h("settings.jail_rule", _jail_rule))
	_jail_fine = _spin(0, 10000, 50, I18n.t("settings.jail_fine"), I18n.t("settings.jail_fine_tip"))
	grid.add_child(_h("settings.jail_fine", _jail_fine))

	_free_parking = OptionButton.new()
	_free_parking.add_item(I18n.t("settings.fp_off")); _free_parking.add_item(I18n.t("settings.fp_on"))
	_free_parking.selected = 0
	_free_parking.tooltip_text = I18n.t("settings.free_parking_tip")
	grid.add_child(_h("settings.free_parking", _free_parking))
	_doubles = CheckButton.new(); _doubles.text = I18n.t("settings.doubles_lbl")
	_doubles.button_pressed = true
	_doubles.tooltip_text = I18n.t("settings.doubles_tip")
	grid.add_child(_h("settings.doubles", _doubles))

	_triple_doubles = CheckButton.new(); _triple_doubles.text = I18n.t("settings.triple_doubles_lbl")
	_triple_doubles.button_pressed = true
	_triple_doubles.tooltip_text = I18n.t("settings.triple_doubles_tip")
	grid.add_child(_h("settings.triple_doubles", _triple_doubles))
	_auctions = OptionButton.new()
	_auctions.add_item(I18n.t("settings.auctions_on")); _auctions.add_item(I18n.t("settings.auctions_off"))
	_auctions.selected = 0
	_auctions.tooltip_text = I18n.t("settings.auctions_tip")
	grid.add_child(_h("settings.auctions", _auctions))

	_housing = CheckButton.new(); _housing.text = I18n.t("settings.housing_lbl")
	_housing.button_pressed = true
	_housing.tooltip_text = I18n.t("settings.housing_tip")
	grid.add_child(_h("settings.housing", _housing))
	_even_build = CheckButton.new(); _even_build.text = I18n.t("settings.even_build_lbl")
	_even_build.button_pressed = true
	_even_build.tooltip_text = I18n.t("settings.even_build_tip")
	grid.add_child(_h("settings.even_build", _even_build))

	_monopoly_x2 = CheckButton.new(); _monopoly_x2.text = I18n.t("settings.monopoly_x2_lbl")
	_monopoly_x2.button_pressed = true
	_monopoly_x2.tooltip_text = I18n.t("settings.monopoly_x2_tip")
	grid.add_child(_h("settings.monopoly_x2", _monopoly_x2))
	_mortgage = CheckButton.new(); _mortgage.text = I18n.t("settings.mortgage_lbl")
	_mortgage.button_pressed = true
	_mortgage.tooltip_text = I18n.t("settings.mortgage_tip")
	grid.add_child(_h("settings.mortgage", _mortgage))

	_loan_pct = _spin(0, 100, 50, I18n.t("settings.loan_pct"), I18n.t("settings.loan_pct_tip"))
	grid.add_child(_h("settings.loan_pct", _loan_pct))
	_repay_pct = _spin(0, 300, 110, I18n.t("settings.repay_pct"), I18n.t("settings.repay_pct_tip"))
	grid.add_child(_h("settings.repay_pct", _repay_pct))

	_trades = CheckButton.new(); _trades.text = I18n.t("settings.trades_lbl")
	_trades.button_pressed = true
	_trades.tooltip_text = I18n.t("settings.trades_tip")
	grid.add_child(_h("settings.trades", _trades))
	_ai_aggression = _spin(0, 100, 50, I18n.t("settings.ai_aggression"), I18n.t("settings.ai_aggression_tip"))
	grid.add_child(_h("settings.ai_aggression", _ai_aggression))

func _build_tempo_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("settings.tab_tempo"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_turn_timer = _seconds_option([0, 5, 10, 15, 20, 30, 45, 60], 30)
	_turn_timer.tooltip_text = I18n.t("settings.turn_timer_tip")
	grid.add_child(_h("settings.turn_timer", _turn_timer))
	_auction_timer = _seconds_option([0, 5, 8, 10, 12, 15, 20], 15)
	_auction_timer.tooltip_text = I18n.t("settings.auction_timer_tip")
	grid.add_child(_h("settings.auction_timer", _auction_timer))

	_timeout_action = OptionButton.new()
	_timeout_action.add_item(I18n.t("settings.timeout_auto_pass")); _timeout_action.add_item(I18n.t("settings.timeout_away"))
	_timeout_action.selected = 0
	_timeout_action.tooltip_text = I18n.t("settings.timeout_tip")
	grid.add_child(_h("settings.timeout", _timeout_action))

func _build_interface_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("settings.tab_interface"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_animations = CheckButton.new(); _animations.text = I18n.t("settings.animations_lbl")
	_animations.button_pressed = true
	_animations.tooltip_text = I18n.t("settings.animations_tip")
	grid.add_child(_h("settings.animations", _animations))
	_event_overlay = CheckButton.new(); _event_overlay.text = I18n.t("settings.event_overlay_lbl")
	_event_overlay.button_pressed = true
	_event_overlay.tooltip_text = I18n.t("settings.event_overlay_tip")
	grid.add_child(_h("settings.event_overlay", _event_overlay))

	_spectacle = CheckButton.new(); _spectacle.text = I18n.t("settings.spectacle_lbl")
	_spectacle.button_pressed = false
	_spectacle.tooltip_text = I18n.t("settings.spectacle_tip")
	grid.add_child(_h("settings.spectacle", _spectacle))
	_sound = CheckButton.new(); _sound.text = I18n.t("settings.sound_lbl")
	_sound.button_pressed = true
	_sound.tooltip_text = I18n.t("settings.sound_tip")
	grid.add_child(_h("settings.sound", _sound))

	_language = OptionButton.new()
	_language.add_item("Русский"); _language.add_item("English")
	_language.selected = 0
	_language.tooltip_text = I18n.t("settings.language_tip")
	_language.connect("item_selected", Callable(self, "_on_language"))
	grid.add_child(_h("ui.language", _language))

	# P6 Phase 3: parametric board size (16..64, step 4). Changing it rebuilds
	# the board at the new tile count on the next START/ПРИМЕНИТЬ.
	_tile_count = SpinBox.new()
	_tile_count.min_value = 16
	_tile_count.max_value = 64
	_tile_count.step = 4
	_tile_count.value = DEF_TILE_COUNT
	_tile_count.tooltip_text = I18n.t("settings.tile_count_tip")
	grid.add_child(_h("settings.tile_count", _tile_count))

## P5: language selected → switch locale (retranslate via _on_locale_changed).
func _on_language(idx: int) -> void:
	I18n.set_locale("en" if idx == 1 else "ru")

func _build_data_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("settings.tab_data"))
	# MD-1: preset quick-select (fast input for the common rule presets)
	var presets_row := HBoxContainer.new()
	presets_row.add_theme_constant_override("separation", 8)
	var plbl := UiTheme.label(I18n.t("settings.presets_lbl"), 13, UiTheme.COL.text_dim)
	I18n.key_on(plbl, "settings.presets_lbl")
	presets_row.add_child(plbl)
	var d_classic := UiTheme.button(I18n.t("settings.preset_classic"), I18n.t("settings.preset_classic_tip"))
	I18n.key_on(d_classic, "settings.preset_classic"); I18n.tip_on(d_classic, "settings.preset_classic_tip")
	d_classic.connect("pressed", Callable(self, "_preset_classic"))
	presets_row.add_child(d_classic)
	var d_fast := UiTheme.button(I18n.t("settings.preset_fast"), I18n.t("settings.preset_fast_tip"))
	I18n.key_on(d_fast, "settings.preset_fast"); I18n.tip_on(d_fast, "settings.preset_fast_tip")
	d_fast.connect("pressed", Callable(self, "_preset_fast"))
	presets_row.add_child(d_fast)
	var d_hard := UiTheme.button(I18n.t("settings.preset_hard"), I18n.t("settings.preset_hard_tip"))
	I18n.key_on(d_hard, "settings.preset_hard"); I18n.tip_on(d_hard, "settings.preset_hard_tip")
	d_hard.connect("pressed", Callable(self, "_preset_hard"))
	presets_row.add_child(d_hard)
	tab.add_child(presets_row)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.label(I18n.t("settings.rng_seed"), 13))
	_rng_seed = SpinBox.new()
	_rng_seed.min_value = 0
	_rng_seed.max_value = 99999
	_rng_seed.value = 0
	_rng_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rng_seed.tooltip_text = I18n.t("settings.rng_seed_tip")
	row.add_child(_rng_seed)
	tab.add_child(row)

func _h(lbl: String, ctl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UiTheme.label(lbl, 13))
	ctl.custom_minimum_size.x = 120
	h.add_child(ctl)
	return h

func _spin(minv: int, maxv: int, def: int, _lbl: String, tip: String) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = def
	sb.tooltip_text = tip
	return sb

func _seconds_option(vals: Array, def: int) -> OptionButton:
	var o := OptionButton.new()
	o.add_item(I18n.t("settings.no_limit"), 0)
	for value in vals:
		if value == 0:
			continue
		o.add_item(str(value) + sec_suffix(), value)
		if value == def:
			o.selected = o.item_count - 1
	return o

## Seconds suffix localized: RU uses "с", EN uses "s".
static func sec_suffix() -> String:
	return "с" if I18n.current == "ru" else "s"

## Localized label for a driver id (CR-2). Falls back to the raw id if the
## key is missing so the engine identifier is never lost.
static func _driver_label(d: String) -> String:
	var key: String = "settings.driver." + d.to_lower().replace(":", "_")
	return I18n.t(key) if I18n.has(key) else d

## Rebuild a driver OptionButton's items in the current locale, preserving the
## selected index (CR-2). Items carry the raw driver id as their item id so
## _collect_settings can read by id, not by localized text.
static func _rebuild_driver_items(o: OptionButton) -> void:
	var keep: int = o.selected
	o.clear()
	for d in DRIVERS:
		o.add_item(_driver_label(d), DRIVERS.find(d))
	if keep >= 0 and keep < o.item_count:
		o.selected = keep
	else:
		o.selected = 0

func _add_row(_unused: Variant = null) -> void:
	if _rows.size() >= 8:
		return
	var idx := _rows.size()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)

	var num := UiTheme.label("%d." % (idx + 1), 14, UiTheme.COL.text_dim)
	num.custom_minimum_size.x = 22
	h.add_child(num)

	var driver := OptionButton.new()
	_rebuild_driver_items(driver)
	driver.selected = 0 if idx == 0 else 1
	driver.tooltip_text = I18n.t("settings.driver_tip")
	if idx == 0:
		driver.disabled = true
	h.add_child(driver)

	var swatch := ColorRect.new()
	swatch.color = COLORS[idx % COLORS.size()]
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.size = Vector2(20, 20)
	h.add_child(swatch)

	var name_edit := LineEdit.new()
	name_edit.text = NAMES[idx % NAMES.size()]
	name_edit.custom_minimum_size.x = 180
	name_edit.tooltip_text = I18n.t("settings.name_tip")
	h.add_child(name_edit)

	var token := OptionButton.new()
	for t in TOKENS:
		token.add_item(t)
	token.selected = idx % TOKENS.size()
	token.tooltip_text = I18n.t("settings.token_tip")
	h.add_child(token)

	var remove_btn := UiTheme.button("✕", I18n.t("settings.remove_tip"))
	remove_btn.custom_minimum_size = Vector2(24, 20)
	remove_btn.disabled = (idx == 0)
	remove_btn.connect("pressed", Callable(self, "_remove_row").bind(idx))
	h.add_child(remove_btn)

	_rows.append({
		"driver": driver, "name": name_edit, "color": swatch,
		"token": token, "remove_btn": remove_btn, "row": h,
	})
	_players_list.add_child(h)
	_refresh_buttons()

func _remove_row(i: int) -> void:
	if i <= 0 or i >= _rows.size():
		return
	var row: HBoxContainer = _rows[i]["row"]
	_players_list.remove_child(row)
	row.queue_free()
	_rows.remove_at(i)
	for j in _rows.size():
		var r: Dictionary = _rows[j]
		(r["num"] as Label).text = "%d." % (j + 1)
		(r["remove_btn"] as Button).disabled = (j == 0)
	_refresh_buttons()

func _collect_settings() -> Settings:
	# host role: "только наблюдаю" => the host seat (row 0) is not driven by a
	# human, it's an AI seat (observer mode). Computed at collection time —
	# we do NOT mutate the row widgets, so toggling host_role back to
	# "играю" restores the host's LOCAL seat.
	var observer: bool = (_host_role.selected == 1)
	var s = Settings.new()
	s.seat_count = _rows.size()
	s.seat_assignments = []
	var first := true
	for r in _rows:
		var drv: String = _driver_id_at(r["driver"])
		if first and observer and drv == "LOCAL":
			drv = "AI"
		first = false
		s.seat_assignments.append({
			"driver": drv,
			"name": str(r["name"].text),
			"token_color": (r["color"] as ColorRect).color.to_html(),
			"token_id": str(r["token"].get_item_text(r["token"].selected)),
		})
	s.rng_seed = int(_rng_seed.value)
	s.tile_count = int(_tile_count.value) if _tile_count != null else DEF_TILE_COUNT
	s.starting_order = "random" if _starting_order.selected == 0 else "manual"
	s.turn_timer = _selected_seconds(_turn_timer)
	s.auction_timer = _selected_seconds(_auction_timer)
	s.free_parking = (_free_parking.selected == 1)
	s.auctions_on_refusal = (_auctions.selected == 0)
	s.animations = _animations.button_pressed
	s.event_overlay = _event_overlay.button_pressed
	s.spectacle = _spectacle.button_pressed
	s.language = "ru" if _language.selected == 0 else "en"
	s.starting_cash = int(_starting_cash.value)
	s.go_bonus = int(_go_bonus.value)
	# engine expects stable ids; read by index (option labels are localized)
	s.jail_rule = ["both", "fine", "card"][_jail_rule.selected if _jail_rule.selected >= 0 else 0]
	s.jail_fine = int(_jail_fine.value)
	s.doubles = _doubles.button_pressed
	s.triple_doubles_to_jail = _triple_doubles.button_pressed
	s.housing = _housing.button_pressed
	s.even_build = _even_build.button_pressed
	s.monopoly_rent_x2 = _monopoly_x2.button_pressed
	s.mortgage = _mortgage.button_pressed
	s.mortgage_loan_pct = int(_loan_pct.value)
	s.mortgage_repay_pct = int(_repay_pct.value)
	s.trades = _trades.button_pressed
	s.ai_aggression = int(_ai_aggression.value)
	s.timeout_action = "auto-pass" if _timeout_action.selected == 0 else "mark-away"
	return s

## Read the raw driver id for a driver OptionButton by its selected item id
## (CR-2 / MD-7). The item id encodes the DRIVERS index, so it is
## locale-independent — never read the localized item text.
func _driver_id_at(o: OptionButton) -> String:
	var idx: int = o.selected
	if idx < 0 or idx >= DRIVERS.size():
		return "AI"
	return DRIVERS[idx]

func _selected_seconds(o: OptionButton) -> int:
	var idx: int = o.selected
	if idx < 0:
		return 0
	# item ID encodes the seconds value (0 = no limit) so it's locale-independent
	return maxi(0, o.get_item_id(idx))

func _index_of_seconds(o: OptionButton, target: int) -> int:
	for i in o.item_count:
		if o.get_item_id(i) == target:
			return i
	return 0

func _validation_error() -> String:
	if _rows.size() < 2:
		return I18n.t("settings.err_min2")
	var names := {}
	var colors := {}
	var tokens := {}
	for r in _rows:
		var nm: String = str(r["name"].text).strip_edges()
		if nm == "":
			return I18n.t("settings.err_empty_name")
		if names.has(nm):
			return I18n.t("settings.err_dup_name")
		names[nm] = true
		var col: String = (r["color"] as ColorRect).color.to_html()
		if colors.has(col):
			return I18n.t("settings.err_dup_color")
		colors[col] = true
		var tok: String = str(r["token"].get_item_text(r["token"].selected))
		if tokens.has(tok):
			return I18n.t("settings.err_dup_token")
		tokens[tok] = true
	return ""

func _refresh_buttons() -> void:
	var err: String = _validation_error()
	_status_lbl.text = err
	_start_btn.disabled = err != ""
	_apply_btn.disabled = err != ""
	_start_btn.tooltip_text = err if err != "" else I18n.t("settings.start_tip")
	_apply_btn.tooltip_text = err if err != "" else I18n.t("settings.apply_tip")
	_start_btn.visible = _pre_game
	_apply_btn.visible = not _pre_game

func _start_pressed() -> void:
	var s := _collect_settings()
	var seats: Array = SeatConfig.from_settings(s)
	started.emit(s, seats)

func _apply_pressed() -> void:
	var s := _collect_settings()
	var seats: Array = SeatConfig.from_settings(s)
	apply_requested.emit(s, seats)

func _on_close() -> void:
	closed.emit()

func _show_rules() -> void:
	var s := _collect_settings()
	var on := I18n.t("rules.on")
	var off := I18n.t("rules.off")
	var jail_lbl: String = {"both": I18n.t("settings.jail_both"), "fine": I18n.t("settings.jail_fine_only"), "card": I18n.t("settings.jail_card_only")}.get(s.jail_rule, s.jail_rule)
	var ta_lbl: String = I18n.t("settings.timeout_auto_pass") if s.timeout_action == "auto-pass" else I18n.t("settings.timeout_away")
	var lines: Array[String] = []
	lines.append(I18n.t("rules.title"))
	lines.append("")
	lines.append(I18n.t("rules.starting_cash", [s.starting_cash]))
	lines.append(I18n.t("rules.go_bonus", [s.go_bonus]))
	lines.append(I18n.t("rules.jail", [jail_lbl, s.jail_fine]))
	lines.append(I18n.t("rules.free_parking", [on if s.free_parking else off]))
	lines.append(I18n.t("rules.doubles", [on if s.doubles else off]))
	lines.append(I18n.t("rules.triple_doubles", [on if s.triple_doubles_to_jail else off]))
	lines.append(I18n.t("rules.auctions", [on if s.auctions_on_refusal else off]))
	lines.append(I18n.t("rules.housing", [on if s.housing else off]))
	lines.append(I18n.t("rules.even_build", [on if s.even_build else off]))
	lines.append(I18n.t("rules.monopoly_x2", [on if s.monopoly_rent_x2 else off]))
	lines.append(I18n.t("rules.mortgage", [on if s.mortgage else off, s.mortgage_loan_pct, s.mortgage_repay_pct]))
	lines.append(I18n.t("rules.trades", [on if s.trades else off]))
	lines.append(I18n.t("rules.turn_timer", [s.turn_timer]))
	lines.append(I18n.t("rules.auction_timer", [s.auction_timer]))
	lines.append(I18n.t("rules.timeout", [ta_lbl]))
	lines.append(I18n.t("rules.ai_aggression", [s.ai_aggression]))
	_show_rules_modal("\n".join(lines))

func _show_rules_modal(text: String) -> void:
	var popup := AcceptDialog.new()
	popup.title = I18n.t("rules.dialog_title")
	popup.dialog_text = text
	popup.ok_button_text = I18n.t("ui.ok")
	popup.size = Vector2(520, 420)
	add_child(popup)
	popup.popup_centered()

func _preset_classic() -> void:
	_reset_all()

func _preset_fast() -> void:
	_reset_all()
	_turn_timer.selected = _index_of_seconds(_turn_timer, 10)
	_auction_timer.selected = _index_of_seconds(_auction_timer, 10)
	_starting_cash.value = 1000

func _preset_hard() -> void:
	_reset_all()
	_mortgage.button_pressed = false
	_trades.button_pressed = false
	_housing.button_pressed = false
	_doubles.button_pressed = false
	_ai_aggression.value = 80

func _reset_all() -> void:
	_starting_cash.value = 1500
	_go_bonus.value = 200
	_jail_rule.selected = 0
	_jail_fine.value = 50
	_free_parking.selected = 0
	_doubles.button_pressed = true
	_triple_doubles.button_pressed = true
	_auctions.selected = 0
	_housing.button_pressed = true
	_even_build.button_pressed = true
	_monopoly_x2.button_pressed = true
	_mortgage.button_pressed = true
	_loan_pct.value = 50
	_repay_pct.value = 110
	_trades.button_pressed = true
	_ai_aggression.value = 50
	_turn_timer.selected = _index_of_seconds(_turn_timer, 30)
	_auction_timer.selected = _index_of_seconds(_auction_timer, 15)
	_timeout_action.selected = 0
	_animations.button_pressed = true
	_event_overlay.button_pressed = true
	_spectacle.button_pressed = false
	_sound.button_pressed = true
	_language.selected = 0
	_rng_seed.value = 0
	_host_role.selected = 0
	_starting_order.selected = 0
	_refresh_buttons()
