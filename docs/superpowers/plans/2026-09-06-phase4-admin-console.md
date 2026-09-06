# Phase 4 — Admin Console & Test Ladder (implementation plan)

**Goal:** Deliver the deep engine + test-ladder slice of Phase 4: a headless-testable
admin console (spec §4) with a full `admin_override` engine entry point, engine
snapshot export/import + diagnostics, Tony scripted scenarios (test-ladder rung 3),
and a WebGL export build. Visual layer explicitly deferred.

**Architecture:** Pure `admin_controller` (RefCounted, headless-testable) + thin
Godot `admin_panel` (Control, F12-toggle in `main.tscn`), both calling into a
new `engine.admin_override(op, params)` that routes every edit through the
authoritative engine and appends to the same append-only event log. Snapshot
logic lives inside `engine.gd` (`to_snapshot`/`from_snapshot`) with a thin
`snapshot.gd` file-I/O wrapper. Tony scenarios run as a `tony_test.gd` module
(registered in `run.gd`) + a `tools/tony.tscn` runtime demo.

**Tech stack:** Godot 4.7.2 GDScript, headless test runner
(`godot --headless --path game --script res://tests/run.gd`), existing
`engine`/`seat_manager`/projection code. Export templates already installed at
`~/.local/share/godot/export_templates/4.7.2.stable/`.

**Branch:** `phase4/admin-console` (created; design doc committed).

**Verification every task:** the orchestrator MUST re-run the full headless
suite (`godot --headless --path game --script res://tests/run.gd`) after each
task and confirm the count grows exactly as expected before committing. Leaf
summaries are self-reports; this repo's tests are cheap and shared, so the
re-run is the guard.

---

## Task 1 — Engine: `admin_override` state-edit operations

**File(s):** modify `game/core/engine.gd`; create `game/tests/admin_test.gd`.
**Scope:** the state-editing ops (spec §4.B) that don't need the turn guard.

- [ ] **Step 1: Write failing tests** in `game/tests/admin_test.gd` covering:
  `set_balance`, `teleport`, `force_dice`, `grant_property`/`revoke_property`,
  `set_houses`, `set_mortgage`, `set_go_jail`, plus validation rejections
  (bad pid, bad tile, negative/oversized values) and that each successful op
  appends an `admin_override` event to the log.

  ```gdscript
  # game/tests/admin_test.gd
  extends RefCounted

  static func test_list() -> Array[String]:
      return [
          "test_set_balance", "test_set_balance_rejects_bad_pid",
          "test_set_balance_rejects_negative", "test_teleport_moves",
          "test_teleport_rejects_bad_tile", "test_force_dice_applies",
          "test_force_dice_rejects_out_of_range", "test_grant_property",
          "test_revoke_property_clears_state", "test_set_houses",
          "test_set_houses_rejects_range", "test_set_mortgage_on_off",
          "test_set_go_jail", "test_admin_override_logged",
          "test_unknown_op_fails",
      ]

  static func _make_engine(names: Array = ["Ada", "Bo"]):
      var E = load("res://core/engine.gd")
      var S = load("res://core/game_settings.gd")
      var e = E.new()
      e.setup(S.new(), names)
      return e

  static func _has_admin_event(e, op: String) -> bool:
      for entry in e.log.entries():
          if entry.get("type", "") == "admin_override" and entry.get("data", {}).get("op", "") == op:
              return true
      return false

  static func test_set_balance() -> String:
      var e = _make_engine()
      var res = e.admin_override("set_balance", {"pid": 0, "amount": 800})
      if not res.get("ok", false): return "expected ok: %s" % str(res)
      if e.player(0).money != 800: return "money want 800 got %d" % e.player(0).money
      if not _has_admin_event(e, "set_balance"): return "expected admin_override log"
      return ""

  static func test_set_balance_rejects_bad_pid() -> String:
      var e = _make_engine()
      var res = e.admin_override("set_balance", {"pid": 9, "amount": 100})
      if res.get("ok", false): return "should reject bad pid"
      if e.player(0).money != 1500: return "no mutation expected"
      return ""

  static func test_set_balance_rejects_negative() -> String:
      var e = _make_engine()
      var res = e.admin_override("set_balance", {"pid": 0, "amount": -5})
      if res.get("ok", false): return "should reject negative balance"
      return ""

  static func test_teleport_moves() -> String:
      var e = _make_engine()
      var res = e.admin_override("teleport", {"pid": 0, "tile": 24})
      if not res.get("ok", false): return "expected ok"
      if e.player(0).position != 24: return "position want 24 got %d" % e.player(0).position
      return ""

  static func test_teleport_rejects_bad_tile() -> String:
      var e = _make_engine()
      var res = e.admin_override("teleport", {"pid": 0, "tile": 99})
      if res.get("ok", false): return "should reject bad tile"
      return ""

  static func test_force_dice_applies() -> String:
      var e = _make_engine()
      var res = e.admin_override("force_dice", {"d1": 5, "d2": 2})
      if not res.get("ok", false): return "expected ok"
      # next roll must be 7, not doubles
      e.submit_intent(0, "roll", {})
      if e._last_roll.get("sum", 0) != 7: return "forced roll sum want 7 got %d" % e._last_roll.get("sum", 0)
      if e._last_roll.get("doubles", true): return "forced roll should not be doubles"
      return ""

  static func test_force_dice_rejects_out_of_range() -> String:
      var e = _make_engine()
      var res = e.admin_override("force_dice", {"d1": 7, "d2": 2})
      if res.get("ok", false): return "should reject dice out of 0..6"
      return ""

  static func test_grant_property() -> String:
      var e = _make_engine()
      var res = e.admin_override("grant_property", {"pid": 1, "tile": 6})
      if not res.get("ok", false): return "expected ok"
      if not e.player(1).owns(6): return "player 1 should own tile 6"
      return ""

  static func test_revoke_property_clears_state() -> String:
      var e = _make_engine()
      var gr = e.admin_override("grant_property", {"pid": 0, "tile": 6})
      var bh = e.admin_override("set_houses", {"tile": 6, "count": 2})
      if not bh.get("ok", false): return "set_houses should be ok (%s)" % str(bh)
      var mg = e.admin_override("set_mortgage", {"tile": 6, "on": true})
      if not mg.get("ok", false): return "set_mortgage should be ok"
      var rv = e.admin_override("revoke_property", {"pid": 0, "tile": 6})
      if not rv.get("ok", false): return "revoke should be ok"
      if e.player(0).owns(6): return "should not own after revoke"
      if e._houses.get(6, 0) != 0 or e._mortgaged.has(6): return "houses/mortgage should clear on revoke"
      return ""

  static func test_set_houses() -> String:
      var e = _make_engine()
      var res = e.admin_override("set_houses", {"tile": 6, "count": 4})
      if not res.get("ok", false): return "expected ok"
      if e._houses_on(6) != 4: return "houses want 4 got %d" % e._houses_on(6)
      return ""

  static func test_set_houses_rejects_range() -> String:
      var e = _make_engine()
      var res = e.admin_override("set_houses", {"tile": 6, "count": 9})
      if res.get("ok", false): return "should reject house count > 5"
      return ""

  static func test_set_mortgage_on_off() -> String:
      var e = _make_engine()
      var g = e.admin_override("grant_property", {"pid": 0, "tile": 6})
      var on = e.admin_override("set_mortgage", {"tile": 6, "on": true})
      if not on.get("ok", false) or not e._mortgaged.has(6): return "mortgage on failed"
      var off = e.admin_override("set_mortgage", {"tile": 6, "on": false})
      if not off.get("ok", false) or e._mortgaged.has(6): return "mortgage off failed"
      return ""

  static func test_set_go_jail() -> String:
      var e = _make_engine()
      var res = e.admin_override("set_go_jail", {"pid": 0})
      if not res.get("ok", false): return "expected ok"
      if not e.player(0).in_jail or e.player(0).position != 10: return "should be in jail at 10"
      return ""

  static func test_admin_override_logged() -> String:
      var e = _make_engine()
      e.admin_override("teleport", {"pid": 1, "tile": 5})
      var found := false
      for entry in e.log.entries():
          if entry.get("type", "") == "admin_override":
              found = true
      if not found: return "no admin_override event in log"
      return ""

  static func test_unknown_op_fails() -> String:
      var e = _make_engine()
      var res = e.admin_override("nonsense", {})
      if res.get("ok", false): return "should reject unknown op"
      return ""
  ```

