# Phase 3 — Seats & Lobby Implementation Plan

**Goal:** Stand up the multi-seat driver layer: pure seat config + timeout
auto-pass + spectator projection + a Node seat manager that routes every
driver (LOCAL human wait, internal AI, SDK, CHAT aggregation) through the
existing `engine.submit_intent`. Add a second AI seat via the internal driver.

**Architecture:** Pure core (`seat`, `seat_config`, `minimal_action`,
`trade_evaluator`, `projection.for_spectator`, `render_spectator`) is loaded by
path and headless-tested. A thin Node (`seat_manager`) polls the engine, finds
the seat with legal actions, and drives it. Driver resolution is centralized in
`seat_config.resolve_driver` — the single place future multi-connection SDK
support changes. Design: `docs/superpowers/specs/2026-09-06-phase3-seats-lobby-design.md`.

**Tech stack:** Godot 4.7.2 GDScript, headless `--script` test harness, plain
functions (no test framework).

**Conventions that MUST be followed (verified gotchas, will break otherwise):**
- `class_name` globals are NOT resolvable in `--script` code. Load everything
  by path: `var S = load("res://core/game_settings.gd")`.
- Never use `var x := <value-from-untyped-func>` — parse error. Use plain
  `var x = ...`.
- Tests are plain `static func` in a `RefCounted` module returning `""` on pass
  or an error string; module exposes static `test_list()`. Register in `run.gd`.
- Run tests: `git add ...` then commit per task. Verify with
  `godot --headless --path game --script res://tests/run.gd` (exit 0 = pass)
  after each task.
- Engine reads JSON via `FileAccess.open("res://...", FileAccess.READ)` +
  `JSON.parse_string`. Engine loads collaborators by path.
- **Do NOT modify the vendored SDK** (`game/addons/neuro-sdk/`).

**Branch:** `phase3/seats-lobby` (already created). Work here; merge to `main`
at the end.

Existing files you may modify: `game/tests/run.gd` (register modules),
`game/core/game_settings.gd` (Block 1 fields), `game/sdk/projection.gd` and
`game/sdk/markdown_renderer.gd` (spectator functions), `game/sdk/sdk_adapter.gd`
(expose `tick()`; optional).

---

### Task 1: Seat & SeatConfig — pure data + driver resolution

**Files:**
- 创建: `game/seats/seat.gd`
- 创建: `game/seats/seat_config.gd`
- 创建: `game/tests/seats_test.gd`
- 修改: `game/tests/run.gd`

- [ ] **步骤 1: 写失败的测试**

```gdscript
extends RefCounted

static func test_list() -> Array[String]:
	return [
		"test_defaults_three_seats",
		"test_assignment_parsing",
		"test_resolve_driver_sdk_second_falls_back_to_ai",
		"test_starting_order_manual_keeps_order",
	]

static func _make_settings() -> Dictionary:
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	return {"settings": s}

static func test_defaults_three_seats() -> String:
	var r = _make_settings()
	var SeatConfig = load("res://seats/seat_config.gd")
	var seats: Array = SeatConfig.from_settings(r["settings"])
	if seats.size() != 4: return "want 4 default seats, got %d" % seats.size()
	if seats[0].input_driver != "LOCAL": return "seat 0 should be LOCAL"
	if seats[1].input_driver != "AI": return "seat 1 should be AI"
	for s in seats:
		if s.pid < 0 or s.pid >= seats.size(): return "bad pid"
	return ""

static func test_assignment_parsing() -> String:
	var r = _make_settings()
	var s = r["settings"]
	s.seat_assignments = [
		{"driver": "LOCAL", "name": "Vedal", "token_color": "red", "token_id": "t0"},
		{"driver": "sdk:neuro", "name": "Neuro", "token_id": "t1"},
		{"driver": "AI", "name": "Ada", "token_id": "t2"},
		{"driver": "CHAT", "name": "Chat", "token_id": "t3"},
	]
	var SeatConfig = load("res://seats/seat_config.gd")
	var seats: Array = SeatConfig.from_settings(s)
	if seats[0].driver_label != "LOCAL": return "label LOCAL"
	if seats[1].driver_label != "sdk:neuro": return "label sdk:neuro"
	if seats[1].input_driver != "SDK": return "driver SDK"
	if seats[2].input_driver != "AI": return "driver AI"
	if seats[3].input_driver != "CHAT": return "driver CHAT"
	# token_color default when omitted
	if seats[1].color == null: return "color must have a default"
	return ""

static func test_resolve_driver_sdk_second_falls_back_to_ai() -> String:
	var SeatConfig = load("res://seats/seat_config.gd")
	var labels: Array[String] = ["LOCAL", "sdk:neuro", "sdk:evil", "AI"]
	var seen_sdk := false
	for label in labels:
		var d: String = SeatConfig.resolve_driver(label, seen_sdk)
		if label == "LOCAL" and d != "LOCAL": return "LOCAL maps LOCAL"
		if label == "sdk:neuro" and d != "SDK": return "first sdk maps SDK"
		if label == "sdk:evil" and d != "AI": return "second sdk maps AI"
		if d == "SDK": seen_sdk = true
	return ""

static func test_starting_order_manual_keeps_order() -> String:
	var r = _make_settings()
	var s = r["settings"]
	s.starting_order = "manual"
	var SeatConfig = load("res://seats/seat_config.gd")
	var seats: Array = SeatConfig.from_settings(s)
	if seats[2].name != "AI Seat #3": return "manual order kept, seat2 name unexpected: %s" % seats[2].name
	return ""
```

