# NPT UI v2 — миграционные заметки (Этап 0: аудит)

Дата: 2026-10-05. Ветка `main` @ `41a9901`. Оракул на момент аудита:
**228 тестов, 0 failed, 0 SCRIPT ERROR** (`tools/ci/run_tests.sh`).
Все расхождения ниже — сверка спеки (`NPT_UI_integration_spec.md`) с реальным кодом.

---

## 1. Допущения A1–A6 (проверка по коду)

| № | Допущение | Факт | Вердикт |
|---|---|---|---|
| A1 | `Projection.for_spectator` даёт игроков, владельцев, здания, залог, ход, фазу, кубики | `sdk/projection.gd` → `{phase, turn_player, board, players, pending}`. В `board[]` есть `owner/owner_name/houses/mortgaged/cost/rent/rent_set`; в `players[]` — `index/name/money/position/in_jail/jail_turns/bankrupt/tiles/houses/mortgaged`. **Но:** нет `round`, нет кубиков (кубики только в событиях), нет аукционного таймера. | **ЧАСТИЧНО** — `round` и `dice` брать из событий/`_last_roll`, а не из проекции. В ядро не лезть. |
| A2 | `engine.log.event_appended` даёт типизированные события | Да, `core/event_log.gd`: `append(type, data)` → `{index, type, data}`, сигнал `event_appended(entry)`. **Но имена типов ≠ схеме UI:** `purchase`(не `buy`), `pass`/`pass_on_purchase`, `auction_start/win/unwon`, `card_draw/card_gain/card_land/card_null`, `trade_proposed/trade_declined`, `bankrupt`, `winner`, `go_bonus`, `cash`, `teleport`, `admin_override`. **И поля не унифицированы:** `rent` — `{from,to,tile,amount}`, `buy` — `{player,tile,cost}`, `tax` — `{player,tile,amount}`. `cash` — отдельное событие на каждое движение денег. | **ЧАСТИЧНО** — `EventAdapter` обязателен, маппинг не 1:1. См. §3. |
| A3 | `legal_actions` возвращает доступные действия | Да, `engine.legal_actions(pid) -> Array[String]`. | **ОК** |
| A4 | Имена в `push_intent` могут отличаться от прототипа | Да, радикально: `buy`, `pass`, `roll`, `pay`, `use_card`, `build_house`, `sell_house`, `mortgage_property`, `unmortgage_property`, `propose_trade`, `respond_trade`, `bid`, `pass`. Параметры: `bid{amount}`, `build_house{tile}`, `propose_trade{to,give_tiles[],give_cash,want_tiles[],want_cash}`, `respond_trade{accept}`. | **ОК** — `IntentMap` обязателен. |
| A5 | Названия клеток и карт в данных | Клетки — да: `game/data/board.json` (40 клеток, поля `name/short/type/group/cost/rent/rent_set/houses[]/house_cost/rent_1/amount`). Карты — `game/data/cards.json` (`decks`). Групп ровно **8** (brown, lightblue, pink, orange, red, yellow, green, darkblue). | **ОК** |
| A6 | Настройки в `game_settings.gd` соответствуют брифу, прил. B | Файл есть, 39 полей. **Расхождения с прототипом:** нет `skin`, нет `sound`. Имена другие: `triple_doubles_to_jail` (не `triple_doubles`), `monopoly_rent_x2` (не `monopoly_x2`), `jail_rule="both"` (не `classic`), `free_parking: bool` (не enum `none/pot`), `ai_aggression` 0–**100** (не 0–10), `timeout_action="auto-pass"` (не `auto`), `bankruptcy` — лишнее поле. | **РАСХОЖДЕНИЕ** — схему настроек строить из `game_settings.gd`, не из прототипа. |

---

## 2. Критично: чего в ядре НЕТ (спека предполагала)

1. **`free_parking` = «банк парковки» не поддерживается.** `game_settings.free_parking: bool`, а `engine.gd:639` трактует `free_parking` как «ничего не происходит». Накопления банка нет. Прототипный `pot`/`e.park`/`cPot` — **нереализуемы** без правки ядра (запрещено).
   → **Решение:** блок «банк парковки» и событие `park` в UI v2 не входят.
