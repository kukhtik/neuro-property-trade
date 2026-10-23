extends Node
## MOCK-02 PROBE — «ВИЗУАЛЬНЫЙ ВКУС»: живой дамп кеглей всех надписей продукта.
##
## ЗАЧЕМ (решение владельца 23.10). «проверка на визуальный вкус (чтобы не было огромных
## выбивающихся надписей к примеру)». Вкус измерим: у каждой надписи есть кегль, и он должен
## быть ШАГОМ ШКАЛЫ, а не произвольным числом, и не должен превышать потолок.
##
## ИСТОЧНИК ИСТИНЫ. Шкала живёт в скине: `game/assets/skins/neuro/skin.json` →
## `tokens.size = {xs: 11, s: 13, m: 14, l: 18, xl: 28}`. Макет читает те же значения
## (`design/ui-prototype.html` → `--fs-xs:11px ... --fs-xl:28px`). Значит «как должно быть» —
## это `tokens.size`, и никаких «своих» чисел.
##
## ЧТО ДАМПИТ. По всем Label в ЖИВОМ продукте: путь узла, ЭФФЕКТИВНЫЙ кегль (после
## `px(design) * ui_scale`), макетовый `design_px` (если задан), признак «это надпись клетки
## доски» (у неё кегль считается от размера клетки — это законно) и текст.
##
## Проба ничего не решает за анализатор: она только даёт живые числа. Решение принимает
## `tools/ci/mockup_taste.py` (он же проверяет исходники на «сырые» числа вне шкалы).
##
## Вердикт печатает анализатор: `==> MOCK-02 PASSED` / `==> MOCK-02 FAILED: <причина>`.
## Запуск:  godot --headless --path game res://tools/mockup_taste_probe.tscn

const MainScript := preload("res://main.gd")
const SeatScript := preload("res://seats/seat.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const UiTheme := preload("res://ui/theme.gd")

const OUT_PREFIX := "TASTE|"


func _ready() -> void:
	var st = SettingsScript.new()
	st.seat_count = 2
	st.starting_order = "manual"

	var seats: Array = []
	var s_sdk = SeatScript.new(0)
	s_sdk.name = "Neuro"
	s_sdk.input_driver = "SDK"
	s_sdk.driver_label = "sdk:neuro"
	seats.append(s_sdk)
	var s_host = SeatScript.new(1)
	s_host.name = "Host"
	s_host.input_driver = "LOCAL"
	seats.append(s_host)

	# Тип НЕ выводим через `:=`: `MainScript.new()` возвращает Variant, а в этом проекте
	# предупреждение «тип выводится из Variant» считается ОШИБКОЙ (warnings as errors).
	var shell = MainScript.new()
	add_child(shell)
	shell.call("_build_game", st, seats)

	var scale := UiTheme.ui_scale()
	print("%smeta|scale|%.4f" % [OUT_PREFIX, scale])
	var dumped := _walk(shell, "root")
	print("==> MOCK-02 PROBE: %d labels dumped (ui_scale %.4f)" % [dumped, scale])
	get_tree().quit(0)


func _walk(node: Node, path: String) -> int:
	var n := 0
	for ch in node.get_children():
		var p := "%s/%s" % [path, str(ch.name)]
		if ch is Label:
			var l := ch as Label
			var eff := int(l.get_theme_font_size("font_size"))
			var dpx := -1
			if l.has_meta("design_px"):
				dpx = int(l.get_meta("design_px"))
			var txt := str(l.text).replace("|", "/")
			if txt.length() > 28:
				txt = txt.substr(0, 28)
			# kind: 0 - обычная надпись (её кегль - РОЛЬ), 1 - надпись клетки доски,
			# 3 - надпись, чей кегль ВЫЧИСЛЯЕТСЯ от клетки (метка `cell_relative`, которую
			# ставит панно: `turn_panno.apply_scale`). Только у 0 кегль - роль, и она обязана
			# быть на экране: у 1 и 3 пересчёт от клетки законен.
			var kind := 0
			if l.has_meta("cell_relative"):
				kind = 3
			elif _under_tile(l):
				kind = 1
			print("%slabel|%s|%d|%d|%d|%s" % [OUT_PREFIX, p, eff, dpx, kind, txt])
			n += 1
		n += _walk(ch, p)
	return n


## Надпись внутри клетки доски (tile_view): её кегль считается от размера клетки.
func _under_tile(node: Node) -> bool:
	var anc: Node = node.get_parent()
	while anc != null:
		var scr = anc.get_script()
		if scr != null and str(scr.resource_path).ends_with("visual/tile_view.gd"):
			return true
		anc = anc.get_parent()
	return false