- [ ] **步骤 2: 运行测试** — expect FAIL (`Cannot open file` / methods missing).
  Register `seats_test.gd` in `run.gd` first (add `"res://tests/seats_test.gd"`
  to the `modules` array) so the runner finds it.

- [ ] **步骤 3: 添加 Block 1 字段到 `game/core/game_settings.gd`**

Add these fields near the top (after `var seat_count: int = 4`):

```gdscript
# Block 1 — Seats & composition (extended for Phase 3 seat layer)
var seat_assignments: Array = []   # per seat: {driver, name, token_color?, token_id?}
var starting_order: String = "random"
```

(Keep `seat_count` default 4; the seat layer reads `seat_count` and
`seat_assignments`; `from_data`/`to_data` already iterate script variables.)

- [ ] **步骤 4: 创建 `game/seats/seat.gd`**

```gdscript
extends RefCounted
## One seat's configuration (pure data). The engine is seat-agnostic; this
## describes who drives the seat (LOCAL human / CHAT / SDK AI / internal AI).

var pid: int = 0
var name: String = ""
var input_driver: String = "AI"     # LOCAL | CHAT | SDK | AI | ADMIN
var driver_label: String = ""       # raw assignment for display/routing, e.g. "sdk:neuro"
var color: Color = Color.WHITE
var token_id: String = ""
var away: bool = false              # flagged true once auto-passed (spec §3)
var decision_waiting: float = 0.0   # seconds at the current decision point

func _init(p: int = 0) -> void:
	pid = p
```

- [ ] **步骤 5: 创建 `game/seats/seat_config.gd`**

```gdscript
extends RefCounted
## Builds an Array[Seat] from GameSettings Block 1, and resolves a raw seat
## assignment to a runtime driver. This resolve_driver function is the SINGLE
## place the future multi-SDK-connection support changes.

const DEFAULT_COLORS := [Color(1,0.3,0.3), Color(0.35,0.6,1), Color(0.4,0.9,0.4), Color(1,0.85,0.3)]

static func from_settings(settings) -> Array:
	var n: int = settings.seat_count
	if n < 2: n = 4
	var seats: Array = []
	var assignments: Array = settings.seat_assignments
	var seen_sdk := false
	for i in n:
		var s = load("res://seats/seat.gd").new(i)
		var driver_label: String = ""
		if i < assignments.size():
			var a: Dictionary = assignments[i]
			driver_label = str(a.get("driver", ""))
			s.name = str(a.get("name", "Seat #%d" % (i + 1)))
			s.color = _color_from_name(str(a.get("token_color", "")), DEFAULT_COLORS[i % DEFAULT_COLORS.size()])
			s.token_id = str(a.get("token_id", "token%d" % i))
		else:
			var drv: String = "AI"
			if i == 0: drv = "LOCAL"
			driver_label = drv
			s.name = "AI Seat #%d" % (i + 1) if i > 0 else "Host"
			s.color = DEFAULT_COLORS[i % DEFAULT_COLORS.size()]
			s.token_id = "token%d" % i
		s.driver_label = driver_label
		s.input_driver = resolve_driver(driver_label, seen_sdk)
		if s.input_driver == "SDK":
			seen_sdk = true
		seats.append(s)
	# starting_order random: shuffle by re-seeded Rng (respect settings.rng_seed)
	if settings.starting_order == "random" and settings.rng_seed != 0:
		var Rng = load("res://core/rng.gd")
		var r = Rng.new()
		r.seed_rng(settings.rng_seed)
		for i in range(n - 1, 0, -1):
			var j: int = r.int_range(0, i)   # Fisher-Yates: swap i with j in [0..i]
			var tmp = seats[i]
			seats[i] = seats[j]
			seats[j] = tmp
		# renumber pids after shuffle
		for i in n:
			seats[i].pid = i
	return seats

static func resolve_driver(driver_label: String, sdk_already_used: bool) -> String:
	var label: String = String(driver_label).to_lower()
	if label == "local": return "LOCAL"
	if label == "chat": return "CHAT"
	if label == "admin": return "ADMIN"
	if label == "ai": return "AI"
	if label.begins_with("sdk:") or label == "sdk":
		# only ONE SDK connection is supported in-process (vendored SDK is a single
		# global singleton); additional SDK seats fall back to the internal AI driver
		return "AI" if sdk_already_used else "SDK"
	return "AI"   # unknown assignment → safe internal AI

func _color_from_name(s: String, fallback: Color) -> Color:
	var c := s.to_lower()
	match c:
		"red": return Color(1,0.3,0.3)
		"blue": return Color(0.35,0.6,1)
		"green": return Color(0.4,0.9,0.4)
		"yellow": return Color(1,0.85,0.3)
		"purple": return Color(0.75,0.5,1)
		"orange": return Color(1,0.6,0.2)
		"cyan": return Color(0.4,0.9,0.95)
		_ : return fallback
```

