extends Node
## HG-15 PROBE — «обещание паузы измерено» (docs/restoration/gates.md, HG-15).
##
## ПАУЗА В ПРОДУКТЕ ЕСТЬ: `engine.paused`, `admin_override` pause/resume, отказ интентов на
## паузе (`match paused`), тишина `seat_manager._tick` (он зануляет `decision_waiting`), ключ
## `paused` в ОБЕИХ проекциях, чип «ПАУЗА» в шапке. Её не измерял никто: в `tools/ci/run_gates.sh`
## не было ни HG-15, ни VOICE-01, ни E-5 — три обещания приёмки висели TODO.
##
## Проба меряет ЖИВОЙ продукт, а не мок: поднимает настоящий `MainScript` (профиль admin, как
## hg12/hg13), доводит матч до живого хода человека (место LOCAL ждёт, потому что `--smoke-drive`
## не передан и автоплей выключен) и работает с настоящим движком и настоящим `SeatManager`.
##
## Шесть пунктов приёмки, измеренных здесь:
##   1. пауза через НАСТОЯЩИЙ путь `engine.admin_override("pause", …)` → `paused == true` и
##      событие типа `pause` в append-only журнале;
##   2. ПОКА ПАУЗА интенты не принимаются: `submit_intent` ЛЕГАЛЬНОГО действия отвечает
##      `ok == false`, а причина называет паузу;
##   3. обе проекции видят одно и то же: `for_player` и `for_spectator` несут `paused == true`
##      и ОДИН И ТОТ ЖЕ непустой `paused_by`;
##   4. пауза живёт ВНЕ снапшота: в `to_snapshot()` нет ключей `paused`/`paused_by`, а движок,
##      восстановленный `from_snapshot`, не считает себя на паузе;
##   5. resume без дублей: на цикл ровно одно `pause` и одно `resume`, повторный resume молчит,
##      и после resume движок снова принимает интент;
##   6. ТАЙМЕР СТОИТ: пока пауза, `phase`/`turn_player` не двигаются, `decision_waiting` ждущего
##      места занулён (это делает `seat_manager._tick`), и журнал не растёт.
##
## НЕГАТИВНАЯ ПРОВЕРКА (без правки чужого кода, вручную):
##   godot --headless --path game res://tools/hg15_pause_probe.tscn -- --hg15-negative
##   Проба прогоняет ТУ ЖЕ проверку «таймер стоит» на НЕпоставленной паузе и обязана покраснеть
##   там: если бы проверка не различала паузу и её отсутствие, она бы осталась зелёной.
##
## Проба печатает, СКОЛЬКО проверок сделала; меньше пола — провал, а не «пусто и хорошо».
##
## Вердикт: ==> HG-15 PASSED (…) / ==> HG-15 FAILED: <причина>
## Запуск:  godot --headless --path game res://tools/hg15_pause_probe.tscn

