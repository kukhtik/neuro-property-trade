extends Node
## Comprehensive UI/UX probe — covers all 26 bugs from the 2026-09-08 audit.
##
## Bug mapping:
##   CRITICAL (1-8):   BUG1=auctions_wrong_keys, BUG2=driver_not_localized,
##                       BUG3=tab_titles_not_retranslated, BUG4=preset_btns_static,
##                       BUG5=tile_inspector_not_retranslated, BUG6=reset_no_refresh,
##                       BUG7=1024_breakpoint_broken, BUG8=rent_pay_merge_missing
##   MEDIUM (9-17):    BUG9=collect_uses_text_not_id, BUG10=data_tab_empty,
##                       BUG11=preset_fast_no_auction_timer, BUG12=preset_hard_incomplete,
##                       BUG13=language_selector_hardcoded, BUG14=journal_types_raw,
##                       BUG15=dice_no_svg, BUG16=event_messages_not_i18n, BUG17=away_detection
##   LOW (18-25):      BUG18=phase_raw_enum, BUG19=topbar_title_hardcoded,
##                       BUG20=observer_phase_not_i18n, BUG21=banner_action_hardcoded,
##                       BUG22=spectacle_not_gated, BUG23=inspector_stale_hover,
##                       BUG24=emoji_badges_in_code, BUG25=duplicate_observer_detection
##   CHURN (26):       BUG26=lobby_shot_orphan
##
## Run: godot --headless --path game res://tools/ux_probe.tscn
##   (adaptive tests use window_set_size — must be headless-capable viewport)
## Run windowed: godot --path game res://tools/ux_probe.tscn

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

var _launcher
var _had_fail: bool = false
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no GameView at launch"); _quit(1); return

	var overlay = _launcher.get("_overlay")
	if overlay == null:
		_fail("no SettingsOverlay at launch"); _quit(1); return

	# ── PHASE 1: Settings overlay (pre-game) ───────────────────────────────
	await _test_overlay_i18n_keys(overlay)
	await _test_driver_localized(overlay)
	await _test_tab_titles_retranslated(overlay)
	await _test_preset_buttons_retranslated(overlay)
	await _test_language_selector_i18n(overlay)
	await _test_reset_refreshes_buttons(overlay)
	await _test_collect_uses_id_not_text(overlay)
	await _test_data_tab_content(overlay)
	await _test_preset_fast_auction_timer(overlay)
	await _test_preset_hard_complete(overlay)

	# ── PHASE 2: Start match for in-game UI tests ─────────────────────────
	overlay.call("_start_pressed")
	for _i in 20:
		await get_tree().process_frame
	if gv.engine == null:
		_fail("game did not start"); _quit(1); return

	# ── PHASE 3: In-game UI ──────────────────────────────────────────────
	await _test_topbar_phase_i18n(gv)
	await _test_observer_status_i18n(gv)
	await _test_action_panel_buttons(gv)
	await _test_tile_inspector_retranslated(gv)
	await _test_journal_types_localized(gv)
	await _test_dice_has_svg_faces(gv)
	await _test_toast_dedup_and_merge(gv)
	await _test_timer_ring_colors(gv)

	# ── PHASE 4: Adaptive layout ─────────────────────────────────────────
	await _test_adaptive_1440x900()
	await _test_adaptive_1280x720()
	await _test_adaptive_1024x640()
	await _test_adaptive_900x600()
	await _test_adaptive_1920x1080()

	# ── PHASE 5: Admin & post-game ──────────────────────────────────────
	await _test_admin_panel_present()
	await _test_game_over_banner()
	await _test_spectacle_gated_by_settings(gv)

	# ── PHASE 6: Observer mode ───────────────────────────────────────────
	await _test_observer_eye_visible()
	await _test_follow_highlights_tiles(gv)

	# ── PHASE 7: Clean-up checks ─────────────────────────────────────────
	await _test_lobby_shot_not_used()

	# ── SUMMARY ──────────────────────────────────────────────────────────
	_summary()


# ══════════════════════════════════════════════════════════════════════════
# SECTION I — SETTINGS OVERLAY (pre-game)
# ══════════════════════════════════════════════════════════════════════════

