extends PanelContainer
## The left dock (`#seats`): the player list, the stats strip and the ownership bar.
## v3 rebuild from the prototype markup; reads the spectator projection + seat list.
##
## 21.10: THE CARDS LIVE IN THE RING. The panno's players zone hosts this panel
## (`turn_panno.players_slot`), so the four seats are laid out as a WRAPPING ROW of cards -
## concept A's ".players 4 колонки карточками" - and `set_embedded(true)` drops the panel's
## own title row because the zone already carries the caption. The same panel is also what
## `drawer-seats` shows, where the row wraps down to one card per line.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
## VOICE-01 «кто говорит»: индикатор в карточке места.
const VoiceLed := preload("res://ui/voice_led.gd")

## E-5 / D13: карточка — не только дверь в `drawer-seats`. Отдельное действие на ней (кнопка
## «КЛЕТКИ») просит ВЫДЕЛИТЬ клетки этого игрока на доске. Это событие, а не побочный эффект
## нажатия: сама карточка остаётся дверью (press уходит наверх, в зону панно), иначе обычный
## клик перестал бы открывать ящик — ровно то поведение, которое просили сохранить.
signal player_tiles_requested(pid: int)

## The narrowest a seat card may be. In the ring's upper belt (1171px wide at 1600x1200) four
## cards sit side by side; in a 320px drawer the flow wraps to one per line. Without a floor the
## cards shrink to their text and the band reads as four strips.
const CARD_MIN_W := 210.0

var _title: Label
var _head: HBoxContainer
var _count: Label
var _list: HFlowContainer
var _stats: HBoxContainer
var _own_track: HBoxContainer
var _own_legend: HBoxContainer
var _skin: SkinManager
var _embedded := false
## E-5: чей инвентарь сейчас подсвечен на доске (-1 = никто). Живёт здесь, а не в доске, потому
## что подсветку заказывает КАРТОЧКА, и после перерисовки (sync) карточки должны помнить выбор.
var _focus_pid := -1
## last sync() state - a locale switch re-renders the cards from it (SG-08)
var _last_proj: Dictionary = {}
var _last_seats: Array = []
## VOICE-01: источники голоса по местам (pid -> источник) и ПОМЯТЬ их состояния. Источник
## подставляет снаружи оболочка (`set_voice_source`): живой сервер голоса — не наша забота, а
## индикатор «кто говорит» — наша. Память нужна потому, что карточки пересобираются на каждой
## проекции: без неё `voice_unavailable` «воскресал» бы вместе с новой карточкой.
var _voice_sources: Dictionary = {}
var _voice_state: Dictionary = {}
## Ключ источника, который ещё не назвал место (-1): он говорит за SDK-место матча.
const VOICE_AUTO_KEY := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 12)
	add_child(m)
	var col := UiTheme.vbox(8)
	m.add_child(col)

	_head = UiTheme.hbox(8)
	_title = UiTheme.label(I18n.t("ui.players"), UiTheme.skin().size("s", 13), UiTheme.COL().text_dim)
	_head.add_child(_title)
	_count = UiTheme.label("", UiTheme.skin().size("xs", 11), UiTheme.COL().text_dim)
	_head.add_child(_count)
	col.add_child(_head)

	# HFlowContainer, not VBox: the four seats are a ROW when the host is the ring's wide upper
	# belt and a COLUMN when it is the 320px drawer - the flow container is the one widget that
	# answers both without a second layout mode to keep in sync.
	_list = HFlowContainer.new()
	_list.name = "seat-cards"
	_list.add_theme_constant_override("h_separation", 6)
	_list.add_theme_constant_override("v_separation", 4)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_list)
	_stats = UiTheme.hbox(4)
	col.add_child(_stats)

	var own := UiTheme.vbox(4)
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().bg, UiTheme.COL().border, 1, 0))
	track.custom_minimum_size.y = 8
	_own_track = UiTheme.hbox(0)
	_own_track.name = "ownbar"
	track.add_child(_own_track)
	own.add_child(track)
	_own_legend = UiTheme.hbox(0)
	own.add_child(_own_legend)
	col.add_child(own)


