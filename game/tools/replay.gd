class_name DReplay
extends RefCounted
## Deterministic replay + decision logging for the rules engine.
##
## WHY: every source of randomness lives behind the engine's seeded Rng, so a
## game is fully determined by (settings, names, seed, the ordered decision
## sequence). Logging decisions - not dice - is therefore a complete replay
## record, and re-running it must reproduce the exact same state. That property
## is the debugger for engine-vs-intent drift in multi-seat play.
##
## Log format: JSONL, one header line, then one "call" line per decision:
##   {"kind":"header","schema":1,"godot_version":"...","game":"g001","seed":1,
##    "names":[...],"settings":{...},"fingerprint0":"<sha256>",
##    "fingerprint":"<sha256>"}
##   {"kind":"call","n":0,"pid":0,"phase":"TURN_START","turn":0,
##    "action":"roll","params":{},"legal":["roll",...],"features":{...}}
## fingerprint = sha256(JSON.stringify(engine.to_snapshot())) - the WHOLE
## authoritative state, so "same seed == same state" is checkable byte for byte.
##
## A log only replays on the SAME engine build: godot_version is stored in the
## header and checked (use allow_version_mismatch to override deliberately).

const SCHEMA := 1
const KIND_HEADER := "header"
const KIND_CALL := "call"

## Params the engine expects as int / int-array / bool. JSON gives back floats
## (and stringified bools), while ownership checks are `Array.has(1)` - so a
## 1.0 would silently fail to match. Normalize on BOTH record and replay.
const INT_PARAMS := ["tile", "amount", "to", "give_cash", "want_cash"]
const INT_ARRAY_PARAMS := ["give_tiles", "want_tiles"]

# --- typed coercion (JSON -> GDScript expectations) ---

static func to_bool(v) -> bool:
	if v is String:
		return String(v).to_lower() == "true"
	return bool(v)

static func _coerce(v, type_id: int):
	match type_id:
		TYPE_INT: return int(v)
		TYPE_FLOAT: return float(v)
		TYPE_BOOL: return to_bool(v)
		TYPE_STRING: return String(v)
		TYPE_ARRAY: return v if v is Array else []
		TYPE_DICTIONARY: return v if v is Dictionary else {}
	return v

## Re-coerce a settings dict (from JSON) to the declared property types of
## GameSettings. Without this `rng_seed` arrives as a float, from_data assigns it
## to an int-typed var, and the engine's Rng never gets seeded -> replay diverges.
static func coerce_settings(d: Dictionary) -> Dictionary:
	var S = load("res://core/game_settings.gd")
	var types := {}
	for p in S.new().get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			types[p.name] = p.type
	var out := {}
	for k in d:
		if types.has(k):
			out[k] = _coerce(d[k], types[k])
		else:
			out[k] = d[k]
	return out

static func apply_settings(d: Dictionary):
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	s.from_data(coerce_settings(d))
	return s

## Normalize an intent's params to the types the engine validates against.
static func normalize_params(action: String, params: Dictionary) -> Dictionary:
	var out := {}
	for k in params:
		var v = params[k]
		if INT_PARAMS.has(k):
			out[k] = int(v)
		elif INT_ARRAY_PARAMS.has(k):
			var arr := []
			if v is Array:
				for x in v:
					arr.append(int(x))
			out[k] = arr
		elif k == "accept":
			out[k] = to_bool(v)
		else:
			out[k] = v
	return out

# --- fingerprint ---

static func fingerprint(engine) -> String:
	var text := JSON.stringify(engine.to_snapshot())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

static func godot_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d.%s.%s" % [v["major"], v["minor"], v["patch"], v["status"], v["hash"]]

# --- the shared deterministic policy ---
## ONE policy for corpus recording and for the seeded soak test, so recorded
## labels and the reference behaviour can never drift apart. Deliberately simple
## and explainable: it is the baseline a learned (System-1) policy has to beat.

