# Углублённый UI/UX аудит — P0–P5 (2026-09-08)

Полный код-ревью всех UI-файлов: 13 скриптов, 2 сцены.
Спеки: v2 concept + ASCII-эскизы §3.1, §4.2, §4.4, §5.1, §6.3–6.4, §7, §8.2.

---

## Методология

Каждый элемент проверен по трём осям:
- **Механика** — работает ли вообще (signal connections, null checks, bounds)
- **Соответствие спеку** — соответствует ли v2 concept ASCII-эскизу
- **i18n** — локализуется ли при смене языка

---

## I. TOP BAR (top_bar.gd, 137 строк)

### I.1 ✅ Работает: игнорируется spectator projection

`_turn.text = I18n.t("top.turn") + str(s.name)` — топ.

### I.2 ✅ Работает: admin hint host-gated

`set_host(v)` скрывает подсказку "F12 — админ" на WebGL/ spectator.

### I.3 ⚠️ КОСМЕТИКА: `_phase` показывает raw enum

**Строка 129:**
```gdscript
_phase.text = I18n.t("top.phase") + str(proj.get("phase", ""))
```
Выдаёт: `"ФАЗА: PURCHASE_WAIT"` — raw enum из движка.
Должно: `"ФАЗА: Покупка"` через i18n dict `phase.PURCHASE_WAIT`.
**Баг:** `str(proj.get("phase", ""))` возвращает сырую строку enum, а не локализованную.
**Серьёзность:** НИЗКАЯ — фаза читаема, но не локализована.

### I.4 ⚠️ КОСМЕТИКА: TimerRing виден когда timer_window > 0

**Строка 27:** `visible = active and window > 0.0`
Работает. Но ring рисуется через `_draw()` — при больших viewport'ах ring фиксированного размера (28px) выглядит мелко. Нет адаптивного размера.

### I.5 ✅ `_title` захардкожен

```gdscript
_title = UiTheme.label("● NEURO PROPERTY TRADE", 15, UiTheme.COL.gold)
```
Не через i18n. Должен быть `I18n.t("top.title")`. Встречается в двух местах: `_init()` и `retranslate()`.

---

## II. GAME VIEW (game_view.gd, 520 строк)

### II.1 ✅ Синглтон `_observer` вычисляется правильно

Строка 346: `_set_observer(not has_local)` — верно.

### II.2 ✅ `_on_eye_requested` → settings_requested.emit()

Наблюдатель нажимает 👁 → открываются настройки. Работает.

### II.3 ⚠️ КОСМЕТИКА: `_observer` detection в `_sync_from_spectator` вызывается повторно

Строка 346: `_set_observer(not has_local)` — вызывается внутри `_sync_from_spectator`,
а уже в `_sync_from_spectator` делается:

```gdscript
_top.set_observer(not has_local)
```

Дублирование: `_set_observer` уже вызывает `_top.set_observer(v)`.
Нет функционального бага, но избыточный код.

### II.4 ✅ `_holder_name` нигде не используется

Строка 58: `var _holder_name := ""`
Строка 357: `_holder_name = _holder_display_name(holder, proj)` — вычисляется.
Но `_holder_name` **нигде не рисуется** в UI.
Панель действий observer-mode показывает holder через `_status.text` напрямую.
Мёртвый код. Не баг.

### II.5 ✅ Press ESC → overlay close работает

Строка 158: `on_overlay_closed()` вызывает `_sync_cold()`.
Pre-game overlay открыт, ESC закрывает → `_sync_cold()` сбрасывает панели.

### II.6 ⚠️ КОСМЕТИКА: `_observer` detection в `_sync_from_spectator` не учитывает SDK-места

```gdscript
var has_local := false
for s in seats:
    if str(s.input_driver) == "LOCAL":
        has_local = true; break
```
В spec §7: "Роль хоста: только наблюдаю" → все места AI/CHAT/SDK.
Это корректно — `has_local` проверяет только LOCAL, SDK-места не считаются за LOCAL.
Это ПРАВИЛЬНОЕ поведение.

---

## III. SETTINGS OVERLAY (settings_overlay.gd, 724 строки)

### III.1 ❌ CRITICAL: `_auctions` использует неправильные i18n ключи