- [ ] **Step 2: Run and confirm the module fails to load** (engine lacks
  `admin_override`):
  `godot --headless --path game --script res://tests/run.gd`
  Expected: admin_test loads but every case errors (missing method) — the
  module must first be registered in `run.gd` **along with the test code**
  (register `res://tests/admin_test.gd`).
  Expected: FAILS.

- [ ] **Step 3: Implement `admin_override` + executors in `engine.gd`.** Add
  the public entry and the private executors at the end of the file. The entry
  is NOT gated by the turn-player guard (admin is host-local, any time), but
  every op range-checks and returns `{ok, reason, events}` (mirroring
  `submit_intent`); successful ops append to the log.

  ```gdscript
  # --- Phase 4: ADMIN overrides (spec §4). Host-local, engine-authoritative. ---
  ## One admin entry — every edit validated, executed, and written to the SAME
  ## append-only event log (spec §4 hard rule #1). Never gate by turn guard.
  func admin_override(op: String, params: Dictionary) -> Dictionary:
      if phase == PHASE_SETUP:
          return _admin_fail("game not started")
      match op:
          "set_balance":
              var pid: int = int(params.get("pid", -1))
              var amount: int = int(params.get("amount", -1))
              if pid < 0 or pid >= players.size():
                  return _admin_fail("bad pid")
              if amount < 0:
                  return _admin_fail("negative balance")
              players[pid].money = amount
              return _admin_ok(op, params)
          "teleport":
              var pid: int = int(params.get("pid", -1))
              var tile: int = int(params.get("tile", -1))
              if pid < 0 or pid >= players.size():
                  return _admin_fail("bad pid")
              if tile < 0 or tile >= board.tile_count():
                  return _admin_fail("bad tile")
              players[pid].position = tile
              return _admin_ok(op, params)
          "force_dice":
              var d1: int = int(params.get("d1", 0))
              var d2: int = int(params.get("d2", 0))
              # d1,d2 in 0..6; 0 marks a non-die (the engine's own _force_dice
              # hook uses d2=0 to force a specific non-doubles sum, e.g. sum 1).
              # Reject values outside that range and a degenerate all-zero roll.
              if d1 < 0 or d1 > 6 or d2 < 0 or d2 > 6 or (d1 == 0 and d2 == 0):
                  return _admin_fail("dice out of 0..6 (not both zero)")
              _force_dice(d1 + d2, d1, d2, d1 == d2)
              return _admin_ok(op, params)
          "grant_property":
              var gpid: int = int(params.get("pid", -1))
              var gtile: int = int(params.get("tile", -1))
              if gpid < 0 or gpid >= players.size():
                  return _admin_fail("bad pid")
              if gtile < 0 or gtile >= board.tile_count():
                  return _admin_fail("bad tile")
              players[gpid].add_ownership(gtile)
              return _admin_ok(op, params)
          "revoke_property":
              var rpid: int = int(params.get("pid", -1))
              var rtile: int = int(params.get("tile", -1))
              if rpid < 0 or rpid >= players.size():
                  return _admin_fail("bad pid")
              if rtile < 0 or rtile >= board.tile_count():
                  return _admin_fail("bad tile")
              players[rpid].remove_ownership(rtile)
              _houses.erase(rtile)
              _mortgaged.erase(rtile)
              return _admin_ok(op, params)
          "set_houses":
              var stile: int = int(params.get("tile", -1))
              var count: int = int(params.get("count", -1))
              if stile < 0 or stile >= board.tile_count():
                  return _admin_fail("bad tile")
              if count < 0 or count > 5:
                  return _admin_fail("house count 0..5")
              _houses[stile] = count
              return _admin_ok(op, params)
          "set_mortgage":
              var mtile: int = int(params.get("tile", -1))
              var on: bool = bool(params.get("on", false))
              if mtile < 0 or mtile >= board.tile_count():
                  return _admin_fail("bad tile")
              if on and not _mortgaged.has(mtile):
                  _mortgaged.append(mtile)
              elif not on:
                  _mortgaged.erase(mtile)
              return _admin_ok(op, params)
          "set_go_jail":
              var jpid: int = int(params.get("pid", -1))
              if jpid < 0 or jpid >= players.size():
                  return _admin_fail("bad pid")
              var p = players[jpid]
              p.in_jail = true
              p.jail_turns = 0
              p.position = 10
              return _admin_ok(op, params)
          _:
              return _admin_fail("unknown admin op %s" % op)

  func _admin_fail(reason: String) -> Dictionary:
      return {"ok": false, "reason": reason, "legal": [], "events": []}

  func _admin_ok(op: String, params: Dictionary) -> Dictionary:
      log.append("admin_override", {"op": op, "params": params})
      return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
  ```

- [ ] **Step 4: Register `admin_test.gd` in `run.gd`** (append to the `modules`
  array, before `sdk_test.gd`). Re-run the full suite. Expected: all new
  cases PASS, and the 109 existing tests stay green. Count = 109 + 15 = **124**.

- [ ] **Step 5: Commit** (orchestrator re-runs suite + confirms count first):
  `git add game/core/engine.gd game/tests/admin_test.gd game/tests/run.gd`
  `git commit -m "feat: engine.admin_override state-edit ops (set_balance, teleport, force_dice, grant/revoke, houses, mortgage, go_jail) + admin_test"`

---

## Task 2 — Engine: `admin_override` unblocking operations

**File(s):** modify `game/core/engine.gd`; modify `game/tests/admin_test.gd`.
**Scope:** spec §4.A — force a stuck decision forward via the current decision
holder (computed on the engine, no turn guard).