static func decide(e, pid: int) -> Dictionary:
	var legal: Array = e.legal_actions(pid)
	if legal.is_empty():
		return {}
	if legal.has("bid"):
		return _decide_bid(e, pid)
	if legal.has("buy"):
		return _decide_buy(e, pid)
	if legal.has("respond_trade") and _is_trade_recipient(e, pid):
		var TE = load("res://seats/trade_evaluator.gd")
		return {"action": "respond_trade", "params": {"accept": TE.accept_with(e, pid, e._pending_trade)}}
	if legal.has("build_house"):
		var t: int = best_build_tile(e, pid)
		if t != -1:
			return {"action": "build_house", "params": {"tile": t}}
	if legal.has("roll"):
		return {"action": "roll", "params": {}}
	if legal.has("pay"):
		return {"action": "pay", "params": {}}
	if legal.has("use_card"):
		return {"action": "use_card", "params": {}}
	return {"action": String(legal[0]), "params": {}}

static func _is_trade_recipient(e, pid: int) -> bool:
	return e._pending_trade.size() != 0 and int(e._pending_trade.get("recipient", -1)) == pid

## What this seat bids.
##
## The increment used to be `high + 1`, which raised the price ONE unit at a time
## while the only guard compared against a cash balance in the thousands. A
## measured single auction ran to 1451 bids before closing, so a match burned its
## entire ply budget inside the first auction and never reached a second turn —
## the soak could not exercise the rest of the engine, and the corpus filled with
## near-identical auction_bid entries.
##
## The step is now a fraction of the lot, which is how a real auction moves and
## what makes the price reach the cash ceiling where the guard can act.
static func _decide_bid(e, pid: int) -> Dictionary:
	var high: int = int(e._pending.get("high", -1))
	var money: int = e.players[pid].money
	var tile: int = int(e._pending.get("tile", -1))
	var amount: int
	if high == -1:
		amount = opening_bid(e, tile)
	else:
		amount = high + bid_step(e, tile, pid)
	if amount > money:
		return {"action": "pass", "params": {}}
	# Stop when the price passes what the lot is WORTH. Without this a seat bids
	# up to its last coin, because cash is the only ceiling — so four seats grind
	# each other to the poorest one's balance and an auction takes dozens of
	# rounds. A real player stops well before that.
	if amount > bid_ceiling(e, tile, pid):
		return {"action": "pass", "params": {}}
	return {"action": "bid", "params": {"amount": amount}}


## The most this seat will pay for a lot: a multiple of its price, lifted when
## buying it completes a colour group (which is what actually makes it valuable).
static func bid_ceiling(e, tile: int, pid: int) -> int:
	var cost: int = int(e.board.tile_at(tile).get("cost", 0))
	if cost <= 0:
		return e.players[pid].money
	var mult := BID_CEILING
	var group: String = str(e.board.tile_at(tile).get("group", ""))
	if group != "":
		var mine := 0
		var total := 0
		for t in range(e.board.tile_count()):
			if str(e.board.tile_at(t).get("group", "")) != group:
				continue
			total += 1
			if e._owner_of(t) == pid:
				mine += 1
		# a piece that completes the set is worth chasing
		if total > 0 and mine == total - 1:
			mult = BID_CEILING_SET
	return int(round(float(cost) * mult))


## How much the price moves per bid: a fraction of the lot, never less than 1, and
## always enough to close an auction in a plausible number of rounds rather than
## thousands of unit steps.
static func bid_step(e, tile: int, pid: int) -> int:
	var cost: int = int(e.board.tile_at(tile).get("cost", 0))
	if cost <= 0:
		cost = opening_bid(e, tile)
	var step: int = int(round(float(cost) * BID_STEP_FRAC))
	if step < 1:
		step = 1
	# never bid past what this seat can pay
	var money: int = e.players[pid].money
	if step > money:
		step = money
	return step

static func _decide_buy(e, pid: int) -> Dictionary:
	if worth_buying(e, pid):
		return {"action": "buy", "params": {}}
	return {"action": "pass", "params": {}}

const BID_STEP_FRAC := 0.1
## Cash kept in hand after a purchase, as a fraction of the starting balance.
const BUY_RESERVE_FRAC := 0.1
## What a seat will pay for a plain lot, and for one that completes its group,
## as a multiple of the lot's price.
const BID_CEILING := 1.5
const BID_CEILING_SET := 2.5


