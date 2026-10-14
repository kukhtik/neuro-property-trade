# NPT — снимок состояния после P0 (2026-10-14, HEAD `cdba563`)

> Каждое число и каждая строка вывода — из прогонов ЭТОГО сеанса (лог-файлы в `build/gates/`).
> Предыдущий снимок — `state-2026-10-13.md` (до P0). Этот снимок — после фаз 0 и P0.

## 1. В двух абзацах

**Продукт снова работает.** Браузерный джойн: экраны `join_lobby` и `host_invite` вернулись
из архива, `has_seat()` снова открывает экран джойна, приглашение показывает настоящие
ссылки `ws://адрес?seat=токен&host=…`; гейт HG-06 сам экспортирует web-сборку этого прогона
и живой Chromium по ссылке играет место: `joined=True`, 24/26 интентов принято движком
хозяина. Консольные кнопки больше не шлют пустые параметры: стройка/залог адресуют
выбранную в инспекторе клетку (или говорят, как её выбрать), торг открывает модалку
состава, ответ на сделку — модалку accept/decline (и рисуется только получателю сделки),
ставка — модалку аукциона с пред-проверкой суммы. `_human_pid` вычисляется из состава мест
(не захардкожен 0), клиент получает свой pid на JOINED и шлёт интенты по сети; авто-ответ
запрещён без флага `--smoke-drive`/`smoke=1`.

**Интерфейс снова полный, а не урезанный.** Лист настроек — снова пять вкладок: шесть
водителей на место (LOCAL/AI/CHAT/REMOTE/`sdk:neuro`/`sdk:evil`), цвета/фишки/персоны,
валидация дублей, теги «живьём/рестарт» на каждом ряду, `_collect_settings()` — единый
читатель для START, APPLY и инвайта. Программа гейтов (`tools/ci/run_gates.sh`) в CI:
9 жёстких гейтов required и **зелёные** (HG-01/02/05/06/07/09/11/12 + SG-01 — компакт
закрыт рейлами и ящиками). Оракул: `ran 292 tests, 0 failed`, MIN_TESTS=292 (включая
`ui_contract_test` — контракт проекций, HG-10).

## 2. Гейты (вердикты — строки `build/gates/*.log`)

| Гейт | Статус | Вердикт из лога |
|---|---|---|
| HG-01 оракул+сироты | required | `HG-01 PASSED (ran 292 tests, 0 SCRIPT ERROR, no orphan modules)` |
| HG-09 контракт i18n | required | `HG-09 PASSED (30 files, 424 literal refs, 0 sentinels, ru+en)` |
| HG-11 свежесть кадров/артефактов | required | `HG-11 PASSED (frames are per-run and requested explicitly; …)` |
| HG-02 консоль/цикл | required | `HG-02 PASSED (12 console presses, 0 UI-caused refusals, roll+purchase+auction accepted)` |
| HG-05 идентичность места | required | `HG-05 PASSED (who-plays derived, no buttons for others, client submits on the wire, no auto-play without the flag)` |
| HG-06 джойн браузера | required | `HG-06 PASSED (fresh export; a real browser joined and the engine accepted its intents)` |
| HG-07 настройки | required | `HG-07 PASSED (5 tabs, 6 drivers, validation, tags, live values, solo + networked configs start)` |
| HG-12 роли | required | `HG-12 PASSED (admin panel builds, F12 toggles, token gate present, stream role clean, observer input dead)` |
| SG-01 компакт | required (с фазы 2) | **зелёный**: рейлы 48px + ящики 320px; 4 профиля `9/9 reachable`; поведенческие проверки рейл→ящик→возврат |
| SG-02 влезание | required (с фазы 2) | **зелёный**: 4 профиля × RU/EN, ничего за вьюпорт, текст не выдавлен (нашёл и закрыл RU-переполнение консоли на 1280×720) |
| SG-06 журнал | required (с фазы 2) | **зелёный**: строки через адаптер + имена клеток, счётчик, фильтры, экспорт, пустые состояния |
| SG-08 язык | required (с фазы 2) | **зелёный**: RU↔EN в живом матче доходит до мебели, строк и всего дерева (дважды); попутно закрыт `{ins.price}:` |
| SG-04 роли текста | required (с фазы 2) | **зелёный**: 106/83 метки — только value/para, один растягивающийся на строку; закрыты чипы статистики и фильтр типов |
| SG-05 тосты | required (с фазы 2) | **зелёный**: 4 профиля; ширина — хост в доке, тосты не задевают stage/act; компакт — тикер консоли |
| SG-09 скины | required (с фазы 2) | **зелёный**: 4 скина на живом матче, места+журнал одной палитрой; пол проверок против тихого аборта |
| HG-08 SDK-место | required (фаза 3) | **зелёный**: адаптер спавнится, мок отвечает, round 3 / 11 интентов; seats_soak (SDK+AI+AI+LOCAL) до кэпа 12 |
| SG-10 перф | required | **зелёный**: хост median=57 / браузер median=51 (страница visible, чистая машина); сэмплер хоста возвращён |
| SG-03 палитра кадра | required | **зелёный (strict)**: 3 кадра × 90–119 токенов, 0 unexplained, 4 allowlist; негатив ловит новый цвет |
| SG-11 юзабилити | required | **зелёный**: тултипы/«Причина:»/RU-запас; паддинг кнопок починен (был нечитаемый theme-constant) |
| HG-13 хоткеи/таймер | required (с фазы 2) | **зелёный**: B берёт покупку, остаток тикает, 0 → пусто, таймаут срабатывает; N снят как пустое обещание |

