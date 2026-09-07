# P4 — Modes: observer, journal, admin tabs (DONE 2026-09-07)

Spec §11 P4 + §7 (observer) + §8.2 (admin rework). Behavioral probe
`tools/p4_probe.gd`+`.tscn` — **5 check-groups, 10 PASS**, exit 0.

**VERIFY:** `godot --headless --path game res://tools/p4_probe.tscn`
(print "P4 PROBE: ALL PASSED", exit 0). Suite still 198 green, 0 SCRIPT ERROR
(`godot --headless --path game --script res://tests/run.gd` + grep).

## What P4 built

- **`ui/journal_panel.gd` (NEW)** — replaces the bare 10-line label in
  game_view. `RichTextLabel` with `scroll_following=true` (auto-scroll),
  colored BBCode lines per event type, filters **player** ("все" + per-pid
  OptionButton) / **type** (unique types present in log) / **money-only**
  CheckButton, `vis/total` count label, export →
  `user://journal_export.jsonl`. Pure static `filter_entries(entries, pid,
  type, money_only)` + `to_jsonl(entries)` are headless-testable.
  Player-mention keys: `player/from/to/proposer/recipient/winner`. Money-only
  = type in `MONEY_TYPES` OR data has `amount/cost/price`.
- **Observer mode (§7) is a SEAT CONFIGURATION, not a mode enum** — detected
  in `_sync_from_spectator` by scanning seats for `input_driver == "LOCAL"`.
  `_set_observer(v)` widens journal to 380px (`_journal_w()` branch),
  `top_bar.set_observer` shows 👁 (ONLY visible in no-LOCAL matches; click →
  settings overlay), `action_panel.set_observer` → 0 buttons + thin status bar
  "ход: <PHASE> · решение за <holder> · авто-через 0:SS" (SDK holders show
  "ожидание Neuro…"; timer numbers from `emit_spectator` P3 fields).
- **Follow**: players_panel rows emit `player_clicked(pid)` (PanelContainer
  gui_input, mouse_filter STOP); game_view toggles `_follow_pid` →
  `board.set_target_tiles(player tiles)` — REUSES the P2 target-frame
  machinery, no new highlight code. **Follow-highlight only applies when
  `_observer` is true** — a LOCAL match intentionally clears it (that's the
  designed behaviour; the follow probe must run in observer mode).
- **Hover→inspector**: new `tile_hovered` signal chained board_view
  (`InputEventMouseMotion` branch in `_on_tile_input`) → board_scene →
  game_view → `_inspector.select(idx)`. Allowed in LOCAL matches too
  (non-destructive preview).
- **respond_trade button filtered by context** — action_panel renders it only
  when `proj.pending.type == "trade"` (mirrors the Phase-3
  `minimal_action.pick` lesson); kills the always-visible "ОТВЕТИТЬ на
  сделку" button that opened an empty modal (spec problem 20).
- **`admin/admin_panel.gd` FULL REWRITE (§8.2)** — 4 tabs
  [Быстрые/Состояние/События/Правки].
  - Быстрые = force_roll / force_pass / rollback / reset_away.
  - Состояние = dump summary + clipboard JSON + snapshot save/load.
  - События = type filter + .jsonl export + colored live feed
    (EventMessages wording).
  - Правки = declarative `EDIT_OPS` const (op → {label, tip, fields,
    confirm?}) building per-op rows that show ONLY their own fields; results
    INLINE on the row (ok/причина, colored) + admin log at bottom — never
    stdout-only (problem 24); search filters rows over op+label+tip;
    destructive ops (reorder_players/redo_turn/snapshot load) gated by a
    ConfirmationDialog with an `auto_confirm` bool hook for probes.
  All mutations still go gate→controller→engine.admin_override (invariant
  intact). Snapshot load emits `game_rebuilt(engine)` → main.gd
  `_on_admin_rebuilt` rebuilds SeatManager+GameView on the restored engine.

## Bugs found & fixed by the probe run (this session)

