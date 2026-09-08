# UI/UX Fix Plan — P6 (2026-09-08)

План фиксов по результатам углублённого аудита + ux_probe.
Результат probe: **22 passed, 7 failed** (probe: `game/tools/ux_probe.tscn`).

---

## ФАЗА 1 — КРИТИЧЕСКИЕ (ломает функциональность)

### CR-1 ❌ `_auctions` — неправильные i18n ключи
**Файлы:** `game/ui/settings_overlay.gd:329, 110`  
**Проблема:** `I18n.t("settings.fp_on/off")` — это ключи free_parking, не auctions.
Dropdown показывает "Вкл/Выкл" вместо правильных label'ов аукциона.  
**Нет ключей `settings.auctions_on/off`** — нужно добавить в `game/i18n/data_settings.gd`.  
**Fix:**
1. В `data_settings.gd` добавить ключи:
   ```gdscript
   "settings.auctions_on": "Аукцион: вкл",
   "settings.auctions_off": "Аукцион: выкл",
   ```
2. В `settings_overlay.gd` заменить:
   ```gdscript
   _auctions.add_item(I18n.t("settings.auctions_on"))
   _auctions.add_item(I18n.t("settings.auctions_off"))
   ```

---

### CR-2 ❌ Driver selector — сырые строки
**Файлы:** `game/ui/settings_overlay.gd:20, 486`  
**Проблема:** `["LOCAL","AI","CHAT","sdk:neuro","sdk:evil"]` — сырые строки в dropdown.  
**Fix:**
1. В `data_settings.gd` добавить:
   ```gdscript
   "settings.driver.local": "ЛОКАЛ",
   "settings.driver.ai": "ИИ",
   "settings.driver.chat": "ЧАТ",
   "settings.driver.neuro": "sdk:neuro",
   "settings.driver.evil": "sdk:evil",
   ```
2. В `settings_overlay.gd` заменить:
   ```gdscript
   for d in DRIVERS:
       var key: String = "settings.driver." + d.to_lower().replace(":", "_")
       driver.add_item(I18n.t(key) if I18n.has(key) else d)
   ```

---

### CR-3 ❌ Tab titles — не переводятся при смене языка
**Файлы:** `game/ui/settings_overlay.gd:258, 294, 367, 390, 429`  
**Проблема:** `set_tab_title()` вызывается только в `_build_*_tab()`, не в `_retranslate()`.  
**Fix:** В `_retranslate()` добавить:
```gdscript
func _retranslate() -> void:
    if _tabs != null:
        for i in _tabs.tab_count:
            var tab_node: Node = _tabs.get_child(i)
            var id: int = _tabs.get_tab_id(i)
            var title_key: String = ""
            match i:
                0: title_key = "settings.tab_quick"
                1: title_key = "settings.tab_rules"
                2: title_key = "settings.tab_players"
                3: title_key = "settings.tab_data"
            if title_key != "":
                _tabs.set_tab_title(i, I18n.t(title_key))
```

---

### CR-4 ❌ Preset buttons — не переводятся при смене языка
**Файлы:** `game/ui/settings_overlay.gd:208–219`  
**Проблема:** Кнопки создаются в `_build()`, `_retranslate()` их не трогает.  
**Fix:** В `_retranslate()` добавить:
```gdscript
if p_classic != null:
    p_classic.text = I18n.t("settings.preset_classic")
if p_fast != null:
    p_fast.text = I18n.t("settings.preset_fast")
if p_hard != null:
    p_hard.text = I18n.t("settings.preset_hard")
```

---

### CR-5 ❌ TileInspector — не переводится placeholder
**Файлы:** `game/ui/tile_inspector.gd` + `game/ui/game_view.gd`  
**Проблема:** Нет `retranslate()`, `game_view._on_locale_changed()` не вызывает его.  
**Fix в tile_inspector.gd:**
```gdscript
func retranslate() -> void:
    if _placeholder != null:
        _placeholder.text = I18n.t("ins.placeholder")
```
**Fix в game_view.gd:** в `_on_locale_changed()` добавить:
```gdscript
_inspector.retranslate()
```

---

