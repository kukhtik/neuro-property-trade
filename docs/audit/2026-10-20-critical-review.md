# NPT — критический разбор проекта (20.10.2026, HEAD `df75adc`)

> Все числа — из прогонов ЭТОГО сеанса. Оракул: `ran 421 tests, 0 failed` → `==> ORACLE
> PASSED (421 tests, 0 SCRIPT ERROR)`. Гейты: `required 27/27 green` → `==> GATES PASSED`.
> Публичные источники — на 20.10.2026.

---

## 0. Коротко (для владельца)

Проект **технически сильный и почти готов**: движок детерминирован и покрыт 421 тестом,
27 обязательных гейтов зелёные, браузерный джойн живой, два SDK-места работают на моках.
Это не «прототип, который надо выкинуть» — это работающая система с превосходной
проверяемостью.

Но есть **три вещи, важнее любого редизайна**:

1. **Проект никогда не был заявлен Vedal'у.** Бриф 002 на `vedal.ai/projects` — «develop a
   Monopoly mod that integrates the game with the Neuro SDK» — это **буквально этот проект**.
   Бриф закрыт 07.10.2026. 368 коммитов, 45 дней, 0 заявок, 0 фидбека. Мы делали «интеграцию
   для Neuro» без единого обращения к заказчику. Это не ошибка кода — это ошибка процесса.
2. **Аудио — не «не доделано», а «не начато».** Тумблер «Звук» в настройках есть, в
   `game_settings` поля `sound` НЕТ, в репо НОЛЬ `AudioStreamPlayer` и НОЛЬ звуковых файлов.
   Это 1 поле + 1 менеджер + ассеты, а не «отдельная сессия».
3. **Редизайн стоит не 5–8 недель, а 1–2, если не тащить за собой проверки.** Настоящая
   стоимость — не вёрстка (750 конструкторских строк), а **6 549 строк гейтов и 182 теста из
   450**, привязанных к именам узлов и числам макета.

---

## 1. Что реально сделано (замер, не самоотчёт)

| Слой | Файлов | Строк | Доля |
|---|---|---|---|
| `game/core` (движок) | 9 | 1 718 | 4,9 % |
| `game/seats` | 11 | 1 228 | 3,5 % |
| `game/sdk` | 5 | 704 | 2,0 % |
| `game/server` | 2 | 363 | 1,0 % |
| `game/admin` | 3 | 942 | 2,7 % |
| **`game/ui`** | **29** | **7 673** | **22,0 %** |
| **`game/visual`** | **4** | **2 008** | **5,8 %** |
| `game/main.gd` | 1 | 793 | 2,3 % |
| `game/i18n` | 6 | 1 039 | 3,0 % |
| `game/tests` | 34 | 7 265 | 20,8 % |
| `game/tools` (пробы/гейты) | 47 | 11 043 | 31,7 % |
| **Продукт целиком** | **151** | **34 776** | |

**Интерфейс — в 5 раз больше ядра.** Это главный факт о проекте, который объясняет и
стоимость, и причину, почему редизайн кажется бесконечным.

Проверяемость — исключительная и редкая:

- 421 headless-тест, `MIN_TESTS` с 200 → 421, растёт только вместе с реальным тестом;
- 27 обязательных гейтов, все зелёные на прогоне сегодня;
- детерминизм: 13 записанных игр в `corpus/`, каждая реплеится в **побайтово тот же**
  fingerprint; `soak_cli` не зависает;
- `unused_symbols.py` честно показывает 129 ORPHAN — инструмент, который **отказывается
  врать** (комментарий ≠ потребитель; пустой product-glob = FAIL).

Это уровень дисциплины, которого нет у большинства студийных проектов. Дальше — что с этим
делать.

---

## 2. Критика: ошибки владельца как управляющего разработкой

### 2.1 Главная ошибка: заказчик не привлекался

Бриф 002 существовал с августа 2026 и требовал ровно того, что делалось. Форма приёмки —
Google Form, «Engagement: Paid». Мы не подали заявку. Бриф закрылся 07.10 — за месяц до того,
как проект разогнался.

Последствия видны в коде:

- **Имя игры в SDK — «Neuro Property Trade»**, а бриф просил «Monopoly mod». Возможно, это
  осознанное решение (Hasbro-риск), но оно **не согласовано**: в описании GitHub-репо и в
  README слово «Monopoly» стоит — против собственного правила `docs/licensing.md`
  («never use … in any asset, UI string, code identifier visible in a build, store page, or
  stream overlay»).
- **«First deliverable: SDK integration feasibility plan»** — такого документа в репо нет ни
  в каком виде. Для платного брифа это первая обязательная вещь.
- **Уровень «живости» проекта для приёмки**: 0 звёзд, 0 форков, 1 issue (с 29.09, висит), 0
  PR, 0 тегов, 0 релизов. С точки зрения «clean Neuro SDK commands, source, notes, and
  handoff» — handoff не оформлен.

- **README цитирует Vedal'а фразой, которую нельзя найти.** `README.md:17`: *«Sits in the gap
  Vedal described as "intellectually challenging work" for the community»*. Цитата **не
  подтверждена** публичными источниками: проверены vedal.ai, GitHub-организация VedalAI,
  вики, Reddit и точный поиск по фразе — не найдено ни одного вхождения. Строка появилась в
  самом первом README (`0de3964`, 06.09) и с тех пор не менялась. Это наш пересказ, поданный
  как цитата. Для приёмки это хуже отсутствия: **цитируемое отсутствует**.

### 2.2 Вторая ошибка: «доделать» вместо «переделать», три раза подряд

Хронология интерфейса:

| Дата | Событие | Результат |
|---|---|---|
| 06.09 | Phase 5 «visual/stream layer complete» | пауза до 09.10 (issue #1) |
| 13.10 | **v3 interface swap** `effb831` | 245 файлов, +9 097/−6 122; **44 пробы и 130 тестов выброшены**; MIN_TESTS 400→270 |
| 12.10 | отчёт `ui-defect-report.md` | D-01: `UiTheme.label` навязал перенос 86 меткам — раскладка втрое дороже; 44 глифа рисовались квадратиками |
| 16–20.10 | 95 коммитов «ring-first» | кольцо во весь кадр, glance-слой, 27 гейтов зелёные |

**Паттерн**: каждая волна «переделки» начинается с полной замены интерфейса, и каждая
заканчивается возвратом к той же архитектуре (код, а не сцены) с новым набором чисел. Три
раунда подряд. Проблема не в том, что переделывали плохо, — переделывали честно и с
замерами. Проблема в том, что **каждый раунд покупался ценой списания проверок**, а
архитектура (100 % кода, 0 `.tres`, 148 `add_theme_*`) оставалась прежней, и следующий раунд
начинался с той же точки.

### 2.3 Третья ошибка: «гейт» как единственный источник правды — и как источник ложной правды

Программа гейтов — сильная сторона проекта и одновременно источник уязвимости. Три случая,
которые вскрылись за 5 дней:

- `6e78dad` (дать визуальным гейтам их тулчейн) → `c116800` **revert** через один коммит:
  CI стал требовать playwright, которого там нет, и гейты начали **пропускаться** вместо
  падения. Revert вернул «зелёное, ничего не проверив» — ту же форму, от которой программа
  гейтов и должна была защищать.
- `3bcb6bd` — «три красных гейта, три разные правды»: FILL сказал «ни одного кадра — я
  ничего не проверил» (это правильное поведение), SG-10 сказал «fps-регрессия», HG-06 —
  «веб-экспорт не закончился». Три разные причины, один зелёный статус.
- `39382670127` (CI от 20.10) — `v3_probe` красный: «1440x900 is a rail profile
  (RAILS_BELOW=2000) but the docks are still shown». Проба знала про порог и проверяла не то.

Паттерн: **каждый новый гейт требует калибровки под конкретную вёрстку**, и при смене
вёрстки гейт либо молча зеленеет (плохо), либо краснеет на старом числе (требует ручной
перенастройки). 27 гейтов, 22 из них завязаны на структуру — это **не актив, а долг**.

### 2.4 Четвёртая ошибка: docs разъезжаются с кодом

Правило «вердикт — строкой» отличное, но числа в доках правятся руками:

- `docs/infra.md`: «227 tests», «MIN_TESTS (default 200)» — в коде 421 и 421;
- `docs/program.md`: «пробы 3 passed» — в реестре 6;
- `docs/specs/ui-integration-status.md` помечен как архив, но `docs/specs/ui-full-redesign-spec.md`
  (старая спека v3) всё ещё лежит рядом с действующей `ui-redesign-brief.md` и содержит
  «407 tests»;
- `docs/licensing.md` ссылается на `docs/assets.md` — **файла нет**;
- `docs/licensing.md` ссылается на `API/SPECIFICATION.md` — **файла нет** (в репо только
  `API/VOICE_CHAT.md`);
- `docs/restoration/gates.md` — 518 строк, тогда как реестр в `run_gates.sh` — 27 гейтов;
  таблица «Правило полноты: гейт без строки в этой таблице не нужен» нарушена.

### 2.5 Пятая ошибка: документированный «зелёный» ≠ «работает»

Классика проекта, и репозиторий честно её зафиксировал (это хорошо). Примеры из живых
коммитов:

- `settings_overlay._validation_error` звал `get_item_text(r["token"]).selected` вместо
  `get_item_text(r["token"].selected)` — **оракул (421 тест) это не поймал**, поймал READ-гейт
  (`SCRIPT ERROR: Invalid type in function 'get_item_text' in base 'OptionButton'`);
- `ai_driver`/`chat_driver` звали `engine.submit_intent` напрямую, минуя менеджер, и не
  отдавали `res["events"]` — **журнал, тосты и плашки были пусты весь матч** (66 событий по
  человеческому пути → 0 по AI-пути). SG-06 был зелёным и слепым к этому, потому что гонял
  матч через работающий путь `push_intent`;
- `compare_mockup.py` сверял `skins/neuro/skin.json`, а игра красила `default`;
- `smoke_all_roles.py` вообще не стартовал (неэкранированный `%s` в GDScript-шаблоне).

Вывод: **статические и «зелёные» проверки в этом проекте регулярно слепят к тому, чего не
касаются**. Правило «проверка обязана падать при возврате дефекта» (negative check) — единственная
защита, и её применение несистемное.

### 2.6 Шестая ошибка: мёртвый груз, который не убирают

129 ORPHAN, 5 UNAPPLIED, 8 UNLISTENED — инструмент честно показывает, а решение принимается
медленно:

- `game_settings.{spectacle, event_overlay, animations, jail_rule, ai_aggression, language}` —
  **UNAPPLIED**: экран настроек их сохраняет, игра не читает. `jail_rule` читается только в
  комментарии `engine.gd:127`; `ai_aggression` — нигде. Это **галочки-декорации в
  пользовательском интерфейсе**;
- `event_presenter` (135), `ui_store` (188), `intent_map` (118) = **441 строка «архитектуры»
  без живого потребителя** (только тесты) — ViewModel + Presenter + IntentMap, которые не
  участвуют в живом пути `main.gd → game_view.apply_projection → панели.sync`;
- `remote_driver.{connect_to_host, request_state, configure, disconnect_from_host}`,
  `game_server.{peer_count, seated_count, close_all}`, `protocol.{S2C, is_valid_client_msg,
  channel_for}` — нативный remote-путь без потребителя (своп v3 увёл сцену, которая им
  пользовалась);
- `engine.{_teleport, _force_draw_card}`, `event_log.entries_of_type` — мёртвые.

Проблема не в размере (441 строка — ерунда), а в **принципе**: `docs/program.md` требует
«код без живого потребителя не коммитится», а на деле это WIP-строки в плане, которые живут
полгода.

### 2.7 Седьмая ошибка: гейт ловит `SCRIPT ERROR:` — и только его

**Это находка, сделанная при разборе логов оракула, и она НЕ видна ни в одном существующем
гейте.** Оракул падает на `SCRIPT ERROR` и `Failed to load script`. Раннер гейтов падает на
`SCRIPT ERROR:` (с двоеточием). **Обычные `ERROR:` от Godot не ловятся нигде.**

Свежий прогон оракула (`/tmp/npt-tests-18559.log`, 20.10 20:33) — 101 строка:

| Строка | Что | Ловится гейтом? |
|---|---|---|
| 0 | `SCRIPT ERROR` | ✅ да |
| **4** | `ERROR: Parse JSON failed` (из негативного теста `test_decode_rejects_garbage`) | ❌ **нет** |
| 1 | `ERROR: NEURO_SDK_WS_URL environment variable is not set` (вендорный аддон) | ❌ нет (и не надо) |
| 3 | `ERROR: … RID allocations … were leaked at exit` (шум при выходе) | ❌ нет (и не надо) |
| 9 | `WARNING: …` | ❌ нет |

Четыре `Parse JSON failed` — **ожидаемый шум негативного теста** (`server_test.gd:60` скармливает
мусор в `Proto.decode`). Но тот же канал — единственный, через который Godot сообщает о
**настоящей** ошибке в рантайме, не являющейся `SCRIPT ERROR`. Например:

```
ERROR: Signal 'host_invite_requested' is already connected to given callable
       'Node(main.gd)::_on_host_invite' in that object.
```

**Это реальный дефект продукта**, найденный в логе гейта SG-09 (4 раза — 4 смены скина):

- `game/main.gd:147` — первый `connect` при создании оверлея;
- `game/main.gd:656` — **второй `connect` в `_on_skin_requested`**, где оверлей уже существует.

Итог: каждая смена скина печатает ошибку. Функционально приглашение работает (Godot
**отклоняет** повторный `connect`, а не дублирует подписку) — гейты SG-09, HG-07, HG-06
зелёные. Но:
- в логе пользователь видит ошибку на каждом переключении скина;
- **ни один гейт этого не видит** — потому что ловится только `SCRIPT ERROR:`;
- это ровно тот класс дефекта, что `program.md` объявляет критическим: гейт SG-09 заявляет
  «смена скина в живом матче чистая», но не замечает ошибку, которую само переключение
  порождает.

**Починка (5 минут):** во втором месте — `if not _overlay.host_invite_requested.is_connected(_on_host_invite):`
(такой guard уже есть в `main.gd:99`, `:482`, `:498`, `:585`, `:590` — стиль соблюдён).

**И шире — предложение в гейт-программу:** раннер должен ловить `ERROR:` **с исключением
белого списка** (вендорный `NEURO_SDK_WS_URL`, RID-leak при выходе, `Parse JSON failed` из
негативных тестов). Сейчас гейт-раннер **не ловит ни одну обычную ошибку Godot** — это самая
широкая из открытых «слепых зон».

### 2.8 Восьмая ошибка: «правка реестра гейтов» без синтаксической проверки

`bash -n` после правки реестра — правило, выученное дорого. Но такие вещи, как «если
карантинный гейт не запускался 3 раза — он не должен блокировать», нигде не формализованы в
`_check_orphan_modules`-стиле: `run.gd` **умеет** проверять, что тест-модуль не выпал из
списка, а `run_gates.sh` **не умеет** проверять, что гейт не выпал из реестра.

---

## 3. Критика: ошибки агентов

| Ошибка | Пример | Почему это системная проблема |
|---|---|---|
| **Проверка, которая не покрывает дерево** | `skin_probe` читал 4 файла из 68; `stage8_contrast` использовал плоский `get_files()` и не открывал `ui/components/` | Агент пишет проверку под свой вывод, а не под дерево. Нет требования «проверка обязана сообщать COVERAGE» |
| **Сканер видит одно написание из трёх** | `#rrggbb`, `Color(r,g,b)`, `Color("c9a84c")` — каждый сканер видел одно; литералы админ-фида пережили два раунда «литералов не осталось» | Агент перечисляет примеры вместо пространства значений |
| **Мёртвый код читается как живой** | `p2` девять мёртвых полей `TileView`; `UiProfile.text_scale` считался «используемым», потому что запись ≠ потребитель | Комментарий/запись ≠ потребитель — надо проверять это КАЖДЫМ сканером |
| **Проверка на отказе = комментарий** | `FILL` в CI падал «ни одного кадра» — и это оказалось ПРАВИЛЬНЫМ поведением, но в другой момент мешало | Нужна явная тактика: «красный без входа» ≠ «красный по существу» |
| **Доверять самоотчёту** | Макеты второго круга: субагент заявил R-1 = 0.00 %, владелец перепроверил своим же инструментом → 7.0 % | Правило уже есть («родитель повторяет ключевой прогон»), но не применялось к каждой макет-приёмке |
| **Коммит вместо задачи** | `c116800` revert через час после `6e78dad` | Агент не оценил последствий изменения в CI; revert — это откат к «зелёному вхолостую» |

**Системный вывод**: агенты в этом проекте **отлично пишут код и плохо проектируют проверки**.
Каждый новый гейт/сканер/проба — это точка отказа, где агент оптимизирует под свой результат.
Лечится не «больше инструкций агенту», а **архитектурно**: гейт должен **сам** сообщать
покрытие (сколько файлов прочитал), а реестр — **сам** проверять свою полноту.

---

## 4. Критика: ошибки окружения и инфраструктуры

Ловушки задокументированы в `monopoly-dev` и в основном пройдены, но есть остатки:

1. **MSYS-пути vs нативные бинари.** `git -C /c/Users/...` молча даёт пусто; нативный godot не
   открывает `/c/...`. В `run_gates.sh` есть хелпер `native()`, в `run_tests.sh` — нет.
   Расхождение в двух соседних скриптах.
2. **`$PYW="py -3.12"` в кавычках** = «command not found». Половина проверки молча не выдаёт
   вердикт. Правило «половина, не оставившая свою строку, обязана валить сценарий» — в
   `scenario_s3.sh` есть, в `sg07_shots_gate.sh` / `hg06_browser_join_gate.sh` — проверяем
   не везде.
3. **`--path` должен быть относительным** — нативный Godot под MSYS. Записано в skill, но
   `run_probes.sh` использует `--path game` (относительный, ок), а часть гейтов — абсолютные
   пути.
4. **Windows-сегfault при выходе Godot** — exit code непригоден, вердикт только строками.
   Обход найден, но каждый новый скрипт должен это знать.
5. **`python3` на Windows — Store-заглушка.** В `run_gates.sh` есть перебор кандидатов, в
   `unused_symbols.py` — нет; скрипт печатает `Python` и падает.
6. **build/ — 532 МБ, 1002 файла, 229 логов, 7 `.bak`.** Не в git (это правильно), но это
   мусор на диске, в котором `hg11_freshness_gate.sh` ищет артефакты. Риск: «свежий» артефакт
   из чужого прогона (ровно тот дефект, который гейт должен ловить, но по дате mtime не
   отличает).
7. **Godot 4.7.2** — версия October 2026; шапка README говорит «Godot 4.x». Репозиторий
   пиннится правильно (`.tools/godot-version` + sha512), это сильно.
8. **Neuro SDK вендорен без LICENSE** (58 файлов в git), при этом `docs/licensing.md` прямо
   говорит «we must not redistribute SDK sources». Формально — внутреннее противоречие
   собственной политике. MIT-лицензию нужно приложить.

---

## 5. Технический анализ: удобство поддержания

### 5.1 Что сделано правильно

- **Детерминизм как контракт.** Seeded `Rng`, AI подаёт только интенты, движок валидирует и
  исполняет. Модель физически не может испортить состояние. Это ровно то, чего требует
  Vedal («Reliable player actions and useful game-state access»).
- **Граница UI↔продукт узкая.** Прямой доступ к движку из UI — **1 файл, 2 вызова**
  (`game_view.gd:725,727`). Запись в мир — **1 функция** (`_submit`), 8 мест вызова.
  Обратных зависимостей «ядро → UI» нет, кроме админ-панели.
- **Контракт замены со стороны шелла** — 15 методов + 4 сигнала `game_view`. Это и есть
  «дверь», через которую входит новый интерфейс.
- **Один дом истины на метрики** (`layout_profile.gd`) — идея верная, исполнение неполное
  (см. 5.3).
- **Кожа как единственный источник визуальных значений** — правило есть, 5 скинов, SG-09
  проверяет смену скина в живом матче.

### 5.2 Что сделано плохо

| Долг | Замер |
|---|---|
| **Интерфейса на сцене нет вообще** | `main.tscn` = 6 строк, `.tres` = 0, `set_theme()` = 0, `theme_type_variation` = 0. 100 % UI строится в `_build()` |
| **`SkinManager.theme()` (12 вариаций) собирается и не применяется** | применяет только тест. Реальная стилизация — 148 `add_theme_*` override'ов в 17 файлах |
| **Строковые чтения полей проекции** | **463 чтения** в 20 файлах, 107 уникальных ключей. Опечатка → `null` → виджет рисует ноль (уже стоило чип банка `$0`) |
| **Дома истины ×3** | ширина дока 268: `layout_profile.LEFT_W` + `game_view.DOCK_L` + сумма в `action_panel.gd:60`. Ящик 320: `drawer_panel.W` + `game_view.gd:597`. Header 56: `layout_profile` + `top_bar.gd:51` |
| **Профильные ширины не используются шеллом** | `left_width()`/`right_width()` протестированы (280/268/240, 380/344/300), но шелл держит свои 268/344 |
| **Мёртвая архитектура** | `ui_store` 188 + `event_presenter` 135 + `intent_map` 118 = 441 строка без живого потребителя |
| **Дизайн-пакет больше половины продукта** | `design/` = 34 263 строки против 34 776 строк продукта. Прототип генерируется из игры, но **0 ссылок на `game/ui`** — он переживёт замену интерфейса, но и не поможет ей |
| **Проб не подключено 6 из 12** | в `run_probes.sh` — 6; на диске 12 `*probe*.tscn`. «Проба не запущена = комментарий, который компилируется» |
| **Док-дрифт** | `infra.md` — «227 tests» / «MIN_TESTS 200» при 421/421; `licensing.md` → несуществующие `docs/assets.md` и `API/SPECIFICATION.md` |

### 5.3 Удобство полной смены интерфейса — честная оценка

**Стоимость вёрстки — малая.** Из 10 474 строк UI-слоя конструкторских — **750 (10,6 %)**;
логики/биндинга — 6 349 (89,4 %). Перерисовать виджеты дёшево.

**Стоимость проверок — большая.** 27 гейтов, из них:

- **14 структурных** — переписать с нуля (адресуют узлы по имени, регионы по `regions.json`
  (19 записей), метрики по числам 56/268/344/96);
- **8 поведенческих** — перепривязать (логика выживает, меняются адреса);
- **5 продуктовых** — не трогать (HG-01, HG-08, HG-11, MULTI-SDK, SG-10).

Плюс **182 теста из 450 (40,4 %)** завязаны на UI.

**Оценка: 196–324 человеко-часа (5–8 недель одного senior + агент).**

Эмпирический якорь: прошлый своп `effb831` занял **два дня** — но только потому, что вместе с
интерфейсом выбросили **44 пробы и 130 тестов** (MIN_TESTS 400→270), а гейт-программы тогда
ещё не существовала (создана 14.10). **Повторить своп «как в прошлый раз» нельзя**: 27 гейтов
стали `required`, и это единственный капитал проекта.

**Дешёвая альтернатива, которую стоит рассмотреть.** Скин-система уже отвязана от виджетов:
5 скинов, 6 мест чтения `SkinManager`, 0 `.tres`. Смена палитры, кеглей, формы = правка JSON +
прогон SG-09/SG-03 — **8–16 часов вместо 200+**. То есть 60–70 % воспринимаемой новизны за
5–8 % цены. Единственное, чего скин не даёт, — **смена композиции** (регионы, доки, порядок
зон). А владелец жаловался именно на композицию («огромное пустое пространство буквально
везде», «интерфейс должен быть всегда таким, чтобы был понятен»).

**Вывод по редизайну:** полная замена — правильное решение, но её надо вести **не как
«перерисовать UI»**, а как **«пересобрать контракт, который UI имеет с проверками»**. Иначе
получится третий круг: красивая вёрстка + 27 гейтов, которые зеленеют на старых числах.

### 5.4 Оптимизация: что даст максимум при минимуме

1. **Включить `SkinManager.theme()` и перевести 148 `add_theme_*` на `theme_type_variation`.**
   1–2 дня работы, и следующий редизайн меняет тему без правки виджетов. Это **анти-рецидиент**:
   сегодня третий круг вынужден трогать 17 файлов, потому что стилизация размазана.
2. **Свести метрики в `layout_profile`** и удалить `DOCK_L/DOCK_R` из `game_view` и сумму из
   `action_panel`. Полдня. Убирает 2 из 3 домов истины.
3. **Заменить строковые `.get()` на константы** (`Proj.PHASE`, `Proj.PARKING_POT`) хотя бы в
   20 файлах UI. 2–3 дня. Убирает класс дефектов «чип банка `$0`» и делает `ui_contract_test`
   настоящим контрактом, а не сканом.
4. **Удалить мёртвую архитектуру** (`ui_store`, `event_presenter`, `intent_map`) — 441 строка +
   ~30 тестов. MIN_TESTS падает на ~30 — но это **правильное** снижение (правило требует
   объяснения и плана возврата, а не запрета).
5. **Подключить 6 осиротевших проб** или удалить их. Полдня.
6. **Гейт-дрейф-страж**: `run_gates.sh` должен сам проверять, что каждый гейт из
   `docs/restoration/gates.md` есть в реестре (как `run.gd` проверяет тест-модули). 1 час,
   и класс дефектов «гейт выпал из реестра» закрыт навсегда.
7. **Числа в доках — только из гейта.** Простейший скрипт `tools/ci/doc_numbers.py`, который
   сверяет «N tests» в `docs/*.md` и README с фактическим прогоном. 2 часа, закрывает
   систематический док-дрифт.

Суммарно п.1–7 — **~2 недели**, и после них редизайн стоит **на 30–40 % дешевле**, а
следующий — ещё дешевле.

---

## 6. Аудио: что это на самом деле

| Проверка | Результат |
|---|---|
| `find . -iname '*.ogg' -o -iname '*.wav' -o -iname '*.mp3'` | **0 файлов** (во всём репо, вне `.git`) |
| `grep -rn 'AudioStreamPlayer' .` | **0 совпадений** |
| `grep -rn 'AudioServer\|audio_bus\|play_sound'` | **0 совпадений** |
| `game_settings.sound` | **нет такого поля** |
| `_sound` в `settings_overlay.gd` | создаётся, показывается, **но НЕ сохраняется** (`s.sound =` отсутствует) |
| `settings.sound` в i18n | есть («Звуковые эффекты (кубики, тосты, таймер)») |

**Вывод: звука нет вообще, и тумблер «Звук» — чистая декорация, которая даже не сохраняется.**
Это ровно тот класс дефекта, что `unused_symbols.py` ловит как UNAPPLIED, но здесь поле
вообще не заведено.

Реальная стоимость: **1 поле в `game_settings` + 1 менеджер звука (`sound_manager.gd`) +
bus'ы в `project.godot` + ~10–15 звуков (кубики, тост, таймер, покупка, аукцион, тюрьма,
событие, победа) + точка вызова из `journal_lines`/`effect_layer`.** Это 3–5 дней работы
вместе с ассетами, а не «отдельная сессия» на неделю.