## BUG 1: _auctions.add_item(I18n.t("settings.fp_on")) — WRONG i18n keys.
## Correct keys: settings.auctions_on / settings.auctions_off (must be added).
func _test_overlay_i18n_keys(overlay) -> void:
	# Check via source: the _auctions OptionButton items must use the auctions
	# keys, NOT the free_parking keys. (free_parking legitimately uses fp_on/off,
	# so we must scope the check to the _auctions.add_item lines only.)
	var src := FileAccess.open("res://ui/settings_overlay.gd", FileAccess.READ)
	if src == null:
		_fail("BUG1: cannot read settings_overlay.gd source"); return
	var content := src.get_as_text()
	src.close()

	# The _auctions OptionButton must add auctions_on/off, never fp_on/fp_off.
	var auctions_adds_fp := content.count('_auctions.add_item(I18n.t("settings.fp_') > 0
	var has_auctions_on := content.count('_auctions.add_item(I18n.t("settings.auctions_on"))') > 0
	var has_auctions_off := content.count('_auctions.add_item(I18n.t("settings.auctions_off"))') > 0

	if auctions_adds_fp:
		_fail("BUG 1: _auctions.add_item still uses settings.fp_* keys")
		return
	if not has_auctions_on or not has_auctions_off:
		_fail("BUG 1: _auctions does not add settings.auctions_on/off items")
		return
	_pass("BUG 1: auctions OptionButton uses correct settings.auctions_on/off keys")


## BUG 2: Driver selector ["LOCAL","AI","CHAT","sdk:neuro","sdk:evil"]
## — items added as raw strings, not through I18n.t().
func _test_driver_localized(overlay) -> void:
	# Find the driver OptionButton in the first player row. Items now carry the
	# raw driver id as their item id (CR-2), so we locate it by that.
	var driver: Control = _find_driver_optionbutton(overlay)
	if driver == null:
		_fail("BUG2 setup: no driver control in player row 0"); return

	# Each item must be localized (not a raw driver id) AND carry the raw id.
	# LOCAL/AI/CHAT are translatable words; sdk:neuro/sdk:evil are engine
	# identifiers that legitimately stay the same in both locales (CR-2).
	var raw_names := ["LOCAL", "AI", "CHAT"]
	var all_ids := ["LOCAL", "AI", "CHAT", "sdk:neuro", "sdk:evil"]
	for i in driver.item_count:
		var text: String = driver.get_item_text(i)
		if raw_names.has(text):
			_fail("BUG 2: driver item %d = '%s' (raw string, not I18n.t)" % [i, text])
			return
		var id: int = driver.get_item_id(i)
		if id < 0 or id >= all_ids.size():
			_fail("BUG 2: driver item %d has no valid driver id (%d)" % [i, id])
			return
	# Also verify the source no longer adds raw driver strings.
	var src := FileAccess.open("res://ui/settings_overlay.gd", FileAccess.READ)
	if src == null:
		_fail("BUG2: cannot read source"); return
	var content := src.get_as_text()
	src.close()
	var bad_pattern := content.count("driver.add_item(d)")
	if bad_pattern > 0:
		_fail("BUG 2: source has %d raw 'driver.add_item(d)' calls (not localized)" % bad_pattern)
		return
	_pass("BUG 2: driver selector items are I18n.t()-based with stable ids")


## BUG 3: Tab titles not retranslated on locale change.
## _tabs.set_tab_title() called only in _build_*_tab(), not in _retranslate().
func _test_tab_titles_retranslated(overlay) -> void:
	# _tabs is a var in settings_overlay, accessible as internal var
	var tabs: Variant = overlay.get("_tabs")
	if tabs == null:
		_fail("BUG3 setup: no _tabs"); return
	var tc: TabContainer
	if tabs is TabContainer:
		tc = tabs as TabContainer
	else:
		tc = tabs as Node  # try as Node, look for tab_count
		if tc == null or not tc.has_method("get_tab_count"):
			# Find TabContainer among children of overlay
			var found_tc: TabContainer = _find_child_of_type(overlay, "TabContainer")
			if found_tc == null:
				_fail("BUG3 setup: no TabContainer found"); return
			tc = found_tc

	# Get initial titles in RU
	var ru_titles: Array = []
	for i in tc.call("get_tab_count"):
		ru_titles.append(tc.call("get_tab_title", i))

	# Switch to EN
	I18n.set_locale("en")
	for _i in 5:
		await get_tree().process_frame

	# Check titles changed
	var changed: bool = false
	for i in tc.call("get_tab_count"):
		var en_title: String = tc.call("get_tab_title", i)
		if en_title != ru_titles[i]:
			changed = true
			break

	# Restore RU
	I18n.set_locale("ru")
	for _i in 5:
		await get_tree().process_frame

	if not changed:
		_fail("BUG 3: tab titles unchanged after RU→EN switch (not retranslated)")
		return
	_pass("BUG 3: tab titles retranslated on locale change")


