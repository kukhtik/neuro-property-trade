extends Node
## Test-ladder rung 3 commandable runner. Runs the same four scripted
## scenarios as tony_test.gd and exits 0/1 so it can be staged before a WebGL
## run.
##   godot --headless --path game res://tools/tony.tscn
func _ready() -> void:
	print("=== tony: scripted scenarios ===")
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