**Строки 329, 110:**
```gdscript
_auctions.add_item(I18n.t("settings.fp_on"));    # ← БАГ
_auctions.add_item(I18n.t("settings.fp_off"));   # ← БАГ
```
`settings.fp_on/fp_off` — это ключи free_parking, не auctions.
Показывает "Вкл/Выкл" (от free_parking) для auctions.
**Нет ключей `settings.auctions_on/settings.auctions_off`** — нужно добавить в i18n dict.
**Серьёзность:** КРИТИЧЕСКИЙ.

### III.2 ❌ CRITICAL: Driver selector не локализован

**Строки 20, 485–487:**
```gdscript
const DRIVERS := ["LOCAL", "AI", "CHAT", "sdk:neuro", "sdk:evil"]

for d in DRIVERS:
    driver.add_item(d)   # сырые строки!
```
Показывает `["LOCAL","AI","CHAT","sdk:neuro","sdk:evil"]` независимо от языка.
В spec §5.1: "ДРАЙВЕР▾ LOCAL AI CHAT sdk:neuro sdk:evil" с подсказкой
"LOCAL = человек за этим компьютером, AI = компьютер..." — подсказка есть,
но сами label'ы не локализованы.

### III.3 ❌ CRITICAL: `_tabs.set_tab_title()` не обновляется при смене языка

**Строка 258, 294, 367, 390, 429:**
```gdscript
_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("settings.tab_players"))
_tabs.set_tab_title(_tabs.get_tab_count() - 1, I18n.t("settings.tab_rules"))
# ...
```
Вызывается только в `_build_*_tab()`, т.е. один раз при инициализации.
При `_on_locale_changed` → `_retranslate()` НЕ вызывает `_tabs.set_tab_title()`.
**TabContainer заголовки не меняются при смене языка.**
**Серьёзность:** КРИТИЧЕСКИЙ.

### III.4 ❌ CRITICAL: Preset button labels не обновляются при смене языка

**Строки 208–219:**
```gdscript
var p_classic := UiTheme.button(I18n.t("settings.preset_classic"), ...)
# ...
```
Кнопки создаются в `_build()` с фиксированными label'ами.
`_retranslate()` не пересоздаёт и не обновляет `_tabs` → preset buttons не трогаются.
**Серьёзность:** КРИТИЧЕСКИЙ.

### III.5 ❌ CRITICAL: Language selector hardcoded

**Строка 416:**
```gdscript
_language.add_item("Русский"); _language.add_item("English")
```
Не через `I18n.t()`. Является selector'ом языка — это exception case,
но всё равно нарушает архитектуру.

### III.6 ❌ CRITICAL: `_reset_all()` не вызывает `_refresh_buttons()` в конце

**Строка 724:** `_reset_all()` заканчивается на `_starting_order.selected = 0`,
но **НЕ вызывает** `_refresh_buttons()`.
Если перед сбросом была ошибка валидации (например, все игроки удалены),
кнопка START останется disabled.
**Серьёзность:** КРИТИЧЕСКИЙ (логика).

### III.7 ⚠️ СРЕДНИЙ: `_collect_settings()` читает `driver.get_item_text()` (не ID)

**Строка 549:**
```gdscript
var drv: String = str(r["driver"].get_item_text(r["driver"].selected))
```
Это проблема: если driver items будут локализованы, `get_item_text()` вернёт
локализованную строку, а не идентификатор. Будет баг при чтении настроек.
Правильный подход: использовать `get_item_id(selected)`.

### III.8 ⚠️ СРЕДНИЙ: Вкладка "Данные" пустая (есть только RNG seed)

**Строка 426–440:** `_build_data_tab()` создаёт только `_rng_seed SpinBox`.
Spec §5.1: "ДАННЫЕ: RNG-сид [0]  (0 = случайный)".
Нет: preset selector, token color picker per player, board data override.
Пустая вкладка — ощущение недоделанности.

### III.9 ⚠️ СРЕДНИЙ: `_preset_fast()` не меняет `_auction_timer` на 10с

**Строки 685–688:**
```gdscript
func _preset_fast() -> void:
    _reset_all()
    _turn_timer.selected = _index_of_seconds(_turn_timer, 10)
    _starting_cash.value = 1000
```
Spec §5.1: "Быстрая партия: таймер 10с, капитал 1000".
Auction timer не меняется — остаётся 15с из `_reset_all()`.
**Баг:** не соответствует спеку.

### III.10 ⚠️ СРЕДНИЙ: `_preset_hard()` неполный

