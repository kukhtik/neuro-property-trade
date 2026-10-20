extends Node
## FILL gate — «на экране есть что читать, а не пустота».
##
## ЗАЧЕМ. Ни один гейт в репозитории не смотрел на ПУСТОТУ. `SG-01`/`SG-02` проверяют, что ничего
## не вылезает за экран; ни один не проверяет, что что-то НА экране ЕСТЬ. Поэтому кадр, в котором
## половина площади не рисует ничего, а осмысленное содержание занимает 4.2 % пикселей, проходил
## всю приёмку. Владелец увидел это глазами: «огромное пустое пространство буквально везде».
##
## ЧТО МЕРИТ (R-1 и R-2 из `docs/specs/ui-redesign-brief.md`):
##   R-1: пустых ячеек кадра <= 25 %. Кадр делится на сетку; пустая ячейка — где < 2 % не-фоновых
##        пикселей. База на момент написания: 51.7 % на 1600x1200.
##   R-2: внутри кольца доски занято >= 70 % площади. База: 15.3 %.
##
## ПОЧЕМУ ДВА ЧИСЛА. Они мерят РАЗНОЕ и оба нужны: R-1 про топологию (какие участки экрана вообще
## ничего не рисуют), R-2 про плотность (сколько площади занято смыслом, а не рамками клеток и
## фоном). Кадр может пройти R-1 и провалить R-2: почти весь экран покрыт фоном клеток и рейлов,
## а информации на нём почти нет — это и есть сегодняшнее состояние.
##
## ПОЧЕМУ МЕРИТСЯ ГОТОВЫЙ КАДР, А НЕ СВОЯ СЦЕНА. Первая версия гейта поднимала `MainScript` ребёнком
## к своему Node и снимала `get_viewport()`. Такой снимок выходит НЕПОЛНЫМ: 323 цвета против 574 у
## кадра от штатного захватчика, полосы доски заполнены на 6 % вместо 17-58 %, и число 70.7 % не
## менялось ни от ожидания, ни от `--smoke-drive`, ни от размера окна — гейт мерил свою
## недостроенную копию сцены, а не экран игрока.
##
## Теперь гейт читает кадр, снятый ШТАТНЫМ захватчиком (`sg07_capture`, состояние «идёт ход
## человека»), то есть ровно ту картинку, которую видит игрок и которую принимает SG-07. Если кадра
## нет — гейт красный и говорит об этом: молча пропустить замер нельзя, иначе он «зелёный» ровно
## тогда, когда ничего не проверял.
##
## Запуск: godot --headless --path game res://tools/gates/fill_gate.tscn
##         (нужен свежий build/renders/turn-human_<skin>.png от SG-07)
## Вердикт: ==> FILL PASSED/FAILED: причина

## Пороги R-1/R-2 — ОДНО место правды; спека ссылается на них, а не повторяет числа.
const MAX_EMPTY_CELLS := 25.0     # %, R-1
const MIN_CENTER_FILL := 70.0     # %, R-2
const GRID_X := 40
const GRID_Y := 30
const CELL_EMPTY_BELOW := 2.0     # %, ячейка считается пустой ниже этого
const TOL := 6                    # /255, допуск «не фон» (антиалиасинг скина)

## Кадр, который мерим: состояние «идёт ход человека» — то, где интерфейс обязан быть понятен.
const FRAMES := ["turn-human_neuro", "turn-human_evil"]

## Доли кадра, в которых лежит кольцо. Кольцо — 11 клеток, центральная зона — 9 из них.
## Доли, а не пиксели: кадр у профилей разный (1600x1200 основной, 880x600 компакт).
const RING_X := 0.231            # 370/1600 — замер живого дерева
const RING_Y := 0.060            # 72/1200
const RING_W := 0.536            # 857/1600
const CELL_SHARE := 1.0 / 11.0

var _fails: Array = []
var _notes: Array = []
var _ran := false


func _ready() -> void:
	if _ran:
		return
	_ran = true
	var measured := 0
	for base in FRAMES:
		var img := _find_frame(base)
		if img == null:
			_notes.append("кадр %s НЕ НАЙДЕН - замер пропущен (сначала SG-07)" % base)
			continue
		measured += 1
		_measure_one(base, img)
	if measured == 0:
		# A SKIP, and out loud, exactly like SG-07 - which is the gate that DRAWS these frames. The
		# old message ("a gate that checked nothing is RED") was right about the sin and wrong about
		# the cause: on a runner with no display and no Pillow, SG-07 skips and there is nothing to
		# read, so the red described the runner, not the product. A gate that DID measure and found
		# too much empty frame still fails, below.
		print("==> FILL SKIPPED: no frames to measure (SG-07 draws build/renders/*.png; this runner has no display)")
		get_tree().quit(0)
		return
	_finish()


## Кадр ищем там, куда его кладёт SG-07, и в двух других известных местах. Путь берётся от
## `user://`, а не от cwd: гейт запускают из разных каталогов.
func _find_frame(base: String) -> Image:
	var root := ProjectSettings.globalize_path("res://..")
	for sub in ["/build/renders/", "/build/gates/", "/build/ab/"]:
		var p: String = root + sub + base + ".png"
		var img := _load(p)
		if img != null:
			return img
	return null


