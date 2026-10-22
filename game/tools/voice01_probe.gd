extends Node
## VOICE-01 PROBE — «кто говорит» измерено на ЖИВОМ продукте (docs/program.md §3а, пункт D1).
##
## ОБЕЩАНИЕ. Вендорённый SDK-модуль (`game/addons/neuro-sdk/voice/voice_chat.gd`) отдаёт
## `speaking_changed(speaking)`, `speech_cancelled()`, `voice_unavailable(reason)`, `voice_ready()`
## — и до этой работы в продукте (`game/`) у них не было НИ ОДНОГО потребителя. Обещание «у игрока
## видно, кто говорит» висело TODO: ни кода, ни гейта.
##
## ГРАНИЦА. Живого сервера голоса нет (внешний блокер), поэтому меряется СОБСТВЕННАЯ логика
## продукта: (1) сигнал «этот говорит» доходит до карточки ЭТОГО места и несёт идентичность
## (`driver_label`); (2) идентичность не путается — горит ровно одно место; (3) `voice_unavailable`
## деградирует ТИХО (индикатор гаснет, ошибок нет, дерево узлов живо) и НЕ воскресает при
## перерисовке карточек; (4) индикатор не «залипает» — `speaking_changed(false)` и `speech_cancelled`
## гасят его.
##
## Проба поднимает настоящий `MainScript` (как hg12/hg15), берёт НАСТОЯЩУЮ панель мест
## (`game_view._seats_panel` — тот самый виджет, что висит в поясе кольца), НАСТОЯЩИЕ места
## (`SeatManager.seats` — объекты `seats/seat.gd` с их `driver_label`) и НАСТОЯЩУЮ зрительскую
## проекцию (`projection.for_spectator`). Источник голоса подставляется снаружи (`FakeVoice` —
## те же четыре сигнала, что у вендорённого модуля, как `FakeRemote` у HG-12): к живому серверу
## проба не привязана вовсе.
##
## Проба печатает, СКОЛЬКО проверок сделала; меньше пола — провал, а не «пусто и хорошо».
##
## НЕГАТИВНАЯ ПРОВЕРКА (возврат дефекта, без правки чужого кода):
##   godot --headless --path game res://tools/voice01_probe.tscn -- --voice01-negative
##   Проба эмулирует СНАРУЖИ ровно тот дефект, ради которого проверка написана: внешний обработчик
##   того же сигнала снова зажигает индикатор после `speaking_changed(false)` (сломанный продукт,
##   у которого индикатор не гаснет). Проверка «индикатор гаснет» ОБЯЗАНА покраснеть — иначе она
##   ничего не измеряет.
##
## Вердикт: ==> VOICE-01 PASSED (…) / ==> VOICE-01 FAILED: <причина>
## Запуск:  godot --headless --path game res://tools/voice01_probe.tscn