## EMBEDDED IN THE RING. The panno's players zone carries the caption "Игроки" already, so the
## panel drops its OWN title row there: two headings over one row of cards is a duplicate, not a
## hierarchy. Everything else stays - the cards, the round/pot strip, the ownership bar - because
## those are facts the ring does not otherwise show.
func set_embedded(on: bool) -> void:
	_embedded = on
	if _head != null:
		_head.visible = not on


## VOICE-01 «КТО ГОВОРИТ»: подставить источник голоса. Источник — любой объект с сигналами
## вендорённого модуля (`speaking_changed(bool)`, `speech_cancelled()`, `voice_unavailable(String)`,
## `voice_ready()`); `voice_led.gd` терпим к отсутствию любого из них, а к живому серверу не
## привязан вовсе — поэтому подставляется снаружи и измеряется headless (как `FakeRemote` у HG-12).
##
## `pid` — место, за которое говорит источник. `pid < 0` означает «источник не назвал место»:
## сначала спрашиваем его самого (`source.pid`), иначе это голос SDK-места матча (место водителя
## `SDK`), и место ищется по водителю на ближайшем `sync`.
func set_voice_source(source: Object, pid: int = -1) -> void:
	var key := pid
	if key < 0 and source != null:
		var own = source.get("pid")
		if own != null:
			key = int(own)
	_voice_sources[key] = source
	if not _voice_state.has(key):
		_voice_state[key] = {"lit": false, "available": true}
	# ПАНЕЛЬ слушает источник САМА, а не только через индикатор. Причина: индикатор
	# привязывается к источнику при СОЗДАНИИ карточки, а `voice_unavailable` (сервера
	# голоса нет) приходит сразу при старте канала - то есть ДО первой карточки. Если бы
	# слушал только индикатор, деградация молча пролетела бы мимо: подсказка молчала бы
	# «голос недоступен», а индикатор - залипал бы в состоянии «доступен».
	_bind_source_state(key, source)
	# перерисовать карточки, если состояние уже есть: источник может прийти и после первого sync
	if not _last_proj.is_empty():
		sync(_last_proj, _last_seats)


## VOICE-01: панель помнит состояние источника сама (индикатор может ещё не существовать).
func _bind_source_state(key: int, source: Object) -> void:
	if source == null or not is_instance_valid(source):
		return
	if not source.has_signal("voice_unavailable"):
		return
	if not source.is_connected("voice_unavailable", _on_source_unavailable):
		source.connect("voice_unavailable", _on_source_unavailable)
	if source.has_signal("voice_ready") and not source.is_connected("voice_ready", _on_source_ready):
		source.connect("voice_ready", _on_source_ready)


func _on_source_unavailable(_reason: String) -> void:
	for key in _voice_sources:
		_voice_state[key] = {"lit": false, "available": false}
	if not _last_proj.is_empty():
		sync(_last_proj, _last_seats)


func _on_source_ready() -> void:
	for key in _voice_sources:
		var st: Dictionary = _voice_state.get(key, {"lit": false, "available": true})
		st["available"] = true
		_voice_state[key] = st
	if not _last_proj.is_empty():
		sync(_last_proj, _last_seats)


## Место голоса, если источник его не назвал: это место с водителем `SDK`.
func _sdk_pid(seats: Array) -> int:
	for s in seats:
		if str(s.input_driver) == "SDK":
			return int(s.pid)
	return -1


