# Phase 2 — Neuro SDK Adapter (design)

Date: 2026-09-06. Status: design → implement.

## Goal

Wire the authoritative engine (Phase 1, 81 tests green) to the Godot Neuro
SDK so an AI seat (Neuro / Evil) plays by submitting intents. The engine
stays the single source of truth; the adapter is a thin, fail-closed bridge
that projects per-seat state, forces at decision points, and maps SDK actions
to `engine.submit_intent`.

## Architecture (pure core + thin SDK shell)

The engine is pure GDScript (RefCounted, no scene tree). The SDK is Node-based
(autoloads, websocket). We split the adapter so the *logic* is headless-testable
and the *wiring* is a thin Node.

```
game/
  core/engine.gd            (+ legal_actions(pid), read-only accessors)
  sdk/
    projection.gd           pure: per-seat view Dictionary (isolates private info)
    markdown_renderer.gd    pure: projection -> markdown string
    decision_controller.gd  pure: (engine,pid) -> {force, query, actions, ...}
    engine_action.gd        NeuroAction subclass: maps SDK action -> submit_intent
    sdk_adapter.gd          Node: startup, register, force, result, reconnect
  addons/neuro-sdk/         vendored Godot SDK (from VedalAI/neuro-sdk)
```

Pure pieces (`projection`, `markdown_renderer`, `decision_controller`,
`engine.legal_actions`) are loaded by path in headless tests and never touch
the SDK. The Node pieces (`engine_action`, `sdk_adapter`) are thin and not
headless-tested (they need a live websocket).

## Action registry (stable set, registered once at startup)

SDK name -> engine action -> params:

| SDK action | engine action | params |
|---|---|---|
| `roll_dice` | `roll` | — |
| `buy_property` | `buy` | — |
| `pass_on_purchase` | `pass` | — (also used for auction pass) |
| `bid_auction` | `bid` | `amount` |
| `build_house` | `build_house` | `tile` |
| `sell_house` | `sell_house` | `tile` |
| `mortgage_property` | `mortgage_property` | `tile` |
| `unmortgage_property` | `unmortgage_property` | `tile` |
| `propose_trade` | `propose_trade` | `to, give_tiles, want_tiles, give_cash, want_cash` |
| `respond_trade` | `respond_trade` | `accept` |
| `pay_jail_fine` | `pay` | — |
| `use_jail_card` | `use_card` | — |

**Deviation from plan:** the plan listed `end_turn`, but the engine has no
`end_turn` decision point — end-of-turn is automatic (`_end_turn_or_continue`).
Registering a no-op `end_turn` would confuse Neuro, so it is omitted. Documented
here so it is not re-added.

## Fail-closed flow (result-before-execute)

The SDK's `Action.validate()` already runs validate → `action/result` → execute.
`EngineAction._validate_action` calls `adapter.try_submit(...)` which calls
`engine.submit_intent(pid, action, params)`. `submit_intent` is atomic and
fail-closed: on `ok:false` it mutates nothing and returns `{reason, legal}`;
on `ok:true` it applies the change and returns `{events}`.

- `ok:false` -> `ExecutionResult.failure(reason + " Legal: " + legal)` — SDK
  sends the failure result, no execute, and Neuro auto-retries the force.
- `ok:true` -> store `events` in state, `ExecutionResult.success()` — SDK sends
  the success result, then `_execute_action` emits the events. The engine change
  is already applied atomically; the result is sent before any visible effect.

No contradictory second result: the SDK `ActionWindow` ends on the first
successful result (`STATE_ENDED`), so a second action in the same window is
rejected. Reconnect: the SDK auto-reconnects and re-registers actions
(`actions/reregister_all`); the adapter re-forces on the `connected` signal.

## Per-seat projection

`projection.for_player(engine, pid)` returns a Dictionary with:
- public board: every tile's index/name/type/group/cost + owner + houses +
  mortgaged flag
- public players: name, money, position, in_jail, jail_turns, bankrupt
- private: only this seat's `get_out_of_jail_cards`
- pending decision context (purchase tile / auction high+bidder / pending trade)
- `legal`: `engine.legal_actions(pid)`

Auction isolation: the current high bid + bidder are public (real auctions show
them), but each seat's private info (jail cards) is never leaked to other seats.
`markdown_renderer.render(proj)` turns it into a `##`-headed markdown string
(~20 items, painfully explicit, per SDK best practices).

## Decision controller

`decision_controller.decide(engine, pid)` returns
`{force, query, actions, ephemeral_context, priority}`. It forces only when
`legal_actions(pid)` is non-empty (it is this seat's turn, or this seat is the
auction bidder, or this seat is a trade recipient). Query text is phase-aware.
`ephemeral_context:true` for the bulky board dump; `priority:low` (turn-based).

## Testing

Headless (no websocket): `legal_actions_test`, `projection_test`,
`markdown_renderer_test`, `decision_controller_test` — deterministic engine
fixtures (same `_force_dice`/`_teleport` hooks as Phase 1). Registered in
`tests/run.gd`. SDK wiring is exercised later via the Randy/Tony ladder
(Phase 4), not headless.