const MainScript := preload("res://main.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
const ProjScript := preload("res://sdk/projection.gd")
const I18n := preload("res://i18n/i18n.gd")
const UiTheme := preload("res://ui/theme.gd")

## Пол проверок: проба, оборвавшаяся молча, обязана быть красной, а не пустой.
const MIN_CHECKS := 24
## Идентичность говорящего, которой называет себя место голоса (его `driver_label`).
const IDENTITY := "sdk:neuro"
## Существующие кегли продукта: VOICE-01 новых размеров шрифта не вводит.
const EXISTING_SIZES := [9, 10, 11, 12, 13, 14]


## Источник голоса для пробы: те же четыре сигнала, что у вендорённого `NeuroVoiceChat`.
## `pid` — место, за которое он говорит; `pid = -1` повторяет НАСТОЯЩИЙ модуль, который своего
## места не называет (там голос принадлежит SDK-месту матча).
class FakeVoice:
	extends RefCounted

	signal speaking_changed(speaking: bool)
	signal speech_cancelled()
	signal voice_unavailable(reason: String)
	signal voice_ready()

	var pid: int = -1


var _launcher = null
var _fails: Array = []
var _checks := 0
var _frame := 0
var _state := "boot"
var _deadline := 0
var _negative := false


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_negative = _has_flag("--voice01-negative")
	_launcher = MainScript.new()
	add_child(_launcher)


func _has_flag(flag: String) -> bool:
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
			_state = "settle"
			_deadline = Time.get_ticks_msec() + 8000
		"settle":
			if _game_view() == null or _panel() == null or _engine() == null or _seats().size() < 2:
				if Time.get_ticks_msec() >= _deadline:
					_fail("продукт не собрался за 8с: нет движка, менеджера мест, экрана игры или панели мест")
					_finish()
				return
			if _frame < 30:
				return
			_state = "run"
			_run()


func _run() -> void:
	var panel = _panel()
	var gv = _game_view()
	var seats := _seats()
	var proj: Dictionary = ProjScript.new().for_spectator(_engine())
	I18n.set_locale("ru")

	# ФИКСТУРА: место голоса — первое не-человеческое место матча; оно называет себя `driver_label`
	# ровно так, как это делает живой матч (`seat_config` кладёт туда сырое назначение, например
	# `sdk:neuro`).
	var voice_pid := _voice_seat_pid(seats)
	_check(voice_pid >= 0, "в матче нет ни одного не-LOCAL места — мерить «кто говорит» не на ком")
	if voice_pid < 0:
		_finish()
		return
	seats[voice_pid].driver_label = IDENTITY
	var other_pid := _other_seat_pid(seats, voice_pid)
	_check(other_pid >= 0, "в матче только одно место — «у остальных не горит» не на чем мерить")
	if other_pid < 0:
		_finish()
		return

	# --- 0. КОНТРОЛЬ: индикатор есть в каждой карточке, и без источника не горит ни один --------
	panel.call("sync", proj, seats)
	var leds := _leds(panel)
	_check(leds.size() == seats.size(),
		"индикаторов %d, а мест %d — индикатор есть не в каждой карточке" % [leds.size(), seats.size()])
	_check(_lit_count(leds) == 0,
		"без источника голоса уже что-то горит (%d индикатор(ов)) — «кто говорит» показан всегда" % _lit_count(leds))
	print("VOICE-01 PROBE: контроль — %d индикатор(ов) на %d мест, горит %d"
		% [leds.size(), seats.size(), _lit_count(leds)])

	# --- 1. СИГНАЛ ДОХОДИТ ДО ЭКРАНА: карточка ЭТОГО места, идентичность названа ----------------
	var src := FakeVoice.new()
	src.pid = voice_pid
	panel.call("set_voice_source", src)
	panel.call("sync", proj, seats)
	var led = panel.find_child("voice-led-%d" % voice_pid, true, false)
	_check(led != null, "в карточке места %d нет индикатора (`voice-led-%d`)" % [voice_pid, voice_pid])
	if led == null:
		_finish()
		return
	_check(str(led.call("identity")) == IDENTITY,
		"индикатор зовёт говорящего `%s`, а место называет себя `%s`"
			% [str(led.call("identity")), IDENTITY])
	_check(not bool(led.call("is_lit")), "индикатор горит ДО сигнала")
	src.speaking_changed.emit(true)
	_check(bool(led.call("is_lit")), "`speaking_changed(true)` не зажёг индикатор места %d" % voice_pid)
	var dot = led.find_child("led-dot", true, false) as Panel
	var who = led.find_child("led-who", true, false) as Label
	_check(dot != null and dot.visible, "точка индикатора не видна при говорящем месте")
	_check(who != null and who.visible and who.text == IDENTITY,
		"подпись индикатора не называет говорящего: `%s`"
			% (who.text if who != null else "нет узла"))
	print("VOICE-01 PROBE: место %d говорит — индикатор несёт `%s`" % [voice_pid, IDENTITY])

	# --- 2. ИДЕНТИЧНОСТЬ НЕ ПУТАЕТСЯ: горит ровно одно место, и это нужное -----------------------
	leds = _leds(panel)
	_check(_lit_count(leds) == 1,
		"горит %d индикатор(ов), а говорит одно место" % _lit_count(leds))
	_check(_lit_owner(panel) == voice_pid,
		"горит индикатор места %d, а говорит место %d" % [_lit_owner(panel), voice_pid])
	var other_led = panel.find_child("voice-led-%d" % other_pid, true, false)
	_check(other_led != null and not bool(other_led.call("is_lit")),
		"индикатор ЧУЖОГО места %d горит вместе с говорящим" % other_pid)
	print("VOICE-01 PROBE: горит ровно место %d из %d" % [voice_pid, seats.size()])

	# --- 3. ОКНО ПОЯВЛЕНИЯ/ИСЧЕЗНОВЕНИЯ: индикатор не «залипает» -------------------------------
	if _negative:
		# НЕГАТИВ: дефект эмулируется СНАРУЖИ — внешний обработчик того же сигнала снова зажигает
		# индикатор после `speaking_changed(false)` (сломанный продукт, у которого он не гаснет).
		src.speaking_changed.connect(func(_s: bool) -> void: led.call("_on_speaking", true))
	src.speaking_changed.emit(false)
	var went_out := not bool(led.call("is_lit"))
	_check(went_out, "`speaking_changed(false)` НЕ погасил индикатор — он залип")
	if _negative:
		if went_out:
			print("==> VOICE-01 NEGATIVE FAILED: проверка «индикатор гаснет» НЕ кусается — с эмулированным дефектом она осталась зелёной")
			get_tree().quit(1)
			return
		print("==> VOICE-01 NEGATIVE OK: проверка «индикатор гаснет» кусается — с эмулированным дефектом она красная (индикатор места %d остался зажжённым)" % voice_pid)
		get_tree().quit(0)
		return
	src.speaking_changed.emit(true)
	_check(bool(led.call("is_lit")), "второй `speaking_changed(true)` не зажёг индикатор снова")
	src.speech_cancelled.emit()
	_check(not bool(led.call("is_lit")), "`speech_cancelled` не погасил индикатор")
	print("VOICE-01 PROBE: окно появления/исчезновения работает (true зажигает, false и cancelled гасят)")

	# --- 4. ТИХАЯ ДЕГРАДАЦИЯ: `voice_unavailable` гасит и не печатает ни строчки ---------------
	src.speaking_changed.emit(true)
	_check(bool(led.call("is_lit")), "контроль перед деградацией: индикатор не зажёгся")
	src.voice_unavailable.emit("no voice server in this match")
	_check(not bool(led.call("is_lit")), "`voice_unavailable` НЕ погасил индикатор")
	_check(not bool(led.call("is_available")), "`voice_unavailable` не пометил голос недоступным")
	_check(dot == null or not dot.visible, "точка индикатора осталась видимой при недоступном голосе")
	_check(who == null or not who.visible, "подпись говорящего осталась при недоступном голосе")
	# ПРОДУКТ ЖИВ: ошибка не «съела» дерево узлов.
	_check(is_instance_valid(panel) and panel.is_inside_tree(), "панель мест исчезла из дерева после `voice_unavailable`")
	_check(is_instance_valid(gv) and gv.is_inside_tree(), "экран игры исчез из дерева после `voice_unavailable`")
	_check(_cards(panel).size() == seats.size(),
		"после деградации карточек %d вместо %d мест" % [_cards(panel).size(), seats.size()])
	# Голос мёртв: следующий `speaking` НЕ имеет права зажечь индикатор.
	src.speaking_changed.emit(true)
	_check(not bool(led.call("is_lit")), "после `voice_unavailable` индикатор снова горит — деградация ложная")
	print("VOICE-01 PROBE: голос недоступен — индикатор погас, дерево узлов на месте")

	# --- 5. ДЕГРАДАЦИЯ ПЕРЕЖИВАЕТ ПЕРЕРИСОВКУ КАРТОЧЕК ------------------------------------------
	panel.call("sync", proj, seats)
	var led2 = panel.find_child("voice-led-%d" % voice_pid, true, false)
	_check(led2 != null, "после перерисовки в карточке места %d нет индикатора" % voice_pid)
	_check(led2 != null and not bool(led2.call("is_available")),
		"перерисовка карточек воскресила голос (карточки пересобираются на каждой проекции)")
	var card = panel.find_child("seat-card-%d" % voice_pid, true, false)
	_check(card != null and str(card.tooltip_text).find(I18n.t("voice.unavailable")) >= 0,
		"подсказка карточки не говорит, что голос недоступен: `%s`"
			% (str(card.tooltip_text) if card != null else "нет карточки"))
	src.speaking_changed.emit(true)
	_check(led2 != null and not bool(led2.call("is_lit")),
		"после перерисовки индикатор снова горит при недоступном голосе")
	print("VOICE-01 PROBE: деградация пережила перерисовку карточек и названа в подсказке карточки")

	# --- 6. ГОЛОС ВЕРНУЛСЯ: `voice_ready` снимает деградацию ------------------------------------
	src.voice_ready.emit()
	_check(led2 != null and bool(led2.call("is_available")), "`voice_ready` не вернул голос")
	src.speaking_changed.emit(true)
	_check(led2 != null and bool(led2.call("is_lit")), "после `voice_ready` индикатор не загорелся")
	_check(led2 != null and str(led2.call("identity")) == IDENTITY,
		"после перерисовки индикатор потерял идентичность говорящего")
	print("VOICE-01 PROBE: `voice_ready` вернул голос, индикатор снова зажигается")

	# --- 7. ПУТЬ НАСТОЯЩЕГО МОДУЛЯ: источник БЕЗ своего места → SDK-место матча ------------------
	# Вендорённый `NeuroVoiceChat` не знает pid: его голос принадлежит SDK-месту. Место ищется по
	# водителю — и это тот же путь, которым пойдёт живой продукт.
	src.speaking_changed.emit(false)
	seats[other_pid].input_driver = "SDK"
	var src2 := FakeVoice.new()          # pid = -1: место не названо
	panel.call("set_voice_source", src2)
	panel.call("sync", proj, seats)
	var led3 = panel.find_child("voice-led-%d" % other_pid, true, false)
	_check(led3 != null, "в карточке SDK-места %d нет индикатора" % other_pid)
	src2.speaking_changed.emit(true)
	_check(led3 != null and bool(led3.call("is_lit")),
		"источник без своего места не привязался к SDK-месту %d" % other_pid)
	var led_voice = panel.find_child("voice-led-%d" % voice_pid, true, false)
	_check(led_voice != null and not bool(led_voice.call("is_lit")),
		"говорит SDK-место %d, а горит место %d" % [other_pid, voice_pid])
	_check(_lit_count(_leds(panel)) == 1,
		"два источника голоса зажгли %d индикатор(ов)" % _lit_count(_leds(panel)))
	print("VOICE-01 PROBE: источник без места привязался к SDK-месту %d" % other_pid)

	# --- 8. КАРТОЧКА НЕ СЛОМАНА: дверь, инвентарь и место индикатора ----------------------------
	var card2 = panel.find_child("seat-card-%d" % voice_pid, true, false)
	_check(card2 != null and (card2 as Control).mouse_filter == Control.MOUSE_FILTER_PASS,
		"карточка перестала пропускать нажатие — дверь в `drawer-seats` сломана")
	_check(card2 != null and card2.find_child("inv-focus-%d" % voice_pid, true, false) != null,
		"в карточке пропала кнопка инвентаря (E-5)")
	_check(panel.find_child("seat-cards", true, false) != null, "в панели нет списка карточек (`seat-cards`)")
	var card_other = panel.find_child("seat-card-%d" % other_pid, true, false)
	_check(card_other != null and led3 != null and _is_descendant(card_other, led3),
		"индикатор не внутри карточки своего места")

	# --- 9. ЦВЕТ И КЕГЛЬ: токен скина и существующий размер; подсказка переводится --------------
	var dot_now = led3.find_child("led-dot", true, false) as Panel
	var who_now = led3.find_child("led-who", true, false) as Label
	var want: Color = UiTheme.COL().success
	var got: Color = (dot_now.get_theme_stylebox("panel") as StyleBoxFlat).bg_color if dot_now != null else Color.BLACK
	_check(dot_now != null and got.is_equal_approx(want),
		"цвет индикатора не токен скина `success`: %s" % got.to_html(false))
	_check(who_now != null and EXISTING_SIZES.has(int(who_now.get_meta("design_px"))),
		"индикатор ввёл новый размер шрифта: %s"
			% (str(who_now.get_meta("design_px")) if who_now != null else "нет подписи"))
	var ru_tip := str(led3.tooltip_text)
	_check(ru_tip == I18n.t("voice.speaking", [str(led3.call("identity"))]),
		"подсказка зажжённого индикатора не называет говорящего: `%s`" % ru_tip)
	# ЖИВОЙ ПЕРЕВОД (SG-08): подсказка пере-выводится из состояния на смене языка.
	I18n.set_locale("en")
	panel.call("retranslate")
	var led_en = panel.find_child("voice-led-%d" % other_pid, true, false)
	_check(led_en != null and str(led_en.tooltip_text) == I18n.t("voice.speaking", [str(led_en.call("identity"))]),
		"в EN подсказка индикатора не перевелась: `%s`"
			% (str(led_en.tooltip_text) if led_en != null else "нет индикатора"))
	I18n.set_locale("ru")
	print("VOICE-01 PROBE: цвет — токен скина, кегль существующий, подсказка переводится")

	# --- 10. ПРОДУКТОВАЯ ПРОВОДКА: голос создаёт ПРОДУКТ, а не проба --------------------
	# Всё выше мерило логику индикатора на ПОДСТАВЛЕННОМ источнике. Но обещание «кто
	# говорит» - это обещание ПРОДУКТА: в настоящей игре модуль голоса должен
	# существовать и доезжать до карточки. Пока продукт его не создавал, индикатор был
	# мёртвым кодом с зелёным гейтом, и гейт этого не замечал. Теперь замечает:
	# убери проводку из main.gd/seat_manager - эта проверка покраснеет.
	var SeatScript := load("res://seats/seat.gd")
	var SettingsScript := load("res://core/game_settings.gd")
	var st2 = SettingsScript.new()
	st2.seat_count = 2
	st2.starting_order = "manual"
	var seats_sdk: Array = []
	var s_sdk = SeatScript.new(0)
	s_sdk.name = "Neuro"
	s_sdk.input_driver = "SDK"
	s_sdk.driver_label = "sdk:neuro"
	seats_sdk.append(s_sdk)
	var s_host = SeatScript.new(1)
	s_host.name = "Host"
	s_host.input_driver = "LOCAL"
	seats_sdk.append(s_host)
	var l2 = MainScript.new()
	add_child(l2)
	l2.call("_build_game", st2, seats_sdk)
	var mgr2 = l2.get("_manager")
	_check(mgr2 != null and mgr2.has_method("voice_source"),
		"менеджер мест не отдаёт источник голоса - продуктовая проводка отсутствует")
	var vsrc = mgr2.call("voice_source") if mgr2 != null else null
	_check(vsrc != null, "продукт не создал канал голоса для SDK-места")
	var gv2 = l2.get("_game_view")
	var panel2 = gv2.get("_seats_panel") if gv2 != null else null
	_check(panel2 != null, "в продукте нет панели мест")
	var bound = panel2.get("_voice_sources") if panel2 != null else {}
	_check(bound is Dictionary and not bound.is_empty(),
		"оболочка не передала источник голоса панели мест - в игре индикатор не загорится")
	# ТИХАЯ ДЕГРАДАЦИЯ В ПРОДУКТЕ: сервера голоса нет (NEURO_SDK_WS_URL не задан) -
	# настоящий модуль говорит `voice_unavailable`, и ПАНЕЛЬ это видит и гаснет.
	panel2.call("sync", proj, seats_sdk) if panel2 != null else null
	var vstate = panel2.get("_voice_state") if panel2 != null else {}
	_check(vstate is Dictionary and not vstate.is_empty(),
		"панель не знает состояние голоса")
	var any_unavailable := false
	for k in (vstate as Dictionary):
		if not bool((vstate[k] as Dictionary).get("available", true)):
			any_unavailable = true
	_check(any_unavailable,
		"настоящий модуль голоса сообщил о недоступности, но панель этого не увидела")
	print("VOICE-01 PROBE: продукт создал канал голоса и передал его карточкам")

	_finish()


## --- доступ к живому продукту -----------------------------------------------------------------

func _game_view():
	return _launcher.get("_game_view")


func _engine():
	return _launcher.get("_engine")


func _manager():
	return _launcher.get("_manager")


func _panel():
	var gv = _game_view()
	return gv.get("_seats_panel") if gv != null else null


func _seats() -> Array:
	var mgr = _manager()
	if mgr == null:
		return []
	var s = mgr.get("seats")
	return s if s is Array else []


## Место голоса: первое место, которым управляет не человек.
func _voice_seat_pid(seats: Array) -> int:
	for s in seats:
		var d := str(s.input_driver)
		if d != "LOCAL" and d != "ADMIN":
			return int(s.pid)
	return -1


## Второе место (для «у остальных не горит» и для SDK-места): предпочитаем не-человеческое.
func _other_seat_pid(seats: Array, skip: int) -> int:
	var fallback := -1
	for s in seats:
		if int(s.pid) == skip:
			continue
		if fallback < 0:
			fallback = int(s.pid)
		if str(s.input_driver) != "LOCAL":
			return int(s.pid)
	return fallback


func _leds(panel) -> Array:
	var out: Array = []
	_collect_named(panel, "voice-led-", out)
	return out


func _cards(panel) -> Array:
	var out: Array = []
	_collect_named(panel, "seat-card-", out)
	return out


func _collect_named(root: Node, prefix: String, out: Array) -> void:
	if root == null:
		return
	if str(root.name).begins_with(prefix):
		out.append(root)
	for c in root.get_children():
		_collect_named(c, prefix, out)


func _lit_count(leds: Array) -> int:
	var n := 0
	for l in leds:
		if bool(l.call("is_lit")):
			n += 1
	return n


func _lit_owner(panel) -> int:
	for l in _leds(panel):
		if bool(l.call("is_lit")):
			return int(l.get("pid"))
	return -1


func _is_descendant(maybe_ancestor: Node, node: Node) -> bool:
	var n: Node = node.get_parent()
	while n != null:
		if n == maybe_ancestor:
			return true
		n = n.get_parent()
	return false


## --- отчёт ------------------------------------------------------------------------------------

func _check(ok: bool, why: String) -> void:
	_checks += 1
	if ok:
		return
	_fails.append(why)
	push_error("VOICE-01: " + why)


func _fail(why: String) -> void:
	_check(false, why)


func _finish() -> void:
	_state = "done"
	print("VOICE-01 PROBE: %d checks, %d red" % [_checks, _fails.size()])
	if _checks < MIN_CHECKS and _fails.is_empty():
		_fails.append("проба сделала %d проверок (пол %d) — молчаливый обрыв нельзя считать зелёным"
			% [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> VOICE-01 PASSED (%d проверок: сигнал доходит до карточки СВОЕГО места и несёт `driver_label`, идентичность не путается, `speaking_changed(false)` и `speech_cancelled` гасят, `voice_unavailable` деградирует тихо и переживает перерисовку карточек, `voice_ready` возвращает голос, источник без места привязывается к SDK-месту)" % _checks)
		get_tree().quit(0)
		return
	print("==> VOICE-01 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
	get_tree().quit(1)