**Рекомендация:** закрыть звук **до** редизайна, а не после. Причина: звук — это событийный
слой, и он диктует, где нужны хуки в UI (`effect_layer`, `board_scene`, `journal_lines`). Если
сначала перерисовать интерфейс, потом придётся переделывать точки вызова звука.

---

## 7. Приёмка у Vedal: критика с его точки зрения

### 7.1 Факт: бриф 002 — это мы

Снимок `vedal.ai/projects` от 24.09.2026 (Wayback `20260924172000`):

> **Brief 002 / Game integration**
> **Monopoly** — «Looking for someone who can develop a Monopoly mod that integrates the game
> with the Neuro SDK.»
> Looking for: Game modder / integration developer
> First deliverable: **SDK integration feasibility plan**
> Engagement: **Paid** · quote after shortlist
> **What matters:** Relevant game-modding or comparable board-game integration experience ·
> Reliable player actions and useful game-state access · Clean Neuro SDK commands, source,
> notes, and handoff

**Бриф закрыт 07.10.2026** (снимок `20261007135515`): «No open projects at the moment».
Живой `vedal.ai/projects` — тоже пусто. Форма приёмки — Google Form.

Значит: **проект делался 45 дней, ни разу не подавшись на бриф, который был про него.**

### 7.2 Официальные критерии (VedalAI/neuro-sdk `API/BEST_PRACTICES.md`, 20.08.2026)

