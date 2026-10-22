extends PanelContainer
## VOICE-01 «КТО ГОВОРИТ» — компонент-индикатор говорящего в карточке места.
##
## ОБЕЩАНИЕ (docs/program.md §3а, пункт D1): у игрока должно быть видно, КТО говорит. Вендорённый
## SDK-модуль (`game/addons/neuro-sdk/voice/voice_chat.gd`) отдаёт `speaking_changed(speaking)`,
## `speech_cancelled()`, `voice_unavailable(reason)`, `voice_ready()` — но в продукте (`game/`) у
## этих сигналов не было НИ ОДНОГО потребителя (`git grep speaking_changed -- game/` находил только
## сам аддон). Обещание висело TODO: ни кода, ни гейта.
##
## ЧТО ЭТО. Индикатор живёт В КАРТОЧКЕ МЕСТА и говорит ЗА ЭТО место: у него есть `pid` (место) и
## `identity` (его `driver_label` — то же «сырое назначение», что карточка уже печатает в строке
## позиции). Пока никто не говорит, компонент занимает НОЛЬ пикселей — точка и подпись скрыты, и
## карточка выглядит ровно как до VOICE-01. По `speaking_changed(true)` точка загорается цветом
## скина и рядом появляется идентичность говорящего: «кто говорит» НАЗВАНО словом, а не
## угадывается по свечению.
##
## ИСТОЧНИК ПОДСТАВЛЯЕТСЯ СНАРУЖИ (`bind`). Компонент не знает ни про вебсокет, ни про
## `NEURO_SDK_WS_URL`: живой сервер голоса — внешний блокер, а измеряемая часть обещания — наша
## логика. Поэтому источником может быть настоящий `NeuroVoiceChat`, мок или `FakeVoice` пробы.
## Отсутствие любого из четырёх сигналов — не ошибка, а «этого канала у источника нет».
##
## ТИХАЯ ДЕГРАДАЦИЯ (`voice_unavailable`). Сервера голоса нет — индикатор ГАСНЕТ и молчит: ни
## `push_error`, ни `push_warning`, ни красного на экране. Продукт обязан работать без голоса.
## Состояние «голос недоступен» переживает перерисовку карточек: панель помнит его по `state_changed`
## (карточки пересобираются на каждой проекции — иначе деградация «воскресала» бы вместе с карточкой).
##
## Вердикт по этому компоненту выносит `tools/ci/gates/voice01_gate.sh` (проба —
## `game/tools/voice01_probe.tscn`): сигнал доходит до экрана, идентичность не путается, деградация
## тихая, индикатор не залипает.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

## Место, за которое говорит индикатор (-1 = не привязан к месту).
var pid: int = -1

## Состояние индикатора изменилось. Панель карточек слушает это, чтобы ПОМНИТЬ состояние между
## перерисовками (карточки пересобираются на каждой проекции).
signal state_changed(seat_pid: int, lit: bool, available: bool)

var _identity := ""
var _lit := false
var _available := true
var _source: Object = null

var _dot: Panel
var _who: Label


func _init() -> void:
	# Прозрачная панель: компонент — ЧИП из точки и подписи, а не ещё одна рамка в карточке.
	add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	# PASS, а не IGNORE: подсказка индикатора — место, где сказано «говорит: <кто>», и она не имеет
	# права отобрать нажатие у карточки (карточка остаётся дверью в `drawer-seats`).
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UiTheme.hbox(4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	# ЦВЕТ — ТОЛЬКО ТОКЕН СКИНА: палитра живёт в скине, а не в компоненте.
	var col: Color = UiTheme.COL().success
	_dot = Panel.new()
	_dot.name = "led-dot"
	_dot.custom_minimum_size = Vector2(10, 10)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.add_theme_stylebox_override("panel", UiTheme.box(col, col, 1, 5))
	row.add_child(_dot)
	# КЕГЛЬ — СУЩЕСТВУЮЩИЙ (9px, как чипы карточки): новых размеров шрифта компонент не вводит.
	_who = UiTheme.label("", 9, col)
	_who.name = "led-who"
	# РОЛЬ ЗНАЧЕНИЯ (SG-04): одна строка, по своему содержимому; длинная идентичность обрезается
	# многоточием внутри карточки (SG-02 разрешает это внутри `seats`), а не растягивает пояс.
	_who.clip_text = true
	_who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_who)
	_apply()


## За какое место говорит индикатор и КАК звать говорящего. `identity` — `driver_label` места.
func setup(seat_pid: int, identity: String) -> void:
	pid = seat_pid
	_identity = identity
	_apply()


## Подписаться на источник голоса. Источник — любой объект с сигналами вендорённого модуля;
## каких сигналов у него нет — тех и нет (мок без `voice_ready` индикатор не ломает).
func bind(source: Object) -> void:
	if source == null:
		return
	_source = source
	_connect_once(source, "speaking_changed", _on_speaking)
	_connect_once(source, "speech_cancelled", _on_cancelled)
	_connect_once(source, "voice_unavailable", _on_unavailable)
	_connect_once(source, "voice_ready", _on_ready)


## Состояние, которое панель помнит с прошлой перерисовки: новая карточка не имеет права
## «воскресить» голос, которого нет.
func seed(lit: bool, available: bool) -> void:
	_lit = lit
	_available = available
	_apply()


## Источник, к которому привязан индикатор (null — никто).
func source() -> Object:
	return _source


## Горит ли индикатор: говорит И голос вообще доступен.
func is_lit() -> bool:
	return _lit and _available


## Идентичность говорящего (`driver_label` места).
func identity() -> String:
	return _identity


## Доступен ли голос: `voice_unavailable` гасит его до `voice_ready`.
func is_available() -> bool:
	return _available


func _connect_once(source: Object, sig: String, handler: Callable) -> void:
	if source.has_signal(sig) and not source.is_connected(sig, handler):
		source.connect(sig, handler)


func _on_speaking(speaking: bool) -> void:
	if not _available:
		return
	_lit = speaking
	_apply()


func _on_cancelled() -> void:
	_lit = false
	_apply()


func _on_unavailable(_reason: String) -> void:
	# ТИХАЯ ДЕГРАДАЦИЯ: сервера голоса нет. Гасим индикатор и НИЧЕГО не печатаем — голос
	# необязателен по контракту (`API/VOICE_CHAT.md`), и «красный» на экране был бы дефектом.
	_available = false
	_lit = false
	_apply()


func _on_ready() -> void:
	_available = true
	_apply()


func _apply() -> void:
	var on := is_lit()
	if _dot != null:
		_dot.visible = on
	if _who != null:
		_who.visible = on
		_who.text = _identity if on else ""
	# Подсказка: пока никто не говорит — молчит; при недоступном голосе называет причину словами.
	if on:
		tooltip_text = I18n.t("voice.speaking", [_identity])
	elif not _available:
		tooltip_text = I18n.t("voice.unavailable")
	else:
		tooltip_text = ""
	state_changed.emit(pid, on, _available)