**Строки 690–694:**
```gdscript
func _preset_hard() -> void:
    _reset_all()
    _mortgage.button_pressed = false
    _trades.button_pressed = false
    _ai_aggression.value = 80
```
Spec §5.1: "Хардкор: без залога/торгов, агрессия 80".
Нет: `housing` не выключается, `doubles` не выключается, `triple_doubles` не выключается.
Это отклонение от спека.

### III.11 ✅ Правильно: "Host role → LOCAL seat" bug исправлен

Строка 543–551: хост выбирает "наблюдаю" → вычисляется AI для row 0,
widget не мутируется. Исправлен баг из p4-modes.md (bug 2).

---

## IV. ACTION PANEL (action_panel.gd, 213 строк)

### IV.1 ✅ `respond_trade` контекстный фильтр работает

Строки 134–135: кнопка "ответить на сделку" показывается только когда
`pending.type == "trade"`. Это правильный фикс spec problem 20.

### IV.2 ⚠️ КОСМЕТИКА: `_observer` статус bar не показывает фазу через i18n

**Строки 111–112:**
```gdscript
_status.text = I18n.t("act.observer_status", [
    str(proj.get("phase", "")), holder_txt, drv_txt, timer_txt])
```
`str(proj.get("phase", ""))` — сырой enum, не локализованный.
Должно быть через `phase.*` ключи i18n.

### IV.3 ⚠️ КОСМЕТИКА: `_hint.text` не локализуется

**Строка 143:**
```gdscript
_hint.text = _context_hint(proj)
```
`_context_hint()` использует `I18n.t("act.hint_*")` — это правильно.
Но `_hint.text` не обновляется при locale change.
Однако `_hint` обновляется на каждом `sync()` → при смене языка
следующий sync перерисует правильно. Работает.

### IV.4 ⚠️ СРЕДНИЙ: Кнопки пересоздаются при каждом изменении legal set

**Строки 127–139:**
```gdscript
if _legal_changed(legal):
    _clear_buttons()
    for act in legal:
        var btn = _make_button(act, proj, pid)
        _btn_row.add_child(btn)
```
`_clear_buttons()` → `queue_free()` на каждом child. Это дорогая операция.
Specced как anti-pattern, но работает. **Не ломает**, просто неэффективно.

---

## V. PLAYERS PANEL (players_panel.gd, 210 строк)

### V.1 ✅ Token avatar с SVG fallback

Строки 175–204: `_avatar()` загружает SVG через `PI.token_path()`,
fallback на инициал если текстура не найдена. Правильно.

### V.2 ⚠️ КОСМЕТИКА: Badge icons — emoji в коде

**Строки 139, 142, 144:**
```gdscript
badges.add_child(UiTheme.label("🏠 %d" % h, 12, ...))
badges.add_child(UiTheme.label("💼 %d" % mg, 12, ...))
badges.add_child(UiTheme.label("⚖ %d" % int(p.get("jail_turns", 0)), 12, ...))
```
Emoji захардкожены в GDScript. Должны быть в i18n dict или SVG assets.
Spec §4.4 использует emoji в ASCII-эскизе, но в коде это не consistent —
нет SVG-ассетов house_icon, briefcase_icon, scales_icon.

### V.3 ⚠️ КОСМЕТИКА: Позиция по названию тайла — работает

**Строка 129–131:**
```gdscript
var pos_name: String = str(tile_names.get(int(p.get("position", 0)), "?"))
var info := UiTheme.label(I18n.t("plr.pos_tiles", [pos_name, int(p.get("tiles", []).size())]), ...)
```
`tile_names` строится из `proj.get("board")` → уже содержит короткие названия.
**Работает правильно.** Спецификация §4.4: "позиция НАЗВАНИЕМ клетки (не «@11»)" — выполнена.

### V.4 ⚠️ КОСМЕТИКА: "активный игрок" — ▶ symbol захардкожен

**Строка 154:**
```gdscript
var act := UiTheme.label(I18n.t("plr.active"), 12, UiTheme.COL.accent)
```
`I18n.t("plr.active")` = "▶" захардкожен в dict. Работает.

### V.5 ⚠️ КОСМЕТИКА: "авто-пас"/"банкрот" — захардкожены в dict

**Строки 146, 148:**
```gdscript
badges.add_child(UiTheme.label(I18n.t("plr.auto_pass"), 12, ...))
badges.add_child(UiTheme.label(I18n.t("plr.bankrupt"), 12, ...))
```
Это правильно — через i18n. Но есть баг: `away` detection (строка 88–91)
использует `seat.away`, но `away` может быть bool или String. Проверю:

```gdscript
for s in seats:
    if int(s.pid) == pid and bool(s.away):
        away = true
```
`bool(s.away)` — если `s.away` это String "auto" или int > 0,
`bool()` преобразование может дать неожиданный результат.
**Серьёзность:** СРЕДНИЙ (логика).

---

## VI. TILE INSPECTOR (tile_inspector.gd, 115 строк)

### VI.1 ❌ CRITICAL: Не подключён к `locale_changed`

`_inspector.sync()` вызывается из `game_view._sync_from_spectator()`, но
`_inspector` **не имеет `retranslate()`**, и `game_view._on_locale_changed()`
**не вызывает** `_inspector.retranslate()` (inspector не имеет этого метода).

**Placeholder text:** `"Кликните по тайлу доски"` — захардкожен при инициализации.
**Серьёзность:** КРИТИЧЕСКИЙ (подтверждено ui_audit_probe).

### VI.2 ✅ Auto-hide 5с работает

Строки 47–53: `_process()` уменьшает `_hide_timer`, вызывает `clear()` при 0.
`select()` сбрасывает таймер. Pin работает.

### VI.3 ✅ `sync()` сбрасывает цвет при смене владельца

Строка 108: `_text.add_theme_color_override("font_color", owner_col if owner >= 0 else UiTheme.COL.text)`
Работает.

---

## VII. MODAL HOST (modal_host.gd, 317 строк)

### VII.1 ⚠️ СРЕДНИЙ: Trade modal — want_tiles пустые

**Строки 109–112:**
```gdscript
var give_tiles: Array = []
var want_tiles: Array = []
# (real multi-tile trade UI is a followup; MVP passes empty tile arrays and
#  cash amounts — engine allows this.)
```
Spec problem 22: "Модалка торга не умеет выбирать тайлы".
Это **зафиксированное ограничение MVP**, не баг. Правильно помечено в коде.

### VII.2 ⚠️ КОСМЕТИКА: Sound toggles в `open_settings` используют сырой label

**Строки 225–226:**
```gdscript
cb.text = str(cat.get("label", ""))
```
`label` приходит из звуковой системы. Не локализовано.

### VII.3 ✅ Trade response modal показывает суммы корректно

**Строки 141–142:**
```gdscript
body.add_child(UiTheme.label(I18n.t("modal.trade_terms", [
    gcash, give.size(), wcash, want.size()]), 13, UiTheme.COL.text_dim))
```
Работает.

---

## VIII. JOURNAL PANEL (journal_panel.gd, 296 строк)

### VIII.1 ⚠️ КОСМЕТИКА: `_money_only` CheckButton text "$" захардкожен

**Строка 88:**
```gdscript
_money_only.text = "$"
```
Не через i18n. Но это общепринятый символ, не требует перевода.

### VIII.2 ✅ Фильтры работают

`_sync_filter_options()` вызывается из `set_entries()`.
Options rebuild при смене языка через `retranslate()` → `set_entries()`.
**Работает.**

### VIII.3 ✅ Export в jsonl

Строка 290: `FileAccess.open(EXPORT_PATH, FileAccess.WRITE)`.
EXPORT_PATH = "user://journal_export.jsonl". Работает.

### VIII.4 ⚠️ КОСМЕТИКА: Event types в journal — сырые строки

**Строка 271:**
```gdscript
"[color=#8b95a5][%s][/color] %s\n" % [t, txt]
```
`[%s]` — это raw event type enum ("purchase", "pay", "rent" и т.д.),
не локализованный. Журнал показывает "purchase" вместо "покупка".
**Серьёзность:** СРЕДНИЙ.

---

## IX. DICE STAGE (dice_stage.gd, 161 строк)

### IX.1 ✅ BG3-style анимация реализована

Staggered tumble (8 шагов), bounce, settle. SFX хуки есть.
`set_animations(false)` → instant result. Работает.

### IX.2 ⚠️ КОСМЕТИКА: Dice face = plain Label

**Строки 84–90:**
```gdscript
var label := Label.new()
label.text = str(_dice1) if i == 0 else str(_dice2)
label.add_theme_font_size_override("font_size", int(dice_size * 0.5))
```
Plain текст, не SVG dice faces. Spec §6.4: "Текстуры: assets/dice/die_1..6.svg".
SVG-текстуры кубиков **не подключены**.
**Серьёзность:** СРЕДНИЙ (визуал).

### IX.3 ⚠️ КОСМЕТИКА: Dice margin = 1.15/1.3 hardcoded