## Ключ `-1` («место неизвестно») превращается в настоящее место SDK-места матча. Делается здесь,
## а не при подстановке источника: список мест приходит вместе с проекцией.
func _resolve_auto_voice(seats: Array) -> void:
	if not _voice_sources.has(VOICE_AUTO_KEY):
		return
	var pid := _sdk_pid(seats)
	if pid < 0:
		return
	if not _voice_sources.has(pid):
		_voice_sources[pid] = _voice_sources[VOICE_AUTO_KEY]
		_voice_state[pid] = _voice_state.get(VOICE_AUTO_KEY, {"lit": false, "available": true})
	_voice_sources.erase(VOICE_AUTO_KEY)
	_voice_state.erase(VOICE_AUTO_KEY)


## Индикатор сообщил своё состояние — панель его ПОМНИТ (карточки пересобираются на каждой
## проекции; «голос недоступен» не имеет права исчезнуть вместе со старой карточкой).
func _on_led_state(seat_pid: int, lit: bool, available: bool) -> void:
	_voice_state[seat_pid] = {"lit": lit, "available": available}


## Update from the projection. `seats` carries pid/name/colour/input_driver.
func sync(proj: Dictionary, seats: Array) -> void:
	_last_proj = proj
	_last_seats = seats
	# VOICE-01: источник без своего места привязывается к SDK-месту матча (голос Neuro говорит
	# именно за него) — ДО раскладки карточек, иначе привязывать было бы не к чему.
	_resolve_auto_voice(seats)
	var players: Array = proj.get("players", [])
	_count.text = str(players.size())
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	# tile names for "pos" lines
	var names := {}
	# E-5: инвентарь карточки строится из ПРОЕКЦИИ (имя, группа, дома, залог клетки), поэтому
	# рядом с именами держим сами записи доски, а не только имена.
	var by_index := {}
	for t in (proj.get("board", []) as Array):
		names[int(t.get("index", -1))] = str(t.get("name", ""))
		by_index[int(t.get("index", -1))] = t
	# rebuild the cards (small n — plain rebuilds are fine and always correct)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for p in players:
		_list.add_child(_card(p, seats, turn, names, by_index))
	_refresh_stats(proj, players)
	_refresh_ownbar(players, seats)


