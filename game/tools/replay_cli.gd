extends SceneTree
## Deterministic replay / determinism-check CLI (harness: res://tools/replay.gd).
##
##   ... --script res://tools/replay_cli.gd -- --verify FILE.jsonl
##   ... --script res://tools/replay_cli.gd -- --verify-all DIR [DIR...]
##   ... --script res://tools/replay_cli.gd -- --record OUT.jsonl --seed 10001 [--game g001] [--turns 400] [--no-auctions]
##   ... --script res://tools/replay_cli.gd            # self-test (no args)
##
## Exit 0 = every requested log replayed to its recorded fingerprint. With no
## arguments it runs a self-test that ALSO proves the checker can fail: it
## records a game, replays it, asserts same seed == same state, and asserts
## three independent mutations (flipped action, bumped amount, changed seed)
## are detected as divergence.

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
		print("replay: %d checks passed" % _checks)
		print("REPLAY OK")
		quit(0)
		return
	for f in _failures:
		printerr("replay: %s" % f)
	print("replay: %d of %d checks FAILED" % [_failures.size(), _checks])
	print("REPLAY FAILED")
	quit(1)

# --- self-test ---

func _selftest() -> void:
	print("=== replay self-test (no args) ===")
	var tmp: String = "user://replay_selftest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp))
	var path: String = tmp + "/g.jsonl"

	var rec: Dictionary = DReplay.play({"seed": 10001, "game": "selftest", "max_plies": 400})
	var plies: int = int(rec.get("plies", 0))
	_check(plies > 0, "recorded a game", "no decisions recorded")
	_check(DReplay.save_log(path, rec["header"], rec["calls"]), "log written", path)
	print("      plies=%d end=%s survivors=%s" % [plies, String(rec.get("end_reason", "")), str(rec.get("survivors", []))])

	var v1: Dictionary = DReplay.verify_file(path)
	_check(bool(v1.get("ok", false)), "replay reproduces the recorded fingerprint", String(v1.get("reason", "")))
	var v2: Dictionary = DReplay.verify_file(path)
	_check(bool(v2.get("ok", false)) and String(v2.get("fingerprint", "")) == String(v1.get("fingerprint", "")), "two replays agree on the fingerprint")
	print("      fingerprint=%s" % String(v1.get("fingerprint", "")).substr(0, 16))

	var rec2: Dictionary = DReplay.play({"seed": 10001, "game": "selftest", "max_plies": 400})
	_check(String(rec2["header"]["fingerprint"]) == String(rec["header"]["fingerprint"]), "same seed -> same final state (independent run)")
	_check(DReplay.line(rec2["header"]) == DReplay.line(rec["header"]), "same seed -> byte-identical header")

	var rec3: Dictionary = DReplay.play({"seed": 99999, "game": "selftest", "max_plies": 400})
	_check(String(rec3["header"]["fingerprint"]) != String(rec["header"]["fingerprint"]), "different seed -> different final state")

	_check(_negative_control(path, "tamper_action"), "negative control: flipped action detected")
	_check(_negative_control(path, "tamper_amount"), "negative control: bumped bid amount detected")
	_check(_negative_control(path, "tamper_seed"), "negative control: changed seed detected")

	var log: Dictionary = DReplay.load_log(path)
	var call0: Dictionary = (log["calls"] as Array)[0]
	_check(int(call0.get("pid", -1)) >= 0, "loaded call parses (JSON numbers coerced)")

func _negative_control(path: String, mode: String) -> bool:
	var loaded: Dictionary = DReplay.load_log(path)
	if not bool(loaded.get("ok", false)):
		return false
	var header: Dictionary = loaded["header"]
	var calls: Array = (loaded["calls"] as Array).duplicate(true)
	if calls.is_empty():
		return false
	match mode:
		"tamper_action":
			var c0: Dictionary = calls[0]
			c0["action"] = "pass" if String(c0.get("action", "")) != "pass" else "roll"
			c0["params"] = {}
			calls[0] = c0
		"tamper_amount":
			var c1: Dictionary = calls[0]
			c1["action"] = "bid"
			c1["params"] = {"amount": 99999}
			calls[0] = c1
		"tamper_seed":
			header["seed"] = 4242
			var s: Dictionary = header["settings"]
			s["rng_seed"] = 4242
			header["settings"] = s
	var res: Dictionary = DReplay.replay({"ok": true, "header": header, "calls": calls})
	return not bool(res.get("ok", false))

# --- argument modes ---

func _args(args: Array) -> void:
	var mode := ""
	var paths: Array = []
	var out := ""
	var seed_v := 10001
	var game := "replay"
	var turns := 400
	var auctions := true
	var allow_ver := false
	var i := 0
	while i < args.size():
		var a := String(args[i])
		match a:
			"--verify":
				mode = "verify"
			"--verify-all":
				mode = "verify-all"
			"--record":
				mode = "record"
			"--allow-version-mismatch":
				allow_ver = true
			"--seed":
				i += 1
				seed_v = int(args[i])
			"--game":
				i += 1
				game = String(args[i])
			"--turns":
				i += 1
				turns = int(args[i])
			"--no-auctions":
				auctions = false
			_:
				if a.begins_with("--"):
					print("unknown flag: %s" % a)
				elif mode == "record":
					out = a
				else:
					paths.append(a)
		i += 1

	match mode:
		"verify":
			if paths.is_empty():
				_check(false, "verify needs a file argument")
				return
			for p in paths:
				var r: Dictionary = DReplay.verify_file(String(p), allow_ver)
				_check(bool(r.get("ok", false)), "verify %s" % String(p), String(r.get("reason", "")))
				if bool(r.get("ok", false)):
					print("      game=%s calls=%d fp=%s" % [String(r.get("game", "")), int(r.get("calls", 0)), String(r.get("fingerprint", "")).substr(0, 12)])
		"verify-all":
			if paths.is_empty():
				_check(false, "verify-all needs a directory argument")
				return
			var res: Dictionary = DReplay.verify_all(paths)
			for r in res.get("files", []):
				var rr: Dictionary = r
				_check(bool(rr.get("ok", false)), "verify %s" % String(rr.get("path", "")), String(rr.get("reason", "")))
				if bool(rr.get("ok", false)):
					print("      game=%s calls=%d" % [String(rr.get("game", "")), int(rr.get("calls", 0))])
			print("==> %d logs, %d diverged" % [(res.get("files", []) as Array).size(), (res.get("failed", []) as Array).size()])
		"record":
			if out == "":
				_check(false, "record needs an output path")
				return
			var rec: Dictionary = DReplay.play({"seed": seed_v, "game": game, "max_plies": turns, "auctions": auctions})
			var ok: bool = DReplay.save_log(out, rec["header"], rec["calls"])
			_check(ok, "record %s" % out)
			if not ok:
				return
			print("      seed=%d plies=%d end=%s fp=%s" % [seed_v, int(rec.get("plies", 0)), String(rec.get("end_reason", "")), String(rec["header"]["fingerprint"]).substr(0, 12)])
			var v: Dictionary = DReplay.verify_file(out, allow_ver)
			_check(bool(v.get("ok", false)), "recorded log replays", String(v.get("reason", "")))
		_:
			_check(false, "no mode: use --verify / --verify-all / --record", str(args))
