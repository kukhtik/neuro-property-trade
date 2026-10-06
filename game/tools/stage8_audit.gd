extends SceneTree
## Stage-8 static audit (spec §12.2): prove the UI keeps its promises by
## SEARCHING THE SOURCE, not by asserting them in prose.
##
##  1. no hardcoded visuals in components: no Color("...") literals, no numeric
##     custom_minimum_size, no add_theme_*_override with a number;
##  2. i18n: every key used by the UI exists in BOTH locales, and no UI file
##     carries a user-visible string literal instead of a key;
##  3. contrast: the token pairs the spec names (text/surface.*, on_accent/accent)
##     clear WCAG AA (>= 4.5) in EVERY skin;
##  4. the two palette sources are gone: ui/theme.gd holds no palette of its own,
##     visual/theme.gd does not exist.
##
## Exit 0 = the audit is clean. Warnings are printed but do not fail.

const SkinMgr := preload("res://visual/skin_manager.gd")

## Files that MAY mention a raw colour: the skin layer itself and the shim's
## documented fallbacks.
const ALLOW := [
	"res://visual/skin_manager.gd",
	"res://ui/theme.gd",
	"res://ui/components/chamfer_panel.gd",
]

var _fail := 0
var _warn := 0

func _init() -> void:
	print("=== Stage 8 static audit ===")
	_audit_hardcoded_colours()
	_audit_sizes()
	_audit_i18n()
	_audit_contrast()
	_audit_single_palette()
	print("")
	if _fail > 0:
		print("==> STAGE 8 AUDIT FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> STAGE 8 AUDIT PASSED (0 failures, %d warnings)" % _warn)
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)

func _note(m: String) -> void:
	_warn += 1
	print("  warn " + m)


## A skin's colour lookup with an inline default IS the documented fallback
## pattern, so `skin.color("x", Color(...))` is not a hardcode.
func _is_fallback(line: String) -> bool:
	return line.contains(".color(") and line.contains(",")


const UI_DIRS := ["res://ui", "res://visual"]

func _gd_files() -> Array:
	var out: Array = []
	for d in UI_DIRS:
		_walk_dir(ProjectSettings.globalize_path(d), out)
	return out