## The opening price: half the lot, but never more than the seat THAT IS BIDDING
## can pay. It used to be clamped by the AUCTIONEER's money — the seat that
## declined — which is not the seat being asked to bid.
static func opening_bid(e, tile: int) -> int:
	var cost: int = int(e.board.tile_at(tile).get("cost", 0))
	var amount: int = int(float(cost) * 0.5)
	if amount < 1:
		amount = 1
	var money: int = e.players[e.turn_player].money
	if amount > money:
		amount = money
	return amount

## Buy while keeping a cash reserve, or whenever the tile completes a set.
## Should this seat buy the lot?
##
## The cushion used to be a FLAT 100. Measured over 20 000 plies on the smoke's
## seed that produced 22 purchases: a 60-cost lot needs money >= 160, which the
## policy seldom had, so almost nothing was ever bought, rent stayed trivial and
## no match reached game-over. The reserve is now a fraction of the starting
## balance, so early purchases happen and the board actually develops.
static func worth_buying(e, pid: int) -> bool:
	var tile: int = int(e._pending.get("tile", -1))
	var cost: int = int(e.board.tile_at(tile).get("cost", 0))
	if completes_set(e, pid, tile):
		return e.players[pid].money >= cost
	var reserve: int = int(round(float(e.settings.starting_cash) * BUY_RESERVE_FRAC))
	return e.players[pid].money - cost >= reserve

static func completes_set(e, pid: int, tile: int) -> bool:
	var group: String = String(e._group_of(tile))
	if group == "":
		return false
	for t in e.board.group_tiles(group):
		var ti: int = int(t)
		if ti != int(tile) and not e.players[pid].owns(ti):
			return false
	return true

## Cheapest legal even-build house, or -1 when the seat cannot build at all.
static func best_build_tile(e, pid: int) -> int:
	var best := -1
	var best_h := 99
	for t in e.players[pid].owned_tiles():
		var tile: int = int(t)
		var group: String = String(e._group_of(tile))
		if group == "":
			continue
		if not e._owns_set(pid, group):
			continue
		var h: int = e._houses_on(tile)
		if h >= 5:
			continue
		if e.settings.even_build and h > e._set_min_houses(group):
			continue
		if e.players[pid].money < int(e.board.tile_at(tile).get("house_cost", 0)):
			continue
		if h < best_h:
			best_h = h
			best = tile
	return best

# --- typed features (the decision-time context, model-readable) ---

static func features(e, pid: int) -> Dictionary:
	var p = e.players[pid]
	var f := {
		"phase": e.phase,
		"turn_player": e.turn_player,
		"money": p.money,
		"position": p.position,
		"in_jail": p.in_jail,
		"jail_turns": p.jail_turns,
		"jail_cards": p.get_out_of_jail_cards,
		"owned_count": p.owned_tiles().size(),
		"set_groups": owned_set_groups(e, pid),
		"houses": houses_owned(e, pid),
		"opponents": [],
		"decision": {},
	}
	for i in e.players.size():
		if i == pid:
			continue
		var o = e.players[i]
		f["opponents"].append({
			"index": i, "money": o.money, "position": o.position,
			"owned_count": o.owned_tiles().size(), "in_jail": o.in_jail,
		})
	if e.phase == "PURCHASE_WAIT" or e.phase == "AUCTION":
		var t: int = int(e._pending.get("tile", -1))
		var d := tile_features(e, pid, t)
		if e.phase == "AUCTION":
			d["high"] = int(e._pending.get("high", -1))
			d["high_player"] = int(e._pending.get("high_player", -1))
			d["bidder"] = int(e._pending.get("bidder", -1))
		f["decision"] = d
	elif e._pending_trade.size() != 0:
		f["decision"] = {
			"trade": e._pending_trade.duplicate(),
			"im_recipient": _is_trade_recipient(e, pid),
		}
	return f

static func tile_features(e, pid: int, tile: int) -> Dictionary:
	var t: Dictionary = e.board.tile_at(tile)
	if t.is_empty():
		return {}
	return {
		"index": tile,
		"name": String(t.get("name", "")),
		"type": String(t.get("type", "")),
		"group": String(t.get("group", "")),
		"cost": int(t.get("cost", 0)),
		"rent": int(t.get("rent", 0)),
		"rent_set": int(t.get("rent_set", 0)),
		"house_cost": int(t.get("house_cost", 0)),
		"houses": e._houses_on(tile),
		"mortgaged": e._mortgaged.has(tile),
		"owner": e._owner_of(tile),
		"completes_set": completes_set(e, pid, tile),
	}