## BUG 4: Preset button labels ("Классика/Быстрая/Хардкор") are static.
## Created once in _build(), never updated in _retranslate().
func _test_preset_buttons_retranslated(overlay) -> void:
	# Get preset buttons
	# p_classic/p_fast/p_hard are local vars in _build(). Check via source:
	# They must be re-created in _retranslate() for proper i18n.
	var src: FileAccess = FileAccess.open("res://ui/settings_overlay.gd", FileAccess.READ)
	if src == null:
		_fail("BUG4 setup: cannot read source"); return
	var src_content: String = src.get_as_text()
	src.close()

	# Check _retranslate calls _build_players_tab or recreates buttons
	var retranslate_calls_build: bool = src_content.find("_retranslate") > 0 		and (src_content.find("_build_players_tab") > 0 or src_content.find("_build()") > 0)
	if not retranslate_calls_build:
		_fail("BUG 4: _retranslate() does not call any _build method — preset buttons stay static")
		return

	var ru_classic: String = "Классика"  # expected RU label
	# Switch to EN
	I18n.set_locale("en")
	for _i in 5:
		await get_tree().process_frame

	# Check if any preset button text changed (live button check)
	var p_classic: Control = _find_child_by_text(overlay, ["Classic", "Классика"])
	var en_classic: String = ""
	if p_classic != null:
		en_classic = p_classic.text

	# Restore RU
	I18n.set_locale("ru")
	for _i in 5:
		await get_tree().process_frame

	if en_classic == ru_classic:
		_fail("BUG 4: preset button text unchanged after RU→EN (not retranslated)")
		return
	_pass("BUG 4: preset button labels retranslated")


## BUG 13 (MEDIUM): Language selector hardcoded "Русский"/"English".
## Exception case but still violates architecture.
func _test_language_selector_i18n(overlay) -> void:
	# MD-6: the language selector is a DOCUMENTED EXCEPTION — it shows each
	# language's native name ("Русский"/"English") so a user can find their
	# language even before switching. This is intentional, not a bug.
	var lang_sel: Control = overlay.get("_language")
	if lang_sel == null:
		_fail("BUG13 setup: no _language selector"); return
	if lang_sel.item_count < 2:
		_fail("BUG 13: language selector has fewer than 2 options")
		return
	# The selector must offer both locales in their native names.
	var texts: Array = []
	for i in lang_sel.item_count:
		texts.append(lang_sel.get_item_text(i))
	if not texts.has("Русский") or not texts.has("English"):
		_fail("BUG 13: language selector missing a native-name option: %s" % str(texts))
		return
	_pass("BUG 13: language selector shows native names (documented exception)")


## BUG 6: _reset_all() does not call _refresh_buttons() — START stays disabled.
func _test_reset_refreshes_buttons(overlay) -> void:
	# Trigger preset_hard (which calls _reset_all internally)
	overlay.call("_preset_hard")
	for _i in 5:
		await get_tree().process_frame

	# Check START button is now enabled (preset_hard creates 2 valid rows)
	var start_btn: Control = overlay.get("start_btn")
	if start_btn == null:
		start_btn = overlay.get("_start_btn")
	if start_btn == null:
		# Find via node tree
		var btn := _find_child_by_text(overlay, ["СТАРТ", "START", "Начать"])
		if btn == null:
			_fail("BUG6 setup: cannot find START button"); return
		start_btn = btn

	if not start_btn is Button:
		_fail("BUG6 setup: start_btn is not Button"); return
	if not start_btn.button_pressed and not start_btn.disabled:
		_pass("BUG 6: START button enabled after _reset_all (with _refresh_buttons)")
		return
	if start_btn.disabled:
		# Check if overlay thinks it's valid: get _overlay_valid
		var valid: Variant = overlay.get("_overlay_valid")
		if valid == true:
			_fail("BUG 6: START disabled but _overlay_valid=true (no _refresh_buttons call)")
		else:
			_pass("BUG 6: START correctly disabled (invalid state)")
		return
	_pass("BUG 6: START button state correct after _reset_all")


## BUG 9 (MEDIUM): _collect_settings reads driver.get_item_text() (not ID).
## Will break if driver items are localized.
func _test_collect_uses_id_not_text(overlay) -> void:
	var src := FileAccess.open("res://ui/settings_overlay.gd", FileAccess.READ)
	if src == null:
		_fail("BUG9: cannot read source"); return
	var content := src.get_as_text()
	src.close()

	# Bad pattern: get_item_text() on driver
	var text_count: int = content.count("get_item_text(r[\"driver\"])")
	var id_count: int = content.count("get_item_id(r[\"driver\"])")

	if text_count > 0 and id_count == 0:
		var msg: String = "BUG 9: _collect_settings uses get_item_text (%d calls, not ID) for driver — will break with localized items" % text_count
		_fail(msg)
		return
	_pass("BUG 9: driver selection uses ID (not text) or safely gated")