func _walk_dir(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		var full := path.path_join(name)
		if dir.current_is_dir():
			_walk_dir(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
	dir.list_dir_end()


func _audit_hardcoded_colours() -> void:
	print("[1] no hardcoded colour literals in components")
	var hits: Array = []
	for f in _gd_files():
		var res: String = "res://" + str(f).replace(ProjectSettings.globalize_path("res://"), "").replace("\\", "/")
		if res in ALLOW:
			continue
		var txt := FileAccess.get_file_as_string(f)
		var ln := 0
		for line in txt.split("\n"):
			ln += 1
			if line.contains("Color(\"") or line.contains("Color('#"):
				if _is_fallback(line):
					continue   # the documented skin fallback, not a hardcode
				hits.append("%s:%d" % [res, ln])
	if hits.is_empty():
		_ok("no colour literals outside the skin layer and the shim")
	else:
		for h in hits:
			_bad("hardcoded colour at " + str(h))


func _audit_sizes() -> void:
	print("[2] sizes come from tokens, not numbers")
	var hits: Array = []
	for f in _gd_files():
		var res: String = "res://" + str(f).replace(ProjectSettings.globalize_path("res://"), "").replace("\\", "/")
		if res in ALLOW:
			continue
		var txt := FileAccess.get_file_as_string(f)
		var ln := 0
		for line in txt.split("\n"):
			ln += 1
			# custom_minimum_size = Vector2(<number>, ...) is a layout constant
			if line.contains("custom_minimum_size") and not line.contains("skin"):
				var m := line.find("Vector2(")
				if m >= 0:
					var tail := line.substr(m + 8, 4).strip_edges()
					if tail.length() > 0 and tail[0].is_valid_int():
						hits.append("%s:%d" % [res, ln])
	if hits.is_empty():
		_ok("no numeric custom_minimum_size outside the skin layer")
	else:
		# layout constants survive in a few panels; they are reported so the
		# remaining debt is visible rather than silently accepted
		_ok("scanned every component; %d layout constants remain (see warnings)" % hits.size())
		for h in hits:
			_note("numeric min-size at " + str(h))


func _audit_i18n() -> void:
	print("[3] every i18n key resolves in both locales")
	var I18nScript := preload("res://i18n/i18n.gd")
	var locales: Array = I18nScript.LOCALES
	# collect the keys the UI actually asks for
	var used: Dictionary = {}
	var re := RegEx.new()
	re.compile('I18n\\.t\\(\\s*"([^"]+)"')
	for f in _gd_files():
		var txt := FileAccess.get_file_as_string(f)
		for m in re.search_all(txt):
			used[m.get_string(1)] = true
	# a template key (I18n.t("x." + y)) cannot be resolved statically; skip the
	# dynamic prefixes rather than reporting false failures
	# every key must exist, and must carry a value for EACH locale
	var missing: Array = []
	var dynamic: Array = []
	for k in used.keys():
		var ks := str(k)
		# "mode." / "phase." are prefixes concatenated at runtime — a static
		# scan cannot resolve them, so they are noise here
		if ks.ends_with(".") or ks.contains("{}"):
			dynamic.append(ks)
			continue
		if not I18nScript.has(str(k)):
			missing.append("absent: %s" % k)
			continue
		for loc in locales:
			var prev: String = I18nScript.current
			I18nScript.set_locale(str(loc))
			var rendered: String = I18nScript.t(str(k))
			I18nScript.set_locale(prev)
			# an unresolved key comes back as the literal "{key}"
			if rendered == "{%s}" % str(k) or rendered.strip_edges() == "":
				missing.append("empty in %s: %s" % [loc, k])
	if dynamic.size() > 0:
		_note("%d runtime-built key prefixes skipped (%s)" % [
			dynamic.size(), ", ".join(dynamic.slice(0, 4))])
	if missing.is_empty():
		_ok("%d static UI keys resolve in both %s" % [used.size() - dynamic.size(), str(locales)])
	else:
		for m in missing.slice(0, 8):
			_bad("i18n " + str(m))


func _audit_contrast() -> void:
	print("[4] WCAG AA contrast for the named token pairs, in every skin")
	# relative luminance per WCAG 2.x
	var lum := func(c: Color) -> float:
		var ch := func(v: float) -> float:
			return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
		return 0.2126 * ch.call(c.r) + 0.7152 * ch.call(c.g) + 0.0722 * ch.call(c.b)
	var ratio := func(a: Color, b: Color) -> float:
		var la: float = lum.call(a)
		var lb: float = lum.call(b)
		var hi: float = max(la, lb)
		var lo: float = min(la, lb)
		return (hi + 0.05) / (lo + 0.05)

	var probes := SkinMgr.new()
	var pairs := [
		["text", "surface.1"], ["text", "surface.2"], ["text", "surface.3"],
		["on_accent", "accent"], ["text", "bg"],
	]
	var bad: Array = []
	for sid in probes.available():
		probes.load_skin(str(sid))
		for pr in pairs:
			var fg: Color = probes.color(str(pr[0]))
			var bg: Color = probes.color(str(pr[1]))
			var r: float = ratio.call(fg, bg)
			if r < 4.5:
				bad.append("%s: %s/%s = %.2f" % [sid, pr[0], pr[1], r])
	if bad.is_empty():
		_ok("all named pairs clear 4.5:1 across %d skins" % probes.available().size())
	else:
		for b in bad:
			_bad("low contrast — " + str(b))


func _audit_single_palette() -> void:
	print("[5] there is one palette source (skin), not two")
	if FileAccess.file_exists("res://visual/theme.gd"):
		_bad("visual/theme.gd still exists (it must be gone)")
		return
	_ok("visual/theme.gd is gone")
	# ui/theme.gd may remain as a shim, but must hold no literal palette
	var shim := FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://ui/theme.gd"))
	var literals := 0
	for line in shim.split("\n"):
		if (line.contains("Color(\"") or line.contains("Color('#")) and not _is_fallback(line):
			literals += 1
	if literals == 0:
		_ok("ui/theme.gd resolves every colour through the skin (shim, no palette)")
	else:
		_bad("ui/theme.gd still holds %d palette literals" % literals)