Проверяемые пункты и соответствие проекта:

| Требование Vedal | Состояние проекта | Вердикт |
|---|---|---|
| Результат **до** исполнения (fail-closed) | `engine_action.gd`: `_validate_action` → `try_submit` → `failure` без `_execute_action` | **ОК** |
| `success:false` = авто-ретрай, сообщение actionable | `msg += " Legal options: " + …` — работает | **ОК** |
| На успехе `message` описывает **изменение состояния** (CHANGELOG 21.08.2026) | `ExecutionResult.success()` — **без message** | **НАРУШЕНИЕ** |
| `actions/force` с `priority: low` для turn-based | `decision_controller.gd` — всегда `"low"` | **ОК** |
| Стабильный набор зарегистрированных действий | 12 действий, регистрация один раз + при reconnect | **ОК** |
| `ephemeral_context: true` для ежедумного дампа | `decision_controller.gd` → `true` | **ОК** |
| Контекст Markdown, без `#`-заголовков | `markdown_renderer.gd` — `##` | **ОК** |
| Не давать ей читов; скрытое — как у человека | `for_player` / `for_spectator`, карты из тюрьмы в `private` | **ОК** |
| «Be painfully explicit» | `markdown_renderer` перечисляет доску, игроков, pending, legal | **ОК** |
| Один force за раз, ждать разрешения | `_force_if_needed` с защитой от двойного форса | **ОК** |
| Перерегистрация после reconnect | `_on_connected` → `_register_actions()` | **ОК** |