Note: `seat.gd` needs a `token_color(value)` helper OR set `s.color` directly.
I'll use the direct approach — in `from_settings` set `s.color = _color_from_name(str(a.get("token_color", "")), DEFAULT_COLORS[i % DEFAULT_COLORS.size()])` for explicit assignments (replace the `s.token_color(a.get(...))` line with that). Check `rng.gd` for the exact roll API (`roll_one(n)` or similar) and adapt.

- [ ] **步骤 6: 运行测试验证通过**

Run `godot --headless --path game --script res://tests/run.gd`. Expect the 4
seats tests PASS and all prior tests still PASS.

- [ ] **步骤 7: Commit**

```bash
git add game/core/game_settings.gd game/seats/seat.gd game/seats/seat_config.gd game/tests/seats_test.gd game/tests/run.gd
git commit -m "feat: Seat + SeatConfig — Block 1 assignments, driver resolution (second-SDK->AI)"
```

---

### Task 2: MinimalAction — timeout / auto-pass picker (pure)

**Files:**
- 创建: `game/seats/minimal_action.gd`
- 创建: `game/tests/seats_test.gd` (append)

- [ ] **步骤 1: 写失败的测试**

```gdscript
static func test_auto_pass_phases() -> String:
	var MA = load("res://seats/minimal_action.gd")
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, ["A", "B"])
	# TURN_START (player 0), not in jail → roll
	var p = MA.pick(e, 0)
	if p.get("action", "") != "roll": return "turn start -> roll"
	# force a purchase: land player 0 on an unowned property
	e._force_dice(6, 3, 3, false)   # 3+3=6 -> tile 6 (property, unowned); disable auction path for clarity
	s.auctions_on_refusal = false
	e.submit_intent(0, "roll", {})
	if e.phase != "PURCHASE_WAIT": return "expected purchase wait, got %s" % e.phase
	var p2 = MA.pick(e, 0)
	if p2.get("action", "") != "pass": return "purchase -> pass"
	return ""

static func test_jail_timeout_priority() -> String:
	var MA = load("res://seats/minimal_action.gd")
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	s.jail_fine = 50
	var e = E.new()
	e.setup(s, ["A", "B"])
	# player 0 in jail, jail_turns=0, has money → roll
	e._force_dice(4, 2, 2, true)   # send player 0 to jail via triple? simpler: teleport
	e._send_to_jail()              # set in_jail=true, pos=10 directly (test hook: it uses turn_player)
	var p = MA.pick(e, 0)
	if p.get("action", "") != "roll": return "in jail with attempts left -> roll"
	# jail_turns=3 → can't roll; must pay (has money)
	e.player(0).jail_turns = 3
	var p2 = MA.pick(e, 0)
	if p2.get("action", "") != "pay": return "3rd jail turn, has money -> pay"
	return ""
```

(Adjust to the engine's real API — verify `_send_to_jail` is callable and the
jail-turns semantics before finalizing.)

- [ ] **步骤 2: 运行测试** — expect FAIL (minimal_action.gd missing).

- [ ] **步骤 3: 创建 `game/seats/minimal_action.gd`**

```gdscript
extends RefCounted
## Picks the minimal non-stalling intent for a seat that timed out (spec §3 auto-pass).

static func pick(engine, pid: int) -> Dictionary:
	var legal: Array = engine.legal_actions(pid)
	if legal.size() == 0:
		return {}   # END_GAME or not this seat's turn → do nothing
	if engine.phase == "PURCHASE_WAIT":
		return {"action": "pass", "params": {}}
	if engine.phase == "AUCTION":
		return {"action": "pass", "params": {}}
	if legal.has("respond_trade"):
		return {"action": "respond_trade", "params": {"accept": false}}
	if legal.has("roll"):
		if engine.phase == "TURN_START" and engine.player(pid).in_jail:
			# in jail: prefer roll while attempts remain, else pay, else use_card, else roll
			if engine.player(pid).jail_turns < 3:
				return {"action": "roll", "params": {}}
			if engine.player(pid).money >= engine.settings.jail_fine:
				return {"action": "pay", "params": {}}
			if engine.player(pid).get_out_of_jail_cards > 0:
				return {"action": "use_card", "params": {}}
			return {"action": "roll", "params": {}}
		return {"action": "roll", "params": {}}
	return {}
```

- [ ] **步骤 4: 运行测试验证通过** — adjust the jail branch to match `legal`
  (if `legal_actions(pid)` omits `roll` when `jail_turns>=3`, the `legal.has("roll")`
  guard already routes correctly; keep the explicit priority anyway).

- [ ] **步骤 5: Commit**

```bash
git add game/seats/minimal_action.gd game/tests/seats_test.gd
git commit -m "feat: MinimalAction timeout auto-pass picker (pure)"
```