2. **`tile_count` параметризация не поддержана движком.** `engine.setup` строит поле из `game/data/board.json` (жёстко 40 клеток). Смена `settings.tile_count` ничего не даст.
   → **Решение:** `BoardLayout.compute` делаем параметрическим (тестируется юнитами), но в UI v2 он питается длиной реального поля из проекции. Смена `tile_count` вживую — только когда ядро отдаст N клеток.
3. **Аукцион — не по одному игроку за раз.** `_pending.bidder` + `_advance_bidder()`: движок сам решает, чей черёд. `legal_actions` даёт `["bid","pass"]` только текущему `bidder`, остальным — `[]`. Скрытых ставок нет, всё публично.
   → **Решение:** `AuctionModal` **не** рисует кнопки всем участникам; кнопки — только если `bid` ∈ `legal_actions(me)`. Остальные — наблюдают. Это снимает риск spectator-safe.
4. **`jail_rule` = `both`:** вход в тюрьму — решение (`roll` / `pay` / `use_card`), есть «выход из тюрьмы» картами (`_private_view.get_out_of_jail_cards`). Это **приватные данные** → в `stream`/наблюдателе брать только `for_spectator` (там секции `private` нет вовсе — хорошо).
5. **Раунда/номера хода в проекции нет** как отдельного поля — только `turn_player` и фазы. Раунд придётся считать в `EventAdapter` (инкремент на `turn_player` → 0).

---

## 3. Точная таблица маппинга (EventAdapter) — из реального кода

| Ядро (тип события) | Поля ядра | UI `k` | Видно в журнале |
|---|---|---|---|
| `setup` | — | `start` | да |
| `roll` | `{player, d1, d2, doubles}`* | `roll` (p,a,b) | да |
| `move` / `teleport` | `{player, from, to}` | `move` | нет |
| `go_bonus` | `{player, amount, reason?}` | `go` | да |
| `purchase` | `{player, tile, cost}` | `buy` | да |
| `rent` | `{from, to, tile, amount}` | `rent` (p=from,q=to) | да |
| `tax` | `{player, tile, amount}` | `tax` | да |
| `card_draw` | `{player, kind, name, effect, value}` | `card` | да |
| `card_gain` / `card_land` / `card_null` | — | `card` (без эффекта) | да |
| `jail` / `send_to_jail` | `{player}` | `jail` | да |
| `auction_start` | `{tile}` | `aucstart` | да |
| `auction_bid` | `{player, amount, tile}` | `bid` | да |
| `auction_pass` | `{player}` | `pass` | да |
| `auction_win` | `{player, tile, amount}` | `aucwin` | да |
| `auction_unwon` | `{tile}` | `aucnone` | да |
| `build` / `sell` | `{player, tile, ...}` | `build`/`sell` | да |
| `mortgage` / `unmortgage` | `{player, tile, amount}` | `mort`/`unmort` | да |
| `trade_proposed` | `{proposer, recipient, ...}` | `trdoffer` | да |
| `trade` | — | `trade` | да |
| `trade_declined` | — | `trdno` | да |
| `bankrupt` | `{player}` | `bank` | да |
| `winner` | `{player}` | `over` | да |
| `cash` | `{player, amount, balance}` | — | **нет** (служебное; используется для дельт) |
| `land` / `land_self` | `{player, tile, type}` | — | нет (визуальный якорь) |
| `pass` / `pass_on_purchase` | `{player, tile}` | — | нет (в журнале — только через `aucstart`/следующее) |
| `admin_override` | — | — | **только AdminConsole** |

\* точный набор полей `roll` сверить при реализации (`engine._last_roll`).

**Нет источников для:** `park` (см. §2.1). Событие из спеки §3.2 удаляется из схемы.

---

## 4. Удаление старых тем

`grep` использований до удаления:

| Файл | Что | Замена |
|---|---|---|
| `game/ui/theme.gd` (90 стр., `class_name UiTheme`, `COL`, `box/label/button/panel/vbox`) | используется в `ui/*` и `admin/admin_panel.gd` | `SkinManager.token/color/slot` + theme type variations |
| `game/visual/theme.gd` (37 стр., `class_name BoardTheme`, `GROUP_COLORS`, `TYPE_COLORS`, `tile_color`) | используется в `visual/*` | `SkinManager.group_color()` / слоты `tile.band.<group>` |
| `game/tests/theme_test.gd` | 5 тестов на `BoardTheme` | перенести на `SkinManager` (группы/типы/контраст), не удалять проверку |

Потребители `UiTheme` (полный список — `admin/admin_panel.gd`: 28 обращений; `ui/action_panel.gd`, `ui/game_view.gd`, остальные `ui/*`). Ненулевой `grep` → удаление `theme.gd` только после полной замены (Этап 8).

**Текущие нарушения «нет хардкода» (базовая линия для статической проверки):**
- `Color(` в `game/ui/*` + `game/visual/*` — **75** вхождений
- `add_theme_font_size_override` / `add_theme_constant_override` с числами — **64**
- `custom_minimum_size` с числами — по всему `ui/`

---

## 5. Что уже есть (не переписывать с нуля)

- **`visual/skin_manager.gd`** — уже есть `class_name SkinManager` (RefCounted) с `load_skin/texture/color/proportion`, читает `assets/skins/<id>/skin.json` формата `{assets:{...}, proportions:{...}}`. Скин `classic` существует. → **Расширять, не заменять:** нужны токены (цвета/шрифты/размеры/форма), слоты 9-slice с `margins`, метрики, `motion`, `extends`, `theme()`, `skin_changed`.
- **`assets/`** уже содержит `tile.svg`, `board_center.svg`, `button.svg`, `corner_icons/`, `type_icons/`, `houses/`, `tokens/`, `dice/` — процедурный fallback-контент есть.
- **`visual/tile_view.gd`** (455 стр.) и `visual/token_panel.gd` (199) — слоты клетки/фишки частично реализованы.
- **`tests/ui_contract_runner.tscn`** — контрактный раннер существует, правится в том же PR, что и UI.
- **`visual/board_scene.gd:106`** уже подписан на `engine.log.event_appended` — точка входа для `EventPresenter`.
- **`i18n/i18n.gd`** — `class_name I18n`, `LOCALES=[ru,en]`, `set_locale` + сигнал `locale_changed`, метаданные `i18n_key`/`i18n_tip` + `I18n.relabel(root)`, шаблоны `{{name}}`. → **Расширять** (`relabel`-протокол уже есть; нужны новые пространства ключей).

---

## 6. Решения владельца (зафиксировано, отменяет спеку §1.4)

Все вопросы ниже закрыты владельцем 2026-10-05. Раздел 1.4 спеки в этих
пунктах НЕ действует.

| № | Вопрос | Решение |
|---|---|---|
| 1 | Светлая тема `paper` | **Не делаем.** Скины: `default` (процедурный fallback) + `neuro` + `evil`. |
| 2 | Источник данных чата/зрителей | **В SDK его нет.** Проверено: `addons/neuro-sdk/**` не отдаёт ни чата, ни списка зрителей, ни счётчика (`Context` — исходящий канал; `voice_chat.gd` — только события голосового чата). `seats/drivers/chat_driver.gd` — заглушка `## Phase-3 stub`: принимает готовые `enqueue(action, params)` от хоста, сам чат не читает. → **`ChatPoll` и счётчик зрителей вне объёма UI v2.** Вернуть, когда появится внешний источник. |
| 3 | Банк парковки (`pot`) | **Реализован в ядре** (см. §7). Флаг `settings.free_parking`. |
| 4 | `tile_count` / хардкод 40 | **Снимаем хардкод 40 в Этапе 3** из 5 файлов (см. §8). Истина — `board.tile_count()`. |
| 5 | `--skin-check` | Валидатор (отчёт по слотам + контраст). Предпросмотр — по желанию, не обязателен. |
| 6 | Режимы UI | **Это не «режимы одного экрана», а разделение исполнений** (см. §9). Переключатель кнопкой в шапке — удалить. |

---

## 7. Банк парковки — реализовано (коммит `700f878`)

