extends Node
## СКОЛЬКО СТОИТ ПРАВКА В `UiTheme.label`.
##
## Вопрос, на который отвечает проба: включение auto-wrap + expand-fill на КАЖДОЙ метке —
## это косметика или это цена в кадре? Меряем раскладку настоящей панели журнала (40 строк)
## с правкой и без неё, в одном прогоне, на одном тексте.
##
## ЧТО МЕРЯЕТСЯ: время полного прохода пересчёта размеров (то, что движок делает при любом
## изменении данных). Если правка удорожает проход во много раз — это и есть «упал fps».
func _ready() -> void:
	var n: int = 40
	var long_text := "Рента удваивается, когда у владельца полный набор всех улиц этой группы — длинная строка"
	var short_text := "Игрок 1"

	# --- с правкой (как сейчас в theme.gd) ---
	var t_on := _cost(n, long_text, true)
	# --- без правки (как было до 3d6928c) ---
	var t_off := _cost(n, long_text, false)

	print("РАСКЛАДКА %d строк журнала, 200 проходов:" % n)
	print("  с auto-wrap + expand-fill: %8.1f мс" % t_on)
	print("  без правки:                %8.1f мс" % t_off)
	if t_off > 0.0:
		print("  отношение:                 %8.2f x" % (t_on / t_off))

	# --- и цена на КОРОТКИХ метках: там wrap не нужен, но он всё равно платится ---
	var s_on := _cost(n, short_text, true)
	var s_off := _cost(n, short_text, false)
	print("КОРОТКИЕ метки («Игрок 1»), 200 проходов:")
	print("  с правкой: %.1f мс   без правки: %.1f мс   отношение: %.2f x"
		% [s_on, s_off, (s_on / s_off) if s_off > 0.0 else 0.0])

	# --- и главное: растёт ли МИНИМАЛЬНАЯ ВЫСОТА от wrap (это ломает сетку) ---
	var l := Label.new()
	l.text = short_text
	add_child(l)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var h_off: float = l.get_minimum_size().y
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var h_wrap: float = l.get_minimum_size().y
	l.size.x = 90.0
	var h_narrow: float = l.get_minimum_size().y
	print("МИНИМАЛЬНАЯ ВЫСОТА метки «%s»:" % short_text)
	print("  без wrap: %.0f px   с wrap при широкой полосе: %.0f px   с wrap в 90 px: %.0f px"
		% [h_off, h_wrap, h_narrow])
	if h_narrow > h_off:
		print("  -> wrap ЛОМАЕТ однострочные подписи: они становятся двух- и трёхстрочными")
	get_tree().quit(0)


## Полная пересборка размеров панели: строим колонку, считаем минимальные размеры и
## прогоняем раскладку `passes` раз.
func _cost(n: int, text: String, wrap: bool) -> float:
	var holder := VBoxContainer.new()
	holder.custom_minimum_size.x = 240.0
	add_child(holder)
	var labels: Array = []
	for i in n:
		var l := Label.new()
		l.text = "%s %d" % [text, i]
		l.add_theme_font_size_override("font_size", 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
		if wrap:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(l)
		labels.append(l)

	var passes := 200
	var t0 := Time.get_ticks_usec()
	for _p in passes:
		for l in labels:
			l.get_minimum_size()
		holder.queue_sort()
	var t1 := Time.get_ticks_usec()
	holder.queue_free()
	return float(t1 - t0) / 1000.0