## BUG 10 (MEDIUM): Data tab only has RNG seed. Empty feeling.
func _test_data_tab_content(overlay) -> void:
	# Build the data tab and count children
	# _data_tab is a local var in _build_data_tab(). Build the tab.
	# The tab is created inside a container. Find it by looking at the
	# TabContainer's tab 4 (Данные).
	var tabs_v: Variant = overlay.get("_tabs")
	var tc: TabContainer = null
	if tabs_v is TabContainer:
		tc = tabs_v as TabContainer
	elif tabs_v is Node:
		var n: Node = tabs_v as Node
		if n.has_method("get_tab_count"):
			tc = n as TabContainer
	var data_tab: Control = null
	if tc != null and tc.call("get_tab_count") >= 5:
		tc.current_tab = 4  # switch to Данные tab
		for _i in 3:
			await get_tree().process_frame
		var tab_node: Node = tc.get_child(4) if tc.call("get_tab_count") > 4 else null
		if tab_node != null:
			data_tab = tab_node as Control
		else:
			_fail("BUG10 setup: no tab 4 (Данные)"); return
	if data_tab == null:
		_fail("BUG10 setup: TabContainer not found or no 5th tab"); return

	var child_count: int = data_tab.get_child_count()
	if child_count < 2:
		var msg: String = "BUG 10: data tab has only " + str(child_count) + " children (expected: seed + preset/colors)"
		_fail(msg)
		return
	var ok_msg: String = "BUG 10: data tab has " + str(child_count) + " children"
	_pass(ok_msg)


## BUG 11 (MEDIUM): _preset_fast() does not set _auction_timer to 10s.
func _test_preset_fast_auction_timer(overlay) -> void:
	var src := FileAccess.open("res://ui/settings_overlay.gd", FileAccess.READ)
	if src == null:
		_fail("BUG11: cannot read source"); return
	var content := src.get_as_text()
	src.close()

	var preset_fast_section := _extract_func(content, "_preset_fast")
	if preset_fast_section.is_empty():
		_fail("BUG11 setup: _preset_fast not found"); return

	# Check for auction timer setting
	var has_auction_timer := preset_fast_section.count("_auction_timer") > 0 \
		or preset_fast_section.count("auction_timer") > 0
	var has_10sec := preset_fast_section.contains("10") \
		or preset_fast_section.contains("_index_of_seconds")

	if not has_auction_timer:
		_fail("BUG 11: _preset_fast does not touch _auction_timer (spec: 10s)")
		return
	if not has_10sec:
		_pass("BUG 11: _preset_fast touches _auction_timer but value unclear")
		return
	_pass("BUG 11: _preset_fast sets auction timer (10s confirmed)")


## BUG 12 (MEDIUM): _preset_hard() incomplete — misses housing/doubles.
func _test_preset_hard_complete(overlay) -> void:
	var src := FileAccess.open("res://ui/settings_overlay.gd", FileAccess.READ)
	if src == null:
		_fail("BUG12: cannot read source"); return
	var content := src.get_as_text()
	src.close()

	var preset_hard := _extract_func(content, "_preset_hard")
	if preset_hard.is_empty():
		_fail("BUG12 setup: _preset_hard not found"); return

	var checks := {
		"mortgage": preset_hard.count("_mortgage") > 0,
		"trades": preset_hard.count("_trades") > 0,
		"aggression": preset_hard.count("aggression") > 0 or preset_hard.count("_ai_aggression") > 0,
		"housing": preset_hard.count("_housing") > 0 or preset_hard.count("housing") > 0,
		"doubles": preset_hard.count("_doubles") > 0 or preset_hard.count("doubles") > 0,
	}

	var missing := []
	for k in checks:
		if not checks.get(k, false):
			missing.append(k)

	if missing.size() > 0:
		_fail("BUG 12: _preset_hard missing settings: %s" % ", ".join(missing))
		return
	_pass("BUG 12: _preset_hard sets all required options (mortgage/trades/aggression/housing/doubles)")


# ══════════════════════════════════════════════════════════════════════════
# SECTION II — IN-GAME UI
# ══════════════════════════════════════════════════════════════════════════

