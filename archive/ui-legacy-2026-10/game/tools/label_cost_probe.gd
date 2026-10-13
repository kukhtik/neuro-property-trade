extends Node
## СКОЛЬКО СТОИТ ФАБРИКА МЕТОК — и во что обошлась её ошибка.
##
## Вопрос, на который отвечает проба: правка `UiTheme.label` (3d6928c) навязала перенос
## строк и растяжение КАЖДОЙ метке проекта. Это была цена в кадре или косметика?
##
## ПРОБА ИДЁТ ЧЕРЕЗ ЖИВЫЕ ФАБРИКИ, а не через захардкоженные флаги: проверка, которая
## сама расставляет флаги, не заметит, что фабрика их больше не ставит.
##
## ГИГИЕНА ЗАМЕРА (без неё проба врёт): контейнеры освобождаются НЕМЕДЛЕННО (`free`, не
## `queue_free`) — отложенные освобождения копятся в дереве, и каждый следующий замер
## меряет более тяжёлое дерево; перед серией идёт прогрев (первый расчёт текста платит
## шрифт и атлас); порядок конфигураций РОТИРУЕТСЯ по раундам, вердикт — по МЕДИАНЕ
## отношений. Замеры в фиксированном порядке давали монотонный дрейф 1.58–1.91 x на
## ровном месте — это артефакт харнесса, а не цена кода.
##
## Меряем четыре конфигурации на одном тексте:
##   1. `эталон`     — метка до 3d6928c: ни переноса, ни растяжения (значение);
##   2. `значение`   — UiTheme.label() как он есть сейчас;
##   3. `3d6928c`    — WORD_SMART + EXPAND_FILL на каждой метке (эталон регрессии);
##   4. `абзац`      — UiTheme.label_wrap() как он есть сейчас (для прозы в рейках).
##
## ВЕРДИКТ: медиана цена(значение)/цена(эталон) <= 1.10. Exit-код — не вердикт
## (см. tools/ci/run_probes.sh), решает строка PASSED/FAILED.
const UiTheme := preload("res://ui/theme.gd")

const TEXT := "Рента удваивается, когда у владельца полный набор всех улиц этой группы — длинная строка"
const N := 40
## 2000, а не 200: окно замера ≈ 150 мс, и один системный «тычок» (тик ОС, Chrome рядом)
## даёт на нём доли процента, а не треть числа. При 200 проходах медианы прыгали 1.01–1.25
## на ровном месте — шум был шире допуска.
const PASSES := 2000

func _ready() -> void:
	# прогрев — первый расчёт текста платит за шрифт и атлас, он не в счёт
	for m in ["plain", "value", "regressed", "wrap"]:
		_cost(8, m)

	# ротация: каждая конфигурация попадает на каждую позицию в порядке ровно один раз
	var orders := [
		["plain", "value", "regressed", "wrap"],
		["value", "regressed", "wrap", "plain"],
		["regressed", "wrap", "plain", "value"],
		["wrap", "plain", "value", "regressed"],
	]
	var ms := {"plain": [], "value": [], "regressed": [], "wrap": []}
	var value_ratio: Array = []
	var regressed_ratio: Array = []
	print("РАСКЛАДКА %d строк журнала, %d проходов, %d раунда (ротация порядка):" % [N, PASSES, orders.size()])
	for round_i in orders.size():
		var t := {}
		for m in orders[round_i]:
			t[m] = _cost(N, m)
			(ms[m] as Array).append(t[m])
		var rv: float = _ratio(t["value"], t["plain"])
		var rr: float = _ratio(t["regressed"], t["plain"])
		value_ratio.append(rv)
		regressed_ratio.append(rr)
		print("  раунд %d: эталон %5.1f · значение %5.1f · 3d6928c %5.1f · абзац %5.1f мс"
			% [round_i + 1, t["plain"], t["value"], t["regressed"], t["wrap"]])

	var mv: float = _median(value_ratio)
	var mr: float = _median(regressed_ratio)
	print("МЕДИАНЫ (4 раунда):")
	print("  эталон:            %6.1f мс" % _median(ms["plain"]))
	print("  значение:          %6.1f мс" % _median(ms["value"]))
	print("  3d6928c:           %6.1f мс" % _median(ms["regressed"]))
	print("  абзац:             %6.1f мс" % _median(ms["wrap"]))
	print("  отношение значение/эталон:  %5.2f x   (допуск 1.10)" % mv)
	print("  отношение 3d6928c/эталон:   %5.2f x   (вот это и стоило кадров)" % mr)

	# --- растёт ли МИНИМАЛЬНАЯ ВЫСОТА подписи от переноса (именно это ломает строки) ---
	var l := UiTheme.label("Игрок 1", 13)
	add_child(l)
	var h_one: float = l.get_minimum_size().y
	var w := UiTheme.label_wrap("Игрок 1", 13)
	add_child(w)
	w.size.x = 50.0
	var h_two: float = w.get_minimum_size().y
	print("МИНИМАЛЬНАЯ ВЫСОТА подписи «Игрок 1»:")
	print("  значение: %.0f px   абзац в колонке 50 px: %.0f px" % [h_one, h_two])
	if h_two > h_one:
		print("  -> перенос ЛОМАЕТ однострочные подписи: подпись становится двухстрочной")

	if mv <= 1.10:
		print("==> LABEL COST PASSED (значение %.2f x от эталона по медиане, допуск 1.10)" % mv)
		get_tree().quit(0)
	else:
		print("==> LABEL COST FAILED (значение %.2f x от эталона по медиане, допуск 1.10)" % mv)
		get_tree().quit(1)


func _ratio(a: float, b: float) -> float:
	return a / b if b > 0.0 else 0.0


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v: Array = values.duplicate()
	v.sort()
	var mid: int = v.size() / 2
	if v.size() % 2 == 1:
		return float(v[mid])
	return (float(v[mid - 1]) + float(v[mid])) * 0.5


## Полная пересборка размеров панели: строим колонку меток и прогоняем раскладку
## `PASSES` раз. Конфигурации «эталон» и «3d6928c» собираются вручную НАМЕРЕННО:
## регрессия должна воспроизводиться и после того, как фабрика перестала её выдавать.
## Освобождается НЕМЕДЛЕННО: queue_free оставил бы контейнеры в дереве, и следующий
## замер мерил бы уже более тяжёлое дерево — это и была ошибка первых прогонов.
func _cost(n: int, mode: String) -> float:
	var holder := VBoxContainer.new()
	holder.custom_minimum_size.x = 240.0
	add_child(holder)
	var labels: Array = []
	for i in n:
		var s := "%s %d" % [TEXT, i]
		var l: Label
		match mode:
			"value":
				l = UiTheme.label(s, 13)
			"wrap":
				l = UiTheme.label_wrap(s, 13)
			"regressed":
				l = Label.new()
				l.text = s
				l.add_theme_font_size_override("font_size", 13)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_:
				l = Label.new()
				l.text = s
				l.add_theme_font_size_override("font_size", 13)
		holder.add_child(l)
		labels.append(l)

	var t0 := Time.get_ticks_usec()
	for _p in PASSES:
		for l in labels:
			l.get_minimum_size()
		holder.queue_sort()
	var t1 := Time.get_ticks_usec()
	holder.free()
	return float(t1 - t0) / 1000.0