**Одно формальное нарушение** (пустой `message` на успехе) и **ноль нарушений по существу**.
Это лучший результат, чем можно ожидать.

### 7.3 Что Vedal с наибольшей вероятностью скажет критического

1. **«Ты не подал заявку, а сделал 45 дней работы.»** — Это первое и самое разрушительное
   возражение. При брифе с `Paid` это не «мимо», а **потраченное чужое время**.
2. **«First deliverable: SDK integration feasibility plan»** — такого документа нет. Для
   платного брифа это первая вещь, которую смотрят.
3. **«Живого коннекта не было.»** Правда: всё SDK-проверено на моках
   (`mock_neuro_ws.py`), реального подключения к серверу Neuro не было. Для приёмки нужно
   показать: реальный `NEURO_SDK_WS_URL`, реальная Neuro играет партию, латентность под
   реальной моделью.
4. **«Это не Модополия — это своя игра.»** Возможно, это плюс (Hasbro-риск снят), но бриф
   просил «Monopoly mod». Нужно решение: либо это осознанное отклонение (и его надо
   **объяснить**), либо бриф не про то, что мы сделали.
5. **«Качество ИИ-кода.»** 368 коммитов, 96 `fix`, 0 `refactor`, 145 коммитов за один день
   (06.09) — почерк агентной генерации. На вопрос «кто это писал» честный ответ «я и
   ИИ-агенты» — нормальный, но вопрос «насколько это поддерживаемо» уже отвечен выше:
   129 ORPHAN, 463 строковых чтения, 0 сцен интерфейса.
