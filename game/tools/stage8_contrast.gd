extends Node
## Resolve every colour the UI actually paints with, and report the contrast that
## matters. Reading the FRAME proved unreliable: the same grey came from a border, from
## an anti-aliased edge, and from a deliberately dimmed player, and no pixel heuristic
## could tell them apart. Asking the code is exact.
##
## For each colour token and each surface it is drawn on, print the WCAG ratio. Exit 0
## when every TEXT token meets AA body on every surface it may appear over.

const UiTheme := preload("res://ui/theme.gd")

## Directories whose scripts must not bake colours in.
const SkinManager := preload("res://visual/skin_manager.gd")

## Tokens used for text. Everything else is a surface, border or state colour and is NOT
## judged by WCAG — a divider is allowed to be quiet, a dimmed player is SUPPOSED to be dim.
const TEXT_TOKENS := [
	"text", "text_dim", "muted", "accent", "accent2", "warn", "danger", "good",
	"ev.text", "ev.money", "ev.build", "ev.danger", "ev.card", "on_panel",
]
## Surfaces text can land on.
const SURFACES := ["surface.1", "surface.2", "surface.3", "panel", "panel_dark",
	"board.bg2", "board.bg3", "bg"]

var _fail := 0


func _ready() -> void:
	print("=== Stage 8 acceptance: the palette, measured ===")
	var skin := SkinManager.new()
	skin.load_skin()
	UiTheme.use_skin(skin)
	var col: Dictionary = UiTheme.COL()

	print("[1] text tokens against every surface they can sit on")
	var worst := []
	for t in TEXT_TOKENS:
		if not col.has(t):
			continue
		var fg: Color = col[t]
		for sname in SURFACES:
			if not col.has(sname):
				continue
			var bg: Color = col[sname]
			# a fully transparent token is not a colour, it is "unset"
			if fg.a < 0.5:
				continue
			var r := _ratio(fg, bg)
			worst.append([r, t, sname, fg, bg])
	worst.sort_custom(func(a, b): return a[0] < b[0])

	var bad := 0
	for row in worst:
		var r: float = row[0]
		if r < 4.5:
			bad += 1
			if bad <= 12:
				print("      %.2f:1  %-12s on %-12s  %s / %s"
					% [r, row[1], row[2], row[3].to_html(false), row[4].to_html(false)])
	if bad == 0:
		_ok("all %d text/surface pairs meet AA body (worst %.2f:1)"
			% [worst.size(), worst[0][0] if worst.size() > 0 else 0.0])
	else:
		for row in worst:
			if row[0] < 4.5:
				_bad("%s on %s is %.2f:1 (needs 4.5)"
					% [row[1], row[2], row[0]])

	print("[2] the palette has ONE source")
	# `SkinManager.FALLBACK_COLORS` is the single source: every skin resolves against it.
	# Its literals are the legal place for them. The rule that matters is that nothing ELSE
	# bakes a colour in — a copy silently drifts from the original after any edit.
	var stray := _scan_for_stray_literals()
	if stray.is_empty():
		_ok("no colour is baked in outside the one fallback table")
	else:
		for path in stray:
			_bad("colour literal baked in %s" % path)

	print("")
	if _fail > 0:
		print("==> STAGE 8 FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> STAGE 8 PASSED — palette contrast verified from the source of truth")
		get_tree().quit(0)


## Files outside the fallback table that still hard-code a 6-digit colour.
## Everything in a line before its first `#` that is not inside a string literal.
static func _strip_comment(line: String) -> String:
	var in_d := false
	var in_s := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"" and not in_s:
			in_d = not in_d
		elif ch == "'" and not in_d:
			in_s = not in_s
		elif ch == "#" and not in_d and not in_s:
			return line.substr(0, i)
	return line


func _scan_for_stray_literals() -> Array:
	var out: Array = []
	var dirs := ["res://ui", "res://visual", "res://admin"]
	var re := RegEx.new()
	re.compile("#[0-9a-fA-F]{6}")
	for d in dirs:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = d.path_join(f)
			if path.ends_with("skin_manager.gd") or path.ends_with("theme.gd"):
				continue   # the fallback table and its thin adapter ARE the source
			var txt := FileAccess.get_file_as_string(path)
			for line in txt.split("
"):
				# A COMMENT IS PROSE, NOT CODE. This check exists to find colours written into
				# the code; a comment that documents a measured pixel (#130b1f) is evidence, and
				# flagging it forced the measurements out of the explanations that justify the
				# fixes. The comment is cut before the line is searched.
				var code := _strip_comment(line)
				for m in re.search_all(code):
					# `[color=#%s]` is a FORMAT, not a literal
					var at := m.get_start()
					if code.substr(maxi(0, at - 8), 10).contains("%s"):
						continue
					out.append(path)
					break
				if not out.is_empty() and out[-1] == path:
					break
	return out




func _ratio(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _lin(x: float) -> float:
	return x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)