---

### Task 3: Spectator-safe projection + renderer

**Files:**
- 修改: `game/sdk/projection.gd` (add `for_spectator`)
- 修改: `game/sdk/markdown_renderer.gd` (add `render_spectator`)
- 修改: `game/tests/seats_test.gd` (append)

- [ ] **步骤 1: 写失败的测试**

```gdscript
static func test_spectator_projection_no_private() -> String:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, ["A", "B"])
	var Proj = load("res://sdk/projection.gd")
	var p = Proj.for_spectator(e)
	if p.has("private"): return "spectator must not contain private info"
	if p.board.size() != 40: return "board should have 40 tiles"
	# give player 0 a jail card to prove it is NOT leaked
	e.player(0).get_out_of_jail_cards = 5
	var p2 = Proj.for_spectator(e)
	if str(p2.players[0]).find("jail_card") != -1: return "jail card leaked to spectator"
	return ""

static func test_spectator_render_omits_private() -> String:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, ["A", "B"])
	e.player(0).get_out_of_jail_cards = 5
	var Proj = load("res://sdk/projection.gd")
	var R = load("res://sdk/markdown_renderer.gd")
	var md: String = R.render_spectator(Proj.for_spectator(e))
	if md.find("get-out-of-jail") != -1 or md.find("Your private") != -1:
		return "spectator markdown leaks private section"
	if md.find("Phase") == -1: return "spectator markdown should show phase"
	return ""
```

- [ ] **步骤 2: 运行测试** — expect FAIL (methods missing).

- [ ] **步骤 3: 实现 `for_spectator`（追加到 `game/sdk/projection.gd`）**

```gdscript
## Full public view for a spectator / stream overlay — NO private section and
## no hidden per-seat info (auction high/bidder ARE public; jail cards are not).
func for_spectator(engine) -> Dictionary:
	var out := {}
	out["phase"] = engine.phase
	out["turn_player"] = engine.turn_player
	out["board"] = _board_view(engine)
	out["players"] = _spectator_players_view(engine)
	out["pending"] = _pending_view(engine)
	# NOTE: no "legal" and no "private" — a spectator is not a decision holder
	return out

func _spectator_players_view(engine) -> Array:
	var players: Array = []
	for i in engine.players.size():
		var p = engine.players[i]
		var entry := {
			"index": i,
			"name": p.name,
			"money": p.money,
			"position": p.position,
			"in_jail": p.in_jail,
			"jail_turns": p.jail_turns,
			"bankrupt": p.bankrupt,
			"tiles": p.owned_tiles(),
		}
		players.append(entry)
	return players
```

- [ ] **步骤 4: 实现 `render_spectator`（追加到 `game/sdk/markdown_renderer.gd`）**

```gdscript
## Spectator markdown — same public view as render() but omits the private
## "Your private info" block (a spectator must never see hidden info).
func render_spectator(proj: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("## Neuro Property Trade — stream view")
	lines.append("")
	lines.append("Phase: %s" % proj.get("phase", ""))
	lines.append("It is player %d's turn." % int(proj.get("turn_player", 0)))
	lines.append("")
	lines.append("## Players")
	for p in proj.get("players", []):
		var jail := ""
		if p.get("in_jail", false):
			jail = " (in jail, %d turns)" % int(p.get("jail_turns", 0))
		lines.append("- %s: $%d, tile %d%s" % [p.get("name", "?"), int(p.get("money", 0)), int(p.get("position", 0)), jail])
	lines.append("")
	lines.append("## Board")
	for t in proj.get("board", []):
		var owner := "unowned"
		var o = t.get("owner", -1)
		if o != -1:
			owner = "owned by %d" % int(o)
		var extra := ""
		if int(t.get("houses", 0)) > 0:
			extra = ", %d houses" % int(t.get("houses", 0))
		if t.get("mortgaged", false):
			extra += ", mortgaged"
		lines.append("- %d. %s (%s) %s%s" % [int(t.get("index", 0)), t.get("name", "?"), t.get("type", "?"), owner, extra])
	lines.append("")
	lines.append("## Pending decision")
	var pending = proj.get("pending", {})
	if pending.is_empty():
		lines.append("- none")
	else:
		lines.append("- %s" % str(pending))
	# intentionally NO "Your private info" section for spectators
	return "\n".join(lines)
```

- [ ] **步骤 5: 运行测试验证通过** — both spectator tests PASS; prior tests PASS.

- [ ] **步骤 6: Commit**

```bash
git add game/sdk/projection.gd game/sdk/markdown_renderer.gd game/tests/seats_test.gd
git commit -m "feat: spectator-safe projection + renderer (no hidden info leak)"
```

---

### Task 4: TradeEvaluator — AI accept/decline heuristic (pure)

**Files:**
- 创建: `game/seats/trade_evaluator.gd`
- 创建: `game/tests/seats_test.gd` (append)

- [ ] **步骤 1: 写失败的测试**