static func owned_set_groups(e, pid: int) -> Array:
	var out := []
	var seen := {}
	for t in e.players[pid].owned_tiles():
		var group: String = String(e._group_of(int(t)))
		if group == "" or seen.has(group):
			continue
		if e._owns_set(pid, group):
			seen[group] = true
			out.append(group)
	out.sort()
	return out

static func houses_owned(e, pid: int) -> int:
	var total := 0
	for t in e.players[pid].owned_tiles():
		total += e._houses_on(int(t))
	return total

# --- record ---

static func make_header(game: String, seed_v: int, settings, names: Array, fp0: String, fp: String) -> Dictionary:
	return {
		"kind": KIND_HEADER,
		"schema": SCHEMA,
		"godot_version": godot_version(),
		"game": game,
		"seed": seed_v,
		"names": names,
		"settings": settings.to_data(),
		"fingerprint0": fp0,
		"fingerprint": fp,
	}

static func line(d: Dictionary) -> String:
	return JSON.stringify(d)

static func default_names() -> Array:
	return ["Neuro", "Ada", "Bo", "Cyd"]

static func log_json(header: Dictionary, calls: Array) -> String:
	var lines := [line(header)]
	for c in calls:
		lines.append(line(c))
	return "\n".join(lines) + "\n"

## Play one full game with the shared deterministic policy. Returns the log
## (header + calls), the resulting engine and summary stats.
##
## opts: seed, names, max_plies, auctions, game (id), record_features.
## Rejected intents are logged too and then backed off deterministically via
## minimal_action, so a stall cannot hang the recorder.
static func play(opts: Dictionary) -> Dictionary:
	var seed_v: int = int(opts.get("seed", 1))
	var names: Array = opts.get("names", default_names())
	if (names as Array).size() < 2:
		names = default_names()
	var max_plies: int = int(opts.get("max_plies", 400))
	var id: String = String(opts.get("game", "g001"))
	var with_features: bool = bool(opts.get("record_features", true))

	var s = load("res://core/game_settings.gd").new()
	s.rng_seed = seed_v
	s.seat_count = (names as Array).size()
	s.starting_order = "manual"
	s.turn_timer = 0          # timers are a seat/UI concern; the recorder drives
	s.auction_timer = 0
	s.auctions_on_refusal = bool(opts.get("auctions", true))

	var E = load("res://core/engine.gd")
	var e = E.new()
	e.setup(s, names)

	var fp0: String = fingerprint(e)
	var calls: Array = []
	var plies := 0
	while e.phase != "END_GAME" and plies < max_plies:
		var holder: int = -1
		for pid in e.player_count():
			if not e.legal_actions(pid).is_empty():
				holder = pid
				break
		if holder == -1:
			break
		var decision: Dictionary = decide(e, holder)
		if decision.is_empty():
			break
		var action: String = String(decision["action"])
		var params: Dictionary = normalize_params(action, decision.get("params", {}))
		var legal: Array = e.legal_actions(holder)
		var feats: Dictionary = features(e, holder) if with_features else {}
		var res: Dictionary = e.submit_intent(holder, action, params)
		var call := {
			"kind": KIND_CALL,
			"n": plies,
			"pid": holder,
			"phase": String(feats.get("phase", "")),
			"turn": int(feats.get("turn_player", -1)),
			"action": action,
			"params": params,
			"legal": legal,
			"ok": bool(res.get("ok", false)),
			"reason": String(res.get("reason", "")),
		}
		if with_features:
			call["features"] = feats
		calls.append(call)
		plies += 1
		if not bool(res.get("ok", false)):
			# deterministic back-off: take the engine-blessed minimal action
			var MA = load("res://seats/minimal_action.gd")
			var p: Dictionary = MA.pick(e, holder)
			if p.is_empty():
				break
			var pa: String = String(p["action"])
			e.submit_intent(holder, pa, normalize_params(pa, p.get("params", {})))
		if e.phase == "END_GAME":
			break
		if e.player_count() < 2:
			break

	var survivors: Array = []
	for p in e.players:
		survivors.append({
			"name": p.name, "money": p.money, "bankrupt": p.bankrupt,
			"tiles": p.owned_tiles().size(),
		})
	var header: Dictionary = make_header(id, seed_v, s, names, fp0, fingerprint(e))
	return {
		"header": header,
		"calls": calls,
		"engine": e,
		"plies": plies,
		"end_reason": "END_GAME" if e.phase == "END_GAME" else ("ply_cap" if plies >= max_plies else "stalled"),
		"survivors": survivors,
		"log_json": log_json(header, calls),
	}

