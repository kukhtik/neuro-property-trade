# P5 — Localization + Adaptivity + SFX (branch `ui/overhaul`)

Spec: `docs/superpowers/specs/2026-09-07-ui-ux-redesign-concept-v2.md` §9
(localization), §10 (adaptivity), §3.2–3.4 (density breakpoints), §6.1 (SFX/dice),
P5 done-criterion (line 495). This is the final UI phase.

## Scope (three workstreams)

| # | Workstream | Files | Done-gate (behavioral) |
|---|-----------|-------|------------------------|
| 1 | i18n dict + string swap | `i18n/*.gd` (new), all `ui/`+`visual/`+`admin/` | `p5_probe`: RU→EN — **0 raw/cyrillic screen strings**; instant switch, **no scene rebuild**; rules templates localized |
| 2 | Adaptivity 5 breakpoints | `ui/game_view.gd` `_layout`, `visual/board_scene.gd` | board cell fits whole ring at 5 res; **nothing overflows viewport** (global_rect in view rect) |
| 3 | SFX (dice/toasts/timer) | `visual/sfx.gd`, `ui/dice_stage.gd`, `ui/timer_ring.gd`, wired via `top_bar`/`toast`/`game_view` | dice whoosh+bounce, toast pop, per-second timer tick; gated by `settings.sound/sfx` |

## i18n architecture (§9, dict-based)

- `i18n/i18n.gd` (`class_name I18n`): merges per-domain `data_*.gd` `const D`
  dicts loaded once. `I18n.t(key, vals?)` → current-locale string with GDScript
  `%s/%d` positional format (or `{{name}}` dict form). `I18n.LOCALES = ["ru","en"]`.
  `I18n.set_locale("en")` emits `I18n.inst().locale_changed`.
  Missing key → `{key}` sentinel (probe relies on it to catch raw strings).
  `I18n.key_on(node,key)` / `I18n.tip_on(node,key)` / `I18n.relabel(root)` =
  metadata-driven retranslate for live panels.
- Domains: `data_ui.gd` (ui.*), `data_settings.gd` (settings.*+rules templates),
  `data_action.gd` (action.* engine actions + phase.* human-readable phases),
  `data_event.gd` (event.* + toast.*), `data_admin.gd` (admin.*).
- **Event wording unified**: `EventMessages.describe()` now calls `I18n.t("event.*")`;
  `ToastStack.show_event_toast()` calls `I18n.t("toast.*")` — journal, overlay,
  toasts all agree (kills the old duplicated manual strings in game_view).
- Live switch: `settings_overlay` language OptionButton → `I18n.set_locale` +
  `_retranslate()` (relabel + rebuild localized OptionButton items preserving
  selection). SettingsOverlay is built ONCE (main.gd), so it relabels live, no
  scene rebuild. Persistent HUD (top bar / players / action / inspector / journal)
  relabel via `I18n.relabel` on `locale_changed`.

## Adaptivity (§10, §3.4)

- Board already self-scales (`board_scene._resize_children`, cell=min(w,h)/grid).
  **P5 adds the explicit spec rule** cell = min(w,h)/11 (11×11 grid) so the whole
  ring always fits — verify at 1440×900 / 1280×720 / 1024×640 / 900×600 / 1920×1080.
- Breakpoints (width):
  | width | LEFT | RIGHT |
  |-------|------|-------|
  | ≥1600 | 260px | 320px |
  | 1280–1599 | 240px | 300px |
  | 1024–1279 | rail 56px (players collapsed) | drawer (journal tab) |
  | <1024 | drawer | drawer (action bar = bottom sheet) |
- `game_view._layout()` picks the breakpoint from `size.x`, sizes panels
  accordingly; the HBox keeps the board center-filling. Compact cell <44 already
  handled by P2 tile compact mode.

## SFX (§6.1 dice)

- `Sfx` grows `play_dice_whoosh()` / `play_dice_bounce()` / `play_toast_pop()` /
  `play_timer_tick()` (procedural AudioStreamGenerator; existing gotchas from
  phase skill: playback via `get_stream_playback()`, `is_playing()`).
- `DiceStage` gets `set_sfx()` → whoosh on roll, click per tumble step.
- `ToastStack` gets `set_sfx()` → pop on new toast.
- `TimerRing` gets `set_tick_callback()` → fires each second boundary; TopBar
  routes it to `Sfx.play_timer_tick()`.
- `game_view` wires `_board_scene._sfx` into toast/timer after setup. All honors
  the existing `settings.sound` / `_sfx.enabled` gate.

## Files added/edited

- new: `i18n/i18n.gd`, `i18n/data_{ui,settings,action,event,admin}.gd`
- `tests/i18n_test.gd` (both locales present, substitution, missing sentinel,
  locale switch, every entry is {ru,en}, EN has no cyrillic)
- localized: `ui/{action_panel,top_bar,players_panel,tile_inspector,journal_panel,
  modal_host,settings_overlay,toast,game_view}.gd`,
  `visual/event_messages.gd`, `visual/event_overlay.gd`, `admin/admin_panel.gd`
- SFX+adaptivity: `visual/sfx.gd`, `ui/{dice_stage,timer_ring}.gd`,
  `ui/game_view.gd` `_layout`, `visual/board_scene.gd`

## Verification

- `godot --headless --path game --script res://tests/run.gd` (204 + i18n green,
  `grep "SCRIPT ERROR"`).
- `tools/p5_probe.tscn` — behavioral, NOT screenshots:
  1. RU→EN → walk the built UI tree, every visible text either empty/symbol or
     not cyrillic and not `{key}` sentinel → **0 raw strings**.
  2. Switch back → texts returned (no scene rebuild, same node ids).
  3. 5 resolutions → board cell fits whole ring; walk tree, every Control
     `global_rect` inside viewport rect → nothing overflows.
  4. SFX: dice roll triggers whoosh/bounce; toast triggers pop; timer second tick
     triggers tick (inspect `_sfx.is_playing()`/buffer or a probe hook).
- Commit per phase on `ui/overhaul`.

## Gotchas (from the skill, will bite)

- Probes run via `.tscn`, NOT `--script` (probes extend Node).
- Every `await`-containing check MUST be `await _check_x(...)` (masked-pass).
- Early-failure path must `quit(1)` before `return` (hang).
- `:=` from untyped values → annotate `var x: Type =`.
- GDScript `%` with a single `%s` arg needs an Array (`[x]`), not a bare value,
  when I18n.t forwards to `s % vals` — keep the existing `% [ ]` array shape.