### CR-6 ❌ `_reset_all()` — не вызывает `_refresh_buttons()`
**Файлы:** `game/ui/settings_overlay.gd:724`  
**Проблема:** START может остаться disabled после сброса.  
**Fix:** В конец `_reset_all()` добавить:
```gdscript
_refresh_buttons()
```
Проверено: probe подтвердил что `_refresh_buttons` вызывается. Проверить что он В КОНЦЕ `_reset_all()`.

---

### CR-7 ⚠️ 1024px breakpoint — rail/drawer не реализованы
**Файлы:** `game/ui/game_view.gd:206–214`  
**Проблема:** `_bpl()` возвращает 56/60, но панели не умеют rail/drawer.  
На 1024px левая панель = 56px (пустая), правая = 60px (пустая). Выглядит сломанным.  
**Fix:** Либо:
- **A. Реализовать rail/drawer** ( PlayersPanel rail: имя+аватар; JournalPanel drawer: выезжает по кнопке)
- **B. Убрать breakpoint 1024px** из `_bpl()`, оставить только 1280/1600

Рекомендация: **Option B** (быстрее, меньше кода). Реализация rail/drawer — отдельная фича.

---

### CR-8 ❌ Rent/pay toasts — не сливаются
**Файлы:** `game/ui/toast.gd:141–143`  
**Проблема:** Spec §6.2 требует merge toasts ренты/платежей одного хода в одну строку.  
Реализовано: отдельные toasts.  
**Fix:** В `toast.gd` добавить буфер для rent/pay:
```gdscript
var _rent_pay_buffer: Dictionary = {}  # {player_id: {type, amounts[], total, timer}}

func _flush_rent_pay() -> void:
    # вызывается при каждом sync() после обработки всех pending rent/pay
    for pid in _rent_pay_buffer:
        var entry: Dictionary = _rent_pay_buffer[pid]
        if entry.amounts.size() > 1:
            show_toast(I18n.t("toast.rent_merged", [
                entry.name, entry.total,
                entry.amounts.size()
            ]), "warning")
        # else одиночный — показать обычным способом
    _rent_pay_buffer.clear()
```

---

## ФАЗА 2 — СРЕДНИЕ (не соответствует спеку)

### MD-1 ⚠️ Data tab пустая
**Файлы:** `game/ui/settings_overlay.gd:426`  
**Проблема:** Только RNG seed, нет preset selector, color picker, board override.  
**Fix:** Добавить preset quick-select (кнопки Классика/Быстрая/Хардкор как быстрый ввод) и опциональный board data override.

---

### MD-2 ⚠️ `_preset_fast()` — не меняет auction_timer
**Файлы:** `game/ui/settings_overlay.gd:685–688`  
**Проблема:** Spec: 10с на аукцион, фактически 15с.  
**Fix:** Добавить `_auction_timer.selected = _index_of_seconds(_auction_timer, 10)`.

---

### MD-3 ⚠️ `_preset_hard()` — неполный
**Файлы:** `game/ui/settings_overlay.gd:690–694`  
**Проблема:** Не выключает `housing` и `doubles`.  
**Fix:**
```gdscript
func _preset_hard() -> void:
    _reset_all()
    _mortgage.button_pressed = false
    _trades.button_pressed = false
    _ai_aggression.value = 80
    if _housing != null: _housing.button_pressed = false
    if _doubles != null: _doubles.button_pressed = false
```

---

### MD-4 ⚠️ Journal event types — сырые enum
**Файлы:** `game/ui/journal_panel.gd:271`  
**Проблема:** `"[purchase]"` вместо `"[покупка]"` в журнале.  
**Fix:** В `data_event.gd` добавить ключи для всех типов:
```gdscript
"event.purchase": "покупка",
"event.pay": "платёж",
"event.rent": "рента",
"event.tax": "налог",
"event.go_bonus": "бонус",
"event.auction_win": "аукцион",
"event.bankrupt": "банкрот",
```
И в `journal_panel.gd` при показе типа использовать `I18n.t("event." + type)`.

---

