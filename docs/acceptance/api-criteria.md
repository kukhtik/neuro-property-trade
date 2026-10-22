# Критерии API — пункт брифа → код → замер

Девять критериев брифа по интеграции с Neuro SDK. Каждая строка отвечает на три вопроса:
что обещано, **где** это в коде (файл и функция), **чем** это измерено (конкретный тест или
гейт). Пути и имена функций проверены по дереву; где замера нет — так и написано, потому
что ссылка на несуществующий тест хуже пустой клетки.

Как устроена нумерация тестов: модули лежат в `game/tests/`, раннер — `game/tests/run.gd`,
запуск — `tools/ci/run_tests.sh`. Тесты в модулях объявлены `static func test_...()` и
возвращают `""` при успехе, иначе — причину.

| № | Пункт брифа | Код | Замер |
|---|---|---|---|
| 1 | Результат **до** исполнения, fail-closed: невалидное действие не меняет состояние | `game/core/engine.gd` → `submit_intent(pid, action, params)`: все проверки (не тот игрок, пауза, конец игры, легальность) стоят до первой мутации и возвращают `{ok:false, reason, legal}`; `game/sdk/engine_action.gd` → `_validate_action()` зовёт `adapter.try_submit()`, а `_execute_action()` (эмиссия событий) идёт только после `ok:true` | `game/tests/engine_test.gd` → `test_submit_intent_invalid_action_rejected` (отказ + непустой список легального), `test_submit_intent_wrong_player_rejected` |
| 2 | `success:false` ⇒ авто-ретрай с actionable-сообщением | `game/sdk/engine_action.gd` → `_validate_action()`: при `ok:false` собирает `ExecutionResult.failure(msg)`, где `msg` = причина движка + `" Legal options: …"` (перечень допустимых действий); сам ретрай — поведение клиента SDK на failure-результат, не код игры | **Нет прямого замера.** Успешный цикл гоняет гейт HG-08, отказ — только тест движка (строка 1). Текст failure-сообщения ни один тест не читает — см. ниже, «Пункт 2» |
| 3 | Успех = `message` со **сменой состояния** (пустой message — нарушение) | `game/sdk/result_message.gd` → `build(engine, proj, events)`: по событиям движка строит фразы («You rolled…», «bought…»), последние три + `" Now legal: …"`; `game/sdk/sdk_adapter.gd` → `success_message(result)` — мост к движку и проекции; `engine_action.gd` → `ExecutionResult.success(msg)` | `game/tests/sdk_test.gd` → `test_success_message_describes_the_change` (непустой и содержит «bought»), `test_success_message_lists_next_legal_actions` (содержит «Now legal:»), `test_success_message_empty_without_events` (без событий — пусто, и это правильно) |
| 4 | `actions/force` с `priority: low` для turn-based игры | `game/sdk/decision_controller.gd` → `decide()` возвращает `"priority": "low"` во всех ветках; `game/sdk/sdk_adapter.gd` → `_force_if_needed()` передаёт в `set_force(...)` константу `ActionsForce.Priority.LOW` | `game/tests/sdk_test.gd` → `test_decision_priority_low_ephemeral` (проверяет `priority == "low"`) |
| 5 | Стабильный набор зарегистрированных действий (12) | `game/sdk/sdk_adapter.gd` → `_register_actions()`: 12 вызовов `_make_action(...)` — `roll_dice`, `buy_property`, `pass_on_purchase`, `bid_auction`, `build_house`, `sell_house`, `mortgage_property`, `unmortgage_property`, `propose_trade`, `respond_trade`, `pay_jail_fine`, `use_jail_card`; регистрируется один раз в `_ready()` и заново по сигналу `connected` (переподключение) | **Нет счёта действий.** Ни один тест не проверяет, что их ровно 12: адаптер — `Node`, который нельзя собрать headless (autoloads SDK). Косвенно — гейт `tools/ci/gates/hg08_sdk_seat_gate.sh`: регистрация и force доходят до мока и место играет — см. ниже, «Пункт 5» |
| 6 | `ephemeral_context: true` для ежедневного дампа | `game/sdk/decision_controller.gd` → `decide()`: `"ephemeral_context": true` в ветке с легальными действиями (`false`, когда форсить нечего); `game/sdk/sdk_adapter.gd` → `_force_if_needed()` передаёт `decision.get("ephemeral_context", true)` в `set_force(...)` | `game/tests/sdk_test.gd` → `test_decision_priority_low_ephemeral` (проверяет `ephemeral_context` истинно для дампа доски) |
| 7 | Контекст Markdown без `#`-заголовков | `game/sdk/markdown_renderer.gd` → `render(proj)`: каждый раздел начинается с `"## "` (`## Players`, `## Board`, `## Pending decision`, `## Your legal actions`, `## Your private info`); `render_spectator(proj)` — то же, без приватного блока | `game/tests/sdk_test.gd` → `test_renderer_contains_sections` (пинит `## Players` / `## Board` / `## Your legal actions`), `test_renderer_legal_actions_listed` |
| 8 | Нет читов: скрытая информация скрыта так же, как от человека | `game/sdk/projection.gd` → `for_player(engine, pid)` + `_private_view(engine, pid)`: в приватный блок попадают только СВОИ карты выхода из тюрьмы; `for_spectator(engine)` — публичное представление вообще без `legal` и `private` | `game/tests/sdk_test.gd` → `test_projection_private_jail_cards_isolated` (у соседа ноль, у себя два); `game/tests/ui_contract_test.gd` → `test_projection_outputs_pinned` (спектатор не содержит `legal`/`private`); оба модуля в сьюте оракула `tools/ci/run_tests.sh` |
| 9 | «Be painfully explicit» — быть предельно явным | `game/sdk/markdown_renderer.gd` → `render(proj)`: фаза, чей ход, каждый игрок (деньги, позиция, тюрьма), все клетки с владельцем/домами/залогом, ожидающее решение с числами (ставка, кто поставил), полный список легальных действий, приватный блок; `game/sdk/decision_controller.gd` → `_query()` формулирует фазу словами («You landed on an unowned property. Choose one: …») | `game/tests/sdk_test.gd` → `test_renderer_contains_sections` + `test_renderer_legal_actions_listed`. Полнота «явности» числом не измеряется — см. ниже, «Пункт 9» |