- [ ] **Step 1: Add failing tests** to `admin_test.gd.test_list` and bodies:

  ```gdscript
  static func _decision_holder(e) -> int:
      # mirrors seat_manager.find_decision_holder
      for pid in e.player_count():
          if not e.legal_actions(pid).is_empty():
              return pid
      return -1

  static func test_force_roll_advances() -> String:
      var e = _make_engine(["Ada", "Bo", "Cyd"])
      var before: int = e.turn_player
      var h: int = _decision_holder(e)
      if h == -1: return "no decision holder at TURN_START"
      var res = e.admin_override("force_roll", {})
      if not res.get("ok", false): return "force_roll should be ok: %s" % str(res)
      # a roll moves to ROLL_RESOLVE or a decision phase; turn_player still holder
      if not ["ROLL_RESOLVE", "PURCHASE_WAIT", "JAIL_DECISION", "CARD_WAIT", "TURN_START", "END_GAME", "AUCTION"].has(e.phase):
          return "unexpected phase after force_roll: %s" % e.phase
      if before != h: return "holder should equal turn_player at start"
      if not _has_admin_event(e, "force_roll"): return "expected admin_override force_roll event"
      return ""

  static func test_force_roll_no_holder_fails() -> String:
      var e = _make_engine()
      e.phase = "END_GAME"
      var res = e.admin_override("force_roll", {})
      if res.get("ok", false): return "should fail with no decision holder"
      return ""

  static func test_force_pass_purchase() -> String:
      var e = _make_engine(["Ada", "Bo"])
      # put player 0 in PURCHASE_WAIT on tile 1 (unowned)
      e.phase = "PURCHASE_WAIT"
      e._pending = {"tile": 1}
      var res = e.admin_override("force_pass", {})
      if not res.get("ok", false): return "force_pass should be ok: %s" % str(res)
      # minimal_action.pick on PURCHASE_WAIT -> "pass". With auctions on, that
      # either starts an auction (phase AUCTION) or, if auctions off, passes & ends turn.
      if e.phase != "AUCTION" and e.phase != "TURN_START":
          return "force_pass should leave AUCTION or TURN_START, got %s" % e.phase
      return ""

  static func test_force_pass_response() -> String:
      var e = _make_engine(["Ada", "Bo"])
      e._pending_trade = {"proposer": 0, "recipient": 1, "give_tiles": [], "give_cash": 0, "want_tiles": [], "want_cash": 0}
      var res = e.admin_override("force_pass", {})
      if not res.get("ok", false): return "force_pass on trade recipient should be ok: %s" % str(res)
      if e._pending_trade.size() != 0: return "trade should be cleared/declined"
      return ""

  static func test_rollback_decision_clears_pending() -> String:
      var e = _make_engine()
      e.phase = "PURCHASE_WAIT"
      e._pending = {"tile": 1}
      e._pending_trade = {"proposer": 0, "recipient": 1, "give_tiles": [], "give_cash": 0, "want_tiles": [], "want_cash": 0}
      var res = e.admin_override("rollback_decision", {})
      if not res.get("ok", false): return "rollback should be ok: %s" % str(res)
      if e._pending.size() != 0: return "pending should be cleared"
      if e._pending_trade.size() != 0: return "pending trade should be cleared"
      if e.phase != "PURCHASE_WAIT": return "phase unchanged expected"
      return ""
  ```

- [ ] **Step 2: Run and confirm the new cases fail** (methods
  `force_roll`/`force_pass`/`rollback_decision` not yet in the match, plus a
  missing `_decision_holder` helper is not in engine yet — add the admin
  `force_*` handlers that use a new engine helper below).
  Expected: FAILS for the new tests.

- [ ] **Step 3: Implement in `engine.gd`.** Add these branches to
  `admin_override` and two helpers. The current decision holder is computed by
  `legal_actions` (already engine-side), so no seat_manager dependency.

  ```gdscript
          "force_roll":
              if _admin_decision_holder() == -1:
                  return _admin_fail("no active decision")
              return _admin_submit_for_holder("roll", {}, "force_roll")
          "force_pass":
              var h: int = _admin_decision_holder()
              if h == -1:
                  return _admin_fail("no active decision")
              var ma = load("res://seats/minimal_action.gd").pick(self, h)
              if ma.is_empty():
                  return _admin_fail("no passive action for holder")
              return _admin_submit_for_holder(ma.get("action"), ma.get("params", {}), "force_pass")
          "rollback_decision":
              _pending = {}
              _pending_trade = {}
              return _admin_ok(op, params)
  ```

  ```gdscript
  func _admin_decision_holder() -> int:
      for pid in players.size():
          if not legal_actions(pid).is_empty():
              return pid
      return -1

  func _admin_submit_for_holder(action: String, params: Dictionary, tag: String) -> Dictionary:
      var h: int = _admin_decision_holder()
      if h == -1:
          return _admin_fail("no active decision")
      var res: Dictionary = submit_intent(h, action, params)
      if res.get("ok", false):
          log.append("admin_override", {"op": tag, "action": action, "params": params})
          return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
      return res
  ```

  (Note: `_admin_submit_for_holder` runs the holder's legal intent through the
  engine — the "unblocking" path. `rollback_decision` is the conservative,
  documented version: clear the current pending decision to let the holder
  re-decide; it does NOT rewind arbitrary history.)

- [ ] **Step 4: Re-run the full suite.** Expected: new cases PASS, existing 124
  stay green. Count = 124 + 5 = **129**.

- [ ] **Step 5: Commit**:
  `git add game/core/engine.gd game/tests/admin_test.gd`
  `git commit -m "feat: engine.admin_override unblocking ops (force_roll, force_pass, rollback_decision) + tests"`

---

## Task 3 — Engine: snapshot export/import (full state round-trip)

**File(s):** modify `game/core/engine.gd`; create `game/core/snapshot.gd`;
create `game/tests/snapshot_test.gd`. **Registered in `run.gd`.**

- [ ] **Step 1: Add failing tests** (round-trip equality + a live-state restore
  determinism check). `to_snapshot`/`from_snapshot`/`Snapshot.save/load` don't
  exist yet → load fails.

  ```gdscript
  # game/tests/snapshot_test.gd
  extends RefCounted

  static func test_list() -> Array[String]:
      return [
          "test_roundtrip_setup", "test_roundtrip_purchase_pending",
          "test_roundtrip_auction", "test_roundtrip_trade_pending",
          "test_roundtrip_post_bankruptcy", "test_restore_deterministic_roll",
          "test_snapshot_file_save_load",
      ]

  static func _make_engine(names: Array = ["Ada", "Bo", "Cyd"]):
      var E = load("res://core/engine.gd")
      var S = load("res://core/game_settings.gd")
      var s = S.new()
      s.rng_seed = 424242
      var e = E.new()
      e.setup(s, names)
      return e

  static func _assert_same(d1: Dictionary, d2: Dictionary) -> String:
      if d1 != d2:
          return "snapshots differ:\n%s\nvs\n%s" % [str(d1), str(d2)]
      return ""

  static func test_roundtrip_setup() -> String:
      var e = _make_engine()
      var snap: Dictionary = e.to_snapshot()
      var e2 = e.from_snapshot(snap)
      return _assert_same(snap, e2.to_snapshot())

  static func test_roundtrip_purchase_pending() -> String:
      var e = _make_engine()
      # craft a live mid-turn state: PURCHASE_WAIT on tile 1 after a forced roll
      e.admin_override("teleport", {"pid": 0, "tile": 0})
      e.admin_override("force_dice", {"d1": 1, "d2": 0})   # sum 1 -> lands tile 1 unowned
      e.submit_intent(0, "roll", {})
      if e.phase != "PURCHASE_WAIT": return "expected PURCHASE_WAIT, got %s" % e.phase
      var snap: Dictionary = e.to_snapshot()
      var e2 = e.from_snapshot(snap)
      return _assert_same(snap, e2.to_snapshot())

  static func test_roundtrip_auction() -> String:
      var e = _make_engine()
      # land on tile 1, pass -> auction (auctions_on_refusal default true)
      e.admin_override("teleport", {"pid": 0, "tile": 0})
      e.admin_override("force_dice", {"d1": 1, "d2": 0})
      e.submit_intent(0, "roll", {})
      e.submit_intent(0, "pass", {})
      if e.phase != "AUCTION": return "expected AUCTION, got %s" % e.phase
      var snap: Dictionary = e.to_snapshot()
      var e2 = e.from_snapshot(snap)
      return _assert_same(snap, e2.to_snapshot())

  static func test_roundtrip_trade_pending() -> String:
      var e = _make_engine()
      e.admin_override("grant_property", {"pid": 0, "tile": 6})
      var tr = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [6], "give_cash": 0, "want_tiles": [], "want_cash": 0})
      if not tr.get("ok", false): return "propose_trade failed: %s" % str(tr)
      var snap: Dictionary = e.to_snapshot()
      var e2 = e.from_snapshot(snap)
      return _assert_same(snap, e2.to_snapshot())

  static func test_roundtrip_post_bankruptcy() -> String:
      var e = _make_engine(["Ada", "Bo"])
      # Bo owns both brown + heavy houses; Ada lands and can't pay -> bankrupt
      e.admin_override("grant_property", {"pid": 1, "tile": 1})
      e.admin_override("grant_property", {"pid": 1, "tile": 3})
      e.admin_override("set_houses", {"tile": 1, "count": 5})
      e.admin_override("set_balance", {"pid": 0, "amount": 50})
      e.admin_override("teleport", {"pid": 0, "tile": 0})
      e.admin_override("force_dice", {"d1": 1, "d2": 0})   # sum 1 -> tile 1, rent 250 > 50
      e.submit_intent(0, "roll", {})
      if e.phase != "END_GAME": return "expected END_GAME, got %s" % e.phase
      var snap: Dictionary = e.to_snapshot()
      var e2 = e.from_snapshot(snap)
      return _assert_same(snap, e2.to_snapshot())

  static func test_restore_deterministic_roll() -> String:
      var e = _make_engine()
      e.admin_override("teleport", {"pid": 0, "tile": 1})
      var snap: Dictionary = e.to_snapshot()
      var e2 = e.from_snapshot(snap)
      # Both engines share the same rng re-seed (settings.rng_seed 424242),
      # so the same next roll draws equal values.
      var r1 = e._next_roll()
      var r2 = e2._next_roll()
      if r1.get("sum", 0) != r2.get("sum", 0) or r1.get("d1", 0) != r2.get("d1", 0):
          return "restored rng diverged: %s vs %s" % [str(r1), str(r2)]
      return ""

  static func test_snapshot_file_save_load() -> String:
      var e = _make_engine()
      e.admin_override("set_balance", {"pid": 1, "amount": 999})
      var SnapShot = load("res://core/snapshot.gd")
      var path: String = "user://test_snapshot.json"
      if not SnapShot.save(path, e):
          return "save failed"
      var e2 = SnapShot.load(path)
      if e2 == null:
          return "load failed -> null"
      if e2.player(1).money != 999:
          return "loaded balance want 999 got %d" % e2.player(1).money
      return ""
  ```