const MainScript := preload("res://main.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
const ProjScript := preload("res://sdk/projection.gd")

## Пол проверок: проба, оборвавшаяся молча, обязана быть красной, а не пустой.
const MIN_CHECKS := 16

var _launcher = null
var _fails: Array = []
var _checks := 0
var _frame := 0
var _state := "boot"
var _deadline := 0
var _negative := false

var _pid := 0
var _legal := ""
var _dw_before := 0.0
var _dw_after := 0.0
var _phase_before := ""
var _turn_before := -1
var _log_before := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_negative = _has_flag("--hg15-negative")
	_launcher = MainScript.new()
	# профиль admin — тот же путь, что у hg12: админка и есть владелец паузы
	_launcher.set("_force_profile", UiProfileScript.for_id("admin"))
	add_child(_launcher)


func _has_flag(flag: String) -> bool:
	# `--path` и прочие аргументы движка могут не попасть в user args, поэтому смотрим оба списка
	for a in OS.get_cmdline_user_args():
		if str(a) == flag:
			return true
	for a in OS.get_cmdline_args():
		if str(a) == flag:
			return true
	return false


func _process(_dt: float) -> void:
	_frame += 1
	match _state:
		"boot":
			if _frame < 10:
				return
			_launcher.call("_autostart")
			_state = "to_human"
			_deadline = Time.get_ticks_msec() + 10000
		"to_human":
			if not _live_human_turn():
				if Time.get_ticks_msec() >= _deadline:
					_fail("матч не дошёл до живого хода человека за 10с (engine/manager/фаза/легальные действия)")
					_finish()
				return
			_pid = _human_pid()
			var acts: Array = _engine().legal_actions(_pid)
			_legal = str(acts[0]) if acts.size() > 0 else ""
			if _legal == "":
				_fail("у ждущего места нет ни одного легального действия — мерить нечего")
				_finish()
				return
			print("HG-15: живой ход человека (pid=%d, legal=`%s`, phase=%s)" % [_pid, _legal, str(_engine().phase)])
			# КОНТРОЛЬ: без паузы таймер ждущего места обязан идти. Без этой проверки «на паузе
			# таймер стоит» ничего не доказывает: он мог бы стоять и без паузы.
			_dw_before = float(_seat(_pid).decision_waiting)
			_state = "baseline_wait"
			_deadline = Time.get_ticks_msec() + 700
		"baseline_wait":
			if Time.get_ticks_msec() < _deadline:
				return
			_dw_after = float(_seat(_pid).decision_waiting)
			_check(_dw_after > _dw_before,
				"таймер не идёт на живом ходу БЕЗ паузы (decision_waiting %.2f -> %.2f) — контроль мёртв" % [_dw_before, _dw_after])
			print("HG-15: контроль — без паузы decision_waiting растёт (%.2f -> %.2f)" % [_dw_before, _dw_after])
			_state = "pause"
		"pause":
			if _negative:
				# НЕГАТИВ: паузу НЕ ставим — та же проверка таймера обязана покраснеть.
				print("HG-15: NEGATIVE — пауза не выставляется намеренно")
				_arm_paused_measurement()
				_state = "paused_wait"
				return
			_do_pause()
			_arm_paused_measurement()
			_state = "paused_wait"
		"paused_wait":
			if Time.get_ticks_msec() < _deadline:
				return
			if _negative:
				_finish_negative()
				return
			_timer_stands_check()
			_do_resume()
			_finish()


## --- пункты 1-4: пауза, отказ интентов, обе проекции, снапшот --------------------------------

func _do_pause() -> void:
	var eng = _engine()
	# 1. НАСТОЯЩИЙ путь паузы — тот же, которым ходит админка.
	var res: Dictionary = eng.admin_override("pause", {"by": "admin", "reason": "hg15-probe"})
	_check(bool(res.get("ok", false)), "admin_override(\"pause\") отказал: %s" % str(res.get("reason", "")))
	_check(bool(eng.paused), "admin_override(\"pause\") не поставил engine.paused")
	_check(_count_type("pause") == 1, "в журнале %d событий `pause` после настоящего пути паузы (ждали одно)" % _count_type("pause"))
	print("HG-15: пауза через admin_override (paused=%s, paused_by=`%s`)" % [str(eng.paused), str(eng.paused_by)])

	# 2. ПОКА ПАУЗА — интенты не принимаются, даже легальное действие.
	var r: Dictionary = eng.submit_intent(_pid, _legal, {})
	_check(not bool(r.get("ok", true)),
		"на паузе движок ПРИНЯЛ интент `%s` (ok=true) — пауза не закрывает вход" % _legal)
	_check(str(r.get("reason", "")).to_lower().find("paused") >= 0,
		"отказ на паузе не назван паузой: reason=`%s`" % str(r.get("reason", "")))
	print("HG-15: интент на паузе отбит (ok=%s, reason=`%s`)" % [str(r.get("ok", false)), str(r.get("reason", ""))])

	# 3. ОБЕ проекции видят одно и то же.
	var proj = ProjScript.new()
	var pp: Dictionary = proj.for_player(eng, _pid)
	var ps: Dictionary = proj.for_spectator(eng)
	var by_p := str(pp.get("paused_by", ""))
	var by_s := str(ps.get("paused_by", ""))
	_check(bool(pp.get("paused", false)), "проекция места не несёт paused=true")
	_check(bool(ps.get("paused", false)), "проекция зрителя не несёт paused=true")
	_check(by_p != "" and by_p == by_s,
		"проекции расходятся в paused_by (место=`%s`, зритель=`%s`)" % [by_p, by_s])
	print("HG-15: обе проекции видят паузу (paused_by=`%s`)" % by_p)

	# 4. Пауза живёт ВНЕ снапшота.
	var snap: Dictionary = eng.to_snapshot()
	_check(not snap.has("paused"), "снапшот несёт ключ `paused` — пауза утекла в сериализацию")
	_check(not snap.has("paused_by"), "снапшот несёт ключ `paused_by` — пауза утекла в сериализацию")
	var restored = eng.from_snapshot(snap)
	_check(restored != null and not bool(restored.paused),
		"восстановленный из снапшота движок считает себя на паузе (paused=%s)"
			% (str(restored.paused) if restored != null else "null"))
	print("HG-15: пауза вне снапшота (ключей нет, restored.paused=%s)"
		% (str(restored.paused) if restored != null else "null"))


## --- пункт 6: пока пауза, таймер стоит (и его отсутствие ловится) ----------------------------

## Заведомо ненулевое ожидание на ждущем месте: если пауза не зануляет его, это будет видно
## ЧИСЛОМ, а не «кажется».
func _arm_paused_measurement() -> void:
	var eng = _engine()
	_phase_before = str(eng.phase)
	_turn_before = int(eng.turn_player)
	_log_before = int(eng.log.size())
	_seat(_pid).decision_waiting = 7.0
	_deadline = Time.get_ticks_msec() + 1200


func _paused_facts() -> Dictionary:
	var eng = _engine()
	var dw := float(_seat(_pid).decision_waiting)
	return {
		"dw": dw,
		"dw_zero": absf(dw) < 0.0001,
		"phase_same": str(eng.phase) == _phase_before,
		"turn_same": int(eng.turn_player) == _turn_before,
		"log_same": int(eng.log.size()) == _log_before,
	}


func _timer_stands_check() -> void:
	var eng = _engine()
	var f := _paused_facts()
	_check(bool(f["dw_zero"]),
		"таймер идёт на паузе: decision_waiting ждущего места = %.2f (в _tick при паузе он зануляется)" % float(f["dw"]))
	_check(bool(f["phase_same"]),
		"фаза двинулась на паузе: %s -> %s" % [_phase_before, str(eng.phase)])
	_check(bool(f["turn_same"]),
		"turn_player двинулся на паузе: %d -> %d" % [_turn_before, int(eng.turn_player)])
	_check(bool(f["log_same"]),
		"журнал растёт на паузе: %d -> %d событий" % [_log_before, int(eng.log.size())])
	print("HG-15: таймер стоит (decision_waiting=%.2f, phase=%s, turn=%d, log=%d)"
		% [float(f["dw"]), str(eng.phase), int(eng.turn_player), int(eng.log.size())])


func _finish_negative() -> void:
	var f := _paused_facts()
	if bool(f["dw_zero"]) and bool(f["phase_same"]) and bool(f["turn_same"]) and bool(f["log_same"]):
		print("==> HG-15 NEGATIVE FAILED: проверка «таймер стоит» НЕ кусается — на непоставленной паузе она осталась зелёной (decision_waiting=%.2f)"
			% float(f["dw"]))
		get_tree().quit(1)
		return
	print("==> HG-15 NEGATIVE OK: проверка «таймер стоит» кусается без паузы (decision_waiting=%.2f вместо нуля; phase_same=%s, turn_same=%s, log_same=%s)"
		% [float(f["dw"]), str(f["phase_same"]), str(f["turn_same"]), str(f["log_same"])])
	get_tree().quit(0)


## --- пункт 5: resume без дублей --------------------------------------------------------------

func _do_resume() -> void:
	var eng = _engine()
	var r1: Dictionary = eng.admin_override("resume", {"by": "admin"})
	_check(bool(r1.get("ok", false)), "admin_override(\"resume\") отказал: %s" % str(r1.get("reason", "")))
	_check(_count_type("pause") == 1, "в журнале %d событий `pause` вместо одного" % _count_type("pause"))
	_check(_count_type("resume") == 1, "в журнале %d событий `resume` вместо одного" % _count_type("resume"))
	# ПОВТОРНЫЙ resume не имеет права добавить второго события (set_paused — no-op на том же значении).
	eng.admin_override("resume", {"by": "admin"})
	eng.admin_override("resume", {"by": "admin"})
	_check(_count_type("pause") == 1 and _count_type("resume") == 1,
		"повторный resume плодит события: pause=%d, resume=%d" % [_count_type("pause"), _count_type("resume")])
	# после resume движок снова принимает интент.
	var r2: Dictionary = eng.submit_intent(_pid, _legal, {})
	_check(bool(r2.get("ok", false)),
		"после resume движок не принял интент `%s`: %s" % [_legal, str(r2.get("reason", ""))])
	print("HG-15: resume без дублей (pause=%d, resume=%d) и вход снова открыт (ok=%s)"
		% [_count_type("pause"), _count_type("resume"), str(r2.get("ok", false))])


## --- доступ к живому продукту ---------------------------------------------------------------

func _engine():
	return _launcher.get("_engine")


func _manager():
	return _launcher.get("_manager")


func _seat(pid: int):
	var mgr = _manager()
	if mgr == null:
		return null
	for s in mgr.get("seats"):
		if int(s.pid) == pid:
			return s
	return null


func _human_pid() -> int:
	var mgr = _manager()
	if mgr == null:
		return -1
	for s in mgr.get("seats"):
		var d := str(s.input_driver)
		if d == "LOCAL" or d == "ADMIN":
			return int(s.pid)
	return -1


func _live_human_turn() -> bool:
	var eng = _engine()
	var mgr = _manager()
	if eng == null or mgr == null:
		return false
	if str(eng.phase) != "TURN_START":
		return false
	var hp := _human_pid()
	if hp < 0 or int(eng.turn_player) != hp:
		return false
	return not eng.legal_actions(hp).is_empty()


func _count_type(kind: String) -> int:
	var eng = _engine()
	if eng == null or eng.log == null:
		return -1
	var n := 0
	for e in eng.log.entries():
		if str(e.get("type", "")) == kind:
			n += 1
	return n


## --- отчёт ----------------------------------------------------------------------------------

func _check(ok: bool, why: String) -> void:
	_checks += 1
	if ok:
		return
	_fails.append(why)
	push_error("HG-15: " + why)


func _fail(why: String) -> void:
	_check(false, why)


func _finish() -> void:
	print("HG-15 PROBE: %d checks, %d red" % [_checks, _fails.size()])
	if _checks < MIN_CHECKS and _fails.is_empty():
		_fails.append("проба сделала %d проверок (пол %d) — молчаливый обрыв нельзя считать зелёным" % [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> HG-15 PASSED (пауза через admin_override: интенты отбиты, обе проекции согласны, снапшот чист, resume без дублей, таймер стоит — %d проверок)" % _checks)
		get_tree().quit(0)
		return
	print("==> HG-15 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
	get_tree().quit(1)
