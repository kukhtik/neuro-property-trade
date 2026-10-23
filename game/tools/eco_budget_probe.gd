extends Node
## ECO-01 PROBE — «БЮДЖЕТ КАДРА»: что продукт ест в кадре.
##
## ЗАЧЕМ (задача владельца 23.10): «приблизиться к качеству оптимизации игр из 2000 года,
## чтобы потребляли минимум ресурсов». Уровень 2000 года — это не «нам кажется быстро», это
## ИЗМЕРЕННЫЕ числа: время кадра, число вызовов отрисовки, живой ObjectDB, осиротевшие узлы и
## статическая память. Пока таких чисел нет, слово «оптимизировано» ничего не значит.
##
## ЧТО ДАМПИТ. По кадру (после прогрева, первые кадры — это разгон и импорт, они не типичны):
##   * время обработки кадра (Performance.TIME_PROCESS);
##   * вызовы отрисовки в кадре (RENDER_TOTAL_DRAW_CALLS_IN_FRAME);
##   * живые объекты (OBJECT_COUNT) и ОСИРОТЕВШИЕ узлы (OBJECT_ORPHAN_NODE_COUNT);
##   * статическая память (MEMORY_STATIC).
## Рост ObjectDB и статической памяти за окно — это отдельные числа: именно они показывают
## утечку, а не «много объектов».
##
## РЕЖИМ. Проба идёт С ОКНОМ (как съёмка кадров SG-07): в headless нет сервера отрисовки,
## поэтому вызовы отрисовки были бы нулём, а время кадра — бессмысленным. Значит числа здесь —
## числа desktop-окна; в браузере они свои, и это честно записано в вердикте.
##
## Проба ничего не решает: вердикт принимает `tools/ci/eco_budget.py` по бюджету.
## Запуск: godot --path game --rendering-driver opengl3 res://tools/eco_budget_probe.tscn

const MainScript := preload("res://main.gd")
const SeatScript := preload("res://seats/seat.gd")
const SettingsScript := preload("res://core/game_settings.gd")

const OUT_PREFIX := "ECO|"
const WARMUP_FRAMES := 30
const MEASURE_FRAMES := 180


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

	for _i in range(WARMUP_FRAMES):
		await get_tree().process_frame

	var first_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var first_static := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var times: Array[float] = []
	var draws: Array[int] = []
	var max_orphans := 0

	for i in range(MEASURE_FRAMES):
		await get_tree().process_frame
		var t := float(Performance.get_monitor(Performance.TIME_PROCESS))
		var d := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var orph := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		times.append(t)
		draws.append(d)
		max_orphans = maxi(max_orphans, orph)
		print("%sframe|%d|%.6f|%d|%d|%d|%d" % [OUT_PREFIX, i, t, d, objs, orph, mem])

	var last_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var last_static := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var sorted: Array[float] = times.duplicate()
	sorted.sort()
	var p50 := sorted[int(float(sorted.size()) * 0.50)]
	var p95 := sorted[mini(sorted.size() - 1, int(float(sorted.size()) * 0.95))]
	var max_t := sorted[sorted.size() - 1]
	var max_d := 0
	for d in draws:
		max_d = maxi(max_d, d)

	print("%ssummary|frames|%d|p50_ms|%.3f|p95_ms|%.3f|max_ms|%.3f|draw_max|%d|objects_first|%d|objects_last|%d|orphans_max|%d|static_first|%d|static_last|%d" % [
		OUT_PREFIX, MEASURE_FRAMES, p50 * 1000.0, p95 * 1000.0, max_t * 1000.0, max_d,
		first_objects, last_objects, max_orphans, first_static, last_static])
	print("==> ECO-01 PROBE: %d frames measured (p95 %.3f ms, max draw calls %d, objects %d -> %d, orphans %d)" % [
		MEASURE_FRAMES, p95 * 1000.0, max_d, first_objects, last_objects, max_orphans])
	get_tree().quit(0)