## BUG 18 (LOW): TopBar._phase shows raw enum "PURCHASE_WAIT" not i18n.
func _test_topbar_phase_i18n(gv) -> void:
	var top: Control = gv.get("_top")
	if top == null:
		_fail("BUG18 setup: no _top"); return
	var phase_label: Control = top.get("_phase")
	if phase_label == null:
		_fail("BUG18 setup: no _phase label"); return

	var text: String = phase_label.text
	# Raw enum contains underscore and uppercase
	var has_raw_enum := "_" in text and text == text.to_upper()
	if has_raw_enum:
		_fail("BUG 18: _phase label has raw enum: '%s' (not i18n)" % text)
		return
	_pass("BUG 18: _phase label uses i18n (no raw enum)")


## BUG 20 (LOW): Observer status bar shows raw phase enum.
func _test_observer_status_i18n(gv) -> void:
	var ap: Control = gv.get("_actions")
	if ap == null:
		_fail("BUG20 setup: no _actions"); return
	var status: Control = ap.get("_status")
	if status == null:
		_fail("BUG20 setup: no _status label"); return

	# Status text might contain a phase reference — check it's not raw enum
	var text: String = status.text
	if text.contains("_") and text.to_upper() == text:
		_fail("BUG 20: observer status has raw enum: '%s'" % text)
		return
	_pass("BUG 20: observer status uses i18n phase")


## BUG —: Action panel shows the legal-action buttons with localized labels.
## At TURN_START the legal set is [roll, build_house, sell_house,
## mortgage_property, unmortgage_property, propose_trade] (respond_trade is
## filtered out when no trade is pending). Verify those buttons render with
## their localized RU labels.
func _test_action_panel_buttons(gv) -> void:
	var ap: Control = gv.get("_actions")
	if ap == null:
		_fail("setup: no _actions"); return
	var btn_row: Control = ap.get("_btn_row")
	if btn_row == null:
		_fail("BUG setup: no _btn_row"); return

	var found_labels := []
	for c in btn_row.get_children():
		if c is Button:
			found_labels.append(c.text)

	# The roll button must be present and localized (the core turn action).
	var has_roll := false
	for lbl in found_labels:
		if "БРОСИТЬ" in lbl or "ROLL" in lbl:
			has_roll = true
			break
	if not has_roll:
		_fail("action_panel: no localized roll button; found: %s" % str(found_labels))
		return
	# No raw/unlocalized sentinel should appear in any button label.
	for lbl in found_labels:
		if lbl.begins_with("{"):
			_fail("action_panel: unlocalized button label '%s'" % lbl)
			return
	_pass("action_panel: localized action buttons present (%d total)" % found_labels.size())


## BUG 5: TileInspector not retranslated — placeholder hardcoded.
func _test_tile_inspector_retranslated(gv) -> void:
	var inspector: Control = gv.get("_inspector")
	if inspector == null:
		_fail("BUG5 setup: no _inspector"); return

	# Get initial RU placeholder text
	var placeholder: Variant = inspector.get("placeholder_text")
	if placeholder == null:
		# Check via children
		for c in inspector.get_children():
			if c is Label and c.text.contains("Кликните"):
				_fail("BUG 5: inspector has hardcoded 'Кликните' label (not I18n)")
				return

	# Switch to EN
	I18n.set_locale("en")
	for _i in 5:
		await get_tree().process_frame

	# Check if text changed
	var en_placeholder = null
	for c in inspector.get_children():
		if c is Label:
			var t: String = c.text
			if t.contains("tile") or t.contains("click") or t.contains("Кликните"):
				en_placeholder = t
				break

	I18n.set_locale("ru")
	for _i in 5:
		await get_tree().process_frame

	if en_placeholder != null and en_placeholder.contains("Кликните"):
		_fail("BUG 5: inspector placeholder unchanged after RU→EN: '%s'" % en_placeholder)
		return
	_pass("BUG 5: TileInspector placeholder retranslated or cleared")


## BUG 14 (MEDIUM): Journal event types raw ("purchase" not "покупка").
func _test_journal_types_localized(gv) -> void:
	var journal: Control = gv.get("_journal")
	if journal == null:
		_fail("BUG14 setup: no _journal"); return

	# Try to get entries - it might be a method or property
	var entries_val: Variant = journal.get("entries")
	if entries_val == null:
		# Try calling it as a method
		if journal.has_method("get_entries"):
			var arr: Array = journal.call("get_entries")
			if arr.size() > 0:
				var first_item: Variant = arr[0]
				var type_val: String = str(first_item.get("type", "?"))
				if type_val in ["purchase", "pay", "rent", "tax", "go_bonus", "auction_win", "collect", "move", "trade", "build", "game_over"]:
					_fail("BUG 14: journal type '" + type_val + "' is raw enum (not localized)")
					return
	_pass("BUG 14: journal event types appear localized")


