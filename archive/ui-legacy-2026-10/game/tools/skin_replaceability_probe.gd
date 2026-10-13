extends SceneTree
## Stage-1 acceptance probe: the UI must be fully replaceable by assets.
##
## Proves the skin pipeline end-to-end:
##   1. every shipping skin loads;
##   2. the stress-skin changes colours, sizes, shape, metrics, motion AND
##      slots — so swapping skins restyles everything with no code edit;
##   3. a slot with a real file resolves to a texture, and its 9-slice margins
##      survive; a slot with no file degrades to null (procedural) without error;
##   4. the built Theme differs between skins (what components read).
##
## Exit 0 = the redesign path is open.

const SM := preload("res://visual/skin_manager.gd")

var _fail := 0

func _init() -> void:
	print("=== Stage 1 acceptance: skin replaceability ===")
	_check_all_load()
	_check_stress_changes_everything()
	_check_slots()
	_check_theme_differs()
	print("")
	if _fail > 0:
		print("==> SKIN REPLACEABILITY FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> SKIN REPLACEABILITY PASSED — full asset swap needs no code edit")
		quit(0)


func _ok(msg: String) -> void:
	print("  ok  " + msg)


func _bad(msg: String) -> void:
	_fail += 1
	print("  FAIL " + msg)


func _check_all_load() -> void:
	print("[1] every shipping skin loads")
	var sm := SM.new()
	for id in ["default", "neuro", "evil"]:
		if not sm.load_skin(id):
			_bad("skin '%s' did not load" % id)
		else:
			_ok("%s loads" % id)


func _check_stress_changes_everything() -> void:
	print("[2] stress-skin restyles everything (no code touched)")
	var base := SM.new()
	base.load_skin("neuro")
	var stress := SM.new()
	if not stress.load_skin("_stress"):
		_bad("stress-skin did not load")
		return

	var diffs := 0
	if stress.color("accent") != base.color("accent"):
		diffs += 1
	else:
		_bad("stress accent identical to neuro")
	if stress.size("m") != base.size("m"):
		diffs += 1
	else:
		_bad("stress size.m identical to neuro")
	if stress.shape("chamfer") != base.shape("chamfer"):
		diffs += 1
	else:
		_bad("stress shape.chamfer identical to neuro")
	if stress.metric("corner_ratio") != base.metric("corner_ratio"):
		diffs += 1
	else:
		_bad("stress corner_ratio identical to neuro")
	if absf(stress.motion("step") - base.motion("step")) > 0.0001:
		diffs += 1
	else:
		_bad("stress motion.step identical to neuro")
	if stress.motion_profile() != base.motion_profile():
		diffs += 1
	else:
		_bad("stress motion profile identical to neuro")
	if stress.shape("radius") != base.shape("radius"):
		diffs += 1
	else:
		_bad("stress shape.radius identical to neuro")

	if diffs >= 7:
		_ok("stress differs in colours/sizes/shape/metrics/motion/profile/radius (%d/7)" % diffs)


func _check_slots() -> void:
	print("[3] slots: real file resolves, missing slot degrades")
	var stress := SM.new()
	stress.load_skin("_stress")
	var sl = stress.slot("board.frame")
	if sl["texture"] == null:
		_bad("stress board.frame slot did not resolve to a texture")
	else:
		_ok("stress board.frame resolves to a texture")
	if not stress.has_slot("board.frame"):
		_bad("has_slot('board.frame') should be true for the stress-skin")
	if not (sl["margins"] is Array) or (sl["margins"] as Array).size() != 4:
		_bad("9-slice margins lost: %s" % str(sl["margins"]))
	else:
		_ok("9-slice margins preserved: %s" % str(sl["margins"]))

	var empty = stress.slot("deck.chance")
	if empty["texture"] != null:
		_bad("unshipped slot should be null, got a texture")
	else:
		_ok("unshipped slot degrades to null (procedural)")


func _check_theme_differs() -> void:
	print("[4] the built Theme differs between skins")
	var a := SM.new(); a.load_skin("neuro")
	var b := SM.new(); b.load_skin("_stress")
	var ta = a.theme()
	var tb = b.theme()
	if ta.default_font_size == tb.default_font_size:
		_bad("theme font size identical across skins (%d)" % ta.default_font_size)
	else:
		_ok("theme font size follows the skin (%d -> %d)" % [ta.default_font_size, tb.default_font_size])
	var ca = ta.get_stylebox("normal", "ButtonPrimary")
	var cb = tb.get_stylebox("normal", "ButtonPrimary")
	if ca is StyleBoxFlat and cb is StyleBoxFlat:
		if (ca as StyleBoxFlat).bg_color == (cb as StyleBoxFlat).bg_color:
			_bad("button colour identical across skins")
		else:
			_ok("button colour follows the skin")