6. **«Intellectually challenging work.»** 12 действий, из них в форс уходят 1–2 за ход.
   По README самого SDK: «games that require a non-low APM will generally not work well».
   Монополия — низкий APM, это ОК. Но `roll` + `buy/pass` — это **2 решения на ход**;
   интерес для LLM не в этом, а в **торговле, аукционе и стратегии застройки**. То есть
   ровно в той части, которая реализована хуже всего для модельной игры (торговля требует
   multi-turn согласования, аукцион — bidding-стратегии).
7. **Юридика.** `docs/licensing.md` ссылается на *Anti-Monopoly v. General Mills* для
   копирования механик — кейс в holding'е, а норма для game mechanics — 17 U.S.C. §102(b) +
   *Baker v. Selden*. Ссылка неверна; внимательный ревьюер найдёт это за минуту. Плюс
   слово «Monopoly» в описании репо.
8. **«Intellectually challenging work» — цитата без источника.** Фраза стоит в `README.md`
   как прямая речь Vedal'а, но публично не находится. Если мы используем её как аргумент
   («проект закрывает ту самую задачу»), ревьюер может спросить «где это сказано» — и
   ответа не будет. Либо найти первоисточник, либо убрать.
9. **Вендор-лок.** Мы вендорим SDK (58 файлов, без LICENSE) и зависим от его API.
   `CHANGELOG.md` показывает, что API меняется: `priority` (17.12.2025), `startup_ack`
   (01.07.2026), voice side-channel (19.08.2026), `BEST_PRACTICES` (20.08.2026). Нужна
   стратегия обновления. Upstream: 863 ★, 76 форков, 8 issues, последний push 21.08.2026.

### 7.4 Шаблон ответа (черновик, английский)

> **Subject:** Neuro Property Trade — applying against Brief 002 (Monopoly / game integration)
>
> Hi,
>
> I'm applying against Brief 002. You asked for someone who can get a Monopoly-style game
> talking to the Neuro SDK with reliable player actions and useful game state. I built the
> whole thing end to end rather than a feasibility plan — so the feasibility plan is now an
> artifact you can run, and I'm proposing it as the first paid deliverable, with a live
> demo of the real connection as the second.
>
> **What it is.** Neuro Property Trade is a standalone Godot 4 board game with classic
> property-trading rules and an original theme (no Hasbro names, art or trade dress). It
> exists because a mod of a commercial Monopoly title can only expose the state that title
> chooses to expose; owning the engine means the model gets a clean, validated projection
> and every intent is checked before it touches state. Seats: human (local or remote
> browser), internal AI, and `sdk:` seats for Neuro-sama and Evil Neuro.
>
> **How to run.**
> ```
> tools/ci/fetch_godot.sh          # pinned Godot, sha512-verified
> tools/ci/run_tests.sh            # headless suite + SCRIPT ERROR gate
> tools/ci/run_gates.sh --all      # 27 required gates
> NEURO_SDK_WS_URL=ws://127.0.0.1:8000 godot --path game
> ```
> A mock Neuro server is included: `tools/ci/gates/hg08_sdk_seat_gate.sh`.
>
> **Verified by machine (run of 2026-10-20).**
> - 421 headless tests, 0 failed, 0 script errors.
> - 27 required gates green: 10 functionality, 17 interface.
> - SDK seat against a mock endpoint: force-to-accepted-intent under a second; 11 intents
>   accepted; the match advanced.
> - Two SDK seats, two separate connections, one process: intents accepted on both, round 5.
> - Every recorded game replays to a byte-identical state fingerprint.
> - A real browser joined a fresh web export and its intents were accepted by the engine.
> - Fps: host median 54, browser median 42, idle machine.
>
> **Not verified — please read this part.**
> - **No real Neuro connection has been made.** I have no server and no credentials.
>   Everything SDK-side above was tested against a local mock of the Neuro websocket, so
>   there is no evidence here about latency under a real model.
> - **The `action/result` window is untested under load.** The server discards a result
>   after ~20 s; our engine answers in milliseconds, but I have not measured that with a
>   real model attached.
> - **A force/action race is not measured.** The API docs call this system "very
>   susceptible to race conditions"; I guard against a double force, but I have not
>   exercised an action arriving simultaneously with a force.
> - **Two SDK seats need two endpoints.** By default only the first `sdk:` seat can use the
>   process-wide `NEURO_SDK_WS_URL`; the second needs its own endpoint (currently
>   `NPT_SDK_A`/`NPT_SDK_B` — a local extension of mine, not part of the spec). If you want
>   both twins at one table, that needs to be agreed.
> - **Voice chat is wired but untested** against the real side-channel.
> - **The Twitch chat seat is not finished.** The bridge and the seat exist; there is no
>   acceptance test for it yet.
> - **No audio.** The settings toggle exists but there is no sound implementation yet.
> - **The interface is being reworked.** The engine, seat layer and SDK adapter are stable;
>   the visual layer is in flux.
>
> **Against BEST_PRACTICES.md.** Actions are registered once and kept stable (12 actions,
> phase-aware forcing, `priority: low`); results are sent before the action is executed;
> failures carry the legal options so a retry can succeed; the context is Markdown without
> `#` headings and is ephemeral per decision; the seat never sees information a human player
> would not have (jail cards are per-seat private). One deviation I know of: successful
> results do not yet carry a `message` describing the state change — I will fix that.
>
> **What I need from you.**
> 1. Two SDK endpoints, if you want both twins at one table — or confirmation that one
>    connection per character is the shape you intend.
> 2. A slot to demonstrate it live, so the real connection can be exercised in front of you.
> 3. A steer on scope: this is a standalone game with Monopoly's mechanics rather than a
>    mod of a retail Monopoly release — deliberately, to keep Hasbro trademarks out. The
>    brief asks which implementation I would target and why, and that answer changes the
>    work. I would rather raise it now than deliver the wrong thing.
>
> Repo: github.com/kukhtik/neuro-property-trade (MIT). Happy to write the feasibility
> plan up as the first deliverable.
>
> — [name] · [discord] · [email]