Движок: `_parking_pot`, `_pot_take()`, `parking_pot()`; налоги копятся при
`settings.free_parking == true`, приземление на tile 20 отдаёт банк.
Проекция: поле `parking_pot` в `for_player` И `for_spectator` (публичные
данные). Снапшот: `_parking_pot` сохраняется.

Поведение по умолчанию не изменилось: `free_parking=false` → `_pot_take()`
no-op, старый лог `"note": "free_parking off"` сохранён
(`test_free_parking_default_noop` сторожит).

---

## 8. Хардкод `40` — снять в Этапе 3

Пять мест, не считая данных (`board.json`, `skin.json` — там 40 законно):

| Файл | Строка | Что |
|---|---|---|
| `visual/board_view.gd` | 24 | `var _tile_count := 40` |
| `visual/spectacle.gd` | 19 | `var _tile_count := 40` |
| `visual/tile_view.gd` | 32 | `var _tile_count := 40` |
| `visual/token_panel.gd` | 29 | `var _tile_count := 40` |
| `ui/settings_overlay.gd` | 445, 624 | дефолт поля ввода `tile_count` |
| `core/engine.gd` | 44 | `else 40` — **законный фолбэк**, оставить |

`engine.setup` уже пытается грузить `board_<N>.json` по `settings.tile_count`
с откатом на `board.json`. Файлов `board_16/24/64.json` нет — параметрическое
поле в ядре заложено наполовину. После снятия хардкода смена `tile_count`
заработает сама, как только эти файлы появятся.

---

## 9. Разделение исполнений (Этап 7) — не «режимы»

В макете три режима переключались кнопкой в шапке. Это неверно. Фактически —
**одно приложение** (решение владельца: один бинарник, не два), роль
выбирается **при запуске**, а не в UI:

| Роль | Точка входа | Ввод | Данные |
|---|---|---|---|
| Игроки | **WebUI** (пресет `Web` уже есть в `export_presets.cfg`) | свой LOCAL-слот | проекция своего места |
| Зрители (Twitch) | observer-вид / админ-окно с сокрытием админ-элементов | нет | **только `for_spectator`** |
| Админ | то же приложение, флаг | полный + админ-API | админ-проекция (`admin_token`) |
| Окно стрима | то же приложение; админ прячет свои кнопки → окно уходит в OBS | нет | `for_spectator` |

Следствия:
1. `UiProfile` **выбирается при запуске**: CLI-флаг → `OS.has_feature("web")` →
   дефолт. Разделение уже частично заложено (`main.gd:35`).
2. Компоненты не проверяют роль, только читают `UiProfile`.
3. **Переключатель режимов в шапке удаляется**; вместо него — индикатор роли
   только для чтения.
4. `F12` (админка) — только в админ-исполнении, не в WebUI.
5. Владелец выбирает между «совместить с админкой» и «отдельное observer-окно»
   **в ходе Этапа 7**; по умолчанию — админ-исполнение с кнопкой сокрытия
   админ-элементов (годится для стрима в OBS).
6. Кнопка «Стрим» в макете переключала LOCAL-места на ИИ — это демо-поведение;
   в игре стрим запускается с хостом-наблюдателем, места не переключаются.

---

## 10. Полная заменяемость ассетами (требование владельца)

UI должен меняться **целиком** сменой скина, без правок кода — для будущего
редизайна. Это критерий приёмки Этапа 1:

| Правило | Проверка |
|---|---|
| Ни одного `Color(...)` в компонентах | статический поиск → 0 |
| Ни одного числового размера | `add_theme_*_override` с числами → 0 |
| Все картинки — через слоты скина | `grep 'res://assets'` в `ui/`+`visual/` → 0 (кроме `skin_manager`) |
| Текст не запекается в картинки | метки — всегда `Label` |
| Отсутствующий слот → процедурная отрисовка | один `push_warning` на слот, не краш |
| **Стресс-скин** с другими шрифтами/метриками/формами | грузится без правок кода, вид меняется целиком |

Шрифты: скин задаёт **файлы** (`font.ui`, `font.mono`, `font.display`) — без
файлов системный fallback. Иначе у художника нет полного контроля.

**Базовая линия долга** (на `41a9901`): `Color(` в `ui/`+`visual/` — 75;
числовых `add_theme_*_override` — 64.

