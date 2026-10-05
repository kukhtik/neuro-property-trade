extends RefCounted
## Determinism / replay-infrastructure tests (tools/replay.gd and the corpus policy).
##
## These guard the property the whole replay story rests on: the decision
## sequence fully determines a game, so the same seed + same decisions == the
## same bytes of state - and a divergence is always DETECTED, never silently
## ignored.

const DReplay := preload("res://tools/replay.gd")

static func test_list() -> Array[String]:
	return [
		"test_fingerprint_is_stable_and_sensitive",
		"test_same_seed_same_state",
		"test_replay_roundtrip",
		"test_replay_detects_tampered_action",
		"test_replay_detects_tampered_amount",
		"test_replay_detects_tampered_seed",
		"test_replay_rejects_bad_logs",
		"test_json_params_are_coerced",
		"test_corpus_policy_decisions_are_legal",
		"test_corpus_feature_shape",
		"test_policy_rolls_terminates_game",
		"test_cli_path_contract",
		"test_verify_all_empty_dir_is_a_failure",
	]

static func _play(seed_v: int, plies: int = 400, auctions: bool = true) -> Dictionary:
	return DReplay.play({"seed": seed_v, "game": "t%03d" % seed_v, "max_plies": plies, "auctions": auctions})

static func test_fingerprint_is_stable_and_sensitive() -> String:
	var a = _play(4242)["engine"]
	var fp1: String = DReplay.fingerprint(a)
	var fp2: String = DReplay.fingerprint(a)
	if fp1 != fp2:
		return "fingerprint of an unchanged engine is not stable"
	if fp1.length() != 64:
		return "want a 64-char sha256 hex, got %d chars" % fp1.length()
	var b = _play(4243)["engine"]
	if DReplay.fingerprint(b) == fp1:
		return "two different seeds produced the same fingerprint"
	return ""

static func test_same_seed_same_state() -> String:
	var r1 = _play(10001)
	var r2 = _play(10001)
	if String(r1["header"]["fingerprint"]) != String(r2["header"]["fingerprint"]):
		return "same seed diverged: %s vs %s" % [str(r1["header"]["fingerprint"]), str(r2["header"]["fingerprint"])]
	if DReplay.line(r1["header"]) != DReplay.line(r2["header"]):
		return "same seed produced a different header"
	if (r1["calls"] as Array).size() != (r2["calls"] as Array).size():
		return "same seed produced a different decision count"
	return ""

static func test_replay_roundtrip() -> String:
	var rec = _play(10001)
	var path := "user://replay_test_roundtrip.jsonl"
	if not DReplay.save_log(path, rec["header"], rec["calls"]):
		return "could not write the log"
	var res: Dictionary = DReplay.verify_file(path)
	if not bool(res.get("ok", false)):
		return "replay diverged: %s" % str(res.get("reason", ""))
	if String(res.get("fingerprint", "")) != String(rec["header"]["fingerprint"]):
		return "replayed fingerprint differs from the recorded one"
	if int(res.get("plies", 0)) != (rec["calls"] as Array).size():
		return "replayed %d of %d decisions" % [int(res.get("plies", 0)), (rec["calls"] as Array).size()]
	return ""

static func _mutate(rec: Dictionary, mode: String) -> Dictionary:
	var header: Dictionary = (rec["header"] as Dictionary).duplicate(true)
	var calls: Array = (rec["calls"] as Array).duplicate(true)
	match mode:
		"action":
			var ca: Dictionary = calls[0]
			ca["action"] = "pass" if String(ca.get("action", "")) != "pass" else "roll"
			ca["params"] = {}
			calls[0] = ca
		"amount":
			var cm: Dictionary = calls[0]
			cm["action"] = "bid"
			cm["params"] = {"amount": 987654}
			calls[0] = cm
		"seed":
			header["seed"] = 314159
			var s: Dictionary = header["settings"]
			s["rng_seed"] = 314159
			header["settings"] = s
	return {"ok": true, "header": header, "calls": calls}

static func test_replay_detects_tampered_action() -> String:
	var res: Dictionary = DReplay.replay(_mutate(_play(10001), "action"))
	if bool(res.get("ok", false)):
		return "a flipped action replayed clean - the checker is blind"
	return ""

static func test_replay_detects_tampered_amount() -> String:
	var res: Dictionary = DReplay.replay(_mutate(_play(10001), "amount"))
	if bool(res.get("ok", false)):
		return "a bogus bid amount replayed clean - the checker is blind"
	return ""

static func test_replay_detects_tampered_seed() -> String:
	var res: Dictionary = DReplay.replay(_mutate(_play(10001), "seed"))
	if bool(res.get("ok", false)):
		return "a changed seed replayed clean - the seed gate is broken"
	return ""