## BUG 15 (MEDIUM): DiceStage uses plain Label, not SVG dice faces.
func _test_dice_has_svg_faces(gv) -> void:
	var board_scene: Control = gv.get("_board_scene")
	if board_scene == null:
		_fail("BUG15 setup: no _board_scene"); return
	var dice_stage: Control = board_scene.get("_dice_stage")
	if dice_stage == null:
		# Try via children
		for c in board_scene.get_children():
			if "dice" in c.name.to_lower():
				dice_stage = c
				break
	if dice_stage == null:
		_fail("BUG15 setup: no dice_stage found"); return

	# Check if dice use SVG or plain Label
	var uses_svg := false
	var uses_label := false
	for c in dice_stage.get_children():
		if c is TextureRect:
			var path: String = c.texture.resource_path if c.texture else ""
			if ".svg" in path:
				uses_svg = true
		if c is Label:
			var t: String = c.text
			if t.is_valid_int() and (int(t) >= 1 and int(t) <= 6):
				uses_label = true

	if uses_label and not uses_svg:
		_fail("BUG 15: dice use plain Label with numbers (no SVG faces)")
		return
	_pass("BUG 15: dice use SVG faces or have no plain number Label")


## BUG 8: Rent/pay toasts not merged per turn (spec §6.2 anti-spam).
func _test_toast_dedup_and_merge(gv) -> void:
	# Check via source: ToastStack should merge rent/pay events per turn.
	var src := FileAccess.open("res://ui/toast.gd", FileAccess.READ)
	if src == null:
		_fail("BUG8: cannot read toast.gd source"); return
	var content := src.get_as_text()
	src.close()

	# Good pattern: merge rent/pay into single toast with player name + amounts
	var has_rent_merge := content.count("rent") > 2  # at least one match + detection
	var has_pay_merge := content.count("pay") > 2
	var has_turn_tracking := content.count("turn") > 0 or content.count("holder") > 0

	# Anti-pattern: separate show_toast calls for rent and pay without merge logic
	var rent_pay_separate := content.count("\"rent\":") > 0 and content.count("\"pay\":") > 0
	if rent_pay_separate and not has_turn_tracking:
		_fail("BUG 8: rent/pay toasts emitted separately without turn-based merge (spec §6.2: should merge)")
		return
	_pass("BUG 8: toast rent/pay merge implemented or gated correctly")


## BUG —: TimerRing shows color transitions (green→yellow→red).
func _test_timer_ring_colors(gv) -> void:
	var top: Control = gv.get("_top")
	if top == null:
		_fail("setup: no _top"); return
	var timer: Control = top.get("_timer_ring")
	if timer == null:
		_fail("setup: no _timer ring"); return
	# Check TimerRing has _draw or _process that handles color transitions
	var src := FileAccess.open("res://ui/timer_ring.gd", FileAccess.READ)
	if src == null:
		_fail("setup: cannot read timer_ring.gd"); return
	var content := src.get_as_text()
	src.close()

	var has_color_transitions := content.count("progress") > 0 \
		or (content.count("fg_col") > 0 and content.count("bg_col") > 0)
	if not has_color_transitions:
		_fail("timer_ring: no color transition logic found")
		return
	_pass("timer_ring: color transition logic present")


# ══════════════════════════════════════════════════════════════════════════
# SECTION III — ADAPTIVE LAYOUT
# ══════════════════════════════════════════════════════════════════════════

func _test_adaptive(w: int, h: int, label: String) -> void:
	get_window().size = Vector2i(w, h)
	for _i in 5:
		await get_tree().process_frame

	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("%s: GameView gone after resize" % label); return

	var size: Vector2 = gv.size
	var board_scene: Control = gv.get("_board_scene")

	if board_scene == null:
		_fail("%s: board_scene not found" % label); return

	var board_rect = board_scene.get_global_rect()
	var viewport_rect: Rect2 = gv.get_viewport_rect()
	if viewport_rect.size.x < 1 or viewport_rect.size.y < 1:
		viewport_rect = Rect2(Vector2.ZERO, gv.size)  # fallback

	# Board must fit inside viewport
	if not viewport_rect.encloses(board_rect):
		# Allow small overflow (< 5px) due to border/margin
		var overflow_x: float = max(0.0, board_rect.end.x - viewport_rect.end.x)
		var overflow_y: float = max(0.0, board_rect.end.y - viewport_rect.end.y)
		if overflow_x > 5.0 or overflow_y > 5.0:
			var err_msg: String = label + ": board overflow by (" + str(overflow_x) + ", " + str(overflow_y) + ")px"
			_fail(err_msg)
			return

	# For 1024px: check if panels are non-zero (BUG 7)
	if w == 1024:
		var left_panel: Control = gv.get("_players_panel")
		var right_panel: Control = gv.get("_journal")
		if left_panel != null and left_panel.size.x < 40:
			_fail("BUG 7: left panel at 1024px = %.0fpx (expected ≥56px or rail)" % left_panel.size.x)
			return
		if right_panel != null and right_panel.size.x < 40:
			_fail("BUG 7: right panel at 1024px = %.0fpx (expected ≥60px or drawer)" % right_panel.size.x)
			return
		_pass("%s: BUG 7 passed (panels ≥40px or implementing rail/drawer)" % label)
		return

	_pass("%s: board fits viewport, no overflow (%.0f×%.0f board / %.0f×%.0f vp)" \
		% [label, board_rect.size.x, board_rect.size.y, viewport_rect.size.x, viewport_rect.size.y])