- [ ] **Step 2: Run and confirm failure** (to_snapshot/from_snapshot/snapshot.gd
  missing). Register `snapshot_test.gd` in `run.gd` in the same step.
  Expected: FAILS.

- [ ] **Step 3: Implement in `engine.gd`:**

  ```gdscript
  # --- Phase 4: SNAPSHOT (export/import full engine state, spec §4.C) ---
  ## Serialize the entire authoritative state to plain JSON-able dictionaries.
  ## Players, phase, pending, houses, mortgaged, decks (remaining order),
  ## RNG seed, and the event log — enough to restore "this exact state".
  func to_snapshot() -> Dictionary:
      var players_d: Array = []
      for p in players:
          players_d.append({
              "name": p.name, "token_id": p.token_id,
              "money": p.money, "position": p.position,
              "in_jail": p.in_jail, "jail_turns": p.jail_turns,
              "bankrupt": p.bankrupt,
              "get_out_of_jail_cards": p.get_out_of_jail_cards,
              "tiles": p.owned_tiles(),
          })
      var decks_d: Dictionary = {}
      for kind in decks:
          decks_d[kind] = decks[kind].cards(kind)
      var names: Array = []
      for p in players:
          names.append(p.name)
      return {
          "settings": settings.to_data(),
          "names": names,
          "players": players_d,
          "phase": phase,
          "turn_player": turn_player,
          "consecutive_doubles": consecutive_doubles,
          "last_roll": _last_roll,
          "last_doubles": _last_doubles,
          "no_extra_turn": _no_extra_turn,
          "card_depth": _card_depth,
          "pending": _pending,
          "pending_trade": _pending_trade,
          "houses": _houses,
          "mortgaged": _mortgaged,
          "decks": decks_d,
          "log": log.entries(),
      }

  ## Rebuild a fresh authoritative engine from a snapshot. Uses the engine's
  ## standard setup (board/cards/settings) then overwrites every live member.
  func from_snapshot(d: Dictionary):
      var E = load("res://core/engine.gd")
      var e = E.new()
      var S = load("res://core/game_settings.gd")
      var s = S.new()
      s.from_data(d.get("settings", {}))
      var names: Array = d.get("names", [])
      e.setup(s, names)
      e._restore_from_snapshot(d)
      return e

  func _restore_from_snapshot(d: Dictionary) -> void:
      phase = d.get("phase", PHASE_TURN_START)
      turn_player = int(d.get("turn_player", 0))
      consecutive_doubles = int(d.get("consecutive_doubles", 0))
      _last_roll = d.get("last_roll", {})
      _last_doubles = bool(d.get("last_doubles", false))
      _no_extra_turn = bool(d.get("no_extra_turn", false))
      _card_depth = int(d.get("card_depth", 0))
      _pending = d.get("pending", {})
      _pending_trade = d.get("pending_trade", {})
      _houses = d.get("houses", {})
      _mortgaged = (d.get("mortgaged", []) as Array).duplicate()
      var pdata: Array = d.get("players", [])
      for i in pdata.size():
          if i >= players.size(): break
          var pd: Dictionary = pdata[i]
          var pp = players[i]
          pp.name = pd.get("name", pp.name)
          pp.money = int(pd.get("money", pp.money))
          pp.position = int(pd.get("position", pp.position))
          pp.in_jail = bool(pd.get("in_jail", false))
          pp.jail_turns = int(pd.get("jail_turns", 0))
          pp.bankrupt = bool(pd.get("bankrupt", false))
          pp.get_out_of_jail_cards = int(pd.get("get_out_of_jail_cards", 0))
          pp._owned = (pd.get("tiles", []) as Array).duplicate()
      var decks_d: Dictionary = d.get("decks", {})
      for kind in decks_d:
          if decks.has(kind):
              decks[kind]._decks[kind] = (decks_d[kind] as Array).duplicate()
      if settings.rng_seed != 0:
          rng.seed_rng(settings.rng_seed)
      log.clear()
      var entries: Array = d.get("log", [])
      for entry in entries:
          log._entries.append(entry as Dictionary)
  ```

  **Create `game/core/snapshot.gd`** as the thin JSON file wrapper:

  ```gdscript
  extends RefCounted
  ## Thin file-I/O wrapper over engine.to_snapshot()/from_snapshot(). The
  ## snapshot logic itself lives in engine.gd; this only persists as JSON.

  static func save(path: String, engine) -> bool:
      var f = FileAccess.open(path, FileAccess.WRITE)
      if f == null:
          return false
      f.store_string(JSON.stringify(engine.to_snapshot(), "\t"))
      f.close()
      return true

  static func load(path: String):
      var f = FileAccess.open(path, FileAccess.READ)
      if f == null:
          return null
      var text: String = f.get_as_text()
      f.close()
      var d: Dictionary = JSON.parse_string(text)
      if d.is_empty():
          return null
      var E = load("res://core/engine.gd")
      return E.from_snapshot(d)
  ```

