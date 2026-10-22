# Handoff — Neuro Property Trade

Передача проекта следующему человеку. Бриф 002 просил четыре части: **commands**,
**source**, **notes**, **handoff**. Здесь они идут в этом порядке, и каждое утверждение
ниже проверяется из репозитория — команды существуют, пути существуют, номера взяты из
самих скриптов, а не из памяти.

Сборка и проверка идут на Windows в git-bash. Godot качается один раз
(`tools/ci/fetch_godot.sh`: закреплённая сборка, проверка sha512) — в репозитории его нет.

---

## 1. Commands — что запускать

### Подготовка (один раз на клон)

```bash
tools/ci/fetch_godot.sh      # закреплённый Godot 4.x, проверка sha512 (~86 MB)
```

### Основные проверки

```bash
tools/ci/run_tests.sh        # ОРАКУЛ: import + headless-сьют + гейт по SCRIPT ERROR
tools/ci/run_gates.sh        # все гейты из реестра, отчёт в build/gates/
tools/ci/build_current.sh    # пересобрать build/current/{windows,web}
tools/ci/scenario_s3.sh      # релизная веб-сборка в настоящем Chromium, 1280x720 и 390x844
```

`run_tests.sh` держит пять условий сразу: import наполнил `.godot/`, `res://tests/run.gd`
вышел с 0, раннер напечатал `ALL TESTS PASSED`, число тестов не ниже `MIN_TESTS`
(по умолчанию 420 — порог в скрипте), и в логе ноль `SCRIPT ERROR` / `Failed to load
script`. Зелёный сьют, который пропустил модуль, — это и есть отказ, который гейт ловит.

`run_gates.sh` читает реестр в себе самом: 39 строк вида
`"ID|hg|required|script|target"`, из них 38 `required` и одна (`ACCEPTANCE`) в
`quarantine`. Флаги: `--hg` (только функциональные), `--sg` (только внешность и
удобство), `--report-only` (пересобрать `build/gates/report.html` из прошлого прогона).

### Точечные гейты (их можно звать по одному)

```bash
bash tools/ci/gates/acceptance_gate.sh        # 12 обещаний приёмки, DONE/TODO по каждому
bash tools/ci/gates/hg08_sdk_seat_gate.sh     # SDK-место играет против мока websocket
bash tools/ci/gates/chat01_gate.sh            # место Twitch-чата без сети и без токена
```

### Детерминизм и корпус

```bash
godot --headless --path game --script res://tools/replay_cli.gd -- --verify-all corpus/games
godot --headless --path game --script res://tools/soak_cli.gd -- --sweep 40 --seed 2000 --players 4
godot --headless --path game --script res://tools/corpus.gd -- --out build/corpus --games 4 --seed 20000
```

### Запуск игры

```bash
godot --path game                                        # обычный запуск
NEURO_SDK_WS_URL=ws://127.0.0.1:8000 godot --path game   # место с драйвером sdk:neuro
```

Хост сетевой партии и раздача мест: `--server-bind=0.0.0.0`, токен места печатает хост;
подключение — `--seat=<token> --host=ws://<address>:<port>`. Полная инструкция (локально,
по сети, в браузере, с таблицей неисправностей) — `docs/how-to-play.md`.

### Как читать вердикт

Не по коду возврата. `run_gates.sh` в шапке говорит прямо: вердикт читается из строк
(`==> HG-XX PASSED` / `==> HG-XX FAILED: причина`), а код возврата Godot — шум (на Windows
он падает при очистке). `build_current.sh` читает вердикт ИЗ ФАЙЛОВ: упавший экспорт
оставляет прошлый артефакт на месте и всё равно выходит с 0. `scenario_s3.sh` печатает
единственный вердикт последней строкой — `==> S3 PASSED (...)` или `==> S3 FAILED: причины`.

---

## 2. Source — где что лежит