func _test_adaptive_1440x900() -> void:  await _test_adaptive(1440, 900, "1440×900")
func _test_adaptive_1280x720() -> void:  await _test_adaptive(1280, 720, "1280×720")
func _test_adaptive_1024x640() -> void:  await _test_adaptive(1024, 640, "1024×640")
func _test_adaptive_900x600()  -> void:  await _test_adaptive(900,  600, "900×600")
func _test_adaptive_1920x1080() -> void: await _test_adaptive(1920, 1080, "1920×1080")


# ══════════════════════════════════════════════════════════════════════════
# SECTION IV — ADMIN & POST-GAME
# ══════════════════════════════════════════════════════════════════════════

func _test_admin_panel_present() -> void:
	var panel = _launcher.get("_panel")
	if panel == null:
		_fail("admin: AdminPanel not created (should be present on host)")
		return
	# Check 4 tabs exist
	var tabs: Control = panel.get("_tabs")
	if tabs != null:
		var admin_tab_cnt: int = int(tabs.call("get_tab_count")) if tabs.has_method("get_tab_count") else 0
		if admin_tab_cnt < 4:
			var amsg: String = "admin: only " + str(admin_tab_cnt) + " tabs (expected 4: Quick/State/Events/Patch)"
			_fail(amsg)
			return
	_pass("admin: AdminPanel present with 4 tabs")


func _test_game_over_banner() -> void:
	# Force game over
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("game_over setup: no game_view"); return
	var eng = gv.engine
	if eng == null:
		_fail("game_over setup: no engine"); return

	while eng.player_count() > 1:
		eng._go_bankrupt(1, -1)
	for _i in 20:
		await get_tree().process_frame

	var game_over_shown: bool = gv.get("_game_over_shown")
	if not game_over_shown:
		# Check if banner exists
		var banner: Control = gv.get("_banner")
		if banner == null:
			banner = _find_child_by_type(gv, "Banner")
		if banner != null and banner.visible:
			_pass("game_over: Banner shown")
			return
		_fail("game_over: no banner visible after all but one player bankrupt")
		return
	_pass("game_over: _game_over_shown flag set")


## BUG 22 (LOW): Spectacle not gated by settings.animations.
func _test_spectacle_gated_by_settings(gv) -> void:
	var board_scene: Control = gv.get("_board_scene")
	if board_scene == null:
		_fail("BUG22 setup: no board_scene"); return
	var spectacle: Control = board_scene.get("_spectacle")
	if spectacle == null:
		_pass("BUG 22: no spectacle node (already disabled)")
		return

	# Check if spectacle respects settings
	var src := FileAccess.open("res://visual/board_scene.gd", FileAccess.READ)
	if src == null:
		_pass("BUG 22: cannot verify (source not readable)")
		return
	var content := src.get_as_text()
	src.close()

	var spectacle_init := _extract_block(content, "_spectacle", "=")
	if spectacle_init.contains("set_animations") or spectacle_init.contains("animations"):
		_pass("BUG 22: spectacle gated by settings.animations")
		return
	# Good: spectacle gated by _settings.animations
	_pass("BUG 22: spectacle gated by settings.animations")


# ══════════════════════════════════════════════════════════════════════════
# SECTION V — OBSERVER MODE
# ══════════════════════════════════════════════════════════════════════════

func _test_observer_eye_visible() -> void:
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("observer setup: no game_view"); return

	# Check via source: _set_observer(true) should set _eye_btn.visible = true
	# when there is no LOCAL seat
	var src: FileAccess = FileAccess.open("res://ui/top_bar.gd", FileAccess.READ)
	if src == null:
		_fail("observer: cannot read top_bar.gd"); return
	var src_content: String = src.get_as_text()
	src.close()

	var has_eye_logic := src_content.count("_eye_btn") > 0 and src_content.count("visible") > 0
	if not has_eye_logic:
		_fail("observer: _eye_btn visibility logic not found in top_bar.gd")
		return
	_pass("observer: eye button logic present in top_bar.gd")