1. **`admin_panel.gd:333` `mv.apply_button = true` on a `SpinBox` — SCRIPT
   ERROR** (SpinBox has no `apply_button`; that's a LineEdit field). The
   abort poisoned every `cost/rent/rent_set/house_cost` edit row and threw a
   cascade `rp_child is null` on the next `add_child`. Removed the bogus
   line. **Lessons:** (a) don't attach a property you're not sure exists on a
   widget; (b) grep the `--import` output for SCRIPT ERROR — the previous
   session's "0 SCRIPT ERROR" was actually false (the run was never exercised).

2. **`settings_overlay.gd` observer-seat bug.** `_collect_settings()` mutated
   the row-0 driver widget (`r["driver"].select(1)`) to AI when the host chose
   "только наблюдаю", then read assignments AFTER — so the assignment still
   recorded "LOCAL" AND the widget was permanently flipped (toggling host_role
   back to "играю" could NOT restore the host's LOCAL seat). **Fixed:** compute
   the host driver at collection time (row 0 → "AI" when observer, else keep
   the widget value) and NEVER mutate the widget. Toggling host_role now
   correctly flips the match between observer / LOCAL.

## Durable gotchas (will bite again)

- **Behavioral probes run via their `.tscn` wrapper, NOT `--script`**
  (`godot --headless --path game res://tools/p4_probe.tscn`). A Node-based
  probe extends Node; `--script` only runs SceneTree/MainLoop runners
  (`tests/run.gd`). Probes ship as `tools/X_probe.tscn`.
- **`var x := ` from untyped/dynamic values is STILL the #1 parse error**
  (journal `OptionButton.selected`, admin `dump_state()`, probe reads of
  `.text`/`_edit_widgets`). Annotate `var x: Type = ...` for anything read off
  a Control or a widget-dict lookup.
- **A probe that early-`return`s on failure WITHOUT calling `quit()` HANGS
  forever** (headless waits on the frame loop). Every `_fail(...)/return`
  must `quit(1)` first (probe-helper pattern).
- **Masked-pass trap (Phase-A lesson, hit AGAIN):** a check function that
  contains `await` but is called WITHOUT `await` becomes a detached coroutine
  that never runs, so its `_fail()`/`_had_fail` is never reached and the probe
  prints "ALL PASSED" while skipping whole groups. **Any `await`-containing
  check MUST be `await _check_x(...)`.**
- **The journal type filter only lists types PRESENT in the log.** On a fresh
  LOCAL restart the human hasn't rolled (turn_timer=0 → no auto-pass), so a
  probe must `manager.push_intent(human_pid, "roll", {})` and wait real time
  (Time deadline, not frames) before asserting a `"roll"` type exists.
- **Follow is observer-only by design.** Don't assert target frames in a LOCAL
  match (clears them); run the follow check while `_observer` is true.
- **Admin tab/panel hooks for probes:** `_edit_widgets(op)` (per-op
  Dictionary of its widgets + `result` Label), `_edit_rows`, `_admin_log_lines`,
  `auto_confirm` (true = skip ConfirmationDialog). Journal exposes `_count_lbl`,
  `_entries`, `_export()`. Follow asserts via `tile._target` flags on
  `board._tile_nodes`.

## Probe authoring: how the 10 PASS are structured

1. observer layout — 0 action buttons, holder status bar, journal 380px,
   👁 visible, journal count non-zero
2. follow (in observer) — grant tile → `follow_player(0)` highlights exactly
   that tile; unfollow clears
3. back to LOCAL — 👁 hidden, human БРОСИТЬ button present, `_observer` false
4. journal filters — money filter changes set, pid-0 filter non-empty,
   "roll" type exists after a driven roll, `filter_entries` pure sanity,
   `_export()` writes `user://journal_export.jsonl` with all lines
5. admin panel — 4 tabs titled, quick force_roll lands in inline admin log,
   set_balance changes engine money + inline "ok", search narrows to 1 row,
   redo_turn blocked by dialog on cancel AND executes on auto_confirm
