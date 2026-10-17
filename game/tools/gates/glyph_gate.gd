extends Node
## GLYPH gate — every symbol a screen DRAWS must be a glyph the font HAS.
##
## WHY THIS EXISTS. The product drew 23 glyphs the default font has no shape for: all its
## pictographs (🃏🎲🏠💰📜🔍🚫 …) and most of its geometric arrows and marks (→ ▶ ◆ ✓ ✕ ↻ ⇄ ♻ ⚖ ✏).
## Godot renders each as the missing-glyph box, so the header's panels button, the settings close
## button, the admin panel and the lobby tick were all drawing a rectangle. Nobody measured it: a
## tofu box LOOKS like a deliberate icon at a glance, and the tree reports a Label with text.
##
## The check is on the FONT, not on a screenshot, because the question is exactly "does this
## codepoint have a shape" - and `has_char` answers it for the same font the screens use
## (`ThemeDB.fallback_font`, the engine default this project never overrides).
##
## Run: godot --headless --path game res://tools/gates/glyph_gate.tscn
## Verdict: ==> GLYPH PASSED/FAILED: reason

const SCAN_DIRS := ["res://ui", "res://visual", "res://i18n"]

## The glyphs a screen may draw. Every entry was checked against the font; add a new one ONLY after
## verifying it renders, or the box comes back.
const ALLOWED := "—•…‹›◊«»§×"

var _fails: Array = []
var _checked := 0
var _files := 0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	if _font == null:
		print("==> GLYPH FAILED: no fallback font to check against")
		get_tree().quit(1)
		return
	for d in SCAN_DIRS:
		_walk(d)
	_report()


func _walk(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(full)
		elif name.ends_with(".gd") and not name.ends_with(".uid"):
			_scan_file(full)
		name = d.get_next()
	d.list_dir_end()


func _scan_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	_files += 1
	# every double-quoted literal, so a glyph reaches us whether it is drawn directly or returned
	# from an i18n table
	var re := RegEx.new()
	re.compile('"([^"\\n]*)"')
	for m in re.search_all(text):
		_lit(m.get_string(1), path)


func _lit(s: String, path: String) -> void:
	for i in s.length():
		var ch: String = s[i]
		var o: int = ch.unicode_at(0)
		# letters (Latin, Cyrillic), digits, punctuation and ASCII are the font's bread and butter.
		# What this gate guards is the SYMBOL range a designer reaches for.
		if o < 0x2000:
			continue
		if o >= 0x0400 and o <= 0x04FF:
			continue                       # Cyrillic
		if ALLOWED.contains(ch):
			continue
		if not _font.has_char(o):
			_checked += 1
			_fails.append("%s: U+%04X '%s' has no glyph in the font" % [path, o, ch])
		else:
			_checked += 1


func _report() -> void:
	print("GLYPH: scanned %d file(s), checked %d symbol(s) beyond ASCII/Cyrillic" % [_files, _checked])
	var seen := {}
	for f in _fails:
		var key: String = str(f).split("'")[1] if "'" in str(f) else str(f)
		seen[key] = str(f)
	for k in seen.keys():
		print("GLYPH NOTE %s" % seen[k])
	if _fails.is_empty():
		print("==> GLYPH PASSED (every symbol a screen draws has a shape in the font)")
		get_tree().quit(0)
	else:
		print("==> GLYPH FAILED: %d symbol(s) would render as a missing-glyph box (see the notes)" % _fails.size())
		get_tree().quit(1)