## Godot's FileAccess only accepts res://, user:// or an absolute NATIVE path.
## The CLI tools are driven from a shell, so translate a project-relative path
## ("corpus/games") into a native one, relative to the repo root (the parent of
## the Godot project directory). res:// and user:// pass through untouched.
static func resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var stripped: String = path.replace("\\", "/")
	# MSYS/Git-bash drive paths ("/c/Users/...") are shell paths, not native ones:
	# translate them, otherwise FileAccess opens a directory that does not exist.
	var drive := RegEx.new()
	drive.compile("^/([a-zA-Z])/(.*)$")
	var m := drive.search(stripped)
	if m != null:
		stripped = "%s:/%s" % [m.get_string(1).to_upper(), m.get_string(2)]
	# bare MSYS paths ("/tmp/tmp.XXXX" from a shell `mktemp -d`) have no drive
	# letter. Godot cannot resolve them at all - it needs a native path - so map
	# the shell temp root onto the engine's own temp dir when they agree.
	var mktemp := RegEx.new()
	mktemp.compile("^/tmp/(.+)$")
	var tm := mktemp.search(stripped)
	if tm != null:
		var native_tmp: String = OS.get_environment("TEMP")
		if native_tmp == "":
			native_tmp = OS.get_environment("TMP")
		if native_tmp != "":
			stripped = native_tmp.replace("\\", "/").rstrip("/") + "/" + tm.get_string(1)
	var is_absolute: bool = stripped.begins_with("/") or stripped.substr(1).contains(":")
	if is_absolute:
		return stripped
	var project_dir: String = ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	var repo_root: String = project_dir.get_base_dir()
	return repo_root + "/" + stripped