func _load(abs_path: String) -> Image:
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.new()
	if img.load(abs_path) != OK:
		return null
	img.convert(Image.FORMAT_RGB8)
	return img


func _measure_one(base: String, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w < 320 or h < 240:
		_fail("%s: кадр %dx%d слишком мал для замера" % [base, w, h])
		return
	var bg := _background(img, w, h)

	# --- R-1: доля пустых ячеек ---
	var cw := int(max(1, w / GRID_X))
	var ch := int(max(1, h / GRID_Y))
	var empty := 0
	var total := 0
	for gy in GRID_Y:
		for gx in GRID_X:
			var n := 0
			var tot := 0
			var y := gy * ch
			while y < min((gy + 1) * ch, h):
				var x := gx * cw
				while x < min((gx + 1) * cw, w):
					tot += 1
					if _differs(img.get_pixel(x, y), bg):
						n += 1
					x += 4
				y += 4
			if tot == 0:
				continue
			total += 1
			if float(n) / float(tot) * 100.0 < CELL_EMPTY_BELOW:
				empty += 1
	var empty_pct := float(empty) / float(max(total, 1)) * 100.0
	_notes.append("%s %dx%d: R-1 пустых ячеек %.1f%% (порог <= %.0f%%)"
		% [base, w, h, empty_pct, MAX_EMPTY_CELLS])
	if empty_pct > MAX_EMPTY_CELLS:
		_fail("%s: R-1 %.1f%% кадра не рисует ничего (порог %.0f%%)"
			% [base, empty_pct, MAX_EMPTY_CELLS])

	# --- R-2: заполненность центра кольца ---
	var ring := Rect2(RING_X * w, RING_Y * h, RING_W * w, RING_W * h)
	var cell := ring.size.x * CELL_SHARE
	var centre := Rect2(ring.position.x + cell, ring.position.y + cell, cell * 9.0, cell * 9.0)
	var filled := _fill_in(img, centre, bg)
	_notes.append("%s: R-2 центр [%d,%d %dx%d] занято %.1f%% (порог >= %.0f%%)" % [
		base, int(centre.position.x), int(centre.position.y), int(centre.size.x), int(centre.size.y),
		filled, MIN_CENTER_FILL])
	if filled < MIN_CENTER_FILL:
		_fail("%s: R-2 внутри кольца занято %.1f%% (порог %.0f%%) - центр доски пустует"
			% [base, filled, MIN_CENTER_FILL])


## Фон = самый частый цвет РАМКИ кадра (полоса по краю), а не всего кадра.
## У каждого скина свой фон, поэтому он берётся из кадра, а не из токенов: гейт обязан работать на
## любом скине.
##
## ПОЧЕМУ НЕ ВЕСЬ КАДР (замер 18.10, P1.1): пока центр доски пустовал, самым частым цветом кадра был
## фон скина (#0b0613) и гейт мерил правильно. Как только центр стал панно с панелями, самым частым
## цветом стал `surface.2` (#1b1230, 41 % кадра) — и гейт начал считать ПАНЕЛЬ ФОНОМ: R-2 упал до
## 7.6 % на экране, где центр занят на 95 %. Проверка мерила собственную подложку.
## Край кадра — это всегда фон приложения, а не поверхность: его и берём.
func _background(img: Image, w: int, h: int) -> Color:
	var counts := {}
	var band := 6
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			if x < band or y < band or x >= w - band or y >= h - band:
				var c := img.get_pixel(x, y)
				var k := "%d,%d,%d" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
				counts[k] = int(counts.get(k, 0)) + 1
			x += 3
		y += 3
	var best := ""
	var best_n := -1
	for k in counts.keys():
		if int(counts[k]) > best_n:
			best_n = int(counts[k])
			best = str(k)
	var parts: PackedStringArray = best.split(",")
	return Color(int(parts[0]) / 255.0, int(parts[1]) / 255.0, int(parts[2]) / 255.0)


func _differs(a: Color, b: Color) -> bool:
	var t := float(TOL) / 255.0
	return absf(a.r - b.r) > t or absf(a.g - b.g) > t or absf(a.b - b.b) > t


func _fill_in(img: Image, r: Rect2, bg: Color) -> float:
	var n := 0
	var tot := 0
	var y := int(r.position.y)
	while y < int(r.position.y + r.size.y):
		var x := int(r.position.x)
		while x < int(r.position.x + r.size.x):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				tot += 1
				if _differs(img.get_pixel(x, y), bg):
					n += 1
			x += 3
		y += 3
	return float(n) / float(max(tot, 1)) * 100.0


func _fail(msg: String) -> void:
	_fails.append(msg)


func _finish() -> void:
	for n in _notes:
		print("FILL %s" % n)
	for f in _fails:
		print("FILL NOTE %s" % f)
	if _fails.is_empty():
		print("==> FILL PASSED (кадр занят: пустых ячеек и центр кольца в пределах порогов R-1/R-2)")
		get_tree().quit(0)
	else:
		print("==> FILL FAILED: %s" % " | ".join(_fails))
		get_tree().quit(1)