## Примечания — что закрыто не полностью

Честный список, а не оговорка: эти клетки выше пусты не случайно.

- **Пункт 1, вторая половина.** Тесты проверяют, что отказ пришёл (`ok == false`) и что
  список легального непустой. Прямого ассерта «состояние не изменилось» (сравнение
  отпечатка до/после отклонённого намерения) в сьюте нет; отсутствие мутации следует из
  порядка кода в `submit_intent` — это чтение, не измерение.
- **Пункт 2 не измерен.** `engine_action.gd` — `Node` поверх autoloads SDK, headless он не
  собирается, поэтому текст failure-сообщения («причина + Legal options») не пинит ни один
  тест. `grep -rn 'Legal options'` находит ровно одну строку — в самом коде. Чтобы это
  закрыть, нужен либо чистый модуль (как `result_message.gd`) с тестом, либо проверка
  строки в моке HG-08; ни того, ни другого сегодня нет.
- **Пункт 5 — число 12 ничем не посчитано.** Двенадцать вызовов видны только чтением
  `_register_actions()`. Счёт вида `grep -c '_make_action('` даёт 13 (включая определение
  функции), то есть как гейт это ненадёжно. Закрывается тестом на чистый список имён или
  проверкой `actions/register` в логе мока.
- **Пункт 7, запрет одиночного `#`.** Тесты пинят, что разделы начинаются с `##`, но
  строку, начинающуюся с одного `#`, не запрещает ни один тест и ни один гейт. Нарушение
  сегодня отсутствует (видно в `render()`), однако это свойство кода, а не измеренное
  обещание.
- **Пункт 8 — та же проекция, что у человека.** Утверждение «скрыто так же, как от
  человека» опирается на то, что UI и место читают одну и ту же проекцию: контракт ключей
  пинит `ui_contract_test.gd`, приватность — `test_projection_private_jail_cards_isolated`.
  Отдельного сравнения «экран человека vs контекст модели» по одному и тому же состоянию
  нет.
- **Пункт 9 — суждение, не число.** «Painfully explicit» проверяется наличием разделов и
  легальных действий, а не полнотой каждой строки. Это остаётся чтением глазами.

## Как перепроверить

```bash
tools/ci/run_tests.sh                                   # весь сьют: строки «ALL TESTS PASSED» и число тестов
bash tools/ci/gates/hg08_sdk_seat_gate.sh               # SDK-место против мока: force → action → result
bash tools/ci/gates/acceptance_gate.sh                  # 12 обещаний приёмки, в т.ч. A1 (message со сменой состояния)
```

Точечно, без Godot (grep по дереву — то же, чем меряет гейт приёмки):

```bash
grep -n 'func submit_intent'          game/core/engine.gd
grep -n 'ExecutionResult.success'     game/sdk/engine_action.gd
grep -n 'func success_message'        game/sdk/sdk_adapter.gd
grep -c '_make_action('               game/sdk/sdk_adapter.gd     # 13 = 12 действий + определение функции
grep -n 'ActionsForce.Priority.LOW'   game/sdk/sdk_adapter.gd
grep -n 'ephemeral_context'           game/sdk/decision_controller.gd
grep -n '## '                         game/sdk/markdown_renderer.gd
grep -n 'func _private_view' -A 6     game/sdk/projection.gd
```

Модули тестов — `game/tests/sdk_test.gd` и `game/tests/engine_test.gd`; список тестов
модуля объявлен в его `test_list()`, и раннер падает, если объявленный тест отсутствует.