**Осторожно в формулировках:**
- **не** называть «принято»/«одобрено» и **не** писать «applying against a brief you may have
  closed» — это указывает на незнание собственного заказчика; подавать как заявку, даже если
  бриф снят со страницы;
- **не** обещать «полностью протестировано» — только «проверено машинно, вот числа»;
- **не** упоминать реального подключения как выполненного;
- явно перечислить «не проверено»: реальный коннект, задержка под моделью, окно 20 с,
  гонка force/action, чат Твича, аудио;
- **не** опираться на цитату «intellectually challenging work» — источник не найден;
- **не** называть игру «Monopoly» как жанр-имя в описании проекта: «Monopoly-style»,
  «property-trading», «classic property-trading rules»;
- **не** подавать «у меня уже всё готово» — бриф ждёт feasibility plan и подрядчика, а не
  готовый продукт; подавать как «план уже есть и проверяем, первая поставка — план + демо»;
- **не** заявлять «лучше мода» — это выбор, а не превосходство; на вопрос «what would you
  target and why» отвечать фактами (control/state exposure), а не риторикой.

---

### 7.5 Два дефекта, найденных в самом проекте (проверено мной)

1. **README врёт про второе SDK-соединение.** `README.md:89`: *«One SDK connection per process: a
   second `sdk:` slot falls back to the internal AI so the match stays playable»*. Но гейт
   `MULTI-SDK` доказывает **два** соединения в одном процессе (`pid { 0: 33, 1: 38 }`, round 5,
   185 с прогона). README написан 06.09 (`0de3964`) и не обновлялся с тех пор, как фича
   появилась. Это ровно тот класс дефекта, что `program.md` называет «ложью в интерфейсе», но
   в документации.
2. **`NPT_SDK_A`/`NPT_SDK_B` — наше локальное расширение протокола, а не спека SDK.**
   Оно есть в `game/tools/multi_sdk_probe.gd` и `demo_multi_sdk.gd` и **не документировано ни
   в одном живом документе** (`grep` по `docs/` и `README.md` — только в моём разборе). Если
   Vedal захочет двух персонажей, это надо либо описать как часть интеграции, либо
   предложить как предложение в API.

3. **Лицензия SDK не приложена.** Upstream `VedalAI/neuro-sdk` имеет `LICENSE.md` (MIT,
   «Copyright (c) 2024 Vedal AI») в корне — вендоренная копия его **не содержит**. MIT требует
   включать уведомление в копии. Наш корневой `LICENSE` — только «Copyright (c) 2026 kukhtik».

### 7.6 Что ещё в требованиях формы приёмки (из найденной формы)

К брифу 002 привязана **живая Google-форма** «Vedal AI Open Projects — Monopoly Mod Development
Intake» (`docs.google.com/forms/d/e/1FAIpQLScMusZHsPuIv88NvXjnKFsB6rq4pHU7ZYIC8jKt4Taj715P7w/viewform`).
Она всё ещё отдаёт HTML без баннера «no longer accepting responses», хотя бриф со страницы снят.

Обязательные вопросы (★): Discord username, email, ссылки на released work, «опишите свой опыт
board-game / game-modding / multiplayer / stream-integration», «работали ли с Neuro SDK или
сопоставимым инструментарием» (варианты: Yes Neuro SDK / Yes comparable / **No, but willing to
learn**), «какую именно игру Monopoly вы бы взяли и почему», «что бы доказал ваш первый
прототип», «как бы вы открыли надёжные controls и game state для **Neuro-sama и Evil Neuro**»,
доступность/сроки. Quote — необязательно.

**Что из этого читается как жёсткие требования:**
- **доказанная released work** (форма требует ссылок);
- **два персонажа сразу** — Neuro-sama И Evil Neuro;
- **воспроизводимый контракт state/controls**;
- **передаваемость**: source + notes + handoff;
- вопрос **«есть ли чужая работа, с которой надо координировать, а не дублировать»** — то есть
  он не хочет второй параллельный Monopoly-проект. Это аргумент ЗА standalone-подход, если
  подать его так, что мы не дублируем, а закрываем.

Показательно, что в форме есть вариант «No, but willing to learn» — **SDK-опыт не блокер,
released-работа — блокер.**

### 7.7 Три технических требования из API, которые надо проверить отдельно

Из `VedalAI/neuro-sdk/API/` (проверено мной):

1. **Таймаут `action/result` ≈ 20 секунд** — сервер отбрасывает опоздавший результат и
   считает действие проваленным. Наш движок отвечает за миллисекунды, но **под нагрузкой
   реальной модели** это окно нужно мерить.
2. **Гонки в `actions/force`.** `API/README.md` прямо: *«this system is very susceptible to race
   conditions»* — экшен может прийти до force, одновременно с force или после результата.
   Наш `_force_if_needed` защищает от двойного форса, но **гонку «force и action одновременно»
   мы не мерили**.
3. **Имена экшенов общие на персонажа** и на все интеграции, подключённые одновременно —
   коллизии реальны, если рядом работает другой мод.

**Переупаковка ответа.** Приёмка здесь — не «примите мой готовый мод», а **платный контрактный
отбор подрядчика**, где первый deliverable — «SDK integration feasibility plan». Проект, поданный
как готовый продукт, отвечает не на тот вопрос. Подавать надо как: «я уже сделал то, что вы
просили, feasibility plan теперь — артефакт, который можно прогнать; вот первая платная
поставка — план и демо».

## 8. Перспективы

### 8.1 Куда это может пойти

| Направление | Оценка |
|---|---|
| **Приёмка в Neuro SDK как референс-интеграция** | Наивысшая. Мы закрываем бриф 002, который сам SDK называет «одна из игр, которые хорошо работают с API». Соблюдение BEST_PRACTICES — 9 из 10 пунктов |
| **Роли «Neuro + Evil Neuro» на одном столе** | Технически близко (MULTI-SDK зелёный на моках), но нужен второй эндпоинт и ре-вендоринг SDK в per-connection инстансы |
| **Чат Твича как место** | Мост есть, `push_chat` есть, `chat_driver` (majority + анти-флуд + авто-пас) есть. **Не хватает одного гейта** — CHAT-01. Это 1–2 дня, а закрывает обещание S2 |
| **Интеграция в другие игры / как образец** | `docs/infra.md` + `docs/licensing.md` + рабочий гейт-раннер — редкое сочетание, пригодное как референс |
| **Продажа/лицензирование** | Возможно, но с оговоркой: бриф Vedal — `Paid`, и это конкурентный канал. Наш проект — «сделай сам» вместо «возьми мой мод» |