static func test_replay_rejects_bad_logs() -> String:
	var f = FileAccess.open("user://replay_bad_empty.jsonl", FileAccess.WRITE)
	f.store_string("")
	f.close()
	var r1: Dictionary = DReplay.replay(DReplay.load_log("user://replay_bad_empty.jsonl"))
	if bool(r1.get("ok", false)):
		return "an empty log was accepted"

	f = FileAccess.open("user://replay_bad_noheader.jsonl", FileAccess.WRITE)
	f.store_string("{\"kind\":\"call\",\"pid\":0,\"action\":\"roll\",\"params\":{}}\n")
	f.close()
	var r2: Dictionary = DReplay.replay(DReplay.load_log("user://replay_bad_noheader.jsonl"))
	if bool(r2.get("ok", false)):
		return "a headerless log was accepted"

	f = FileAccess.open("user://replay_bad_json.jsonl", FileAccess.WRITE)
	f.store_string("{\"kind\":\"header\",\"schema\":1}\n{not json}\n")
	f.close()
	var r3: Dictionary = DReplay.replay(DReplay.load_log("user://replay_bad_json.jsonl"))
	if bool(r3.get("ok", false)):
		return "a malformed line was accepted"

	f = FileAccess.open("user://replay_bad_schema.jsonl", FileAccess.WRITE)
	f.store_string("{\"kind\":\"header\",\"schema\":99,\"names\":[\"A\",\"B\"]}\n")
	f.close()
	var r4: Dictionary = DReplay.replay(DReplay.load_log("user://replay_bad_schema.jsonl"))
	if bool(r4.get("ok", false)):
		return "an unsupported schema was accepted"
	return ""

static func test_json_params_are_coerced() -> String:
	# Simulate what a JSON round-trip does to an intent: floats everywhere.
	var raw := {"tile": 7.0, "give_tiles": [1.0, 3.0], "accept": "true", "amount": 250.0}
	var p: Dictionary = DReplay.normalize_params("propose_trade", raw)
	if typeof(p["tile"]) != TYPE_INT:
		return "tile should be an int, got %s" % type_string(typeof(p["tile"]))
	if typeof(p["give_tiles"]) != TYPE_ARRAY or typeof((p["give_tiles"] as Array)[0]) != TYPE_INT:
		return "give_tiles entries should be ints"
	if typeof(p["accept"]) != TYPE_BOOL or p["accept"] != true:
		return "a stringified bool should coerce to true"
	if typeof(p["amount"]) != TYPE_INT or p["amount"] != 250:
		return "amount should be an int 250"
	# settings too: rng_seed must land as an int or the engine never seeds the Rng
	var s: Dictionary = DReplay.coerce_settings({"rng_seed": 424242.0, "doubles": "false", "tile_count": 40.0})
	if typeof(s["rng_seed"]) != TYPE_INT or s["rng_seed"] != 424242:
		return "rng_seed should coerce to int 424242, got %s" % str(s["rng_seed"])
	if typeof(s["doubles"]) != TYPE_BOOL or s["doubles"] != false:
		return "a stringified bool setting should coerce to false"
	return ""

static func test_corpus_policy_decisions_are_legal() -> String:
	var rec = _play(2026, 150)
	var calls: Array = rec["calls"]
	if calls.is_empty():
		return "policy recorded no decisions"
	for i in calls.size():
		var c: Dictionary = calls[i]
		var legal: Array = c.get("legal", [])
		if legal.is_empty():
			return "call %d has no legal set" % i
		if not legal.has(String(c.get("action", ""))):
			return "call %d: action %s was not legal (%s)" % [i, str(c.get("action", "")), str(legal)]
	return ""

static func test_corpus_feature_shape() -> String:
	var rec = _play(777, 150)
	var saw_purchase := false
	for c in rec["calls"]:
		var call: Dictionary = c
		var feat: Dictionary = call.get("features", {})
		for key in ["phase", "money", "position", "owned_count", "opponents", "decision"]:
			if not feat.has(key):
				return "features missing '%s' in phase %s" % [key, str(call.get("phase", ""))]
		if String(call.get("phase", "")) in ["PURCHASE_WAIT", "AUCTION"]:
			var d: Dictionary = feat["decision"]
			for key in ["index", "cost", "rent", "group", "completes_set"]:
				if not d.has(key):
					return "decision features missing '%s'" % key
			saw_purchase = true
	if not saw_purchase:
		return "no purchase/auction decision appeared in 150 plies"
	return ""