func _card(p: Dictionary, seats: Array, turn: int, names: Dictionary, by_index: Dictionary = {}) -> Control:
	var pid: int = int(p.get("index", 0))
	var name := str(p.get("name", "P%d" % pid))
	var col: Color = UiTheme.COL().accent
	var driver := ""
	# VOICE-01: идентичность говорящего — `driver_label` места (то же «сырое назначение», что
	# печатает строка позиции). Пустое значение — не беда: зовём по водителю.
	var driver_label := ""
	for s in seats:
		if int(s.pid) == pid:
			col = s.color
			driver = str(s.input_driver)
			var dl = s.get("driver_label")
			driver_label = str(dl) if dl != null else ""
	var card := PanelContainer.new()
	# E-5: карточка называет себя — по этому имени её находит гейт/тест, а не «третий ребёнок
	# списка» (позиция ломается от любого нового чипа).
	card.name = "seat-card-%d" % pid
	var active: bool = pid == turn
	var focused: bool = pid == _focus_pid
	# E-5: выбранная карточка носит кольцо ЦВЕТА СВОЕГО ИГРОКА (3px), как кольцо на его клетках:
	# связка «карточка ↔ доска» читается одним взглядом. Активный ход важнее выбора — при active
	# кольцо остаётся от хода, иначе два факта спорили бы за одну рамку.
	var border_col: Color = col if active else UiTheme.COL().border
	var border_w: int = 2 if active else 1
	if focused and not active:
		border_col = col
		border_w = 3
	# R-2 / D5: the cards DISTRIBUTE over the host's room instead of stacking at the top and
	# leaving ~555px of dead space under them; a viewer read that as "the panel is broken".
	# In the ring they share the upper belt WIDTH instead (four across), which is why the floor
	# is a width and the flow container wraps a narrow host back into a column.
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = CARD_MIN_W
	# The ring's players zone is a DOOR (a click opens `drawer-seats`). A card that swallowed the
	# press would leave only the band's 20px caption clickable, so the press is passed up to the
	# panno's zone column instead of being eaten here.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	# E-5: ПОДСКАЗКА КАРТОЧКИ - это и есть инвентарь: все клетки игрока по именам, с домами и
	# залогом, плюс деньги, тюрьма и карты выхода. До этого карточка умела только счётчик.
	card.tooltip_text = _inventory_text(p, by_index)
	card.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark if active else UiTheme.COL().panel,
			border_col, border_w, 0))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 8)
	card.add_child(m)
	var col_box := UiTheme.vbox(2)
	# a card taller than its four lines centres them instead of hugging the top edge (the belt is
	# 326px at 1600x1200 - a top-aligned card would be half empty inside its own border)
	col_box.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(col_box)
	var row1 := UiTheme.hbox(8)
	var av := Panel.new()
	av.custom_minimum_size = Vector2(30, 30)
	av.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), col, 2, 15))
	row1.add_child(av)
	var nm := UiTheme.label(name, 13, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	row1.add_child(nm)
	var money := UiTheme.label(MoneyFmt.make("$").amount(int(p.get("money", 0))), 13, UiTheme.COL().money)
	money.clip_text = true
	row1.add_child(money)
	col_box.add_child(row1)
	# position line
	var pos: int = int(p.get("position", 0))
	var pos_lbl := UiTheme.label("%s · %s" % [str(names.get(pos, "?")), driver], 11, UiTheme.COL().text_dim)
	pos_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pos_lbl.clip_text = true
	col_box.add_child(pos_lbl)
	# VOICE-01 «КТО ГОВОРИТ». Индикатор есть в КАЖДОЙ карточке, но занимает ноль пикселей, пока
	# никто не говорит: точка и подпись скрыты. Источник подставляет оболочка (`set_voice_source`);
	# если для этого места источника нет, индикатор просто молчит — карточка выглядит как раньше.
	var led := VoiceLed.new()
	led.name = "voice-led-%d" % pid
	led.call("setup", pid, driver_label if driver_label != "" else driver)
	var remembered: Dictionary = _voice_state.get(pid, {})
	if not remembered.is_empty():
		led.call("seed", bool(remembered.get("lit", false)), bool(remembered.get("available", true)))
	var src: Object = _voice_sources.get(pid)
	if src != null:
		led.call("bind", src)
	led.connect("state_changed", Callable(self, "_on_led_state"))
	col_box.add_child(led)
	if not bool(led.call("is_available")):
		# ТИХАЯ ДЕГРАДАЦИЯ НАЗВАНА ЧЕЛОВЕЧЕСКИ: индикатор погас, а подсказка карточки говорит,
		# почему голоса нет — без «красного» и без единой строки в консоли.
		card.tooltip_text = "%s\n%s" % [card.tooltip_text, I18n.t("voice.unavailable")]
	# chips: jail / bankrupt / tiles owned
	var chips := UiTheme.hbox(4)
	if bool(p.get("in_jail", false)):
		chips.add_child(_chip(I18n.t("plr.jail"), UiTheme.COL().danger))
	if bool(p.get("bankrupt", false)):
		chips.add_child(_chip(I18n.t("plr.bankrupt"), UiTheme.COL().danger))
	var tiles: Array = p.get("tiles", [])
	if tiles.size() > 0:
		chips.add_child(_chip(I18n.t("plr.owned", [tiles.size()]), col))
	# E-5: ОТДЕЛЬНОЕ ДЕЙСТВИЕ карточки. Кнопка ест только СВОЁ нажатие (MOUSE_FILTER_STOP), так что
	# клик по остальной карточке по-прежнему уходит наверх, в зону панно, и открывает drawer-seats.
	# Это и есть требование: выделение не отменяет дверь, а живёт рядом с ней.
	var focus_btn := Button.new()
	focus_btn.name = "inv-focus-%d" % pid
	focus_btn.text = I18n.t("plr.inv_show")
	focus_btn.tooltip_text = I18n.t("plr.inv_tip", [name])
	focus_btn.focus_mode = Control.FOCUS_NONE
	focus_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	focus_btn.add_theme_font_size_override("font_size", UiTheme.skin().size("xs", 11))
	focus_btn.add_theme_color_override("font_color", col)
	for st in ["normal", "hover", "pressed"]:
		focus_btn.add_theme_stylebox_override(st, UiTheme.box(
			UiTheme.COL().panel_dark if st == "hover" else UiTheme.COL().panel,
			col, 1, 2, 4.0))
	focus_btn.pressed.connect(func() -> void: player_tiles_requested.emit(pid))
	chips.add_child(focus_btn)
	col_box.add_child(chips)
	# E-5: полоска ОБРАЗЦОВ - цвет группы это ЦВЕТ, а не слово. Один 7x7 образец на клетку,
	# поток (HFlow) переносит длинный инвентарь внутрь узкой карточки, поэтому карточка в поясе
	# кольца не растягивается на 20 клеток в ряд.
	var inv := _inventory_row(p, by_index)
	if inv.get_child_count() > 0:
		col_box.add_child(inv)
	return card


## E-5 / D13: ИНВЕНТАРЬ по именам. До этого карточка умела только чип «В собственности: N» —
## количество без списка, и зритель не мог узнать, ЧТО собрал человек, не щёлкая по каждой клетке.
##
## Почему текстом в подсказке, а не строками в карточке: пояс кольца тесный, а 10 строк отняли бы
## место у доски. Цвет группы остаётся В ВИДЖЕТЕ (полоска `_inventory_row`), здесь он назван
## токеном — ровно так его показывает инспектор клетки, и новых `group.*` ключей это не требует.
func _inventory_text(p: Dictionary, by_index: Dictionary) -> String:
	var lines: Array = []
	lines.append(I18n.t("plr.inv_head", [str(p.get("name", "")), int(p.get("money", 0))]))
	if bool(p.get("in_jail", false)):
		lines.append(I18n.t("plr.inv_jail", [int(p.get("jail_turns", 0))]))
	# КАРТЫ ТЮРЬМЫ есть ТОЛЬКО в проекции своего места (`for_player`): у зрительской их нет.
	# Ключа нет - строки нет: тихо, без пустого «карты: 0», которое читалось бы как «ноль карт».
	if p.has("get_out_of_jail_cards"):
		lines.append(I18n.t("plr.inv_cards", [int(p.get("get_out_of_jail_cards", 0))]))
	var tiles: Array = (p.get("tiles", []) as Array).duplicate()
	tiles.sort()
	lines.append(I18n.t("plr.inv_count", [tiles.size()]))
	if tiles.is_empty():
		lines.append("· " + I18n.t("plr.inv_none"))
	# E-5: каждая клетка - своей строкой, по возрастанию индекса (порядок доски читается)
	for idx in tiles:
		lines.append("· " + _inventory_line(int(idx), by_index))
	return "\n".join(lines)


## Одна клетка инвентаря: имя из `proj.board[].name`, токен группы, дома, залог.
func _inventory_line(idx: int, by_index: Dictionary) -> String:
	var t: Dictionary = by_index.get(idx, {})
	var parts: Array = [str(t.get("name", "#%d" % idx))]
	var group := str(t.get("group", ""))
	if group != "":
		parts.append(group)
	var houses: int = int(t.get("houses", 0))
	if houses > 0:
		parts.append(I18n.t("plr.inv_houses", [houses]))
	if bool(t.get("mortgaged", false)):
		parts.append(I18n.t("plr.inv_mortgaged"))
	return " · ".join(parts)


## Полоска образцов цвета группы: одна клетка игрока - один образец, с именем в подсказке.
func _inventory_row(p: Dictionary, by_index: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.name = "inv-row"
	row.add_theme_constant_override("h_separation", 3)
	row.add_theme_constant_override("v_separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tiles: Array = (p.get("tiles", []) as Array).duplicate()
	tiles.sort()
	for idx in tiles:
		var t: Dictionary = by_index.get(int(idx), {})
		var sw := ColorRect.new()
		sw.name = "inv-swatch-%d" % int(idx)
		sw.custom_minimum_size = Vector2(7, 7)
		sw.color = _tile_color(t)
		sw.tooltip_text = str(t.get("name", "#%d" % int(idx)))
		# PASS, а не IGNORE: подсказка образца - единственное место, где цвет клетки назван именем
		sw.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(sw)
	return row


## Цвет клетки для образца: свойство - цвет ГРУППЫ из активного скина, всё остальное (старт,
## налог, шанс) берёт роль темы. Литералов цвета здесь нет и быть не должно: палитра живёт
## в скине, а не в карточке.
func _tile_color(t: Dictionary) -> Color:
	var group := str(t.get("group", ""))
	if group != "":
		return UiTheme.skin().group_color(group)
	return UiTheme.COL().border


## E-5: выбрать игрока, чьи клетки светятся на доске. Карточка — источник выбора, доска —
## потребитель (game_view соединяет их сигналом `player_tiles_requested`).
func focus_player(pid: int) -> void:
	if _focus_pid == pid:
		pid = -1     # повторное нажатие снимает выделение: у выбора есть выключатель
	_focus_pid = pid
	if not _last_proj.is_empty():
		sync(_last_proj, _last_seats)


func focused_player() -> int:
	return _focus_pid


func _chip(text: String, col: Color) -> Label:
	var l := UiTheme.label(text, 9, col)
	l.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().panel, col, 1, 2))
	return l


func _refresh_stats(proj: Dictionary, players: Array) -> void:
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var cells := [
		[str(proj.get("round", 1)), I18n.t("stat.round")],
		[str(players.size()), I18n.t("ui.players")],
		# `parking_pot`, not `pot`: the projection has one name for the bank (HG-10)
		["$%d" % int(proj.get("parking_pot", 0)), I18n.t("top.pot")],
	]
	for cell in cells:
		var p := PanelContainer.new()
		# the cells are VALUES: they sit at their content width, and the row's single stretch
		# slot goes to the trailing spacer (P-4: exactly one grower per flex row)
		p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		p.add_theme_stylebox_override("panel",
			UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
		var v := UiTheme.vbox(0)
		var val := UiTheme.label(cell[0], 14, UiTheme.COL().text)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.clip_text = true
		var key := UiTheme.label(cell[1], UiTheme.skin().size("xs", 11), UiTheme.COL().text_dim)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.clip_text = true
		v.add_child(val)
		v.add_child(key)
		p.add_child(v)
		_stats.add_child(p)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.add_child(sp)


func _refresh_ownbar(players: Array, seats: Array) -> void:
	for c in _own_track.get_children():
		_own_track.remove_child(c)
		c.queue_free()
	for c in _own_legend.get_children():
		_own_legend.remove_child(c)
		c.queue_free()
	# total owned across players -> proportional segments
	var total := 0
	for p in players:
		total += (p.get("tiles", []) as Array).size()
	for p in players:
		var pid: int = int(p.get("index", 0))
		var col: Color = UiTheme.COL().accent
		for s in seats:
			if int(s.pid) == pid:
				col = s.color
		var seg := ColorRect.new()
		var n: int = (p.get("tiles", []) as Array).size()
		seg.color = col
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = maxf(0.0001, float(n) / maxf(1.0, float(total)))
		_own_track.add_child(seg)
		var l := UiTheme.label(str(p.get("name", "")), 9, UiTheme.COL().text_dim)
		_own_legend.add_child(l)


func retranslate() -> void:
	_title.text = I18n.t("ui.players")
	# the cards, stats and the ownership bar are state-driven: re-render from the last state
	# so a locale switch mid-match relabels them without waiting for the next event
	if not _last_proj.is_empty():
		sync(_last_proj, _last_seats)
