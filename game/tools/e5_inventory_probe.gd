extends Node
## E-5 PROBE — инвентарь карточки игрока и подсветка ЕГО клеток на доске (D2 / D13).
##
## Обещание приёмки: карточка игрока отдаёт не только чип «В собственности: N», а ЧТО именно у
## человека - список его клеток по именам (подсказка карточки: имя, группа, дома, залог, деньги,
## тюрьма, карты выхода), а отдельное действие карточки выделяет его клетки НА ДОСКЕ: свои
## получают кольцо, рамки владения остальных глушатся.
##
## Проба меряет РЕАЛЬНЫЙ продукт, а не мок: настоящий PlayersPanel, наполненный настоящим sync(),
## и настоящая BoardScene с 40 настоящими TileView, у которых спрашивается их собственная рамка
## состояния (`state_frame()`). Связка «карточка → доска» воспроизводится ровно так, как её
## делает оболочка (`game_view._on_player_tiles_requested`): сигнал карточки → `set_owner_focus`.
##
## Проба НЕ имеет права быть зелёной, ничего не измерив: если проверок меньше пола - это провал
## (гейт, который ничего не измерил, не считается зелёным).
##
## Run: godot --headless --path game res://tools/e5_inventory_probe.tscn
## Verdict: ==> E-5 PASSED (...) / ==> E-5 FAILED: <reason>

const I18n := preload("res://i18n/i18n.gd")
const UiTheme := preload("res://ui/theme.gd")
const PlayersPanel := preload("res://ui/players_panel.gd")
const BoardScene := preload("res://visual/board_scene.gd")

## Цвет места игрока 1: он же `owner_color` его клеток, поэтому «кольцо цвета игрока» измеримо.
const SEAT_COL := Color(0.85, 0.35, 0.20)
const MINE := [1, 3, 5]
const RIVAL_TILE := 8
const FREE_TILE := 9
## Пол проверок: проба, которая оборвалась молча, обязана быть красной, а не пустой.
const MIN_CHECKS := 8

var _fails: Array = []
var _checks := 0


class Seat:
	var pid := 0
	var name := "Seat"
	var color := Color(0.5, 0.5, 0.5)
	var input_driver := "LOCAL"


func _ready() -> void:
	var b: Control = BoardScene.new()
	add_child(b)                      # `_ready` доски строит скин и панно
	b.size = Vector2(1440, 900)       # размер ДО прохода раскладки, иначе клеток не будет
	b.call("_load_board")
	b.call("_layout")
	await get_tree().process_frame
	await get_tree().process_frame
	_run(b)
	_report()