| Путь | Что это |
|---|---|
| `game/core/` | движок правил: `engine.gd` (авторитет, `submit_intent`), `board.gd`, `player.gd`, `card_deck.gd`, `rng.gd`, `snapshot.gd`, `event_log.gd`, `game_settings.gd`, `player_identity.gd` |
| `game/sdk/` | адаптер Neuro SDK: `sdk_adapter.gd` (регистрация действий, force, результат), `projection.gd` (проекция состояния для места), `markdown_renderer.gd` (контекст), `decision_controller.gd` (когда и что форсить), `engine_action.gd` (действие → намерение, fail-closed), `result_message.gd` (сообщение успеха) |
| `game/seats/` | места: `seat_manager.gd`, `seat.gd`, `seat_config.gd`, `minimal_action.gd`, `ai_persona.gd`, `trade_evaluator.gd`, `trade_negotiator.gd`, `drivers/` (`ai_driver`, `chat_driver`, `local_driver`, `remote_driver` — SDK-место ведёт `game/sdk/sdk_adapter.gd`) |
| `game/ui/` | интерфейс: панели, журнал, инспектор, тема; контракт раскладки — `game/ui/core/layout_profile.gd` |
| `game/tests/` | headless-модули: `run.gd` + `engine_test.gd`, `sdk_test.gd`, `ui_contract_test.gd`, `replay_test.gd`, `seats_test.gd`, `server_test.gd` и остальные |
| `game/tools/` | пробы и CLI: `replay_cli.gd`, `soak_cli.gd`, `corpus.gd`, `phone_fit_probe.gd`, `layout_dump.gd`; гейтовые сцены — `game/tools/gates/` |
| `game/addons/neuro-sdk/` | вендоренный Godot Neuro SDK (MIT, `LICENSE.md` рядом с кодом) |
| `tools/ci/` | оракул (`run_tests.sh`), реестр гейтов (`run_gates.sh`), сборка (`build_current.sh`), сценарий релиза (`scenario_s3.sh`), закреплённый Godot (`fetch_godot.sh`), мок websocket (`mock_neuro_ws.py`), мост Twitch (`twitch_bridge.py`); шелл-гейты — `tools/ci/gates/` |
| `docs/` | `program.md` (единственный план), `licensing.md` (норма права), `how-to-play.md`, `infra.md`, `acceptance/`, `release/`, `restoration/`, `specs/` |
| `corpus/games/` | записанный корпус решений (JSONL), воспроизводится побайтово |
| `build/current/{windows,web}` | артефакты сборки; в git их нет (`.gitignore`), они пересобираются |

Как запустить проверку целиком: `tools/ci/fetch_godot.sh` один раз, затем
`tools/ci/run_tests.sh`, `tools/ci/run_gates.sh`, `tools/ci/build_current.sh`,
`tools/ci/scenario_s3.sh`. Приёмка пакета — `bash tools/ci/gates/acceptance_gate.sh`.

---

## 3. Notes — честные ограничения

**Контракт узкого окна.** `game/ui/core/layout_profile.gd` объявляет
`const MIN_WIDTH := 880`. Телефонное окно 390 px продукт не поддерживает: проба
`game/tools/phone_fit_probe.gd` измеряет раскладку в 390×844, и по комментарию в
`tools/ci/gates/probes_gate.sh` раскладка занимает 817 px в окне 390 px — переполнение
больше чем вдвое. Это **не регрессия**: проба подключена к PROBES с инвертированным
ожиданием (она обязана быть красной, пока раскладка не станет узкой) и держится в
`quarantine`, её красный не блокирует сборку. Отдельное обещание — «зритель читает
картинку с телефона» — меряет другой гейт, STREAM-READ: он масштабирует кадр 1920×1080
до 390 px и судит эффективный кегль против порога 12 px. Поэтому «телефон не играет» и
«телефон не читает стрим» — два разных ответа, и второй измерен.