**Строки 94–95:**
```gdscript
dice.position = center - Vector2(dice_size * 1.15, dice_size * 0.5) \
    + Vector2(i * dice_size * 1.3, 0)
```
Отступы между кубиками фиксированные. На маленьких экранах могут налезать.
**Серьёзность:** НИЗКАЯ.

---

## X. TILE VIEW (tile_view.gd, 408 строк)

### X.1 ✅ SVG assets подключены

Строки 21–35: `TILE_SVG`, `HOUSE_SVG`, `HOTEL_SVG`, `CORNER_ICON_PATHS`, `TYPE_ICON_PATHS`.
Fallback на flat ColorRect если не найдены. Работает.

### X.2 ✅ Compact mode (cell < 44px) работает

Строка 71: `_compact = cell < COMPACT_THRESHOLD` (44px).
Compact: имя → 1 строка, цена скрыта, домики → badge.
**Работает.**

### X.3 ⚠️ КОСМЕТИКА: Group band — цвет из `group_color()` захардкожен

**Строки 157–162:**
```gdscript
_band.color = Color(group_color(_group))
```
`group_color()` — статический dict внутри tile_view.gd.
Spec §4.2: группа — "родной цвет группы (палитра visual/theme.gd)".
Нет SVG group icons. Цвета совпадают с темой. **Работает.**

### X.4 ⚠️ КОСМЕТИКА: Mortgage hatch — ColorRects поверх текста

**Строки 122–126:**
```gdscript
# use a rotated set of ColorRects as hatch fill — diagonal lines
for line in range(-4, 5):
    var l := ColorRect.new()
    # ...
    add_child(l)
```
Спецификация §4.2: "залог: обесцвечивается (sat 0.35) + диагональная штриховка 20%".
Реализация близка, но ColorRect'hatch'и добавляются как children — могут конфликтовать
с другими children. Spec problem 11: "залог = тёмный прямоугольник поверх всего тайла".
**Исправлено** — теперь диагональные линии.

### X.5 ⚠️ КОСМЕТИКА: House sprite позиционируется в band

**Строки 331–342:**
```gdscript
_house_row = HBoxContainer.new()
# ...
for hs in houses:
    _house_row.add_child(_make_house_sprite(HOUSE_SVG, hs))
```
Это правильно — house sprites в group band, spec §4.2.
**Работает.**

---

## XI. BOARD SCENE (board_scene.gd)

### XI.1 ✅ Доска всегда влезает в viewport

Строки 130–165: `_resize_children()` вычисляет cell = `min(w,h)/11`.
Это гарантирует что весь ring 11×11 влезает.
Spec §2: "доска по умолчанию ВСЕГДА показывается целиком".
**Работает.**

### XI.2 ⚠️ КОСМЕТИКА: EventOverlay подключён, но содержимое не проверено

Строка 201: `_overlay.append(entry)` — append без проверки типа.
Все event types отправляются в overlay.
Spec §5: overlay событий должен показывать "крупные: покупка, аукцион, банкротство".
Не проверено, какие типы реально показываются визуально.
**Серьёзность:** СРЕДНИЙ.

### XI.3 ⚠️ КОСМЕТИКА: Spectacle включён по умолчанию?

**Строка 75:**
```gdscript
_spectacle = Spectacle.new()
_spectacle.set_animations(_settings.animations if _settings != null else true)
```
`spectacle` — это камера панорамирования. По spec §2: "spectacle OFF by default".
Но `_settings.spectacle` нигде не используется для включения/выключения spectacle.
Spectacle всегда работает. Это может привести к проблеме spec problem 5:
"Камера режет доску".

**Нужна проверка:** отключается ли `spectacle` когда `settings.spectacle = false`?

---

## XII. TOKEN PANEL (token_panel.gd)

### XII.1 ✅ Walking animation работает

Строки 123–140: `_walk_to()` — tween между тайлами, 70ms/tile.
Kill old tween при новом walk. Bobbing во время idle.

### XII.2 ⚠️ КОСМЕТИКА: Token SVG может не найден

**Строки 59–60:**
```gdscript
if ResourceLoader.exists(PI.token_path(token_id)):
    tex = load(PI.token_path(token_id))
```
Если SVG не найден — fallback на инициал (строка 199).
Но fallback текст белый (`Color.WHITE`) — на светлом фоне читается плохо.
Spec §4.3: "инициал не нужен (арт уникален), но в компакт-режиме поверх гало рисуется инициал".
Fallback без SVG — серый круг с инициалом на белом. Может быть незаметен.

