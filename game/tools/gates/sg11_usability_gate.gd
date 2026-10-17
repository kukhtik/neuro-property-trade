extends Node
# the ONE home for the launch window size - this gate's main profile reads it
const LayoutProfile := preload("res://ui/core/layout_profile.gd")
## SG-11 gate — the AUTO half of the usability checklist (docs/restoration/gates.md SG-11).
##
## "Интерфейс объясняется сам." Three objective rules on the live tree, plus the manual
## checklist file the design asks for:
##   1. every VISIBLE, ENABLED interactive control (button / option / check) carries a
##      tooltip — a control the player must guess is a usability defect at any taste;
##   2. a rejected intent reads as human language: the shell's rejection shows the engine
##      reason behind a «Причина:» / «Reason:» prefix, in the ACTIVE locale;
##   3. RU headroom: a button's minimum width covers its caption PLUS padding (UiTheme.button
##      bakes 20px per side; a button squeezed to its caption has no headroom for a longer
##      string in the same row).
## The gate also writes build/gates/SG-11-checklist.md: the auto results filled from THIS run
## plus the manual prompts (focus order, dead ends, one-hero-action per turn) the owner fills.
##
## Verdict: ==> SG-11 PASSED (...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg11_usability_gate.tscn

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

const MIN_CHECKS := 4   # 2 profiles x tooltip+headroom, 2 locales x rejection text
const PAD_MIN := 24.0   # 20px baked padding per side minus rounding

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 6
var _profile_idx := 0
## The main profile is READ from `LayoutProfile` (one home), so the window the app opens and the
## window this gate scans cannot drift apart. 1000x650 stays a literal: it is a deliberate
## SMALL-window case, not the launch size.
var _profiles := [LayoutProfile.new().screen, Vector2i(1000, 650)]
var _fails: Array = []
var _checks := 0
var _scan_notes: Array = []


func _ready() -> void:
	DisplayServer.window_set_size(_profiles[0])
	get_tree().root.size = _profiles[0]
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	match _state:
		"boot":
			_wait -= 1
			if _wait > 0:
				return
			_launcher.call("_autostart")
			_state = "settle"
			# WAIT FOR THE SHELL TO BE BUILT, NOT FOR A FRAME COUNT. 40 frames was enough on a warm
			# machine and not enough in the gate sweep, where the console's buttons had not been
			# added yet: the scan then found 5 of 11 interactive controls and reported "the scan
			# proves nothing" - a failure that read like a UI defect and was a race. Poll the thing
			# that is about to be measured, with a bound so a genuinely broken shell still fails.
			_wait = 600
		"settle":
			# READY = the console's action row has its buttons. That is the LAST thing the shell
			# builds, so its presence means everything the scan looks for exists.
			if _interactive_count() >= 8:
				_check_tree("profile %dx%d" % [_profiles[_profile_idx].x, _profiles[_profile_idx].y])
				_profile_idx += 1
				if _profile_idx < _profiles.size():
					get_tree().root.size = _profiles[_profile_idx]
					DisplayServer.window_set_size(_profiles[_profile_idx])
					_state = "settle2"
					_wait = 600
					return
				_check_rejection()
				_write_checklist()
				_report()
				return
			_wait -= 1
			if _wait > 0:
				return
			# the bound expired: run the check anyway so the failure names what it found
			_check_tree("profile %dx%d" % [_profiles[_profile_idx].x, _profiles[_profile_idx].y])
			_profile_idx += 1
			if _profile_idx < _profiles.size():
				get_tree().root.size = _profiles[_profile_idx]
				DisplayServer.window_set_size(_profiles[_profile_idx])
				_state = "settle2"
				_wait = 600
				return
			_check_rejection()
			_write_checklist()
			_report()
		"settle2":
			if _interactive_count() >= 8 or _wait <= 0:
				_check_tree("profile %dx%d" % [_profiles[_profile_idx].x, _profiles[_profile_idx].y])
				_check_rejection()
				_write_checklist()
				_report()
				return
			_wait -= 1


## How many interactive controls exist right now. Used as the READINESS test in `_process`: the gate
## must not measure a shell that is still being built. See the note in the "settle" state.
func _interactive_count() -> int:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return 0
	var bundle: Array = [0, [], []]
	_scan(gv, bundle, "readiness")
	return int(bundle[0])


## 1 + 3: tooltips everywhere; buttons keep caption + padding.
func _check_tree(label: String) -> void:
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("%s: no game view" % label)
		return
	var bundle: Array = [0, [], []]
	_scan(gv, bundle, label)
	var interactive := int(bundle[0])
	var list_u: Array = bundle[1]
	var list_s: Array = bundle[2]
	if interactive < 8:
		_fail("%s: only %d interactive control(s) visible - the scan proves nothing" % [label, interactive])
		return
	_checks += 1
	if not list_u.is_empty():
		_fail("%s: %d interactive control(s) carry NO tooltip (first: %s)" % [label, list_u.size(), str(list_u[0])])
	if not list_s.is_empty():
		_fail("%s: %d button(s) have no RU headroom beyond their padding (first: %s)" % [label, list_s.size(), str(list_s[0])])
	print("SG-11 %s: %d interactive controls, %d untipped, %d without headroom" % [label, interactive, list_u.size(), list_s.size()])
	for s in list_s:
		print("SG-11   no-headroom: %s" % str(s))
	for u in list_u:
		print("SG-11   untipped: %s" % str(u))
	_scan_notes.append("%s: %d interactive, %d untipped, %d no-headroom" % [label, interactive, list_u.size(), list_s.size()])