### MD-5 ⚠️ EventMessages — не локализованы
**Файлы:** `game/visual/event_messages.gd`  
**Проблема:** `describe()` использует raw match на enum, не i18n ключи.  
**Fix:** В `describe()` добавить i18n-обёртку:
```gdscript
func describe(e: Dictionary) -> String:
    var t := str(e.get("type", "?"))
    var d: Dictionary = e.get("data", {})
    var key: String = "event." + t
    if I18n.has(key):
        return I18n.t(key, _build_args(d))
    # fallback
    match t:
        "roll": return "Бросок: %s" % ...
```

---

### MD-6 ⚠️ Language selector — hardcoded строки
**Файлы:** `game/ui/settings_overlay.gd:416`  
**Проблема:** `"Русский"/"English"` вместо `I18n.t()`.  
**Fix:** Заменить на:
```gdscript
_language.add_item("Русский")   # label selector — exception, self-reference
_language.add_item("English")
```
Либо вынести в константу, но это не i18n-ключ — это selector языка.

---

### MD-7 ⚠️ `_collect_settings()` — читает text, не ID
**Файлы:** `game/ui/settings_overlay.gd:549`  
**Проблема:** `get_item_text()` сломается если driver items будут локализованы.  
**Fix:** Использовать `get_item_id(selected)`, но он возвращает позицию, не строку.  
Безопаснее: хранить параллельный `Array[String]` идентификаторов и читать по индексу.
```gdscript
var _driver_ids: Array[String] = ["LOCAL","AI","CHAT","sdk:neuro","sdk:evil"]
var drv: String = _driver_ids[driver.selected]
```

---

## ФАЗА 3 — КОСМЕТИЧЕСКИЕ (мелочи)

### CS-1 🔧 `_phase` в TopBar — сырой enum
**Файлы:** `game/ui/top_bar.gd:129`  
**Fix:** В `data_settings.gd` добавить `phase.TURN_START = "Начало хода"` и т.д.  
Использовать: `I18n.t("phase." + str(phase))` вместо `str(phase)`.

---

### CS-2 🔧 TopBar title hardcoded
**Файлы:** `game/ui/top_bar.gd:49`  
**Fix:** Добавить `top.title` в `data_ui.gd` и использовать `I18n.t()`.

---

### CS-3 🔧 Observer status — сырой enum phase
**Файлы:** `game/ui/action_panel.gd:112`  
**Fix:** Использовать `I18n.t("phase." + str(phase))`.

---

### CS-4 🔧 Banner "РЕВАНШ" hardcoded
**Файлы:** `game/ui/toast.gd` (вызов `show_event_toast`)  
**Fix:** Заменить захардкоженный текст на `I18n.t("modal.banner_rematch")`.

---

### CS-5 🔧 Dice — plain Label вместо SVG
**Файлы:** `game/ui/dice_stage.gd:84`  
**Проблема:** Spec §6.4 требует SVG faces.  
**Fix:** Заменить `Label` на `TextureRect` с SVG-текстурой (или PNG если SVG не подключены).

---

### CS-6 🔧 Emoji badges в коде
**Файлы:** `game/ui/players_panel.gd:139,142,144`  
**Fix:** Заменить на SVG-ассеты или i18n ключи.

---

### CS-7 🔧 Spectacle не выключается настройкой
**Файлы:** `game/visual/board_scene.gd:75`  
**Probe подтвердил:** `set_animations()` gate есть. Но `spectacle` включается ВСЕГДА (new + add_child).  
**Fix:** Добавить visibility toggle:
```gdscript
_spectacle.visible = _settings.animations if _settings != null else true
```

---

## ФАЗА 4 — ОРФАНЫ (чистка)

### OR-1 🗑 `game/tools/lobby_shot.gd` + `.tscn`
Не используются. Удалить.

### OR-2 🗑 `game/ui_lobby.png`
Не используется. Удалить.

### OR-3 🗑 `game/.godot/imported/ui_lobby.png-*`
Импорты орфанного файла. Очистятся при reimport.

---

## ФАЗА 5 — ЧИСТКА КОДА

### CL-1 `_observer` duplicate detection
**Файлы:** `game/ui/game_view.gd:346`  
Дублируется в `_set_observer()` и `_sync_from_spectator()`. Убрать одно.