- [ ] **Step 4: Re-run the full suite.** Expected: new cases PASS, existing 129
  stay green. Count = 129 + 7 = **136**.

- [ ] **Step 5: Commit**:
  `git add game/core/engine.gd game/core/snapshot.gd game/tests/snapshot_test.gd game/tests/run.gd`
  `git commit -m "feat: engine snapshot export/import (full state round-trip) + snapshot.gd + tests"`

---

## Task 4 — Admin controller (pure) + diagnostics

**File(s):** create `game/admin/admin_controller.gd`; create
`game/tests/admin_controller_test.gd` (or extend `admin_test.gd` — use a new
`admin_controller_test.gd` for clarity). Register in `run.gd`.

- [ ] **Step 1: Write failing tests:** `reset_seat_away`, `dump_state` shape,
  `list_events` unfiltered and filtered, and that `override` forwards to the
  engine (set_balance round-trips).

  ```gdscript
  # game/tests/admin_controller_test.gd
  extends RefCounted

  static func test_list() -> Array[String]:
      return [
          "test_override_forwards_set_balance",
          "test_reset_seat_away",
          "test_reset_seat_away_no_seat_fails",
          "test_dump_state_shape",
          "test_list_events_unfiltered",
          "test_list_events_filtered",
      ]

  static func _make():
      var E = load("res://core/engine.gd")
      var S = load("res://core/game_settings.gd")
      var e = E.new()
      e.setup(S.new(), ["Ada", "Bo"])
      return e

  static func _make_seats():
      var Seat = load("res://seats/seat.gd")
      return [Seat.new(0), Seat.new(1)]

  static func test_override_forwards_set_balance() -> String:
      var e = _make()
      var AC = load("res://admin/admin_controller.gd")
      var c = AC.new()
      c.setup(e, _make_seats())
      var res = c.override("set_balance", {"pid": 0, "amount": 600})
      if not res.get("ok", false): return "expected ok"
      if e.player(0).money != 600: return "want 600 got %d" % e.player(0).money
      return ""

  static func test_reset_seat_away() -> String:
      var e = _make()
      var seats = _make_seats()
      seats[0].away = true
      var AC = load("res://admin/admin_controller.gd")
      var c = AC.new()
      c.setup(e, seats)
      var res = c.reset_seat_away(0)
      if not res.get("ok", false): return "expected ok"
      if seats[0].away: return "seat 0 should be un-away"
      return ""

  static func test_reset_seat_away_no_seat_fails() -> String:
      var e = _make()
      var AC = load("res://admin/admin_controller.gd")
      var c = AC.new()
      c.setup(e, _make_seats())
      var res = c.reset_seat_away(7)
      if res.get("ok", false): return "should fail for unknown seat"
      return ""

  static func test_dump_state_shape() -> String:
      var e = _make()
      var AC = load("res://admin/admin_controller.gd")
      var c = AC.new()
      c.setup(e, [])
      var dump = c.dump_state()
      if not dump.has("phase") or not dump.has("turn_player"): return "dump missing top keys"
      if (dump.get("players", []) as Array).size() != 2: return "dump should list 2 players"
      var first = (dump["players"] as Array)[0]
      for k in ["pid", "name", "money", "position", "in_jail", "bankrupt", "tiles", "away"]:
          if not first.has(k): return "player entry missing key %s" % k
      return ""

  static func test_list_events_unfiltered() -> String:
      var e = _make()
      e.admin_override("teleport", {"pid": 1, "tile": 5})
      var AC = load("res://admin/admin_controller.gd")
      var c = AC.new()
      c.setup(e, [])
      var ev = c.list_events("")
      if (ev as Array).size() < 2: return "should list setup + admin_override events"
      return ""

  static func test_list_events_filtered() -> String:
      var e = _make()
      e.admin_override("teleport", {"pid": 1, "tile": 5})
      var AC = load("res://admin/admin_controller.gd")
      var c = AC.new()
      c.setup(e, [])
      var ev = c.list_events("admin_override")
      if (ev as Array).size() != 1: return "filter should return 1 admin_override"
      return ""
  ```

- [ ] **Step 2: Run and confirm failure** (controller missing).
  Expected: FAILS.

- [ ] **Step 3: Implement `admin_controller.gd`:**

  ```gdscript
  extends RefCounted
  ## Phase 4 admin policy layer (pure, headless-testable). Wraps
  ## engine.admin_override plus seat-level housekeeping. A future full panel or
  ## token-guarded remote panel is a thin consumer of this class.

  var engine
  var seats: Array = []

  func setup(eng, seat_list: Array = []) -> void:
      engine = eng
      seats = seat_list

  ## Forward an admin state-edit / unblocking intent to the authoritative engine.
  func override(op: String, params: Dictionary) -> Dictionary:
      return engine.admin_override(op, params)

  ## Seat flag (not engine state — lives on the Seat objects in the manager).
  func reset_seat_away(pid: int) -> Dictionary:
      for s in seats:
          if s.pid == pid:
              s.away = false
              return {"ok": true, "reason": ""}
      return {"ok": false, "reason": "no seat with pid %d" % pid}

  ## Flattened live state table for diagnostics (spec §4.C).
  func dump_state() -> Dictionary:
      var players_d: Array = []
      for i in engine.player_count():
          var p = engine.player(i)
          players_d.append({
              "pid": i,
              "name": p.name,
              "money": p.money,
              "position": p.position,
              "in_jail": p.in_jail,
              "bankrupt": p.bankrupt,
              "tiles": p.owned_tiles(),
              "away": _seat_away(i),
          })
      return {"phase": engine.phase, "turn_player": engine.turn_player, "players": players_d}

  ## Event list, optionally filtered by type. spec §4.C diagnostics.
  func list_events(type_filter: String = "") -> Array:
      var entries: Array = engine.log.entries()
      if type_filter == "":
          return entries
      var out: Array = []
      for entry in entries:
          if str(entry.get("type", "")) == type_filter:
              out.append(entry)
      return out

  func _seat_away(pid: int) -> bool:
      for s in seats:
          if s.pid == pid:
              return s.away
      return false
  ```

- [ ] **Step 4: Re-run.** Expected: new PASS, existing 136 stay green.
  Count = 136 + 6 = **142**.

- [ ] **Step 5: Commit**:
  `git add game/admin/admin_controller.gd game/tests/admin_controller_test.gd game/tests/run.gd`
  `git commit -m "feat: admin_controller (pure override + diagnostics + seat reset) + tests"`

---

## Task 5 — Tony scripted scenarios (test-ladder rung 3)

**File(s):** create `game/tests/tony_test.gd`; create `game/tools/tony.tscn` +
`game/tools/tony.gd`. Register `tony_test.gd` in `run.gd`.

This task is independent of tasks 1–4 (uses only engine + existing test hooks),
so it may be run **in parallel** with Task 4. Keep each scenario deterministic
with `_force_dice`/`_teleport`/`admin_override` (no RNG). Each asserts a named
ending invariant.