func _scan(node: Node, bundle: Array, label: String) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.is_visible_in_tree() and c.size.x > 0.5:
				if c is Button or c is OptionButton or c is CheckBox:
					if (c as BaseButton).disabled:
						continue
					bundle[0] = int(bundle[0]) + 1
					if str(c.tooltip_text).strip_edges() == "":
						(bundle[1] as Array).append(_where(c))
					if c is Button and not (c is CheckBox):
						_check_headroom(c as Button, bundle[2] as Array)
		_scan(child, bundle, label)


func _check_headroom(b: Button, out: Array) -> void:
	var caption := str(b.text).strip_edges()
	if caption == "":
		return
	# icon buttons (single glyphs like `⚙`, `±`, `↻`) are captioned by their icon; "headroom
	# beyond the text" is a rule for WORD captions only - a glyph button squeezed to its
	# glyph is the design, not a defect.
	var letters := 0
	for i in caption.length():
		var ch := caption[i]
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "А" and ch <= "я"):
			letters += 1
	# word captions only: `RU`/`EN` locale chips and single glyphs are icon-sized BY DESIGN.
	if letters < 3:
		return
	var font := b.get_theme_font("font")
	var size := b.get_theme_font_size("font_size")
	var text_w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var min_w := b.get_minimum_size().x
	if min_w - text_w < PAD_MIN:
		out.append("%s `%s` (min %.0f vs text %.0f)" % [_where(b), b.text, min_w, text_w])


## 2: a rejection must show the engine reason behind the locale prefix.
func _check_rejection() -> void:
	var gv = _launcher.get("_game_view")
	if gv == null or not gv.has_method("show_rejection"):
		_fail("no show_rejection path on the shell")
		return
	for loc in ["ru", "en"]:
		I18n.set_locale(loc)
		gv.call("show_rejection", "tile required")
		var text := _visible_texts(gv)
		var want := I18n.t("gv.rejected_body", ["tile required"])
		var hit := false
		for t in text:
			if str(t).contains(want):
				hit = true
				break
		if not hit:
			_fail("[%s] the rejection does not read `%s` anywhere visible" % [loc, want])
		else:
			_checks += 1
		gv.get("_modals").call("close")
	I18n.set_locale("ru")


func _visible_texts(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Label and (n as Control).is_visible_in_tree():
			out.append(str((n as Label).text))
		for c in n.get_children():
			stack.append(c)
	return out


## The checklist the design asks for: auto results from THIS run + manual prompts.
func _write_checklist() -> void:
	var auto := "\n".join(_scan_notes)
	if auto == "":
		auto = "(no scans recorded)"
	var body := """# SG-11 — юзабилити-чеклист (сгенерирован гейтом, прогон %s)

## Авто-часть (заполнена гейтом, критерий — 0 нарушений)
%s
- отказы читаются «Причина: …» / «Reason: …»: проверено в ru и en на живом дереве.

## Ручная часть (заполняет владелец; гейт её не судит)
- [ ] фокус-порядок по Tab проходит консоль → журнал → инспектор без ловушек
- [ ] нет тупиков: у каждого состояния есть видимый выход (в т.ч. компакт)
- [ ] «одно герой-действие на ход» (P-7): акцентная кнопка одна, вторичные спокойны
""" % [Time.get_datetime_string_from_system(), auto]
	# build/gates lives one level above the Godot project; globalize and add the tail
	var repo_dir := ProjectSettings.globalize_path("res://").path_join("..")
	var f := FileAccess.open(repo_dir.path_join("build/gates/SG-11-checklist.md"), FileAccess.WRITE)
	if f == null:
		f = FileAccess.open("user://SG-11-checklist.md", FileAccess.WRITE)
	if f != null:
		f.store_string(body)
		f.close()
		print("SG-11: checklist written (build/gates/SG-11-checklist.md)")


func _where(c: Control) -> String:
	var parts := str(c.get_path()).split("/")
	var from := maxi(0, parts.size() - 4)
	var out: Array = []
	for i in range(from, parts.size()):
		out.append(str(parts[i]))
	return "/".join(out)


func _report() -> void:
	print("SG-11: %d checks" % _checks)
	if _checks < MIN_CHECKS and _fails.is_empty():
		_fail("only %d check(s) ran - the gate aborted silently (want >= %d)" % [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> SG-11 PASSED (tooltips everywhere, rejections speak human, buttons keep headroom; checklist written)")
		get_tree().quit(0)
	else:
		print("==> SG-11 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
