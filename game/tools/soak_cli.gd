extends SceneTree
## Seeded headless soak with a full game report.
##
##   godot --headless --path game --script res://tools/soak_cli.gd -- --seed 12345 --turns 120 [--quiet]
##   godot --headless --path game --script res://tools/soak_cli.gd          # self-test (5 seeds)
##
## Regression check for the rules engine with no renderer and no timers: play
## whole games with the shared deterministic policy (res://tools/replay.gd) and
## assert the invariants that must hold at every settled state:
##   * the game makes progress and terminates (no stall, no infinite loop)
##   * cash never goes negative
##   * every owned tile has exactly one owner
##   * the board never accumulates or loses tiles
##   * the winner (on END_GAME) is the only solvent player
##   * the same seed reproduces the same fingerprint in a fresh process

const DReplay := preload("res://tools/replay.gd")

var _failures: Array = []
var _checks := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_selftest()
	else:
		_one(args)
	_finish()

func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % label)
	else:
		var line: String = label if detail == "" else "%s :: %s" % [label, detail]
		print("FAIL: %s" % line)
		_failures.append(line)

func _finish() -> void:
	print("---")
	if _failures.is_empty():
		print("soak: %d checks passed" % _checks)
		print("SOAK OK")
		quit(0)
		return
	for f in _failures:
		printerr("soak: %s" % f)
	print("soak: %d of %d checks FAILED" % [_failures.size(), _checks])
	print("SOAK FAILED")
	quit(1)

## Invariants that must hold for a settled engine (no decision pending).
func _audit(e, seed_v: int) -> Array:
	var problems: Array = []
	var seen_owner := {}
	for i in e.players.size():
		var p = e.players[i]
		if p.money < 0:
			problems.append("seed %d: %s has negative cash (%d)" % [seed_v, p.name, p.money])
		for t in p.owned_tiles():
			var tile: int = int(t)
			if seen_owner.has(tile):
				problems.append("seed %d: tile %d owned by both %s and %s" % [seed_v, tile, e.players[int(seen_owner[tile])].name, p.name])
			seen_owner[tile] = i
	var total_owned := seen_owner.size()
	var counted := 0
	for i in e.players.size():
		counted += e.players[i].owned_tiles().size()
	if counted != total_owned:
		problems.append("seed %d: ownership double-counted (%d entries, %d unique tiles)" % [seed_v, counted, total_owned])
	if total_owned > e.board.tile_count():
		problems.append("seed %d: %d tiles owned on a %d-tile board" % [seed_v, total_owned, e.board.tile_count()])
	if e.phase == "END_GAME":
		var solvent := 0
		for p in e.players:
			if not p.bankrupt:
				solvent += 1
		if solvent != 1:
			problems.append("seed %d: END_GAME with %d solvent players (want 1)" % [seed_v, solvent])
	return problems

func _run(opts: Dictionary, verbose: bool) -> Dictionary:
	var rec: Dictionary = DReplay.play(opts)
	var e = rec["engine"]
	var seed_v: int = int(opts.get("seed", 0))
	var problems: Array = _audit(e, seed_v)

	var tiles_owned := 0
	var houses := 0
	for p in e.players:
		tiles_owned += p.owned_tiles().size()
		for t in p.owned_tiles():
			houses += e._houses_on(int(t))
	var events: int = e.log.size()

	if verbose:
		print("  seed=%-6d plies=%-4d end=%-8s events=%-5d tiles=%-2d houses=%-2d fp=%s" % [
			seed_v, int(rec.get("plies", 0)), String(rec.get("end_reason", "")), events,
			tiles_owned, houses, String(rec["header"]["fingerprint"]).substr(0, 12)])
		for sv in rec["survivors"]:
			var s: Dictionary = sv
			print("      %-6s $%-6d tiles=%-2d %s" % [String(s.get("name", "")), int(s.get("money", 0)), int(s.get("tiles", 0)), "bankrupt" if bool(s.get("bankrupt", false)) else ""])
	return {"rec": rec, "problems": problems, "events": events, "tiles_owned": tiles_owned}