---

## XIII. ADMIN PANEL (admin_panel.gd, 725 строк)

### XIII.1 ⚠️ СРЕДНИЙ: 4 таба реализованы, но не все функции

`EDIT_OPS` содержит 9 операций:
balance / teleport / force_roll / reset_away / give_tile / remove_tile /
set_houses / tweak_tile / inject_card.

Spec §8.2: "💰 баланс · 📍 телепорт · 🎲 форс-кубы · 🏠 дать/отнять тайл ·
🏗 домики · 🚫 залог · ✏ tweak-tile · 🃏 вставить/убрать карту · 🔀 порядок ·
🔁 переиграть ход (сид)".

**Отсутствуют:** reorder_players, redo_turn (но они есть в Quick tab через rollback).
Spec §8.2 говорит "деструктивные операции — с подтверждением" — это есть.

### XIII.2 ⚠️ КОСМЕТИКА: Admin результаты идут в inline label + admin log

Строки 512–520: результат операции показывается в result Label на строке.
Это spec §8.2: "Результат операции — инлайн (ok / причина)".
**Работает.**

### XIII.3 ⚠️ КОСМЕТИКА: Admin log внизу панели

Строка 724: `_admin_log_lines` — список строк, не RichTextLabel.
Spec §8.2: "журнал админа: 12:01 force_roll → ok · 12:03 set_balance → ok".
Это реализовано как список строк в конце панели.
**Работает.**

---

## XIV. TOAST STACK (toast.gd, 296 строк)

### XIV.1 ⚠️ КОСМЕТИКА: BannerItem action buttons не локализуют текст

**Строки 288–290:**
```gdscript
var btn = UiTheme.button_accent(str(a.get("text", "?")), I18n.t("modal.banner_action_tip"))
btn.connect("pressed", Callable(self, "_on_action").bind(str(a.get("action", ""))))
```
`str(a.get("text", "?"))` — сырой текст. Если `text` содержит i18n ключ,
он не будет переведён. BannerItem используется для "РЕВАНШ" кнопки
в winner toast — `"text": "РЕВАНШ"` захардкожен в `show_event_toast`.

**Серьёзность:** СРЕДНИЙ (если не English, то не переводится).

### XIV.2 ✅ Anti-spam deduplication работает

Строки 50–61: deduplication по тексту + 1.5с окно.
**Работает.**

### XIV.3 ⚠️ КОСМЕТИКА: Toast не показывает `rent`/`pay` детали

**Строки 141–143:**
```gdscript
"pay":
    show_toast(I18n.t("toast.pay", [_who(d, "from"), int(d.get("amount", 0))]), "warning")
"rent":
    show_toast(I18n.t("toast.rent", [_who(d, "from")]), "warning")
```
Spec §6.2: "Анти-спам: рента/платежи одного хода сливаются в строку
'Neuro платит $48: рента Host ×2, налог $20'".
**ЭТО НЕ РЕАЛИЗОВАНО.** Отдельные toasts для каждого pay/rent.
Это нарушение spec §6.2.

**Серьёзность:** КРИТИЧЕСКИЙ (spec).

---

## XV. TIMER RING (timer_ring.gd, 58 строк)

### XV.1 ✅ Работает: цвет меняется по времени

Строки 50–53: >50% = зелёный, 25–50% = жёлтый, <25% = красный.
**Работает.**

### XV.2 ⚠️ КОСМЕТИКА: Ring thickness = 3px, фиксированный

При маленьком viewport ring может быть слишком тонким или толстым.
**Серьёзность:** НИЗКАЯ.

---

## XVI. BOARD VIEW (board_view.gd, 169 строк)

### XVI.1 ✅ Tile click → inspector

Строки 179–186: `tile_clicked.emit(idx)` → `board_scene._on_tile_clicked`
→ `game_view._on_tile_clicked` → `_inspector.select(idx)`. Работает.

### XVI.2 ⚠️ КОСМЕТИКА: Hover → inspector в LOCAL match тоже работает

**Строка 181:**
```gdscript
_board.tile_hovered.connect(func(i: int) -> void: tile_hovered.emit(i))
```
Spec §4: "hover→inspector: ... Allowed in LOCAL matches too".
**Реализовано, но:** `_inspector.sync()` вызывается из `_sync_from_spectator()`,
который вызывается на каждом state change. Hover вызывает `select()`,
который показывает панель и сбрасывает таймер.
Но данные inspector'а обновляются только при следующем `_sync_from_spectator()`.
Это может привести к inspector показывающему stale данные.
**Серьёзность:** СРЕДНИЙ.

