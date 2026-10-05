extends SceneTree
## Decision-corpus recorder.
##
##   godot --headless --path game --script res://tools/corpus.gd -- \
##         --out corpus/games --games 12 --seed 10000 [--turns 60] [--no-auctions]
##   godot --headless --path game --script res://tools/corpus.gd        # self-test
##
## Plays full games with the SHARED deterministic policy (res://tools/replay.gd)
## and records every decision point as a typed row:
##   phase, legal (the closed option set), action+params (the label), and the
##   features the engine had at that moment.
##
## WHY (from the backlog): a System-1/typed-decision model (Laya, ONNX) can only
## be adopted on evidence, and evidence needs recorded decisions to benchmark
## against. A learned policy is a seat like any other: the engine validates every
## intent it submits (invariant: AI can never corrupt state), so switching
## policies is a swap of the "decide()" implementation, not an engine change.
##
## Output: <out>/<game>.jsonl (replay-compatible logs, verifiable with
## res://tools/replay_cli.gd) plus <out>/index.json summarising the corpus.

const DReplay := preload("res://tools/replay.gd")

var _failures: Array = []
var _checks := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_selftest()
	else:
		_args(args)
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
		print("corpus: %d checks passed" % _checks)
		print("CORPUS OK")
		quit(0)
		return
	for f in _failures:
		printerr("corpus: %s" % f)
	print("corpus: %d of %d checks FAILED" % [_failures.size(), _checks])
	print("CORPUS FAILED")
	quit(1)

# --- corpus generation ---

const PHASES := ["TURN_START", "PURCHASE_WAIT", "AUCTION", "TRADE"]

## Generate `games` games starting at `seed_v` (seed = seed_v + i) into dir.
func generate(dir_arg: String, games: int, seed_v: int, turns: int, auctions: bool) -> Dictionary:
	# Resolve once: FileAccess/DirAccess only accept res://, user:// or native
	# absolute paths, and the CLI passes a project-relative directory.
	var dir: String = DReplay.resolve_path(dir_arg)
	DirAccess.make_dir_recursive_absolute(dir)
	var rows: Array = []
	var index_games: Array = []
	var phase_counts := {}
	var action_counts := {}
	var total_plies := 0
	var total_calls := 0

	for i in games:
		var s := seed_v + i
		var id := "g%03d" % s
		var rec: Dictionary = DReplay.play({"seed": s, "game": id, "max_plies": turns, "auctions": auctions})
		var path := dir.rstrip("/") + "/" + id + ".jsonl"
		var ok: bool = DReplay.save_log(path, rec["header"], rec["calls"])   # resolve_path: idempotent
		_check(ok, "recorded %s" % id, path)
		if not ok:
			continue
		total_plies += int(rec.get("plies", 0))
		total_calls += (rec["calls"] as Array).size()
		var histogram := {}
		for c in rec["calls"]:
			var call: Dictionary = c
			var a := String(call.get("action", ""))
			action_counts[a] = int(action_counts.get(a, 0)) + 1
			histogram[a] = int(histogram.get(a, 0)) + 1
			var ph := String(call.get("phase", ""))
			if ph != "":
				phase_counts[ph] = int(phase_counts.get(ph, 0)) + 1
		var winner := ""
		if String(rec.get("end_reason", "")) == "END_GAME":
			for sv in rec["survivors"]:
				var svd: Dictionary = sv
				if not bool(svd.get("bankrupt", false)):
					winner = String(svd.get("name", ""))
		index_games.append({
			"game": id,
			"seed": s,
			"file": id + ".jsonl",
			"plies": int(rec.get("plies", 0)),
			"end_reason": String(rec.get("end_reason", "")),
			"winner": winner,
			"fingerprint": String(rec["header"]["fingerprint"]),
			"action_histogram": histogram,
		})
		print("  %s  plies=%-4d end=%-8s winner=%-6s fp=%s" % [id, int(rec.get("plies", 0)), String(rec.get("end_reason", "")), winner, String(rec["header"]["fingerprint"]).substr(0, 12)])

	var index := {
		"kind": "corpus_index",
		"schema": DReplay.SCHEMA,
		"generated_by": "res://tools/corpus.gd",
		"godot_version": DReplay.godot_version(),
		"games": index_games,
		"totals": {
			"games": index_games.size(),
			"calls": total_calls,
			"plies": total_plies,
			"avg_plies": (float(total_plies) / float(max(index_games.size(), 1))),
			"phases": phase_counts,
			"actions": action_counts,
		},
	}
	var f := FileAccess.open(DReplay.resolve_path(dir.rstrip("/") + "/index.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(index, "  "))
		f.close()
	index["path"] = dir_arg.rstrip("/") + "/index.json"
	return index

# --- self-test ---

func _selftest() -> void:
	print("=== corpus self-test (no args) ===")
	var dir: String = "user://corpus_selftest"
	var index: Dictionary = generate(dir, 2, 10000, 60, true)
	var totals: Dictionary = index["totals"]
	_check(int(totals.get("games", 0)) == 2, "recorded 2 games")
	_check(int(totals.get("calls", 0)) > 0, "decisions recorded", str(totals))

	# every recorded decision was legal at the time (the engine never accepted junk)
	var bad := 0
	var labelled := 0
	var with_features := 0
	for g in index["games"]:
		var gd: Dictionary = g
		var loaded: Dictionary = DReplay.load_log(dir + "/" + String(gd["file"]))
		for c in loaded["calls"]:
			var call: Dictionary = c
			var legal: Array = call.get("legal", [])
			if legal.is_empty() or not legal.has(String(call.get("action", ""))):
				bad += 1
			if not (call.get("features", {}) as Dictionary).is_empty():
				with_features += 1
			labelled += 1
	_check(bad == 0, "every recorded action was legal at its decision point", "%d illegal rows" % bad)
	_check(labelled > 0, "rows carry a label (action+params)")
	_check(with_features == labelled, "every row carries typed features", "%d of %d" % [with_features, labelled])

	# every game must replay to its fingerprint
	var res: Dictionary = DReplay.verify_all(dir)
	_check(bool(res.get("ok", false)), "all recorded games replay", String(res.get("reason", "")))
	print("      totals=%s" % str(totals))

# --- argument mode ---

func _args(args: Array) -> void:
	var out := "user://corpus"
	var games := 8
	var seed_v := 10000
	var turns := 60
	var auctions := true
	var i := 0
	while i < args.size():
		var a := String(args[i])
		match a:
			"--out":
				i += 1
				out = String(args[i])
			"--games":
				i += 1
				games = int(args[i])
			"--seed":
				i += 1
				seed_v = int(args[i])
			"--turns":
				i += 1
				turns = int(args[i])
			"--no-auctions":
				auctions = false
			_:
				print("unknown arg: %s" % a)
		i += 1
	print("=== corpus: %d games from seed %d -> %s (turns=%d auctions=%s) ===" % [games, seed_v, out, turns, auctions])
	var index: Dictionary = generate(out, games, seed_v, turns, auctions)
	var totals: Dictionary = index["totals"]
	_check(int(totals.get("games", 0)) == games, "recorded %d games" % games, str(totals))
	var res: Dictionary = DReplay.verify_all(out)
	_check(bool(res.get("ok", false)), "all recorded games replay to their fingerprint", String(res.get("reason", "")))
	print("==> corpus: %d games, %d decisions, index %s" % [int(totals.get("games", 0)), int(totals.get("calls", 0)), String(index.get("path", ""))])
	print("==> action histogram: %s" % str(totals.get("actions", {})))
	print("==> phase histogram: %s" % str(totals.get("phases", {})))