- [ ] **Step 1: Write `game/tests/tony_test.gd`:**

  ```gdscript
  # game/tests/tony_test.gd — test-ladder rung 3: scripted scenarios.
  extends RefCounted

  static func test_list() -> Array[String]:
      return [
          "scenario_auction_resolve",
          "scenario_bankruptcy_transfer",
          "scenario_trade_chain",
          "scenario_admin_unblock",
      ]

  static func _make_engine(names: Array = ["Ada", "Bo", "Cyd"]):
      var E = load("res://core/engine.gd")
      var S = load("res://core/game_settings.gd")
      var e = E.new()
      e.setup(S.new(), names)
      return e

  ## Land Ada (currently turn_player 0) on an unowned property so she gets a
  ## PURCHASE_WAIT choice. Forced roll sum 1 moves 0 -> 1 (tile 1, brown, cost 60).
  static func _land_on_unowned(e) -> void:
      e.admin_override("teleport", {"pid": 0, "tile": 0})
      e.admin_override("force_dice", {"d1": 1, "d2": 0})

  static func scenario_auction_resolve() -> String:
      var e = _make_engine(["Ada", "Bo"])   # 2 players gives a clean 2-way rotation
      e.phase = "TURN_START"
      e.turn_player = 0
      e.admin_override("teleport", {"pid": 0, "tile": 0})
      e.admin_override("force_dice", {"d1": 1, "d2": 0})
      var r = e.submit_intent(0, "roll", {})
      if not r.get("ok", false): return "roll failed: %s" % str(r)
      if e.phase != "PURCHASE_WAIT": return "want PURCHASE_WAIT got %s" % e.phase
      var p = e.submit_intent(0, "pass", {})   # starts auction (auctions_on_refusal default on)
      if e.phase != "AUCTION": return "want AUCTION got %s" % e.phase
      # 2-player: active=[0,1], bidder starts at turn_player 0 (Ada).
      if e._pending.get("bidder", -1) != 0: return "Ada should open the bid"
      var b1 = e.submit_intent(0, "bid", {"amount": 61})
      if not b1.get("ok", false): return "Ada bid failed: %s" % str(b1)
      # after Ada's bid bidder advances to the next active: Bo (1)
      if e._pending.get("bidder", -1) != 1: return "expected Bo (1) to bid next"
      var b2 = e.submit_intent(1, "bid", {"amount": 62})
      if not b2.get("ok", false): return "Bo bid failed: %s" % str(b2)
      # after Bo's bid bidder wraps back to Ada (0)
      if e._pending.get("bidder", -1) != 0: return "expected Ada (0) to bid next"
      e.submit_intent(0, "pass", {})
      # only Bo (1) left with a high -> Bo wins at 62
      if not e.players[1].owns(1): return "Bo should own tile 1 after auction"
      if e.players[1].money != 1500 - 62: return "Bo money want %d got %d" % [1500 - 62, e.players[1].money]
      if e.players[0].money != 1500: return "passing bidder should not be charged"
      if e._pending.size() != 0: return "auction pending should be cleared after win"
      return ""

  static func scenario_bankruptcy_transfer() -> String:
      var e = _make_engine(["Ada", "Bo"])
      # Bo owns both brown tiles with max houses; Ada is broke and lands on one.
      e.admin_override("grant_property", {"pid": 1, "tile": 1})
      e.admin_override("grant_property", {"pid": 1, "tile": 3})
      e.admin_override("set_houses", {"tile": 1, "count": 5})
      e.admin_override("set_balance", {"pid": 0, "amount": 50})
      e.phase = "TURN_START"
      e.turn_player = 0
      e.admin_override("teleport", {"pid": 0, "tile": 0})
      e.admin_override("force_dice", {"d1": 1, "d2": 0})   # lands tile 1 (rent 250 > 50)
      var r = e.submit_intent(0, "roll", {})
      if not r.get("ok", false): return "roll failed: %s" % str(r)
      if e.phase != "END_GAME": return "want END_GAME got %s" % e.phase
      if e.player_count() != 1: return "Ada should be removed; want 1 player got %d" % e.player_count()
      var winner_name: String = e.player(0).name
      if winner_name != "Bo": return "Bo should be winner, got %s" % winner_name
      return ""

  static func scenario_trade_chain() -> String:
      var e = _make_engine()
      # Ada (0) proposes to Bo (1): give tile 6 for tile 11 + 50 cash. Bo accepts.
      e.admin_override("grant_property", {"pid": 0, "tile": 6})
      e.admin_override("grant_property", {"pid": 1, "tile": 11})
      var money_before_a: int = e.player(0).money
      var money_before_b: int = e.player(1).money
      var pr = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [6], "give_cash": 0, "want_tiles": [11], "want_cash": 50})
      if not pr.get("ok", false): return "propose failed: %s" % str(pr)
      # recipient (Bo) responds accept (cross-player path bypasses turn guard)
      var rs = e.submit_intent(1, "respond_trade", {"accept": true})
      if not rs.get("ok", false): return "accept failed: %s" % str(rs)
      if e.player(0).owns(6) or not e.player(1).owns(6): return "tile 6 should move to Bo"
      if e.player(1).owns(11) or not e.player(0).owns(11): return "tile 11 should move to Ada"
      if e.player(0).money != money_before_a + 50: return "Ada should gain 50 cash"
      if e.player(1).money != money_before_b - 50: return "Bo should lose 50 cash"
      if e._pending_trade.size() != 0: return "pending trade should be cleared"
      # chain onward: Ada (turn) now proposes back to Bo
      var pr2 = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [11], "give_cash": 0, "want_tiles": [6], "want_cash": 0})
      if not pr2.get("ok", false): return "second propose failed: %s" % str(pr2)
      var rs2 = e.submit_intent(1, "respond_trade", {"accept": true})
      if not rs2.get("ok", false): return "second accept failed: %s" % str(rs2)
      if not e.player(0).owns(6) or not e.player(1).owns(11): return "chain should swap back"
      return ""

  static func scenario_admin_unblock() -> String:
      var e = _make_engine(["Ada", "Bo"])
      # A LOCAL seat (Ada) is the decision holder at TURN_START. Admin forces a roll.
      e.phase = "TURN_START"
      e.turn_player = 0
      var phase_before: String = e.phase
      var res = e.admin_override("force_roll", {})
      if not res.get("ok", false): return "admin force_roll failed: %s" % str(res)
      if e.phase == phase_before: return "phase should have advanced after force_roll"
      var logged := false
      for entry in e.log.entries():
          if entry.get("type", "") == "admin_override":
              logged = true
      if not logged: return "expected admin_override event in log"
      return ""
  ```

- [ ] **Step 2: Register `tony_test.gd` in `run.gd` and run.** Expected: all four
  PASS; existing 142 stay green. Count = 142 + 4 = **146**.

- [ ] **Step 3: Create the `tools/tony.tscn` + `tony.gd` runtime demo** (reuses
  the module so the "rung 3" is also commandable as a scene, mirroring the soak
  pattern). `tony.gd`:

  ```gdscript
  extends Node
  ## Test-ladder rung 3 commandable runner. Runs the same four scripted
  ## scenarios as tony_test.gd and exits 0/1 so it can be staged before a WebGL
  ## run.
  ##   godot --headless --path game res://tools/tony.tscn
  func _ready() -> void:
      print("=== tony: scripted scenarios ===\n")
      var mod = load("res://tests/tony_test.gd")
      var names: Array = mod.call("test_list")
      var failed := 0
      for name in names:
          var err: Variant = mod.call(name)
          if err != null and err != "":
              failed += 1
              print("FAIL  %s :: %s" % [name, err])
          else:
              print("PASS  %s" % name)
      print("=== tony: %s (%d/%d passed) ===" % ["FAILED" if failed > 0 else "PASSED", names.size() - failed, names.size()])
      get_tree().quit(0 if failed == 0 else 1)
  ```

  `tony.tscn`:
  ```
  [gd_scene load_steps=2 format=3]

  [ext_resource type="Script" path="res://tools/tony.gd" id="1_tony"]

  [node name="Tony" type="Node"]
  script = ExtResource("1_tony")
  ```

