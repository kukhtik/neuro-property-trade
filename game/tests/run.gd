extends SceneTree
## Headless test runner.
##
## Usage:  godot --headless --path game --script res://tests/run.gd
##
## Each test module (e.g. board_test.gd) exposes a static `test_list()`
## returning Array[String] of test-function names. Each test runs as a
## static func returning ""/null on pass, or an error string on failure.
## No test-class framework (project convention: plain functions).

var _failures: Array = []
var _count: int = 0

func _init() -> void:
	print("=== Neuro Property Trade — headless tests ===")
	var modules: Array[String] = [
		"res://tests/board_test.gd",
		"res://tests/rng_test.gd",
		"res://tests/player_test.gd",
		"res://tests/event_log_test.gd",
		"res://tests/ascii_board_test.gd",
		"res://tests/card_test.gd",
		"res://tests/game_settings_test.gd",
		"res://tests/engine_test.gd",
		"res://tests/seats_test.gd",
		"res://tests/sdk_test.gd",
		"res://tests/admin_test.gd",
		"res://tests/admin_controller_test.gd",
		"res://tests/snapshot_test.gd",
		"res://tests/tony_test.gd",
		"res://tests/visual_layout_test.gd",
		"res://tests/theme_test.gd",
		"res://tests/overlay_test.gd",
		"res://tests/voice_test.gd",
		"res://tests/admin_gate_test.gd",
		"res://tests/player_identity_test.gd",
	]
	for path in modules:
		_run_module(path)
	_summary()
	quit(0 if _failures.size() == 0 else 1)

func _run_module(path: String) -> void:
	var mod: GDScript = load(path)
	if mod == null:
		_failures.append("cannot load %s" % path)
		return
	var names: Array = mod.call("test_list")
	for test_name in names:
		_count += 1
		var err: Variant = mod.call(test_name)
		if err != null and err != "":
			_failures.append("%s :: %s" % [path.get_file(), test_name])
			push_error("%s :: %s :: %s" % [path.get_file(), test_name, err])

func _summary() -> void:
	print("---")
	print("ran %d tests, %d failed" % [_count, _failures.size()])
	if _failures.size() == 0:
		print("ALL TESTS PASSED")
	else:
		for f in _failures:
			push_error(f)