func _run(b: Control) -> void:
	var tiles: Array = b.get("_tiles")
	_check(tiles.size() == 40, "доска не собралась: %d клеток вместо 40" % tiles.size())
	if tiles.size() != 40:
		return
	# доска наполняется той же проекцией, что и карточка: владения и цвет владельца приходят
	# из `proj.board[]` + `seats`, как в живом приложении
	b.sync(_proj(true), _seats(), 0)
	var pp: Control = PlayersPanel.new()
	add_child(pp)
	I18n.set_locale("ru")
	pp.sync(_proj(true), _seats())

	# --- 1: подсказка карточки = инвентарь по именам -------------------------------------------
	var card := pp.find_child("seat-card-1", true, false)
	_check(card != null, "в панели нет карточки игрока 1 (`seat-card-1`)")
	if card == null:
		return
	var tip := str(card.tooltip_text)
	for nm in ["Nova Terrace", "Palm Row", "Harbor Station"]:
		_check(tip.find(nm) >= 0, "подсказка карточки не называет клетку `%s`" % nm)
	_check(tip.find("$1350") >= 0, "подсказка не несёт деньги игрока ($1350)")
	_check(tip.find(I18n.t("plr.inv_jail", [2])) >= 0, "подсказка не несёт состояние тюрьмы")
	_check(tip.find(I18n.t("plr.inv_houses", [2])) >= 0, "подсказка не несёт дома на клетке")
	_check(tip.find(I18n.t("plr.inv_mortgaged")) >= 0, "подсказка не несёт залог клетки")
	_check(tip.find(I18n.t("plr.inv_cards", [1])) >= 0,
		"ключ `get_out_of_jail_cards` есть, а строки карт в подсказке нет")

	# --- 2: цвет группы - цвет, а не слово -----------------------------------------------------
	var row := pp.find_child("inv-row", true, false)
	_check(row != null, "в карточке нет полоски образцов инвентаря (`inv-row`)")
	if row != null:
		_check(row.get_child_count() == MINE.size(),
			"образцов %d, а клеток у игрока %d" % [row.get_child_count(), MINE.size()])
		var skin = UiTheme.skin()
		for idx in MINE:
			var sw = row.find_child("inv-swatch-%d" % idx, true, false)
			_check(sw != null and sw is ColorRect, "нет образца цвета для клетки %d" % idx)
			if sw == null or not (sw is ColorRect):
				continue
			var group := ""
			for t in _board():
				if int(t["index"]) == idx:
					group = str(t["group"])
			var want: Color = skin.group_color(group) if group != "" else UiTheme.COL().border
			_check((sw as ColorRect).color.is_equal_approx(want),
				"образец клетки %d носит %s, группа `%s` в скине - %s" % [
					idx, (sw as ColorRect).color.to_html(false), group, want.to_html(false)])

	# --- 3: у зрительской проекции карт нет - и карточка молчит --------------------------------
	I18n.set_locale("ru")
	pp.sync(_proj(false), _seats())
	var view_tip := str((pp.find_child("seat-card-1", true, false) as Control).tooltip_text)
	_check(view_tip.find("карты выхода") < 0,
		"в зрительской проекции ключа нет, а карточка пишет карты: %s" % view_tip.replace("\n", " | "))

	# --- 4: второй язык ------------------------------------------------------------------------
	I18n.set_locale("en")
	pp.sync(_proj(true), _seats())
	var en_tip := str((pp.find_child("seat-card-1", true, false) as Control).tooltip_text)
	_check(en_tip.find("Nova Terrace") >= 0 and en_tip.find(I18n.t("plr.inv_jail", [2])) >= 0,
		"в EN подсказка потеряла имя клетки или состояние тюрьмы: %s" % en_tip.replace("\n", " | "))
	I18n.set_locale("ru")
	pp.sync(_proj(true), _seats())

	# --- 5: дверь не сломана, действие - отдельное ---------------------------------------------
	card = pp.find_child("seat-card-1", true, false)
	_check((card as Control).mouse_filter == Control.MOUSE_FILTER_PASS,
		"карточка перестала пропускать нажатие - дверь в drawer-seats сломана")
	var btn := card.find_child("inv-focus-1", true, false)
	_check(btn != null and btn is Button, "в карточке нет отдельной кнопки инвентаря (`inv-focus-1`)")
	if btn == null:
		return
	_check((btn as Control).mouse_filter == Control.MOUSE_FILTER_STOP,
		"кнопка инвентаря пропускает нажатие дальше: отдельным действием она быть не может")
	# связка как в оболочке: сигнал карточки -> выбор на доске
	var asked: Array = []
	pp.connect("player_tiles_requested", func(pid: int) -> void: asked.append(pid))
	pp.connect("player_tiles_requested", func(pid: int) -> void: b.call("set_owner_focus", pid))
	(btn as Button).pressed.emit()
	_check(asked.size() == 1 and int(asked[0]) == 1,
		"нажатие кнопки не попросило клетки игрока 1: %s" % str(asked))

	# --- 6: на доске светятся РОВНО его клетки, чужие рамки глушатся ---------------------------
	var ringed: Array = []
	var stray: Array = []
	for i in tiles.size():
		var sf: Dictionary = (tiles[i] as Control).state_frame()
		var owner: int = int(((b.get("_entries") as Dictionary).get(i, {}) as Dictionary).get("owner", -1))
		if bool(sf["visible"]) and int(sf["width"]) == 3:
			ringed.append(i)
			if not (sf["color"] as Color).is_equal_approx(SEAT_COL):
				_fail("кольцо клетки %d не цвета игрока (%s)" % [i, (sf["color"] as Color).to_html(false)])
		elif owner >= 0 and bool(sf["visible"]) and int(sf["width"]) == 2:
			stray.append(i)
	ringed.sort()
	_check(ringed == MINE.duplicate(),
		"кольцо стоит на клетках %s, а у игрока 1 - %s" % [str(ringed), str(MINE)])
	_check(stray.is_empty(),
		"при выделении игрока 1 рамки владения остались на клетках %s (чужие глушатся)" % str(stray))

	# --- 7: выделение снимается, рамки владения возвращаются ------------------------------------
	b.call("set_owner_focus", -1)
	var rival: Dictionary = (tiles[RIVAL_TILE] as Control).state_frame()
	_check(bool(rival["visible"]) and int(rival["width"]) == 2,
		"после снятия выделения рамка владения клетки %d не вернулась: %s" % [RIVAL_TILE, str(rival)])
	var mine_after: Dictionary = (tiles[1] as Control).state_frame()
	_check(int(mine_after["width"]) != 3, "кольцо игрока 1 осталось после снятия выделения")
	pp.free()