## 3. Доказательства (команды этого сеанса)

```
$ bash tools/ci/run_tests.sh          # полный прогон с импортом
==> ORACLE PASSED (292 tests, 0 SCRIPT ERROR)     # 283 -> 289 (theme_test) -> 292 (ui_contract_test)

$ bash tools/ci/run_gates.sh --all    # сводный прогон всех гейтов
gates: required 9/9 green - quarantine 0 green, 0 red, 0 not run
==> GATES PASSED (every required gate is green)

$ NPT_WEB=… py -3.12 tools/ci/browser_seat_e2e.py     # (то же делает гейт HG-06)
joined      = True
intents sent= 26
accepted    = 24 of 26 verdicts      # хост: SEAT_CLAIMED pid=1, EVENTS 65

$ py -3.12 tools/ci/smoke_all_roles.py     # три роли в одном прогоне
RESULT: SMOKE PASSED — every role live, result matches the mockup

$ bash tools/ci/check_freshness.sh
FRESH    build/current/web/index.html (…mtime > shipping-коммита)
ARCHIVED build/web/index.html (reason: pre-swap reference)
ARCHIVED build/windows/NeuroPropertyTrade.exe (reason: pre-swap reference)
==> FRESHNESS ok
```

## 4. Что закрыто из P0 (по plan.md)

1. Join/инвайт — HG-06 зелёный (свой экспорт + живой браузер). ✔
2. Идентичность места — HG-05 зелёный (`_human_pid` из мест, клиент по сети, авто-ответ по флагу). ✔
3. Консоль и модалки — HG-02 зелёный (12 нажатий, 0 отказов; аукцион через модалку). ✔
4. Настройки мест — HG-07 зелёный (5 вкладок, 6 водителей, обе конфигурации стартуют). ✔
5. Свежие артефакты — `build/current/{web,windows}` пересобраны ИЗ ЭТОГО коммита; старые
   помечены «архив» с причиной (`tools/ci/freshness_allowlist.txt`), гейт HG-11 следит. ✔

## 5. Что осталось (фаза 2 продолжение и далее)

* **SG-01 ✅** (закрыт фазой 2): рейлы 48px + ящики 320px, 1000×650 и 880×600 достижимы.
* **HG-10 ✅** (закрыт): UI читает `parking_pot`; контракт запинен `game/tests/ui_contract_test.gd`
  (выводы `for_spectator`/`for_player`, скан чтений по game/ui+server, регресс-кейс `pot`;
  негативная проверка прогонялась — тест падает ровно на подменённом ключе).
* **SG-02**: влезание/клиппинг RU+EN на 4 профилях (ничего не вылезает за вьюпорт, текст не
  обрезан; ellipsis — только по allowlist).
* **SG-06**: журнал — включить `EventAdapter` (имена клеток словами, категории, слияния),
  счётчик, фильтры, экспорт. **SG-08**: живая локализация (подписать панели на
  `locale_changed`). **HG-13**: хоткеи B/N и таймер.
* **HG-08 / фаза 3**: спавн `SdkAdapter` для места с драйвером SDK; мок-WS; «один SDK на
  процесс» — честно в интерфейсе.
* **SG-07/SG-10/SG-03/SG-11** (фаза 4): скриншот-серия, FPS, палитра-репорт, юзабилити-авто;
  `side_by_side.py` падает с пустым текстом ошибки (видно в смоуке) — починить.
* Долг: тесты UI возвращать вместе с фичами (MIN_TESTS только вверх), `docs/plan.md:134`
  (ложное «DONE» про браузерный E2E — инструмент теперь существует и зелёный гейтом HG-06,
  строку переписать по факту), `ui-integration-status.md` — пометить как архив.
