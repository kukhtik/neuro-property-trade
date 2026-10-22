extends RefCounted
## E-5 / D13: ИНВЕНТАРЬ КАРТОЧКИ ИГРОКА.
##
## Обещание приёмки: карточка игрока показывает не только чип «В собственности: N», но и ЧТО
## именно у него — список ЕГО клеток по именам (подсказка карточки), а по отдельному действию
## карточки его клетки подсвечиваются на доске, пока рамки остальных владений глушатся.
##
## Две линзы, как принято в репо:
##   * ПРАВИЛО — `BoardScene.focus_flags()`: арифметика подсветки, падает с индексом клетки;
##   * ЖИВОЙ ВИДЖЕТ — настоящие PlayersPanel и настоящий BoardScene (40 настоящих TileView):
##     правило может быть верным, а кисть молчать — это и проверяем.
##
## Негативная проверка (правило плана: новый чек обязан краснеть на возврате дефекта):
## убери строки инвентаря из `_inventory_text()` — падают test_inventory_lists_every_owned_tile
## и test_inventory_carries_money_jail_and_suffixes; убери кольцо из tile_view — падает
## test_board_focus_marks_exactly_his_tiles.

const I18n := preload("res://i18n/i18n.gd")
const UiTheme := preload("res://ui/theme.gd")
const PlayersPanel := preload("res://ui/players_panel.gd")
const TileView := preload("res://visual/tile_view.gd")
const BoardScene := preload("res://visual/board_scene.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

## Цвет места для фикстуры: он же `owner_color` клеток, поэтому «кольцо цвета игрока» проверяемо.
const SEAT_COL := Color(0.85, 0.35, 0.20)
## Клетки игрока 1 в фикстуре: brown (2 дома), amber (в залоге), станция (без группы).
const MINE := [1, 3, 5]
## Клетка СОПЕРНИКА (индекс 2) и свободная (индекс -1): по ним проверяется, что чужое не светится.
const RIVAL_TILE := 8
const FREE_TILE := 9


static func test_list() -> Array[String]:
	return [
		"test_inventory_lists_every_owned_tile",
		"test_inventory_carries_money_jail_and_suffixes",
		"test_inventory_swatches_carry_the_group_colour",
		"test_jail_cards_are_shown_only_when_the_key_exists",
		"test_card_action_is_separate_from_the_door",
		"test_focus_rule_marks_exactly_his_tiles",
		"test_board_focus_marks_exactly_his_tiles",
		"test_board_focus_clears_and_restores_owner_frames",
	]


## --- фикстура ---------------------------------------------------------------------------------

class Seat:
	var pid := 0
	var name := "Seat"
	var color := Color(0.5, 0.5, 0.5)
	var input_driver := "LOCAL"


static func _seats() -> Array:
	var out: Array = []
	for i in 3:
		var s := Seat.new()
		s.pid = i
		s.name = ["Host", "Tester", "Rival"][i]
		s.color = SEAT_COL if i == 1 else Color(0.4, 0.5, 0.8)
		out.append(s)
	return out


## Доска фикстуры: три клетки игрока 1 (дома/залог/без группы), клетка соперника и свободная.
static func _board() -> Array:
	return [
		{"index": 1, "name": "Nova Terrace", "group": "brown", "owner": 1, "houses": 2, "mortgaged": false},
		{"index": 3, "name": "Palm Row", "group": "amber", "owner": 1, "houses": 0, "mortgaged": true},
		{"index": 5, "name": "Harbor Station", "group": "", "owner": 1, "houses": 0, "mortgaged": false},
		{"index": RIVAL_TILE, "name": "Rival Lot", "group": "brown", "owner": 2, "houses": 1, "mortgaged": false},
		{"index": FREE_TILE, "name": "Free Lot", "group": "amber", "owner": -1, "houses": 0, "mortgaged": false},
	]


## `with_cards` = проекция СВОЕГО места (`for_player`): только она несёт `get_out_of_jail_cards`.
## Зрительская проекция этого ключа не имеет вовсе - и карточка обязана промолчать, а не напечатать
## «карты выхода: 0».
static func _players(with_cards: bool) -> Array:
	var p0 := {"index": 0, "name": "Host", "money": 900, "position": 0, "in_jail": false,
		"jail_turns": 0, "bankrupt": false, "tiles": [], "houses": 0, "mortgaged": 0}
	var p1 := {"index": 1, "name": "Tester", "money": 1350, "position": 5, "in_jail": true,
		"jail_turns": 2, "bankrupt": false, "tiles": MINE.duplicate(), "houses": 2, "mortgaged": 1}
	if with_cards:
		p1["get_out_of_jail_cards"] = 1
	var p2 := {"index": 2, "name": "Rival", "money": 300, "position": RIVAL_TILE, "in_jail": false,
		"jail_turns": 0, "bankrupt": false, "tiles": [RIVAL_TILE], "houses": 1, "mortgaged": 0}
	return [p0, p1, p2]


static func _proj(with_cards: bool = true) -> Dictionary:
	return {
		"round": 4, "parking_pot": 120, "turn_player": 0, "phase": "TURN_START",
		"board": _board(), "players": _players(with_cards),
	}


static func _panel(with_cards: bool = true) -> Control:
	I18n.set_locale("ru")
	var pp: Control = PlayersPanel.new()
	pp.sync(_proj(with_cards), _seats())
	return pp


static func _card(pp: Control, pid: int) -> Control:
	return pp.find_child("seat-card-%d" % pid, true, false)


static func _skin() -> SkinManager:
	var s := SkinManager.new()
	s.load_skin()
	return s


static func _real_board() -> Control:
	# Тот же порядок, каким доску поднимает проба/тест аукциона: без размера `_layout` выходит
	# рано и клеток нет, поэтому размер ставится ДО явного прохода раскладки.
	var b: Control = BoardScene.new()
	b.size = Vector2(1440, 900)
	b.call("_load_board")
	b.call("_build_centre")
	b.call("_layout")
	return b


## --- 1-4: инвентарь в подсказке карточки -------------------------------------------------------

static func test_inventory_lists_every_owned_tile() -> String:
	# ЯДРО ОБЕЩАНИЯ: список ЕГО клеток ИМЕНАМИ. Чип «В собственности: 3» отвечал на «сколько» и
	# молчал про «какие» - зрителю приходилось щёлкать по каждой клетке доски.
	var pp := _panel(true)
	var card := _card(pp, 1)
	if card == null:
		pp.free()
		return "в панели нет карточки игрока 1 (`seat-card-1`)"
	var tip := str(card.tooltip_text)
	for nm in ["Nova Terrace", "Palm Row", "Harbor Station"]:
		if tip.find(nm) < 0:
			pp.free()
			return "подсказка карточки не называет клетку `%s`; в ней: %s" % [nm, tip.replace("\n", " | ")]
	pp.free()
	return ""


static func test_inventory_carries_money_jail_and_suffixes() -> String:
	# Деньги, тюрьма и суффиксы домов/залога: без них список имён - не инвентарь, а оглавление.
	var pp := _panel(true)
	var card := _card(pp, 1)
	if card == null:
		pp.free()
		return "в панели нет карточки игрока 1"
	var tip := str(card.tooltip_text)
	var want := [
		["$1350", "деньги"],
		[I18n.t("plr.inv_jail", [2]), "состояние тюрьмы"],
		[I18n.t("plr.inv_houses", [2]), "дома на клетке"],
		[I18n.t("plr.inv_mortgaged"), "залог клетки"],
	]
	for pair in want:
		if tip.find(str(pair[0])) < 0:
			pp.free()
			return "подсказка не несёт %s (`%s`); в ней: %s" % [pair[1], pair[0], tip.replace("\n", " | ")]
	pp.free()
	return ""


static func test_inventory_swatches_carry_the_group_colour() -> String:
	# ЦВЕТ ГРУППЫ - это цвет, а не слово: подсказка цвет рисовать не умеет, поэтому карточка несёт
	# полоску образцов, и образец обязан совпасть с цветом группы из АКТИВНОГО скина.
	var pp := _panel(true)
	var row := pp.find_child("inv-row", true, false)
	if row == null:
		pp.free()
		return "в карточке нет полоски образцов инвентаря (`inv-row`)"
	if row.get_child_count() != MINE.size():
		pp.free()
		return "образцов %d, а клеток у игрока %d" % [row.get_child_count(), MINE.size()]
	var skin := _skin()
	for idx in MINE:
		var sw := row.find_child("inv-swatch-%d" % idx, true, false)
		if sw == null or not (sw is ColorRect):
			pp.free()
			return "нет образца для клетки %d" % idx
		var group := ""
		for t in _board():
			if int(t["index"]) == idx:
				group = str(t["group"])
		var want: Color = skin.group_color(group) if group != "" else UiTheme.COL().border
		if not (sw as ColorRect).color.is_equal_approx(want):
			pp.free()
			return ("образец клетки %d носит %s, а группа `%s` в скине - %s" % [
				idx, (sw as ColorRect).color.to_html(false), group, want.to_html(false)])
	pp.free()
	return ""


static func test_jail_cards_are_shown_only_when_the_key_exists() -> String:
	# Карты тюрьмы есть ТОЛЬКО в проекции своего места. У зрительской проекции ключа нет, и строка
	# обязана исчезнуть ЦЕЛИКОМ: «карты выхода: 0» читалось бы как факт «карт нет».
	var pp_mine := _panel(true)
	var card_mine := _card(pp_mine, 1)
	if card_mine == null:
		pp_mine.free()
		return "в панели нет карточки игрока 1"
	var with_key := str(card_mine.tooltip_text)
	if with_key.find(I18n.t("plr.inv_cards", [1])) < 0:
		pp_mine.free()
		return "ключ `get_out_of_jail_cards` есть, а строки карт нет: %s" % with_key.replace("\n", " | ")
	pp_mine.free()
	var pp_view := _panel(false)
	var card_view := _card(pp_view, 1)
	if card_view == null:
		pp_view.free()
		return "в зрительской панели нет карточки игрока 1"
	var without_key := str(card_view.tooltip_text)
	if without_key.find("карты выхода") >= 0:
		pp_view.free()
		return "у зрительской проекции нет ключа, а карточка всё равно пишет карты: %s" % without_key.replace("\n", " | ")
	pp_view.free()
	return ""


## --- 5: действие карточки не ломает дверь ------------------------------------------------------

static func test_card_action_is_separate_from_the_door() -> String:
	# Карточка в кольце - ДВЕРЬ в drawer-seats (press уходит наверх). Выделение клеток обязано
	# приходить ОТДЕЛЬНЫМ действием, иначе одно нажатие делало бы две вещи и дверь сломалась бы.
	var pp := _panel(true)
	var card := _card(pp, 1)
	if card == null:
		pp.free()
		return "в панели нет карточки игрока 1"
	if card.mouse_filter != Control.MOUSE_FILTER_PASS:
		pp.free()
		return "карточка перестала пропускать нажатие (mouse_filter=%d) - дверь в ящик сломана" % card.mouse_filter
	var btn := card.find_child("inv-focus-1", true, false)
	if btn == null or not (btn is Button):
		pp.free()
		return "в карточке нет отдельной кнопки инвентаря (`inv-focus-1`)"
	if (btn as Control).mouse_filter != Control.MOUSE_FILTER_STOP:
		pp.free()
		return "кнопка инвентаря пропускает нажатие дальше: она не может быть отдельным действием"
	var got: Array = []
	# По ИМЕНИ сигнала: `pp` объявлен как Control, и типизированный доступ к сигналу панели
	# здесь невозможен - а имя сигнала и есть контракт, который проверяет эта строка.
	pp.connect("player_tiles_requested", func(pid: int) -> void: got.append(pid))
	(btn as Button).pressed.emit()
	if got.size() != 1 or int(got[0]) != 1:
		pp.free()
		return "нажатие кнопки не попросило клетки игрока 1: %s" % str(got)
	# оболочка (game_view) отвечает на сигнал вызовом focus_player - здесь это и проверяем:
	# панель обязана ЗАПОМНИТЬ выбор, чтобы кольцо на карточке пережило перерисовку (sync)
	pp.call("focus_player", 1)
	if int(pp.call("focused_player")) != 1:
		pp.free()
		return "карточка не запомнила выбор игрока (focused=%d)" % int(pp.call("focused_player"))
	pp.call("focus_player", 1)
	if int(pp.call("focused_player")) != -1:
		pp.free()
		return "повторное действие не снимает выделение (focused=%d)" % int(pp.call("focused_player"))
	pp.free()
	return ""


## --- 6: правило подсветки ----------------------------------------------------------------------

static func test_focus_rule_marks_exactly_his_tiles() -> String:
	# ПРАВИЛО: свои клетки - кольцо, чужие и свободные - нет; при активном выборе рамка владения
	# глушится у ВСЕХ. Арифметика, поэтому проверяется отдельно от кисти.
	for pid in [1, 2, 0]:
		for owner in [0, 1, 2, -1]:
			var fl: Dictionary = BoardScene.focus_flags(owner, pid)
			var want: bool = owner == pid
			if bool(fl["owner_focus"]) != want:
				return "при выборе игрока %d клетка владельца %d получила owner_focus=%s" % [
					pid, owner, str(fl["owner_focus"])]
			if not bool(fl["owner_muted"]):
				return "при выборе игрока %d рамка владения не глушится (owner %d)" % [pid, owner]
	var none: Dictionary = BoardScene.focus_flags(1, -1)
	if bool(none["owner_focus"]) or bool(none["owner_muted"]):
		return "без выбора правило всё равно подсвечивает/глушит: %s" % str(none)
	return ""


## --- 7-8: живая доска (40 настоящих TileView) --------------------------------------------------

static func test_board_focus_marks_exactly_his_tiles() -> String:
	# ЖИВОЙ ВИДЖЕТ. Правило выше может быть верным, а `apply()` - не рисовать кольцо; поэтому
	# спрашиваем САМУ доску и САМУ клетку (`state_frame()`), а не пересчитываем её правила.
	I18n.set_locale("ru")
	var b := _real_board()
	var tiles: Array = b.get("_tiles")
	if tiles.size() != 40:
		b.free()
		return "доска не собралась: %d клеток вместо 40" % tiles.size()
	b.sync(_proj(true), _seats(), 0)
	b.call("set_owner_focus", 1)
	var ringed: Array = []
	var intruders: Array = []
	for i in tiles.size():
		var sf: Dictionary = (tiles[i] as Control).state_frame()
		var owner: int = int(((b.get("_entries") as Dictionary).get(i, {}) as Dictionary).get("owner", -1))
		if int(sf["width"]) == 3 and bool(sf["visible"]):
			ringed.append(i)
			if not (sf["color"] as Color).is_equal_approx(SEAT_COL):
				b.free()
				return "кольцо клетки %d не цвета игрока: %s" % [i, (sf["color"] as Color).to_html(false)]
		elif owner >= 0 and bool(sf["visible"]) and int(sf["width"]) == 2:
			intruders.append(i)
	b.free()
	ringed.sort()
	if ringed != MINE.duplicate():
		return "кольцо стоит на клетках %s, а у игрока 1 - %s" % [str(ringed), str(MINE)]
	if not intruders.is_empty():
		return "при выделении игрока 1 рамки владения остались на клетках %s (чужие должны глушиться)" % str(intruders)
	return ""


static func test_board_focus_clears_and_restores_owner_frames() -> String:
	# ВЫКЛЮЧАТЕЛЬ. Выбор обязан сниматься, а рамки владения - возвращаться: подсветка без выхода
	# оставляет доску навсегда перекрашенной, и «где его клетки» перестаёт быть ответом на вопрос.
	I18n.set_locale("ru")
	var b := _real_board()
	var tiles: Array = b.get("_tiles")
	if tiles.size() != 40:
		b.free()
		return "доска не собралась: %d клеток вместо 40" % tiles.size()
	b.sync(_proj(true), _seats(), 0)
	b.call("set_owner_focus", 1)
	var rival: Control = tiles[RIVAL_TILE]
	var muted: Dictionary = rival.state_frame()
	if bool(muted["visible"]):
		b.free()
		return "при выделении игрока 1 клетка соперника (%d) всё ещё носит рамку владения" % RIVAL_TILE
	b.call("set_owner_focus", -1)
	var back: Dictionary = rival.state_frame()
	if not bool(back["visible"]) or int(back["width"]) != 2:
		b.free()
		return "после снятия выделения рамка владения клетки %d не вернулась: %s" % [RIVAL_TILE, str(back)]
	var mine_after: Dictionary = (tiles[1] as Control).state_frame()
	if int(mine_after["width"]) == 3:
		b.free()
		return "кольцо игрока 1 осталось после снятия выделения"
	b.free()
	return ""