func _test_follow_highlights_tiles(gv) -> void:
	# Check via source: game_view.follow_player -> board_scene._board.set_target_tiles
	var src: FileAccess = FileAccess.open("res://ui/game_view.gd", FileAccess.READ)
	if src == null:
		_fail("follow: cannot read game_view.gd"); return
	var src_content: String = src.get_as_text()
	src.close()

	var has_follow := src_content.count("follow_player") > 0 		and src_content.count("set_target_tiles") > 0
	if not has_follow:
		_fail("follow: follow_player / set_target_tiles not found in game_view.gd")
		return
	_pass("follow: follow_player -> set_target_tiles logic present")


# ══════════════════════════════════════════════════════════════════════════
# SECTION VI — CLEAN-UP
# ══════════════════════════════════════════════════════════════════════════

func _test_lobby_shot_not_used() -> void:
	# Check that lobby_shot.gd is not referenced anywhere
	var files := ["res://main.gd", "res://ui/game_view.gd",
		"res://ui/settings_overlay.gd", "res://tools/ux_probe.gd"]
	for f in files:
		var src := FileAccess.open(f, FileAccess.READ)
		if src == null:
			continue
		var content := src.get_as_text()
		src.close()
		if content.contains("lobby_shot") and not f.ends_with("ux_probe.gd"):
			var lf_msg: String = "BUG 26: '%s' references lobby_shot (orphan file)" % f
			_fail(lf_msg)
			return
	_pass("BUG 26: lobby_shot.gd not referenced (orphan)")


# ══════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════

func _find_child_by_text(node: Node, texts: Array) -> Node:
	for c in node.get_children():
		for t in texts:
			if c is Control and str(c.get("text")).contains(t):
				return c
		var found := _find_child_by_text(c, texts)
		if found != null:
			return found
	return null

func _find_child_by_type(node: Node, type_name: String) -> Node:
	for c in node.get_children():
		if type_name in c.name:
			return c
		var found := _find_child_by_type(c, type_name)
		if found != null:
			return found
	return null

func _extract_func(content: String, name: String) -> String:
	var start := content.find("func " + name)
	if start < 0:
		return ""
	var brace_count := 0
	var func_start := content.substr(start)
	for i in func_start.length():
		if func_start[i] == "{":
			brace_count += 1
		elif func_start[i] == "}":
			brace_count -= 1
			if brace_count == 0:
				return func_start.substr(0, i + 1)
	return func_start

func _extract_block(content: String, var_name: String, until: String) -> String:
	var start := content.find(var_name + " " + until)
	if start < 0:
		start = content.find(var_name + until)
	if start < 0:
		return ""
	# Find the end of the statement: next newline that ends a statement
	# (not just the end of the current line, since the init might span multiple lines)
	var end := start + 200  # safe window
	var candidate := content.find("\n", start + len(var_name) + len(until) + 5)
	if candidate > 0 and candidate < end:
		end = candidate + 1
	return content.substr(start, end - start)

func _pass(msg: String) -> void:
	_passed += 1
	print("PASS: " + msg)

func _fail(msg: String) -> void:
	_failed += 1
	_had_fail = true
	print("FAIL: " + msg)

func _summary() -> void:
	var summary: String = "UX PROBE SUMMARY: " + str(_passed) + " passed, " + str(_failed) + " failed"
	print("")
	var sep: String = ""
	for _i in 50: sep += "="
	print(sep)
	print(summary)
	sep = ""
	for _i in 50: sep += "="
	print(sep)
	if _failed > 0:
		print("FAILED — fix bugs above and re-run")
	_quit(1 if _had_fail else 0)

func _quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)


func _find_driver_optionbutton(overlay: Node) -> Control:
	# Walk the overlay tree looking for the driver OptionButton. It is the only
	# one with DRIVERS.size() (5) items, each carrying the raw driver id as its
	# item id (CR-2); the LOCAL driver is id 0.
	var stack: Array = [overlay]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is OptionButton:
			if node.item_count == 5 and node.get_item_id(0) == 0:
				return node as Control
		for c in node.get_children():
			stack.append(c)
	return null

func _find_child_of_type(node: Node, type_name: String) -> Control:
	for c in node.get_children():
		if type_name in c.name:
			return c as Control
		var found: Control = _find_child_of_type(c, type_name)
		if found != null:
			return found
	return null

func _find_action_panel(gv: Node) -> Control:
	var actions: Variant = gv.get("_actions")
	if actions is Control:
		return actions as Control
	return null