### 8.2 Реалистичный горизонт

| Неделя | Что |
|---|---|
| 1 | Аудио (поле + менеджер + ассеты) — 3–5 дней; CHAT-01 гейт — 1–2 дня; `message` в успешном результате — полдня |
| 2 | Техдолг-пункт 1–7 из §5.4: `Theme`-ресурс, единый дом метрик, константы проекции, удаление мёртвой архитектуры, гейт-дрейф-страж, числа-доков. ~2 недели |
| 3–8 | Редизайн: спека → макет → перенос → переписывание 14 структурных гейтов и 182 тестов. **196–324 ч** |
| 9 | Приёмка: feasibility plan, живое демо с реальным SDK, handoff-документ, `message`-фикс, юридическая правка |

### 8.3 Что НЕ надо делать

- **Не перерисовывать UI поверх текущей архитектуры.** Третий круг без смены носителя
  (`.tscn` + `.tres`) повторит первые два.
- **Не выбрасывать гейты ради скорости.** Минимум 400 → 270 при следующем свопе — это
  откат к состоянию «зелёное, ничего не проверив». Гейты — единственный капитал проекта.
- **Не начинать редизайн до аудио и до tech-долга.** Иначе третий круг.
- **Не пушить редизайн в `main` одним коммитом.** Ветка `origin/ui/overhaul` уже есть — её и
  надо переиспользовать.

---

## 9. Сводка приоритетов

| # | Действие | Цена | Эффект |
|---|---|---|---|
| 1 | **Податься на приёмку / написать Vedal** с честным списком «не проверено» | 1 день | Закрывает главный риск проекта |
| 2 | **Feasibility plan** (то, что бриф просил первым) | 1–2 дня | Обязательный deliverable |
| 3 | **Аудио**: поле + `sound_manager.gd` + ассеты | 3–5 дней | Закрывает «не доделано» |
| 4 | **CHAT-01 гейт** (чат Твича) | 1–2 дня | Закрывает S2 |
| 5 | **`message` в успешном результате** SDK | полдня | Соответствие BEST_PRACTICES |
| 6 | **Юр. правка** `licensing.md` (Baker v. Selden) + приложить LICENSE SDK + убрать «Monopoly» из описания репо | 2 часа | Снимает риск на приёмке |
6а | **Правка README**: «One SDK connection per process» → правда (2 соединения); убрать или подтвердить цитату «intellectually challenging work»; задокументировать `NPT_SDK_A/B` | 1 час | README — первое, что читает ревьюер |
| 7 | **Техдолг §5.4 п.1–7** | ~2 недели | Удешевляет редизайн на 30–40 % |
| 8 | **Редизайн** (спека → макет → перенос → гейты) | 5–8 недель | Закрывает «не нравится интерфейс» |
| 9 | **Убрать 6 неподключённых проб / подключить** | полдня | Закрывает класс «проба не запущена» |
| 10 | **Гейт-дрейф-страж** (`run_gates.sh` проверяет свой реестр) | 1 час | Закрывает класс «гейт выпал» |
| 11 | **Ловить `ERROR:` в гейт-раннере** (с белым списком шума) + починить двойной `connect` в `main.gd:656` | 1 час | Закрывает самую широкую «слепую зону» |

---

## 10. Приложение: команды, которыми получены числа

```bash
# Оракул
bash tools/ci/run_tests.sh
#   ran 421 tests, 0 failed
#   ==> ORACLE PASSED (421 tests, 0 SCRIPT ERROR)

# Гейты
bash tools/ci/run_gates.sh --all
#   gates: required 27/27 green - quarantine 0 green, 0 red, 0 not run
#   ==> GATES PASSED

# Потребители символов
python tools/ci/unused_symbols.py
#   scanned: 71 product file(s), 121 check file(s), 3086 declaration(s)
#   ORPHANS (0 reference in product code): 129
#   UNAPPLIED: jail_rule, ai_aggression, spectacle, event_overlay, language

# Аудио
find . -iname '*.ogg' -o -iname '*.wav' -o -iname '*.mp3'   # 0
grep -rn 'AudioStreamPlayer' .                                  # 0
grep -n 'sound' game/core/game_settings.gd                      # 0

# Метрики
find game -name '*.gd' | wc -l                                   # 179
find game -name '*.gd' -exec cat {} + | wc -l                    # 36136
find game -name '*.tres' | wc -l                                 # 0
find game -name '*.tscn' -not -path '*/tools/*' -not -path '*/addons/*'
#   game/main.tscn, game/tests/ui_contract_runner.tscn
grep -rc 'add_theme_' game/ui game/visual --include='*.gd' | awk -F: '{s+=$2} END {print s}'  # 148
grep -rhoE '(proj|spec)\.get\("[a-z_]+"' game/ui game/visual --include='*.gd' | wc -l  # 81 (顶层)
grep -rhoE '\.get\("[a-z_]+"' game/ui game/visual --include='*.gd' | wc -l  # 463 (все)

# Пробы
for p in $(ls game/tools/*probe*.tscn | xargs -n1 basename | sed 's/.tscn//'); do
  grep -q "\b$p\b" tools/ci/run_probes.sh && echo "WIRED:   $p" || echo "UNWIRED: $p"
done
#   WIRED: 6; UNWIRED: cell_step, keyboard_only, layout_density, multi_sdk, phone_fit, touch

# Публичные источники
web.archive.org/web/20260924172000/https://vedal.ai/projects/   # Brief 002 = Monopoly
web.archive.org/web/20261007135515/https://vedal.ai/projects/   # closed 07.10.2026
raw.githubusercontent.com/VedalAI/neuro-sdk/main/API/BEST_PRACTICES.md
gh api repos/kukhtik/neuro-property-trade
#   {"private":false,"stargazers_count":0,"forks_count":0,"open_issues_count":1,
#    "license":"MIT","created_at":"2026-09-06T00:47:16Z"}
```