## --- фикстура ---------------------------------------------------------------------------------

func _seats() -> Array:
	var out: Array = []
	for i in 3:
		var s := Seat.new()
		s.pid = i
		s.name = ["Host", "Tester", "Rival"][i]
		s.color = SEAT_COL if i == 1 else Color(0.4, 0.5, 0.8)
		out.append(s)
	return out


func _board() -> Array:
	return [
		{"index": 1, "name": "Nova Terrace", "group": "brown", "owner": 1, "houses": 2, "mortgaged": false},
		{"index": 3, "name": "Palm Row", "group": "amber", "owner": 1, "houses": 0, "mortgaged": true},
		{"index": 5, "name": "Harbor Station", "group": "", "owner": 1, "houses": 0, "mortgaged": false},
		{"index": RIVAL_TILE, "name": "Rival Lot", "group": "brown", "owner": 2, "houses": 1, "mortgaged": false},
		{"index": FREE_TILE, "name": "Free Lot", "group": "amber", "owner": -1, "houses": 0, "mortgaged": false},
	]


func _players(with_cards: bool) -> Array:
	var p0 := {"index": 0, "name": "Host", "money": 900, "position": 0, "in_jail": false,
		"jail_turns": 0, "bankrupt": false, "tiles": [], "houses": 0, "mortgaged": 0}
	var p1 := {"index": 1, "name": "Tester", "money": 1350, "position": 5, "in_jail": true,
		"jail_turns": 2, "bankrupt": false, "tiles": MINE.duplicate(), "houses": 2, "mortgaged": 1}
	if with_cards:
		p1["get_out_of_jail_cards"] = 1
	var p2 := {"index": 2, "name": "Rival", "money": 300, "position": RIVAL_TILE, "in_jail": false,
		"jail_turns": 0, "bankrupt": false, "tiles": [RIVAL_TILE], "houses": 1, "mortgaged": 0}
	return [p0, p1, p2]


func _proj(with_cards: bool) -> Dictionary:
	return {
		"round": 4, "parking_pot": 120, "turn_player": 0, "phase": "TURN_START",
		"board": _board(), "players": _players(with_cards),
	}


## --- отчёт ------------------------------------------------------------------------------------

func _check(ok: bool, why: String) -> void:
	_checks += 1
	if ok:
		return
	_fails.append(why)
	push_error("E-5: " + why)


func _fail(why: String) -> void:
	_check(false, why)


func _report() -> void:
	print("E-5 PROBE: %d checks, %d red" % [_checks, _fails.size()])
	if _checks < MIN_CHECKS:
		_fails.append("проба сделала %d проверок (пол %d) - молчаливый обрыв нельзя считать зелёным"
			% [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> E-5 PASSED (инвентарь карточки по именам + кольцо ровно на его клетках, ru+en)")
		get_tree().quit(0)
		return
	print("==> E-5 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
	get_tree().quit(1)