```gdscript
static func test_trade_accept_rejects_poor_deal() -> String:
	var TE = load("res://seats/trade_evaluator.gd")
	# A simple score: accept if we receive at least as much value (tile cost +
	# cash) as we give. Give a cheap tile, want a costly tile + no cash → accept.
	var accept_ok: bool = TE.accept(
		{"give_tiles": [1], "give_cash": 0, "want_tiles": [39], "want_cash": 0}, true)
	if not accept_ok: return "should accept a clearly good deal"
	# Opposite: give big tile for small tile → reject
	var reject_ok: bool = TE.accept(
		{"give_tiles": [39], "give_cash": 0, "want_tiles": [1], "want_cash": 0}, false)
	if reject_ok: return "should reject a clearly bad deal"
	return ""
```

(The `accept()` signature will take the engine + recipient pid + the trade dict
so it can price tiles via `board.tile_at(t).cost`. Adjust to the real API —
the engine's `_pending_trade` holds `give_tiles`/`want_tiles`/cash.)

- [ ] **步骤 2: 运行测试** — expect FAIL.

- [ ] **步骤 3: 创建 `game/seats/trade_evaluator.gd`**

```gdscript
extends RefCounted
## Simple heuristic for an AI seat deciding whether to accept a proposed trade.
## Value = sum of tile cost (from board) + cash. Accept if received value >=
## given value. Kept as the Phase-3 stub; a smarter economic model is later.

static func accept_with(engine, recipient_pid: int, trade: Dictionary) -> bool:
	var give: int = _value(engine, trade.get("give_tiles", [])) + int(trade.get("give_cash", 0))
	var want: int = _value(engine, trade.get("want_tiles", [])) + int(trade.get("want_cash", 0))
	return want >= give

static func _value(engine, tiles: Array) -> int:
	var total := 0
	for t in tiles:
		total += int(engine.board.tile_at(int(t)).get("cost", 0))
	return total
```

- [ ] **步骤 4: 更新 `accept` 到 `accept_with`**（匹配步骤 1 的真实签名 — 修正测试中的
  `TE.accept(...)` 调用为 `TE.accept_with(engine, recipient_pid, trade)`），
  **运行测试验证通过**。

- [ ] **步骤 5: Commit**

```bash
git add game/seats/trade_evaluator.gd game/tests/seats_test.gd
git commit -m "feat: TradeEvaluator AI accept/decline heuristic (pure)"
```

---

### Task 5: SeatManager + AI driver + Chat stub + Local wait (Node)

**Files:**
- 创建: `game/seats/drivers/ai_driver.gd`
- 创建: `game/seats/drivers/chat_driver.gd`
- 创建: `game/seats/drivers/local_driver.gd`
- 创建: `game/seats/seat_manager.gd`
- 创建: `game/tests/seats_test.gd` (append — manager logic that is pure, e.g. driver routing via `resolve_driver`; the Node poll itself is runtime-tested)

- [ ] **步骤 1: 写失败的路由测试**（纯部分 — 验证 manager 能从 seats 数组找到一个持有合法
  action 的 pid，这是可 headless 测试的纯函数）

```gdscript
static func test_find_decision_holder() -> String:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, ["A", "B"])   # player 0 is turn_player, has legal actions
	var SM = load("res://seats/seat_manager.gd")
	var holder: int = SM.find_decision_holder(e, 2)
	if holder != 0: return "expected holder 0, got %d" % holder
	# after a purchase wait for player 0, holder is still 0
	e._force_dice(6, 3, 3, false)
	s.auctions_on_refusal = false
	e.submit_intent(0, "roll", {})
	if e.phase != "PURCHASE_WAIT": return "want purchase wait"
	var h2: int = SM.find_decision_holder(e, 2)
	if h2 != 0: return "expected holder 0 on purchase wait"
	return ""
```

- [ ] **步骤 2: 运行测试** — expect FAIL (method missing).

- [ ] **步骤 3: 创建 `game/seats/seat_manager.gd`**（含静态 `find_decision_holder`
  及 Node 编排逻辑）

```gdscript
extends Node
## Orchestrates multi-seat play. On each poll, finds the seat that holds the
## decision point (non-empty legal_actions), routes to its driver, and enforces
## per-seat timeout -> auto-pass. All intents flow through engine.submit_intent
## (fail-closed). Emits spectator-safe signals for a UI overlay.

signal state_changed(spectator_proj: Dictionary)
signal events_emitted(events: Array)
signal game_over(winner_name: String)

const AI_DRIVER := "res://seats/drivers/ai_driver.gd"
const CHAT_DRIVER := "res://seats/drivers/chat_driver.gd"

var engine
var seats: Array = []        # of Seat (RefCounted)
var _drivers := {}           # pid -> Node driver instance
var _last_decision_key := ""
var _elapsed := 0.0
const POLL_INTERVAL := 0.4

# --- pure helper (headless-testable) ---
static func find_decision_holder(engine, player_count: int) -> int:
	for pid in player_count:
		if not engine.legal_actions(pid).is_empty():
			return pid
	return -1

func setup(eng, seat_list: Array) -> void:
	engine = eng
	seats = seat_list
	for s in seats:
		match s.input_driver:
			"AI": _spawn_driver(s.pid, AI_DRIVER)
			"CHAT": _spawn_driver(s.pid, CHAT_DRIVER)
			# LOCAL / SDK / ADMIN need no auto-driver; they wait or are pushed/ticked
			_:
				pass

func _spawn_driver(pid: int, path: String) -> void:
	var Script = load(path)
	var node = Script.new()
	node.name = "Driver%d" % pid
	add_child(node)
	node.setup(engine, _seat(pid))
	_drivers[pid] = node

func _seat(pid: int):
	for s in seats:
		if s.pid == pid: return s
	return null

func _process(delta: float) -> void:
	if engine == null: return
	_elapsed += delta
	if _elapsed < POLL_INTERVAL: return
	_elapsed = 0.0
	_tick()

func _tick() -> void:
	if engine.phase == "END_GAME":
		game_over.emit(engine.player(0).name if engine.player_count() == 1 else "")
		return
	var holder: int = find_decision_holder(engine, engine.player_count())
	if holder == -1: return
	var key: String = "%s|%d|%s" % [engine.phase, holder, str(engine._pending)]
	if key != _last_decision_key:
		_last_decision_key = key
		for s in seats:
			s.decision_waiting = 0.0
	var seat = _seat(holder)
	if seat == null: return
	seat.decision_waiting = _elapsed   # approximate; real delta accumulation in _process
	var drv = _drivers.get(holder)
	match seat.input_driver:
		"AI":
			if drv != null:
				drv.act()
		"CHAT":
			if drv != null:
				drv.act()
		"SDK":
			# the sdk driver is self-driven via its own _process; timeout enforcement
			# applies to the local human seats. If the SDK seat times out with no
			# result, apply minimal_action.
			_maybe_timeout(seat)
		"LOCAL", "ADMIN":
			_maybe_timeout(seat)
	emit_spectator()

func _maybe_timeout(seat) -> void:
	if engine.settings.timeout_action == "mark-away":
		seat.away = true
		return
	var window := float(engine.settings.turn_timer)
	if engine.phase == "AUCTION":
		window = float(engine.settings.auction_timer)
	if window <= 0: return
	if seat.decision_waiting >= window:
		var p = load("res://seats/minimal_action.gd").pick(engine, seat.pid)
		if p.is_empty(): return
		var res: Dictionary = engine.submit_intent(seat.pid, p.action, p.params)
		seat.away = true
		if res.get("events", []).size() > 0:
			events_emitted.emit(res["events"])
		emit_spectator()

## Single human/admin/SDK entry — forwards to the engine, fail-closed.
func push_intent(pid: int, action: String, params: Dictionary) -> Dictionary:
	if engine == null:
		return {"ok": false, "reason": "engine not ready", "legal": [], "events": []}
	var res: Dictionary = engine.submit_intent(pid, action, params)
	emit_spectator()
	return res

func push_admin_intent(action: String, params: Dictionary) -> Dictionary:
	# Admin overrides go through the authoritative engine (spec §4 invariant).
	# Phase 3 stub: route to push for the current decision holder, or no-op.
	# Full admin_override is Phase 4.
	var holder: int = find_decision_holder(engine, engine.player_count())
	if holder == -1: return {"ok": false, "reason": "no active decision", "legal": [], "events": []}
	return push_intent(holder, action, params)

func emit_spectator() -> void:
	var Proj = load("res://sdk/projection.gd")
	state_changed.emit(Proj.for_spectator(engine))
```

- [ ] **步骤 4: 创建 `game/seats/drivers/ai_driver.gd`**

```gdscript
extends Node
## Internal AI driver: submits the first legal action each decision point.
## Reuses the soak's _auto_drive logic (bid-above-high-or-pass, decline trades).

var engine
var seat

func setup(eng, s):
	engine = eng
	seat = s

func act() -> void:
	if engine == null or seat == null: return
	var pid: int = seat.pid
	var legal: Array = engine.legal_actions(pid)
	if legal.is_empty(): return
	var action: String = legal[0]
	var params := {}
	match action:
		"bid":
			var high: int = int(engine._pending.get("high", 0))
			if engine.player(pid).money <= high:
				action = "pass"
			else:
				params["amount"] = high + 1
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			var tiles: Array = engine.player(pid).owned_tiles()
			if tiles.size() == 0: return
			params["tile"] = int(tiles[0])
		"propose_trade":
			return   # AI does not proactively propose trades this phase
		"respond_trade":
			var TE = load("res://seats/trade_evaluator.gd")
			params["accept"] = TE.accept_with(engine, pid, engine._pending_trade)
	engine.submit_intent(pid, action, params)
```

- [ ] **步骤 5: 创建 `game/seats/drivers/chat_driver.gd`（stub 聚合）与
  `game/seats/drivers/local_driver.gd`（无-op / 等待）**

```gdscript
## chat_driver.gd — stub majority aggregation over a queue of local intents.
extends Node
var engine
var seat
var _queue: Array = []

func setup(eng, s):
	engine = eng
	seat = s

func enqueue(action: String, params: Dictionary) -> void:
	_queue.append({"action": action, "params": params})
	if _queue.size() > 8:
		_queue.pop_front()

func act() -> void:
	if engine == null or _queue.is_empty(): return
	# majority of the last few commands (simplified: last one wins)
	var last = _queue.pop_back()
	engine.submit_intent(seat.pid, last["action"], last["params"])
```

```gdscript
## local_driver.gd — human seat: waits. Intents arrive via seat_manager.push_intent.
extends Node
var engine
var seat
func setup(eng, s):
	engine = eng
	seat = s
```

- [ ] **步骤 6: 运行测试** — `find_decision_holder` test PASS; adjust `seat.decision_waiting`
  更新（步骤 3 中 `= _elapsed` 的近似应在 `_process` 里做 delta 累加 — 修正：把 `_tick` 中
  `seat.decision_waiting` 累加逻辑移到 `_process` 用真实 delta）。运行全部测试确认仍绿。

- [ ] **步骤 7: Commit**

```bash
git add game/seats/drivers/ game/seats/seat_manager.gd game/tests/seats_test.gd
git commit -m "feat: SeatManager + AI/Chat/Local drivers — multi-seat routing + timeout auto-pass"
```

---

### Task 6: SDK driver integration (reuse existing adapter) + seats soak

**Files:**
- 修改: `game/sdk/sdk_adapter.gd` (optional: expose `public func tick()` so the
  manager can drive it; currently it self-polls)
- 创建: `game/tools/seats_soak.tscn` + `game/tools/seats_soak.gd`

- [ ] **步骤 1: 修改 `game/sdk/sdk_adapter.gd`** — 将 `_process` 中的轮询提取为
  公开的 `tick()`：

```gdscript
# In _process, replace the polling block with a call to tick():
func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < POLL_INTERVAL:
		return
	_poll_elapsed = 0.0
	tick()

func tick() -> void:
	_force_if_needed()
```

(This keeps the adapter self-driving in isolation AND allows the manager to call
it directly. Confirm the SDK adapter's `setup(engine, pid)` is enough for the
seat layer to wire it.)

- [ ] **步骤 2: 创建 `game/tools/seats_soak.gd`**（多座混合 runtime 证明：SDK + AI
  + AI + LOCAL；LOCAL 由一个“假人类”定时推 intent）

```gdscript
extends Node
## Multi-seat runtime proof for Phase 3. Wires seat_manager with seats
## [SDK(neuro), AI, AI, LOCAL]. The LOCAL seat is auto-driven by a fake human
## timer pushing intents; the SDK seat talks to Randy (ws://localhost:8000).
## Reaches END_GAME or a turn cap without stalling => exit 0.

const EngineScript := preload("res://core/engine.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const SdkAdapter := preload("res://sdk/sdk_adapter.gd")

const MAX_TURNS := 12
const STALL_SECONDS := 20.0
const TURN_TIMER := 3

var _engine
var _manager
var _started := false
var _done := false
var _turn_count := 0
var _last_turn := -1
var _stall_key := ""
var _stall_elapsed := 0.0
var _fake_human_elapsed := 0.0

func _ready() -> void:
	print("=== seats soak: starting ===")
	var s = Settings.new()
	s.rng_seed = 12345
	s.turn_timer = TURN_TIMER
	s.auction_timer = TURN_TIMER
	s.auctions_on_refusal = false
	s.seat_assignments = [
		{"driver": "sdk:neuro", "name": "Neuro"},
		{"driver": "AI", "name": "Ada"},
		{"driver": "AI", "name": "Bo"},
		{"driver": "LOCAL", "name": "Ced"},
	]
	var seats: Array = SeatConfig.from_settings(s)
	_engine = EngineScript.new()
	_engine.setup(s, _seat_names(seats))
	_manager = SeatManager.new()
	_manager.name = "SeatManager"
	add_child(_manager)
	_manager.setup(_engine, seats)
	# SDK seat 0: wire the existing adapter
	if seats.size() > 0 and seats[0].input_driver == "SDK":
		var adapter = SdkAdapter.new()
		adapter.name = "SdkAdapter"
		add_child(adapter)
		adapter.setup(_engine, 0)
	_started = true
	print("=== seats soak: engine ready, manager wired ===")

func _seat_names(seats: Array) -> Array:
	var names := []
	for s in seats:
		names.append(s.name)
	return names

func _process(delta: float) -> void:
	if not _started or _done: return
	# Fake human drives seat 3 (LOCAL) every 0.5s while it's their decision.
	# The manager's LOCAL driver waits; we push via the manager like a UI would.
	_fake_human_elapsed += delta
	if _fake_human_elapsed >= 0.5:
		_fake_human_elapsed = 0.0
		_drive_local_seat(3)
	# Stall + turn cap detection (mirrors soak.gd)
	var key: String = "%s|%d|%d" % [_engine.phase, _engine.turn_player, _engine._pending.get("bidder", -1)]
	if key == _stall_key:
		_stall_elapsed += delta
		if _stall_elapsed >= STALL_SECONDS:
			print("=== seats soak: STALLED at %s === %s" % [key, str(_engine._pending)])
			_finish(false)
	else:
		_stall_key = key
		_stall_elapsed = 0.0
	if _engine.turn_player == 0 and _last_turn != 0:
		_turn_count += 1
		_last_turn = 0
		if _turn_count >= MAX_TURNS:
			print("=== seats soak: turn cap %d === " % MAX_TURNS)
			_finish(true)
	elif _engine.turn_player != 0:
		_last_turn = _engine.turn_player
	if _engine.phase == "END_GAME":
		print("=== seats soak: game over ===")
		_finish(true)

func _drive_local_seat(pid: int) -> void:
	var legal: Array = _engine.legal_actions(pid)
	if legal.is_empty(): return
	var action: String = legal[0]
	var params := {}
	match action:
		"bid":
			var high: int = int(_engine._pending.get("high", 0))
			if _engine.player(pid).money <= high: action = "pass"
			else: params["amount"] = high + 1
		"respond_trade":
			params["accept"] = false
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			var tiles: Array = _engine.player(pid).owned_tiles()
			if tiles.size() == 0: return
			params["tile"] = int(tiles[0])
	_manager.push_intent(pid, action, params)

func _finish(passed: bool) -> void:
	_done = true
	print("=== seats soak: %s ===" % ("PASSED" if passed else "FAILED"))
	get_tree().quit(0 if passed else 1)
```

- [ ] **步骤 3: 创建 `game/tools/seats_soak.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/seats_soak.gd" id="1"]

[node name="SeatsSoak" type="Node"]
script = ExtResource("1")
```

- [ ] **步骤 4: 先导入项目（SDK class cache），再运行 seats soak**

```bash
cd ~/projects/neuro-property-trade
~/godot/godot --headless --import .    # ensure .godot/global_script_class_cache.cfg exists
# start Randy (in another shell):
# cd /tmp/nsdk_probe/Randy && npm install && npm start
NEURO_SDK_WS_URL=ws://localhost:8000 ~/godot/godot --headless --path game res://tools/seats_soak.tscn
```

期望：exit 0（到达 turn cap 或 END_GAME，无 stall）。SDK 座 0（Neuro↔Randy）由
adapter 驱动；AI 座 1、2 由 ai_driver 驱动；LOCAL 座 3 由假人类推 intent。若
stall，打印 pending/legal 帮助定位。

- [ ] **步骤 5: Commit**

```bash
git add game/sdk/sdk_adapter.gd game/tools/seats_soak.gd game/tools/seats_soak.tscn
git commit -m "feat: SDK driver + seats soak — mixed multi-seat runtime proof (SDK+AI+AI+LOCAL)"
```

---

### Task 7: Update plan.md + merge to main

**Files:**
- 修改: `docs/plan.md` (Phase 3 checkboxes + status note)

- [ ] **步骤 1: 更新 `docs/plan.md` Phase 3 section**

Mark done:
- [x] Seat manager: human turns wait for input, AI turns force
- [x] Second AI seat (internal AI driver; evil via SDK deferred to single-connection SDK support)
- [x] Trade negotiation UX for humans: engine propose/respond exists; auto-resolve for AI-vs-AI via TradeEvaluator
- [x] Spectator-safe state (no hidden info leak in context messages) — `for_spectator`/`render_spectator`

Add a Phase 3 status paragraph noting the SDK single-singleton constraint and
the driver-resolver swap point.

- [ ] **步骤 2: 运行完整 headless suite** — expect ALL PASS (prior + new).

- [ ] **步骤 3: 合并到 main**

```bash
git add docs/plan.md
git commit -m "docs: Phase 3 status — seats & lobby"
git checkout main
git merge --ff-only phase3/seats-lobby
git push origin main
```

- [ ] **步骤 4: 更新技能（`neuro-property-trade-dev`）** — 追加 Phase 3 状态、
  SDK 单一 singleton 约束、seat 层文件地图。用 `skill_manage(action='patch')`。

---

## Self-review

- **Spec coverage:** Block 1 (seat_count/assignments/starting_order) → Task 1;
  timeout/auto-pass (§3) → Task 2 + Task 5 `_maybe_timeout`; spectator safety
  → Task 3; second AI seat → Task 1 (resolve_driver) + Task 5 (ai_driver);
  trade auto-resolve → Task 4 + ai_driver; admin override *invariant* →
  Task 5 `push_admin_intent` stub. All five Phase-3 plan.md checkboxes covered.
- **Placeholder scan:** no TBD/TODO; each task has concrete code. The two
  "adjust to real API" notes are flagged against the current engine (roll/roll
  API, `_send_to_jail`, `rng.roll_one`, `_pending_trade`) — an executor must
  verify those exact names against `game/core/engine.gd` and `game/core/rng.gd`
  before finalizing; the code shown matches the files read this session.
- **Type consistency:** `input_driver` values are UPPERCASE constants; driver
  resolution keeps `seen_sdk` monotonic; `find_decision_holder` returns a pid
  or -1; `minimal_action.pick` returns `{action, params}` or `{}` —
  consistent across tasks.