static func test_policy_rolls_terminates_game() -> String:
	# A policy that never rolls would stall the recorder; assert real progress.
	var rec = _play(31337, 200)
	var rolls := 0
	var plies := 0
	for c in rec["calls"]:
		plies += 1
		if String((c as Dictionary).get("action", "")) == "roll":
			rolls += 1
	if rolls < 10:
		return "only %d rolls in %d decisions - the policy is not driving the game" % [rolls, plies]
	if String(rec.get("end_reason", "")) == "stalled":
		return "the policy stalled the game"
	return ""

static func test_cli_path_contract() -> String:
	# The CLIs are driven from a shell. Three shapes must resolve to a writable
	# native path, or CI silently emits nothing (this caught a real bug: a
	# Git-bash "/c/Users/..." path opened a nonexistent directory and the corpus
	# step reported "no logs found" while still exiting 0).
	var cases := {
		"res://": "res://core/engine.gd",
		"user://": "user://replay_test_roundtrip.jsonl",
	}
	for label in cases:
		if DReplay.resolve_path(cases[label]) != cases[label]:
			return "%s paths must pass through untouched" % label
	var project_dir: String = ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	var repo_root: String = project_dir.get_base_dir()
	if DReplay.resolve_path("corpus/games/x.jsonl") != repo_root + "/corpus/games/x.jsonl":
		return "a project-relative path must resolve under the repo root, got %s" % DReplay.resolve_path("corpus/games/x.jsonl")
	if DReplay.resolve_path("/c/tmp/x.jsonl") != "C:/tmp/x.jsonl":
		return "an MSYS drive path must be translated, got %s" % DReplay.resolve_path("/c/tmp/x.jsonl")
	if DReplay.resolve_path("C:/tmp/x.jsonl") != "C:/tmp/x.jsonl":
		return "a native absolute path must pass through, got %s" % DReplay.resolve_path("C:/tmp/x.jsonl")
	# A bare MSYS temp path (shell `mktemp -d` -> "/tmp/tmp.XXXX") has no drive
	# letter: Godot cannot resolve it at all, so it maps onto the engine's temp dir.
	var native_tmp: String = OS.get_environment("TEMP").replace("\\", "/").rstrip("/")
	if native_tmp != "":
		var got_tmp: String = DReplay.resolve_path("/tmp/tmp.abc/g.jsonl")
		if got_tmp != native_tmp + "/tmp.abc/g.jsonl":
			return "a bare /tmp path must map onto the engine temp dir, got %s" % got_tmp
		# and it must actually be usable
		var tmp_target: String = "/tmp/npt_path_contract/x.jsonl"
		if not DReplay.save_log(tmp_target, {"kind": "header", "schema": 1, "godot_version": DReplay.godot_version(), "game": "tmp", "seed": 1, "names": ["A", "B"], "settings": {}, "fingerprint0": "", "fingerprint": ""}, []):
			return "save_log refused a /tmp target (%s)" % DReplay.resolve_path(tmp_target)
		if not bool(DReplay.load_log(tmp_target).get("ok", false)):
			return "the log written through /tmp could not be read back"
	# and the resolved path must be actually writable through the log API
	var target: String = "build/replay_path_contract/x.jsonl"
	if not DReplay.save_log(target, {"kind": "header", "schema": 1, "godot_version": DReplay.godot_version(), "game": "path", "seed": 1, "names": ["A", "B"], "settings": {}, "fingerprint0": "", "fingerprint": ""}, []):
		return "save_log refused a project-relative target"
	var loaded: Dictionary = DReplay.load_log(target)
	if not bool(loaded.get("ok", false)):
		return "the written log could not be read back: %s" % str(loaded.get("reason", ""))
	return ""

static func test_verify_all_empty_dir_is_a_failure() -> String:
	# "nothing was checked" must not be reported as success: CI would go green
	# while verifying an empty directory (found when the corpus step wrote to an
	# unresolvable /tmp path and --verify-all happily printed REPLAY OK).
	var empty: String = "user://replay_empty_dir"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(empty))
	var res: Dictionary = DReplay.verify_all(empty)
	if bool(res.get("ok", false)):
		return "verify_all on an empty directory reported success"
	if String(res.get("reason", "")) == "":
		return "verify_all on an empty directory gave no reason"
	# a nonexistent directory must fail too, and say why
	var missing: Dictionary = DReplay.verify_all("user://replay_missing_dir_xyz")
	if bool(missing.get("ok", false)):
		return "verify_all on a missing directory reported success"
	if not String(missing.get("reason", "")).contains("cannot open"):
		return "a missing directory should report 'cannot open', got '%s'" % String(missing.get("reason", ""))
	return ""