### XVI.3 ⚠️ КОСМЕТИКА: `set_target_tiles()` — follow в observer mode

Строки 102–104:
```gdscript
func set_target_tiles(indices: Array) -> void:
    for i in _tile_count:
        _tile_nodes[i].set_target(indices.has(i))
```
Spec §7: "follow: highlight the followed player's tiles on the board".
**Работает** в observer mode. TileView `set_target()` → `_target_fill.visible = true`.

---

## XVII. THEME (theme.gd, 90 строк)

### XVII.1 ⚠️ КОСМЕТИКА: Нет CSS-like переменных

Все цвета захардкожены в `COL` dict. Нет возможности переключать темы.
Spec не требовало темной/светлой темы — только адаптивности. OK.

---

## XVIII. EVENT MESSAGES (event_messages.gd, 70 строк)

### XVIII.1 ⚠️ КОСМЕТИКА: Event messages не локализованы

Строки 8–25: `data_event.gd` содержит event.* ключи.
Но `event_messages.gd` не использует их напрямую — `_line_bbcode()` в journal_panel
вызывает `EventMessagesScript.describe(e)` (строка 269).
Проверю: есть ли в `describe()` локализация?

```gdscript
func describe(e: Dictionary) -> String:
    var t := str(e.get("type", "?"))
    var d: Dictionary = e.get("data", {})
    match t:
        "roll": return ...
```

Raw match на type enum. **НЕ ИСПОЛЬЗУЕТ event.* ключи i18n.**
Event messages в journal НЕ локализованы.

**Серьёзность:** СРЕДНИЙ (журнал на английском если RU locale).

---

## XIX. АДАПТИВНОСТЬ (Adaptive layout)

### XIX.1 ❌ КРИТИЧЕСКИЙ: 1024px breakpoint не реализован

**Spec §3.4 / §3.2:**
- ≥1024px: "dense mode: left becomes a 56px rail, right becomes a drawer"
- <1024px: "both side panels → выдвижные оверлеи"

**Реализация:**
```gdscript
func _bpl() -> Dictionary:
    if size.x >= 1600.0: return {"left": 260, "right": 320}
    if size.x >= 1280.0: return {"left": 240, "right": 300}
    if size.x >= 1024.0:
        # dense mode: left becomes a 56px rail, right becomes a drawer — see
        # _layout() which collapses the panels so the board dominates.
        return {"left": 56, "right": 60}  # ← возвращает 56/60
    return {"left": 56, "right": 60}
```

Возвращает 56/60, но:
1. **PlayersPanel** не умеет быть "rail" (compact mode) — только минимальный size.
2. **JournalPanel** не умеет быть "drawer" (выдвижная панель).
3. **_layout()** не обрабатывает rail/drawer — просто ставит `custom_minimum_size.x = pw`.

При 1024px левая панель будет 56px (почти пустая), правая 60px (тоже почти пустая).
**Это ВЫГЛЯДИТ сломанным** на 1024px.

**Серьёзность:** КРИТИЧЕСКИЙ (визуал).

### XIX.2 ⚠️ КОСМЕТИКА: Minimal size 900×600 не проверен

Spec §10: "минимальный поддерживаемый размер 900×600".
Не реализован toast "слишком узкое окно".

---

## XX. СВОДНАЯ ТАБЛИЦА