**Что меряется только на моке.** SDK-место проверяется гейтом HG-08 против
`tools/ci/mock_neuro_ws.py`, а не против живого сервера Neuro: живой сервер — внешняя
зависимость, в дереве его нет. Настоящая модель в цикле проверялась вручную в сессиях,
этот факт в репозиторий как гейт не попал.

**Twitch.** Живой IRC требует токена: `tools/ci/twitch_bridge.py --live` читает
`NPT_TWITCH_TOKEN` из окружения (никогда из командной строки и никогда не печатает его);
без токена мост честно падает на проверке. Гейт CHAT-01 при этом доказывает место чата
без сети и без токена: грамматика голосования, антифлуд, молчащий чат не вешает матч,
нелегальная ставка отсекается движком.

**Что вне дерева.** Заявка на `vedal.ai/projects` подаётся только владельцем — так и
записано в `docs/program.md` (строка A7: «вне дерева — подаётся только владельцем»).
Текст заявки, канал, стримовое имя (`docs/licensing.md`: stream-facing name TBD with
Vedal) — решения владельца, не инженера.

**Сам гейт приёмки в карантине.** Строка реестра в `tools/ci/run_gates.sh`:
`"ACCEPTANCE|hg|quarantine|script|tools/ci/gates/acceptance_gate.sh"`. Он пересчитывает
12 обещаний на каждом прогоне и печатает DONE/TODO с доказательством; пока обещания
открыты, его красный — это состояние трека, а не дефект гейта, и он не блокирует раннер.
В `required` он переходит после подписания пакета.

**Что уже измерено и чем.** Оракул — `tools/ci/run_tests.sh` (порог 420 тестов, ноль
`SCRIPT ERROR`). Гейты — `tools/ci/run_gates.sh` (39 строк реестра, отчёт
`build/gates/report.html`, результат каждого гейта — `build/gates/<id>.json`; у HG-13 там
вердикт `pass`). Релизная сборка — `tools/ci/scenario_s3.sh`: экспорт делается этим же
прогоном, свежесть pck сверяется со временем старта, кадр открывается в Chromium на
1280×720 и 390×844. Детерминизм — `replay_cli.gd --verify-all` (повтор даёт тот же
отпечаток), `soak_cli.gd`, `corpus.gd`.

---

## 4. Handoff — что делает следующий человек

1. **Прочитать состояние, а не поверить отчёту.** `bash tools/ci/gates/acceptance_gate.sh`
   — 12 строк, каждая пересчитана сейчас. Открытые строки и есть настоящий список работы.
2. **Собрать и проверить пакет.** `tools/ci/build_current.sh`, затем `run_tests.sh`,
   `run_gates.sh`, `scenario_s3.sh`. Вердикты читать по строкам (см. раздел Commands).
   Состав поставки, манифест и ограничения — `docs/release/package-notes.md`.
3. **Отдать критерии приёмки.** `docs/acceptance/api-criteria.md` — таблица «пункт брифа →
   код → замер» по девяти критериям API; там же под таблицей сказано, какие пункты закрыты
   не полностью и почему.
4. **Заявка на `vedal.ai/projects` — за владельцем.** Форма вне дерева; инженер готовит
   приложения (релизный пакет, критерии, лицензионную записку `docs/licensing.md`), но не
   подписывает и не отправляет её. Точный текст заявки — решение владельца.
5. **Данные владельца.** Токен Twitch (`NPT_TWITCH_TOKEN`), адрес живого сервера Neuro
   (`NEURO_SDK_WS_URL`), имя канала и стримовое название игры — это его данные; в
   репозитории их нет и быть не должно.
6. **Не трогать без нужды.** Числа в доках сверяет гейт DOC-NUMBERS
   (`tools/ci/gates/doc_numbers_gate.sh`): он сравнивает счёт тестов и число гейтов в
   текстах с тем, что реально даёт оракул и реестр. Если цифра разошлась с деревом —
   правится источник, а не цифра на глаз.