- [ ] **Step 4: Run the tony scene headless and confirm exit 0**:
  `godot --headless --path game res://tools/tony.tscn`
  Expected: PASS x4, exit 0.

- [ ] **Step 5: Commit**:
  `git add game/tests/tony_test.gd game/tests/run.gd game/tools/tony.tscn game/tools/tony.gd`
  `git commit -m "feat: Tony scripted scenarios (auction, bankruptcy, trade chain, admin unblock) + tony runner"`

---

## Task 6 — F12 admin panel (thin Godot Control) + main scene wiring

**File(s):** modify `game/main.tscn` + `game/main.gd`; create
`game/admin/admin_panel.gd`. **This task is GUI/non-headless** — it is verified
by a runtime export, NOT by the headless suite (which never loads `main.tscn`).
It depends on the controller (Task 4), so run after Task 4.

- [ ] **Step 1: (design is already approved — skip spec; implement directly.)**
  Replace `main.gd` so it sets up settings + seats + engine + seat_manager,
  wires an `admin_controller`, instantiates `admin_panel`, and toggles it on F12.

  `game/main.gd`:
  ```gdscript
  extends Node
  ## Phase 4 entry point. Hosts the seat manager, a default game, and a hidden
  ## (F12) admin panel wired to admin_controller. All admin edits route through
  ## engine.admin_override (fail-closed, same event log).

  const EngineScript := preload("res://core/engine.gd")
  const Settings := preload("res://core/game_settings.gd")
  const SeatConfig := preload("res://seats/seat_config.gd")
  const SeatManager := preload("res://seats/seat_manager.gd")
  const AdminController := preload("res://admin/admin_controller.gd")
  const AdminPanel := preload("res://admin/admin_panel.gd")

  var _engine
  var _manager
  var _controller
  var _panel

  func _ready() -> void:
      var s = Settings.new()
      var seats: Array = SeatConfig.from_settings(s)
      _engine = EngineScript.new()
      _engine.setup(s, _names(seats))
      _manager = SeatManager.new()
      _manager.name = "SeatManager"
      add_child(_manager)
      _manager.setup(_engine, seats)
      _controller = AdminController.new()
      _controller.setup(_engine, seats)
      _panel = AdminPanel.new()
      _panel.name = "AdminPanel"
      add_child(_panel)
      _panel.setup(_controller)
      _panel.visible = false
      print("Neuro Property Trade — ready. F12 toggles admin panel.")

  func _names(seats: Array) -> Array:
      var out := []
      for s in seats:
          out.append(s.name)
      return out

  func _unhandled_key_input(event: InputEvent) -> void:
      if event is InputEventKey and event.pressed and not event.echo:
          if event.keycode == KEY_F12:
              if _panel != null:
                  _panel.visible = not _panel.visible
  ```

  `game/main.tscn` (keep the script ext_resource; the Node now runs the above):
  ```
  [gd_scene load_steps=2 format=3 uid="uid://neurotrade_main"]

  [ext_resource type="Script" path="res://main.gd" id="1_main"]

  [node name="Main" type="Node"]
  script = ExtResource("1_main")
  ```

- [ ] **Step 2: Implement `admin_panel.gd`** — a `PanelContainer` built in code
  (avoids hand-authoring a large .tscn). Controls: an `OptionButton` of ops, a
  few `LineEdit` param fields, an Apply button, a live `RichTextLabel` for
  `dump_state`, and a scrollable `RichTextLabel` for the filtered event log.

  ```gdscript
  extends PanelContainer
  ## Thin host-local admin panel (spec §4). Dumb UI over admin_controller.
  ## F12 toggle is handled in main.gd. No engine logic here.

  var _controller
  var _op: OptionButton
  var _param_pid: SpinBox
  var _param_tile: SpinBox
  var _param_amount: SpinBox
  var _param_flag: OptionButton   # on/off for mortgage flag
  var _param_d1: SpinBox
  var _param_d2: SpinBox
  var _apply: Button
  var _refresh: Button
  var _state: RichTextLabel
  var _log: RichTextLabel
  var _refresh_timer: float = 0.0

  const OPS := ["set_balance", "teleport", "force_dice", "grant_property",
                "revoke_property", "set_houses", "set_mortgage", "set_go_jail",
                "force_roll", "force_pass", "rollback_decision"]

  func setup(controller) -> void:
      _controller = controller
      _build()
      _refresh_all()

  func _build() -> void:
      custom_minimum_size = Vector2(520, 420)
      var v = VBoxContainer.new()
      add_child(v)
      var header = Label.new()
      header.text = "Admin Console (host-local)"
      v.add_child(header)

      var row = HBoxContainer.new()
      v.add_child(row)
      _op = OptionButton.new()
      for op in OPS:
          _op.add_item(op)
      _op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      row.add_child(_op)

      var params = GridContainer.new()
      params.columns = 4
      v.add_child(params)
      _param_pid = _spin(0, "pid", params)
      _param_tile = _spin(0, "tile", params)
      _param_amount = _spin(0, "amount/count", params)
      _param_d1 = _spin(0, "d1", params)
      _param_d2 = _spin(0, "d2", params)
      _param_flag = OptionButton.new()
      _param_flag.add_item("on"); _param_flag.add_item("off")
      _param_flag.add_item("pid")
      _param_flag.add_item("tile")
      var flagrow = HBoxContainer.new()
      var flaglabel = Label.new()
      flaglabel.text = "on:"
      flagrow.add_child(flaglabel)
      flagrow.add_child(_param_flag)
      params.add_child(flagrow)

      var buttons = HBoxContainer.new()
      v.add_child(buttons)
      _apply = Button.new(); _apply.text = "Apply"
      _apply.pressed.connect(_apply_op)
      buttons.add_child(_apply)
      _refresh = Button.new(); _refresh.text = "Reset away seat pid"
      buttons.add_child(_refresh)

      var state_label = Label.new()
      state_label.text = "Live state:"
      v.add_child(state_label)
      _state = RichTextLabel.new()
      _state.bbcode_enabled = true
      _state.bbcode_text = ""
      _state.custom_minimum_size.y = 120
      v.add_child(_state)

      var log_label = Label.new()
      log_label.text = "Event log (last 30):"
      v.add_child(log_label)
      _log = RichTextLabel.new()
      _log.bbcode_enabled = true
      _log.custom_minimum_size.y = 120
      v.add_child(_log)

  func _spin(minv: int, label_text: String, parent: Control) -> SpinBox:
      var sb = SpinBox.new()
      sb.min_value = minv
      sb.max_value = 999
      var wrap = HBoxContainer.new()
      var lab = Label.new()
      lab.text = label_text + ":"
      var v = sb.value
      wrap.add_child(lab); wrap.add_child(sb)
      parent.add_child(wrap)
      sb.editable = true
      return sb

  func _apply_op() -> void:
      if _controller == null: return
      var op: String = _op.get_item_text(_op.selected)
      var params := {}
      match op:
          "set_balance", "grant_property", "revoke_property", "set_go_jail":
              params["pid"] = int(_param_pid.value)
          "teleport", "set_houses", "set_mortgage":
              params["tile"] = int(_param_tile.value)
          "set_balance":
              params["amount"] = int(_param_amount.value)
          "set_houses":
              params["count"] = int(_param_amount.value)
          "set_mortgage":
              params["on"] = (_param_flag.selected == 0)
          "force_dice":
              params["d1"] = int(_param_d1.value)
              params["d2"] = int(_param_d2.value)
      if op == "force_roll" or op == "force_pass" or op == "rollback_decision":
          params = {}
      # pid-bearing ops also need pid/tile where they have one param each:
      if op == "grant_property" or op == "revoke_property" or op == "set_go_jail":
          params["pid"] = int(_param_pid.value)
      var res: Dictionary = _controller.override(op, params)
      if op == "grant_property" or op == "revoke_property" or op == "set_mortgage":
          params["tile"] = int(_param_tile.value)
      _refresh_all()
      print("[admin] %s -> %s" % [op, str(res)])

  func _refresh_all() -> void:
      if _controller == null: return
      var dump = _controller.dump_state()
      _state.bbcode_text = "[code]%s[/code]" % _dump_to_text(dump)
      var ev = _controller.list_events("")
      var tail: Array = (ev as Array).slice(max(0, ev.size() - 30))
      _log.bbcode_text = "[code]%s[/code]" % _events_to_text(tail)

  func _dump_to_text(d: Dictionary) -> String:
      var lines: Array = ["phase %s | turn %s" % [d.get("phase",""), str(d.get("turn_player",""))]]
      for p in (d.get("players", []) as Array):
          lines.append("p%d %-8s $%-6d @%-2d jail:%s away:%s tiles:%s" % [
              int(p.get("pid",0)), str(p.get("name","")), int(p.get("money",0)),
              int(p.get("position",0)), str(p.get("in_jail",false)),
              str(p.get("away",false)), str(p.get("tiles",[]))])
      return "\n".join(PackedStringArray(lines))

  func _events_to_text(ev: Array) -> String:
      var lines: Array = []
      for entry in ev:
          lines.append("%d:%s %s" % [int(entry.get("index",0)), str(entry.get("type","")), str(entry.get("data",{}))])
      return "\n".join(PackedStringArray(lines))

  func _process(delta: float) -> void:
      _refresh_timer += delta
      if _refresh_timer >= 1.0 and visible:
          _refresh_timer = 0.0
          _refresh_all()
  ```

  **Godot API note:** `Color` etc. are not used here. `PackedStringArray` join
  with an Array of String works in Godot 4 (`"\n".join(arr)`). Avoid `:=` from
  Variant-returning funcs (project gotcha). Keep the panel free of engine
  internals (it only calls `controller`).

