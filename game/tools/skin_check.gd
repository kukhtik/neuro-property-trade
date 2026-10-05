extends SceneTree
## Skin validator — `--skin-check <id>` (spec §4.6).
##
##   godot --headless --path game --script res://tools/skin_check.gd -- <id>
##   godot --headless --path game --script res://tools/skin_check.gd -- --all
##
## Checks: JSON validity, extends resolution, slot file existence, image size
## limits, 9-slice margins, and WCAG AA contrast for the token pairs that carry
## text. Exit code != 0 when there are ERRORS; warnings are listed separately
## and do not fail the run.

const SM := preload("res://visual/skin_manager.gd")

const MAX_SLOT_BYTES := 256 * 1024          # ≤ 256 KB per raster asset
const MAX_SKIN_BYTES := 2 * 1024 * 1024     # ≤ 2 MB for the whole skin

var _errors: Array[String] = []
var _warnings: Array[String] = []

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var targets: Array[String] = []
	for a in args:
		if a == "--all":
			var sm := SM.new()
			for id in sm.available():
				targets.append(id)
		elif not a.begins_with("--"):
			targets.append(a)
	if targets.is_empty():
		targets = ["default", "neuro", "evil"]

	for id in targets:
		_check(id)

	print("")
	if _warnings.size() > 0:
		print("WARNINGS (%d):" % _warnings.size())
		for w in _warnings:
			print("  ! " + w)
	if _errors.size() > 0:
		print("ERRORS (%d):" % _errors.size())
		for e in _errors:
			print("  x " + e)
		print("==> SKIN CHECK FAILED")
		quit(1)
	else:
		print("==> SKIN CHECK PASSED (%d skins, 0 errors, %d warnings)" % [targets.size(), _warnings.size()])
		quit(0)


func _check(id: String) -> void:
	print("--- skin: %s" % id)
	var path := SM.SKINS_DIR + id + "/skin.json"
	if not FileAccess.file_exists(path):
		_errors.append("%s: no skin.json" % id)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		_errors.append("%s: skin.json is not a JSON object" % id)
		return

	# extends must resolve
	var parent := str(parsed.get("extends", ""))
	if parent != "" and not FileAccess.file_exists(SM.SKINS_DIR + parent + "/skin.json"):
		_errors.append("%s: extends '%s' does not exist" % [id, parent])

	var sm := SM.new()
	if not sm.load_skin(id):
		_errors.append("%s: SkinManager could not load it" % id)
		return

	_check_slots(id, parsed, sm)
	_check_contrast(id, sm)
	_check_size_budget(id)

	# token sanity: sizes ascend, space is a list
	_check_metrics(id, sm)


func _check_slots(id: String, parsed: Dictionary, sm) -> void:
	var slots: Variant = parsed.get("slots", {})
	if not (slots is Dictionary):
		return
	var dict: Dictionary = slots
	if dict.is_empty():
		_warnings.append("%s: ships no asset slots (everything is procedural)" % id)
		return
	for slot_id in dict:
		var s: Variant = dict[slot_id]
		if not (s is Dictionary):
			continue
		var sd: Dictionary = s
		var tex := str(sd.get("tex", ""))
		if tex == "":
			continue
		var full := tex if tex.begins_with("res://") else SM.SKINS_DIR + id + "/" + tex
		if not FileAccess.file_exists(full):
			_errors.append("%s: slot '%s' -> missing file %s" % [id, slot_id, full])
			continue
		# raster size limits (owner: prefer SVG, small PNG allowed)
		var ext := full.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp"]:
			var size_bytes := _file_size(full)
			if size_bytes > MAX_SLOT_BYTES:
				_errors.append("%s: slot '%s' is %d KB (limit %d KB)" % [id, slot_id, size_bytes / 1024, MAX_SLOT_BYTES / 1024])
		# 9-slice needs explicit margins
		if sd.has("mode") and str(sd["mode"]) == "slice" and not sd.has("margins"):
			_errors.append("%s: slot '%s' is a 9-slice but has no margins" % [id, slot_id])


## WCAG AA (>= 4.5:1) for the text-on-surface pairs that carry real copy.
func _check_contrast(id: String, sm) -> void:
	var pairs := [
		["text", "surface.1"], ["text", "surface.2"], ["muted", "surface.1"],
		["on_accent", "accent"], ["money", "surface.1"],
	]
	for p in pairs:
		var fg: Color = sm.color(p[0], Color.BLACK)
		var bg: Color = sm.color(p[1], Color.BLACK)
		var ratio := _contrast(fg, bg)
		if ratio < 4.5:
			_errors.append("%s: contrast %s on %s = %.2f (need >= 4.5)" % [id, p[0], p[1], ratio])
		elif ratio < 7.0:
			_warnings.append("%s: contrast %s on %s = %.2f (AA ok, below AAA 7.0)" % [id, p[0], p[1], ratio])


func _check_size_budget(id: String) -> void:
	var dir_path := SM.SKINS_DIR + id
	var total := _dir_size(dir_path)
	if total > MAX_SKIN_BYTES:
		_errors.append("%s: skin folder is %d KB (limit %d KB)" % [id, total / 1024, MAX_SKIN_BYTES / 1024])


func _check_metrics(id: String, sm) -> void:
	# sizes must ascend xs < s < m < l < xl
	var order := ["xs", "s", "m", "l", "xl"]
	for i in range(1, order.size()):
		if sm.size(order[i]) <= sm.size(order[i - 1]):
			_errors.append("%s: size.%s must exceed size.%s" % [id, order[i], order[i - 1]])
	if sm.shape("chamfer") < 0.0:
		_errors.append("%s: shape.chamfer must be >= 0" % id)
	if sm.metric("corner_ratio") < 1.0:
		_errors.append("%s: metrics.corner_ratio must be >= 1.0" % id)


# --- helpers ------------------------------------------------------------------

func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


func _lum(c: Color) -> float:
	var f := func(x: float) -> float:
		return x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	return f.get_length()


func _dir_size(path: String) -> int:
	var total := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var p := path + "/" + name
			if dir.current_is_dir():
				total += _dir_size(p)
			else:
				total += _file_size(p)
		name = dir.get_next()
	dir.list_dir_end()
	return total
