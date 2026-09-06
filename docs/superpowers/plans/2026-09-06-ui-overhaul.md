# UI overhaul — historical plan (superseded)

**This document predates the approved v2 UI/UX redesign concept and is kept
only for history.** It still describes the work that was done for Phase A and
the asset-copy phase (G), but every later phase (what used to be B/C/D/E/F)
has been replanned and renumbered in line with the v2 concept.

Authoritative roadmap from 2026-09-07 onwards:

- **Source of truth:** `docs/superpowers/specs/2026-09-07-ui-ux-redesign-concept-v2.md`
- **Rolling status / next steps:** `docs/plan.md`, section "Current phase —
  UI/UX overhaul".

The mapping below lets you read the v1 plan without losing context:

| v1 phase | v2 status / replacement |
|---|---|
| A (foundation, A1–A5) | **DONE** — kept as-is, with the v2 layout/adaptivity tweaks landing in P5 |
| G (SVG assets) | **In progress** — asset copy + import done; wiring into TileView/TokenPanel continues inside P2/P1 |
| B1 host-observer | Replaced by **P4** (observer is a seat-config, not a driver) |
| B2 restart + settings | **P0** — settings overlay + restart + game-over flow in one commit |
| B3 toasts | **P3** (toast/banner stack + anti-spam, fed by EventMessages upgrade) |
| B4 top timer | **P3** (timer ring in TopBar, honest about SDK seats) |
| C1 admin host-only | **P0** (is_host gate + no-render on WebGL) |
| C2 admin clarity | **P4** (per-operation fields, inline results, admin log) |
| D1 rules button | **P0** (rules modal, F2, dynamic from settings; localized in P5) |
| D2 more settings | **P0** (the SettingsOverlay exposes the full 5-block config) |
| D3 parametric board (tile_count, presets) | **Descoped** — not part of the 17-problem fix list; revisit post-v2 if stream format really wants a small board |
| E logging (`ai_decision`, filters) | **P4** (journal rewrite with filters/export; `ai_decision` event still queued there) |
| F i18n | **P5** (dict-based `game/i18n/i18n.gd`, instant switch, RU/EN) |

Do NOT schedule new work against the v1 numbering below this line.

---

## (archived v1 content)

**Фаза A — Фундамент (СДЕЛАНО, 2026-09-06)**

A1 адаптивный лейаут · A2 тултипы · A3 авто-скрытие справки · A4 фишки/цвет/домики · A5 переработка клеток.
Коммиты `cca9b11` + `7583980` на `ui/overhaul`.

**Фаза G — Подключение ассетов (в работе)**

- Шаг 0: ассеты скопированы `C:\Users\kukhtik\Desktop\assets` → `game/assets/`, `godot --headless --import .` прогнан (28 `.import` файлов).
- Карта слотов: `tokens/{ship,top_hat,dog,cat,race_car,boot,iron,wheelbarrow}.svg`, `corner_icons/{go_arrow,jail,free_parking,go_to_jail}.svg`, `type_icons/{tax,chance,community_chest,railroad,utility}.svg`, `dice/die_1..6.svg`, `houses/{house,hotel}.svg`, `board_center.svg`, `button.svg`, `tile.svg`.
- Интеграция в код — теперь часть фаз P1/P2 v2 (AssetLoader seam в `ui/theme.gd` остаётся).

Всё ниже — историческое, заменено v2-концепцией.

### B1. Хост-наблюдатель → v2 P4 (наблюдатель = матч без LOCAL-места, не новый драйвер)
### B2. Рестарт + меню → v2 P0 (настройки-оверлей + рестарт + game-over)
### B3. Уведомления → v2 P3
### B4. Таймер → v2 P3
### C1. Админ host-only → v2 P0
### C2. Админ-понятность → v2 P4
### D1. Правила → v2 P0
### D2. Больше настроек → v2 P0 (полный GameSettings в оверлее)
### D3. Параметризуемая доска → descoped
### E. Логирование → v2 P4
### F. Локализация → v2 P5

Проверка всегда: `godot --headless --path game --script res://tests/run.gd`
(+ grep SCRIPT ERROR), `tools/tony.tscn`, phase-specific probes. Скриншоты —
только иллюстрация.