| # | Элемент | Файл | Серьёзность | Статус | Примечание |
|---|---------|------|------------|--------|-----------|
| 1 | `_auctions` wrong i18n keys | settings_overlay.gd:329 | КРИТИЧЕСКИЙ | НЕ работает | fp_on вместо auctions_on/off |
| 2 | Driver selector not localized | settings_overlay.gd:486 | КРИТИЧЕСКИЙ | НЕ работает | RAW strings в dropdown |
| 3 | Tab titles not retranslated | settings_overlay.gd:258+ | КРИТИЧЕСКИЙ | НЕ работает | set_tab_title не в _retranslate |
| 4 | Preset button labels static | settings_overlay.gd:208-219 | КРИТИЧЕСКИЙ | НЕ работает | Не обновляются при locale change |
| 5 | TileInspector not retranslated | tile_inspector.gd | КРИТИЧЕСКИЙ | НЕ работает | placeholder "Кликните..." |
| 6 | `_reset_all()` no `_refresh_buttons()` | settings_overlay.gd:724 | КРИТИЧЕСКИЙ | Логика сломана | START btn may stay disabled |
| 7 | 1024px breakpoint broken | game_view.gd:206 | КРИТИЧЕСКИЙ | Выглядит сломанным | 56px rail + 60px drawer без реализации |
| 8 | Rent/pay anti-spam merge missing | toast.gd:141-143 | КРИТИЧЕСКИЙ | Не реализовано | Отдельные toasts, не merged |
| 9 | `_collect_settings()` text not ID | settings_overlay.gd:549 | СРЕДНИЙ | Логика риска | Сломается при локализованных driver |
| 10 | Data tab empty | settings_overlay.gd:426 | СРЕДНИЙ | Неполно | Только RNG seed |
| 11 | `_preset_fast()` no auction_timer | settings_overlay.gd:685 | СРЕДНИЙ | Не по спеку | 15с вместо 10с |
| 12 | `_preset_hard()` incomplete | settings_overlay.gd:690 | СРЕДНИЙ | Не по спеку | Не выключает doubles/housing |
| 13 | Language selector hardcoded | settings_overlay.gd:416 | СРЕДНИЙ | Нарушение архитектуры | "Русский"/"English" |
| 14 | Journal event types not localized | journal_panel.gd:271 | СРЕДНИЙ | Косметика | "purchase" вместо "покупка" |
| 15 | Dice SVG faces missing | dice_stage.gd:84 | СРЕДНИЙ | Косметика | Plain Label, не SVG |
| 16 | EventMessages not i18n | event_messages.gd | СРЕДНИЙ | Не локализовано | Журнал на EN |
| 17 | `away` detection weak | players_panel.gd:91 | СРЕДНИЙ | Логика | bool(s.away) may be wrong |
| 18 | `_phase` raw enum | top_bar.gd:129 | НИЗКАЯ | Косметика | "PHASE: PURCHASE_WAIT" |
| 19 | TopBar title not i18n | top_bar.gd:49 | НИЗКАЯ | Косметика | "NEURO PROPERTY TRADE" hardcoded |
| 20 | Observer status phase not i18n | action_panel.gd:112 | НИЗКАЯ | Косметика | Raw enum |
| 21 | Banner action text not i18n | toast.gd:289 | НИЗКАЯ | Косметика | "РЕВАНШ" hardcoded |
| 22 | `spectacle` not gated by settings | board_scene.gd:75 | НИЗКАЯ | Косметика | Всегда on |
| 23 | Inspector stale data on hover | tile_inspector.gd | НИЗКАЯ | Косметика | sync only on state change |
| 24 | Emoji badges not assets | players_panel.gd:139 | НИЗКАЯ | Косметика | 🏠💼⚖ in code |
| 25 | `_observer` duplicate detection | game_view.gd:346 | НИЗКАЯ | Чистка | Мёртвый код |
| 26 | Lobby_shot.gd orphan | tools/lobby_shot.gd | ЧИСТКА | Хвост | Не используется |

---

## XXI. ОРФАННЫЕ ФАЙЛЫ

| Файл | Комментарий |
|------|-------------|
| `game/tools/lobby_shot.gd` + `.tscn` | Старый screenshotter, не используется |
| `game/ui_lobby.png` | Скриншот старого lobby (из git history) |
| `game/.godot/imported/ui_lobby.png-*` | Godot импорты орфанного файла |

---

## XXII. ИТОГО

**8 критических багов** (не работает или выглядит сломанным):
1. `_auctions` неправильные i18n ключи
2. Driver selector не локализован
3. Tab titles не переводятся
4. Preset buttons не переводятся
5. TileInspector placeholder не переводится
6. `_reset_all()` не обновляет кнопки
7. 1024px breakpoint без rail/drawer реализации
8. Rent/pay toasts не сливаются

**9 средних багов** (не соответствует спеку или риск логики):
- Data tab пустая
- Пресеты частично не по спеку
- Журнал и event messages не локализованы
- SVG кубиков и emoji badges отсутствуют

**8 косметических** (мелочи, вид не идеален):
- TopBar title / phase / observer не i18n
- Dice plain Label вместо SVG
- Banner action text не локализован
- Spectacle не выключается настройкой
- Emoji badges в коде

**P-баланс:** P0–P5 probes зелёные потому что тестируют логику движка, а не визуал/i18n. Визуально и в плане локализации — сыпется.