- [ ] **Step 3: Verify the F12 panel runs.** Use the export (Task 7) plus a
  short `godot --path game --export-debug "Web"` smoke; a headless run of
  `main.tscn` is NOT possible (GUI). If a local X display is available
  (`DISPLAY=:0`, llvmpipe), run `timeout 12 godot --path game` and check the
  console prints the ready banner and that no script parse errors appear.
  Expected: no `SCRIPT ERROR` in the console.

- [ ] **Step 4: Commit** (no headless count delta — GUI-only):
  `git add game/main.tscn game/main.gd game/admin/admin_panel.gd`
  `git commit -m "feat: F12 admin panel + main scene wiring (over admin_controller)"`

---

## Task 7 — WebGL export build (test-ladder rung 4 artifact)

**File(s):** create `export_presets.cfg`; create a `build/` output dir.
Depends on engine work being complete (it exports the whole game). Run last.

- [ ] **Step 1: Write `export_presets.cfg`** with a Web (HTML5) preset. The
  project already sets `renderer/rendering_method="gl_compatibility"` which is
  required for WebGL. Export path goes to `build/web/index.html`.

  ```
  [preset.0]

  name="Web"
  platform="Web"
  runnable=true
  advanced_options=false
  dedicated_server=false
  custom_features=""
  export_filter="all_resources"
  include_filter=""
  exclude_filter=""
  export_path="build/web/index.html"
  patches=PackedStringArray()
  encryption_include_filters=""
  encryption_exclude_filters=""
  seed=12345
  encryption_key=""

  [preset.0.options]

  custom_template/debug=""
  custom_template/release=""
  variant/extensions_support=false
  vram_texture_compression/for_desktop=true
  vram_texture_compression/for_mobile=false
  html/export_icon=true
  html/custom_html_shell=""
  html/head_include=""
  html/canvas_resize_policy=2
  html/focus_canvas_on_start=true
  html/experimental_virtual_keyboard=false
  progress_bar/loading_image=""
  progress_bar/color=Color(0, 0, 0, 1)
  progress_bar/background=Color(0, 0, 0, 1)
  ```
  (A `linux` native fallback preset is optional/left out — the plan's rung-4
  artifact is the WebGL build per plan.md.)

- [ ] **Step 2: Import + export headless.** The project must be imported first
  so `.godot/global_script_class_cache.cfg` exists (SDK addon types).
  `godot --headless --path game --import .`
  `godot --headless --path game --export-debug "Web" build/web/index.html`
  Expected: exit 0, no export errors.

- [ ] **Step 3: Verify the build artifact.** Check these exist and are non-empty:
  `build/web/index.html`, `build/web/index.wasm`, and `build/web/index.js`
  (Godot 4 names the wasm/js per the export path's basename `index`).
  `ls -la build/web/`
  Expected: index.html + index.wasm + index.js present.

- [ ] **Step 4: Commit the export preset** (the `build/` dir is a generated
  artifact — add `build/` to `.gitignore`; commit only `export_presets.cfg` and
  any `.gitignore` change):
  `git add export_presets.cfg .gitignore`
  `git commit -m "build: WebGL export preset + ignore generated build/ (rung 4 artifact smoke)"`

---

## Task 8 — Final integration & full suite

**File(s):** none new — verification + doc update.

- [ ] **Step 1: Run the FULL headless suite** and confirm the final count:
  `godot --headless --path game --script res://tests/run.gd`
  Expected: **146 tests green** (109 prior + 15 admin + 5 unblocking + 7
  snapshot + 6 controller + 4 tony). Exit 0.

- [ ] **Step 2: Run the tony runner scene** once more:
  `godot --headless --path game res://tools/tony.tscn` → exit 0.

- [ ] **Step 3: Re-export WebGL** to confirm the full integrated tree builds:
  `godot --headless --path game --import .`
  `godot --headless --path game --export-debug "Web" build/web/index.html`
  → exit 0, artifact present.

- [ ] **Step 4: Update `docs/plan.md` Phase 4** status: mark the admin-console /
  admin_override / snapshot / diagnostics / Tony / WebGL items done, note the
  deferred visual layer + deck-card/tweak-cost/redo-turn ops + remote panel.
  `git add docs/plan.md`
  `git commit -m "docs: Phase 4 admin console, Tony ladder, WebGL — complete"`

- [ ] **Step 5: Merge to main.** Squash-fast-forward as in prior phases:
  `git checkout main && git merge --ff-only phase4/admin-console && git push`

---

## Self-review checklist

- [ ] Every test snippet compiles as plain GDScript (no `:=` from untyped funcs;
      no untyped-var type inference on dynamic `load()` handles).
- [ ] `engine.admin_override` and `from_snapshot` avoid `class_name` globals
      (loaded by path) so headless `--script` works.
- [ ] Admin ops append to `log` via `_admin_ok`; `force_*` append via
      `_admin_submit_for_holder` → log preserves the admin_override event.
- [ ] Snapshot round-trip is `to_snapshot() == from_snapshot(s).to_snapshot()`.
- [ ] Tony scenarios are deterministic (forced dice/teleports/admin_override; no
      RNG), matching test-hook conventions.
- [ ] `run.gd` registers all 4 new modules (admin_test, snapshot_test,
      admin_controller_test, tony_test); count grows 109 → 146.
- [ ] WebGL uses `gl_compatibility` (already set) so the export succeeds.
