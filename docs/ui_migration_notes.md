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

## 6. Открытые вопросы владельцу (действуют решения спеки §1.4)

1. Светлая тема `paper` — нужна ли в поставке? (спека: опциональный скин)
2. Источник данных чата/зрителей для `stream` (`ChatPoll`) — есть ли драйвер CHAT данные? (в `seats/drivers/chat_driver.gd` — проверить, отдаёт ли что-то UI)
3. `pot`/банк парковки — механики в ядре нет; подтвердить, что выпиливаем из UI v2 (см. §2.1).
4. `tile_count` — движок жёстко 40; делать ли `BoardLayout` параметрическим «на будущее» (да, дёшево) при отключённом переключателе в настройках (см. §2.2).
5. `--skin-check` — только валидатор или ещё предпросмотр?