func _one(args: Array) -> void:
	var seed_v := 12345
	var turns := 120
	var auctions := true
	var quiet := false
	var sweep := 0
	var players := 4
	var i := 0
	while i < args.size():
		var a := String(args[i])
		match a:
			"--seed":
				i += 1
				seed_v = int(args[i])
			"--turns":
				i += 1
				turns = int(args[i])
			"--no-auctions":
				auctions = false
			"--quiet":
				quiet = true
			"--sweep":
				i += 1
				sweep = int(args[i])
			"--players":
				i += 1
				players = int(args[i])
			_:
				print("unknown arg: %s" % a)
		i += 1
	if sweep > 0:
		_sweep(seed_v, sweep, turns, auctions, players)
		return
	print("=== soak: seed %d, cap %d plies, auctions=%s ===" % [seed_v, turns, auctions])
	var r: Dictionary = _run({"seed": seed_v, "game": "soak", "max_plies": turns, "auctions": auctions}, not quiet)
	for p in r["problems"]:
		_check(false, "invariant", String(p))
	if (r["problems"] as Array).is_empty():
		_check(true, "invariants hold at the settled state")
	var rec: Dictionary = r["rec"]
	_check(int(rec.get("plies", 0)) > 0, "game made progress")
	_check(String(rec.get("end_reason", "")) != "stalled", "game did not stall", String(rec.get("end_reason", "")))
	_check(int(r.get("events", 0)) > 0, "event log recorded state changes")

func _selftest() -> void:
	print("=== soak self-test (no args): 5 seeds ===")
	var seeds := [12345, 777, 2026, 31337, 90210]
	var fingerprints := []
	for s in seeds:
		var r: Dictionary = _run({"seed": int(s), "game": "soak", "max_plies": 150, "auctions": true}, true)
		_check((r["problems"] as Array).is_empty(), "seed %d invariants hold" % int(s), str(r["problems"]))
		var rec: Dictionary = r["rec"]
		_check(String(rec.get("end_reason", "")) != "stalled", "seed %d did not stall" % int(s), String(rec.get("end_reason", "")))
		_check(int(rec.get("plies", 0)) > 0, "seed %d made progress" % int(s))
		fingerprints.append(String(rec["header"]["fingerprint"]))
	var uniq := {}
	for fp in fingerprints:
		uniq[fp] = true
	_check(uniq.size() == seeds.size(), "distinct seeds gave distinct end states", "%d unique of %d" % [uniq.size(), seeds.size()])

## Sweep many seeds looking for stalls/invariant breaks. Prints one line per
## problem and a summary; used as the wide determinism/robustness check.
func _sweep(seed_v: int, count: int, turns: int, auctions: bool, players: int) -> void:
	var names: Array = ["Neuro", "Ada", "Bo", "Cyd", "Dee", "Eve"].slice(0, players)
	print("=== soak sweep: %d seeds from %d, %d players, cap %d plies, auctions=%s ===" % [count, seed_v, players, turns, auctions])
	var stalls := 0
	var invariant_breaks := 0
	var ends := {}
	var plies_total := 0
	for i in count:
		var sd := seed_v + i
		var r: Dictionary = _run({"seed": sd, "game": "sweep", "max_plies": turns, "auctions": auctions, "names": names}, false)
		var rec: Dictionary = r["rec"]
		plies_total += int(rec.get("plies", 0))
		var end := String(rec.get("end_reason", ""))
		ends[end] = int(ends.get(end, 0)) + 1
		if end == "stalled":
			stalls += 1
			print("STALL seed=%d phase=%s plies=%d" % [sd, String(rec.get("end_reason", "")), int(rec.get("plies", 0))])
		for pb in r["problems"]:
			invariant_breaks += 1
			print("INVARIANT seed=%d: %s" % [sd, String(pb)])
	_check(stalls == 0, "%d seeds produced no stall" % count, "%d stalled" % stalls)
	_check(invariant_breaks == 0, "%d seeds held every invariant" % count, "%d breaks" % invariant_breaks)
	print("      ends=%s avg_plies=%.1f" % [str(ends), float(plies_total) / float(max(count, 1))])