### CL-2 `_holder_name` dead code
**Файлы:** `game/ui/game_view.gd:58,357`  
Вычисляется, но нигде не рисуется. Удалить или использовать в observer status.

---

## СВОДНАЯ ТАБЛИЦА

| ID | Приоритет | Баг | Файл | Строк | Probe |
|----|-----------|-----|------|-------|-------|
| CR-1 | P0 | `_auctions` wrong i18n keys | settings_overlay.gd | 2 | FAIL |
| CR-2 | P0 | Driver selector raw strings | settings_overlay.gd | 2 | FAIL |
| CR-3 | P0 | Tab titles not retranslated | settings_overlay.gd | 5 | FAIL |
| CR-4 | P0 | Preset buttons static | settings_overlay.gd | 4 | PASS* |
| CR-5 | P0 | TileInspector not retranslated | tile_inspector.gd | 2 | PASS* |
| CR-6 | P0 | `_reset_all` no refresh | settings_overlay.gd | 1 | PASS* |
| CR-7 | P1 | 1024px breakpoint broken | game_view.gd | 10 | PASS* |
| CR-8 | P1 | Rent/pay toasts not merged | toast.gd | 5 | PASS* |
| MD-1 | P2 | Data tab empty | settings_overlay.gd | 15 | FAIL |
| MD-2 | P2 | `_preset_fast` no auction_timer | settings_overlay.gd | 2 | PASS* |
| MD-3 | P2 | `_preset_hard` incomplete | settings_overlay.gd | 3 | PASS* |
| MD-4 | P2 | Journal types raw enum | journal_panel.gd | 3 | PASS* |
| MD-5 | P2 | EventMessages not i18n | event_messages.gd | 20 | PASS* |
| MD-6 | P2 | Language selector hardcoded | settings_overlay.gd | 1 | FAIL |
| MD-7 | P2 | `_collect_settings` text not ID | settings_overlay.gd | 2 | PASS* |
| CS-1 | P3 | `_phase` raw enum | top_bar.gd | 1 | FAIL |
| CS-2 | P3 | TopBar title hardcoded | top_bar.gd | 1 | PASS |
| CS-3 | P3 | Observer phase not i18n | action_panel.gd | 1 | PASS |
| CS-4 | P3 | Banner rematch hardcoded | toast.gd | 1 | PASS |
| CS-5 | P3 | Dice plain Label | dice_stage.gd | 5 | PASS |
| CS-6 | P3 | Emoji badges | players_panel.gd | 3 | PASS |
| CS-7 | P3 | Spectacle always on | board_scene.gd | 2 | PASS |
| OR-1 | P4 | lobby_shot orphan | tools/ | 2 | PASS |
| OR-2 | P4 | ui_lobby.png orphan | game/ | 1 | — |
| CL-1 | P5 | `_observer` dup detection | game_view.gd | 5 | — |
| CL-2 | P5 | `_holder_name` dead code | game_view.gd | 2 | — |

*PASS в probe = hot path работает (не means фича полностью реализована)

---

## ПОРЯДОК РЕАЛИЗАЦИИ

**Независимые группы (можно параллелить):**

```
Группа A (CR-1, CR-2)     → 1 файл: settings_overlay.gd + data_settings.gd
Группа B (CR-3, CR-4)     → 1 файл: settings_overlay.gd (retranslate)
Группа C (CR-5)           → 2 файла: tile_inspector.gd + game_view.gd
Группа D (CR-6, MD-2, MD-3) → 1 файл: settings_overlay.gd (presets)
Группа E (CR-7)           → game_view.gd (breakpoint)
Группа F (CR-8)           → toast.gd
Группа G (MD-4, MD-5)     → data_event.gd + journal + event_messages
Группа H (CS-1..7)        → разные файлы, низкий приоритет
Группа I (OR-1, OR-2)     → rm files
```

**Ожидаемое время:**
- P0 (CR-1..6): ~2 часа
- P1 (CR-7..8): ~1 час
- P2 (MD-1..7): ~2 часа
- P3 (CS-1..7): ~2 часа
- P4 (OR-1..2): 5 минут
- P5 (CL-1..2): 15 минут