## Write a recorded game to disk ("res://", "user://", project-relative or native).
static func save_log(path: String, header: Dictionary, calls: Array) -> bool:
	var native: String = resolve_path(path)
	if not native.begins_with("user://") and not native.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(native.get_base_dir())
	var f := FileAccess.open(native, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(log_json(header, calls))
	f.close()
	return true

# --- load and replay ---

## Parse a JSONL log. Returns {ok, reason, header, calls}. Malformed lines,
## unknown record kinds and schema drift are hard failures.
static func load_log(path: String) -> Dictionary:
	var f := FileAccess.open(resolve_path(path), FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "cannot open %s" % path, "header": {}, "calls": []}
	var text: String = f.get_as_text()
	f.close()
	var header := {}
	var calls: Array = []
	var n := 0
	for raw in text.split("\n"):
		var ln: String = String(raw).strip_edges()
		if ln == "":
			continue
		n += 1
		var parsed = JSON.parse_string(ln)
		if parsed == null or not (parsed is Dictionary):
			return {"ok": false, "reason": "line %d is not a JSON object" % n, "header": header, "calls": calls}
		var d: Dictionary = parsed
		match String(d.get("kind", "")):
			KIND_HEADER:
				if not header.is_empty():
					return {"ok": false, "reason": "multiple header lines", "header": header, "calls": calls}
				header = d
			KIND_CALL:
				calls.append(d)
			_:
				return {"ok": false, "reason": "line %d has unknown kind %s" % [n, str(d.get("kind", ""))], "header": header, "calls": calls}
	if header.is_empty():
		return {"ok": false, "reason": "no header line", "header": {}, "calls": calls}
	if int(header.get("schema", 0)) != SCHEMA:
		return {"ok": false, "reason": "schema %s unsupported (want %d)" % [str(header.get("schema")), SCHEMA], "header": header, "calls": calls}
	return {"ok": true, "reason": "", "header": header, "calls": calls}

## Rebuild the engine a log was recorded against (settings + names + seed).
static func engine_from_header(header: Dictionary):
	var s = apply_settings(header.get("settings", {}))
	var names: Array = header.get("names", default_names())
	if (names as Array).size() < 2:
		names = default_names()
	var E = load("res://core/engine.gd")
	var e = E.new()
	e.setup(s, names)
	return e

## Replay a loaded log. Returns {ok, reason, engine, plies, fingerprint}.
static func replay(loaded: Dictionary, allow_version_mismatch: bool = false) -> Dictionary:
	if not bool(loaded.get("ok", false)):
		return {"ok": false, "reason": String(loaded.get("reason", "bad log")), "engine": null, "plies": 0, "fingerprint": ""}
	var header: Dictionary = loaded["header"]
	var calls: Array = loaded["calls"]

	if not allow_version_mismatch:
		var want: String = String(header.get("godot_version", ""))
		if want != "" and want != godot_version():
			return {"ok": false, "reason": "engine build mismatch: log=%s this=%s" % [want, godot_version()], "engine": null, "plies": 0, "fingerprint": ""}

	var e = engine_from_header(header)
	var fp0: String = String(header.get("fingerprint0", ""))
	if fp0 != "":
		var got0: String = fingerprint(e)
		if got0 != fp0:
			return {"ok": false, "reason": "initial state diverged (settings/names not restored): %s != %s" % [got0, fp0], "engine": e, "plies": 0, "fingerprint": got0}

	for i in calls.size():
		var c: Dictionary = calls[i]
		var pid: int = int(c.get("pid", -1))
		var action: String = String(c.get("action", ""))
		var params: Dictionary = normalize_params(action, c.get("params", {}))
		var res: Dictionary = e.submit_intent(pid, action, params)
		if not bool(res.get("ok", false)):
			# A recorded intent that ALREADY failed at record time may fail again
			# (the log stores that outcome). A recorded SUCCESS failing here is
			# divergence.
			if bool(c.get("ok", true)):
				return {"ok": false, "reason": "intent %d (%s by pid %d) rejected on replay: %s" % [i, action, pid, str(res.get("reason", ""))], "engine": e, "plies": i, "fingerprint": fingerprint(e)}
			var p: Dictionary = load("res://seats/minimal_action.gd").pick(e, pid)
			if not p.is_empty():
				var pa: String = String(p["action"])
				e.submit_intent(pid, pa, normalize_params(pa, p.get("params", {})))

	var got: String = fingerprint(e)
	var want_fp: String = String(header.get("fingerprint", ""))
	if want_fp != "" and got != want_fp:
		return {"ok": false, "reason": "final state diverged: %s != %s" % [got, want_fp], "engine": e, "plies": calls.size(), "fingerprint": got}
	return {"ok": true, "reason": "", "engine": e, "plies": calls.size(), "fingerprint": got}

## Verify one file end to end.
static func verify_file(path: String, allow_version_mismatch: bool = false) -> Dictionary:
	var loaded: Dictionary = load_log(path)
	var out: Dictionary = replay(loaded, allow_version_mismatch)
	out["path"] = path
	out["game"] = String((loaded.get("header", {}) as Dictionary).get("game", ""))
	out["calls"] = (loaded.get("calls", []) as Array).size()
	return out

## Verify every *.jsonl in the given directory (or array of dirs/files).
static func verify_all(targets) -> Dictionary:
	var files: Array = []
	var list: Array = targets if targets is Array else [targets]
	for target in list:
		var t: String = String(target)
		if t.ends_with(".jsonl"):
			files.append(t)
			continue
		var native_dir: String = resolve_path(t)
		var dir := DirAccess.open(native_dir)
		if dir == null:
			return {"ok": false, "reason": "cannot open directory %s" % t, "files": [], "failed": []}
		var names := dir.get_files()
		names.sort()
		for name in names:
			if String(name).ends_with(".jsonl"):
				files.append(native_dir.rstrip("/") + "/" + String(name))
	if files.is_empty():
		return {"ok": false, "reason": "no .jsonl logs found in %s" % str(targets), "files": [], "failed": []}
	var failed: Array = []
	var results: Array = []
	for path in files:
		var r: Dictionary = verify_file(String(path))
		results.append(r)
		if not bool(r.get("ok", false)):
			failed.append(r)
	return {
		"ok": failed.is_empty(),
		"reason": "" if failed.is_empty() else "%d of %d logs diverged" % [failed.size(), files.size()],
		"files": results,
		"failed": failed,
	}
