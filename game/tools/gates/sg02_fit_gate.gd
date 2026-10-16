extends Node
## SG-02 gate — fit & clipping (docs/restoration/gates.md, SG-02).
##
## Two objective invariants, independent of any taste in design (gates.md §0):
##   1. no visible control leaves the viewport (its effective rect must lie inside it ±2px);
##   2. no text is squeezed out of its box: for a Label the code did NOT ask to wrap or
##      ellipsize, the allocated width must cover the text's minimum; the same for buttons
##      (a button whose text is wider than the button is a clipped caption).
## Ellipsis is allowed ONLY where the design says so - the player names, the rail titles, the
## inspector title, the toast title - i.e. only inside the ancestors below. Anything else that
## trims its text is a finding, not a style.
##
## Run in RU and in EN on a FRESH game view per language: today the panels do not relabel in
## place (that is SG-08's defect), so an EN scan of an RU-built tree would lie - and it will
## keep working after SG-08 lands because each language gets its own build either way.
##
## Verdict: ==> SG-02 PASSED (4 profiles x 2 languages, ...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg02_fit_gate.tscn

const MainScript := preload("res://main.gd")

const PROFILES := [
	{"label": "1440x900", "size": Vector2i(1440, 900)},
	{"label": "1280x720", "size": Vector2i(1280, 720)},
	{"label": "1000x650", "size": Vector2i(1000, 650)},
	{"label": "880x600", "size": Vector2i(880, 600)},
]
const LOCALES := ["ru", "en"]
## The design's allowed ellipsis sites (gates.md SG-02: "компакт-имена, рейлы"): a name that has
## genuinely run out of room may ellipsize rather than be clipped silently.
##
## A RING CELL'S NAME IS ONE OF THEM (owner's rule, 16.10 evening): the name is now shown at EVERY
## cell size, so on the tightest ring it must be allowed to ellipsize - "Sunset Bl…" is a cell a
## player can still name, and an empty square is not. Before this the name was simply HIDDEN at that
## size, which is the defect the owner reported.
const ELLIPSIS_ANCESTORS := ["seats", "drawer-seats", "toast", "inspector", "drawer-inspector",
	"rail-left", "rail-right", "stage", "stage-camera", "act"]
## Controls that manage their own content size (scroll/rich text): skip the text-fit rule.
const TEXT_FIT_SKIP := ["RichTextLabel", "TextEdit", "LineEdit", "ItemList", "Tree", "TabBar",
	"ScrollBar", "VScrollBar", "HSlider", "ProgressBar"]

var _launcher = null
var _state := "boot"
var _wait := 8
var _phase := 0
var _profile_idx := 0
var _fails: Array = []
var _checks := 0
var _clipped := 0
var _offscreen := 0


func _ready() -> void:
	DisplayServer.window_set_size(PROFILES[0].size)
	get_tree().root.size = PROFILES[0].size
	_spawn()
	_state = "boot"
	_wait = 6


## A fresh MainScript per language: today's panels do not relabel in place (SG-08), so an EN
## scan of an RU-built tree would lie about EN.
func _spawn() -> void:
	I18n.set_locale(LOCALES[_phase])
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	match _state:
		"rebuild":
			_wait -= 1
			if _wait > 0:
				return
			_spawn()
			_state = "boot"
			_wait = 6
		"boot":
			_wait -= 1
			if _wait > 0:
				return
			_launcher.call("_autostart")
			_state = "wait_human"
			_wait = 600
		"wait_human":
			# The WORST CASE for fit is a human turn with the full management set on the row.
			# Without --smoke-drive the match parks on the first LOCAL turn and stays there,
			# so the scanned state is deterministic instead of phase-dependent (the first
			# version of this gate only saw the RU overflow on some runs - exactly because it
			# scanned whatever phase was up).
			_wait -= 1
			if _human_turn() or _wait <= 0:
				if _wait <= 0:
					print("SG-02 warning: no human turn seen in 600 frames; scanning the current state")
				_state = "scan"
				_wait = 5
		"scan":
			_wait -= 1
			if _wait > 0:
				return
			_check_profile(PROFILES[_profile_idx])
			_profile_idx += 1
			if _profile_idx < PROFILES.size():
				get_tree().root.size = PROFILES[_profile_idx].size
				DisplayServer.window_set_size(PROFILES[_profile_idx].size)
				_wait = 12
				return
			_phase += 1
			if _phase >= LOCALES.size():
				_report()
				return
			_profile_idx = 0
			get_tree().root.size = PROFILES[0].size
			DisplayServer.window_set_size(PROFILES[0].size)
			_launcher.queue_free()
			_launcher = null
			_state = "rebuild"
			_wait = 4


## The console parks on a human turn without --smoke-drive; that is the worst case for the
## control row and the state we want to scan (deterministic across runs).
func _human_turn() -> bool:
	if _launcher == null:
		return false
	var gv = _launcher.get("_game_view")
	if gv == null:
		return false
	var act = gv.find_child("act", true, false)
	return act != null and bool(act.get("_human_now"))


func _check_profile(profile: Dictionary) -> void:
	var label := "%s %s" % [str(profile["label"]), LOCALES[_phase]]
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("%s: no game view" % label)
		return
	_walk(gv, label)
	print("SG-02 %s: scanned, %d finding(s) so far" % [label, _fails.size()])


func _walk(node: Node, label: String) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.is_visible_in_tree() and c.size.x > 0.5 and c.size.y > 0.5:
				_audit(c, label)
		_walk(child, label)


func _audit(c: Control, label: String) -> void:
	_checks += 1
	# 1. nothing may leave the viewport - unless a clipping ancestor holds it in (a scrolling
	#    list's virtual space legitimately extends past the window: it is clipped, not shown).
	if not _has_clipping_ancestor(c):
		var r := c.get_global_rect()
		var vs := Vector2(get_tree().root.size)
		if r.position.x < -2.0 or r.position.y < -2.0 or r.end.x > vs.x + 2.0 or r.end.y > vs.y + 2.0:
			_offscreen += 1
			_fail("%s: `%s` leaves the viewport (rect %s vs %s) - it cannot be reached on screen"
				% [label, _where(c), _rect_str(r), _rect_str(Rect2(Vector2.ZERO, vs))])
			_debug_minwidth(c)
	# 2. text must fit its box, unless the code explicitly asked for wrap/ellipsis/clip.
	if _skip_text_fit(c):
		return
	var text := ""
	var min_w := 0.0
	if c is Label:
		var l := c as Label
		text = l.text
		if text.strip_edges() == "":
			return
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			return
		if l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or l.clip_text:
			if not _ellipsis_allowed(l):
				_clipped += 1
				_fail("%s: `%s` trims/clips `%s` but is not an allowed ellipsis site (design says: player names, rail/inspector/toast titles)"
					% [label, _where(l), text])
			return
		min_w = l.get_minimum_size().x
	elif c is Button:
		var b := c as Button
		text = b.text
		if text.strip_edges() == "":
			return
		min_w = b.get_minimum_size().x
	else:
		return
	if c.size.x + 1.0 < min_w:
		_clipped += 1
		_fail("%s: `%s` clips its text `%s` - %dpx wide, needs %dpx (%s text)"
			% [label, _where(c), text, int(c.size.x), int(min_w), LOCALES[_phase].to_upper()])


func _skip_text_fit(c: Control) -> bool:
	for cls in TEXT_FIT_SKIP:
		if c.is_class(cls):
			return true
	return not (c is Label or c is Button)


## A control held inside a clipping ancestor cannot visually leave it (scroll virtual space,
## dock clipping) - the ancestor itself is what must stay on screen.
func _has_clipping_ancestor(c: Control) -> bool:
	var p: Node = c.get_parent()
	while p != null and p != _launcher:
		if p is Control and (p as Control).clip_contents:
			return true
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## The design's own ellipsis sites: names that must fit a dock, the rail strips, the inspector
## and toast titles. Everything else must show its full text on a real profile.
func _ellipsis_allowed(node: Control) -> bool:
	var p: Node = node
	while p != null and p != _launcher:
		if String(p.name) in ELLIPSIS_ANCESTORS:
			return true
		p = p.get_parent()
	return false


func _where(c: Control) -> String:
	## last few segments of the path - enough to find the node, short enough to read
	var parts := str(c.get_path()).split("/")
	var from := maxi(0, parts.size() - 4)
	var out: Array = []
	for i in range(from, parts.size()):
		out.append(str(parts[i]))
	return "/".join(out)


func _rect_str(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]


## On failure: who forces the overflowing width? Walks the subtree and prints every control
## whose minimum width is suspiciously large - the finding must name its source itself.
func _debug_minwidth(c: Control) -> void:
	_dump_min(c, 0)


func _dump_min(c: Control, depth: int) -> void:
	if depth > 4:
		return
	var mw := int(c.get_combined_minimum_size().x)
	if mw > 60 and depth > 1:
		print("%sminwidth: %s (%s) = %d" % ["    ".repeat(depth), str(c.name), c.get_class(), mw])
	for ch in c.get_children():
		if ch is Control:
			_dump_min(ch, depth + 1)


## A silent runtime abort leaves 0 checks and used to still say PASSED (SG-09 lesson):
## the report refuses a run that did not actually check anything.
const MIN_CHECKS := 20   # 4 profiles x 2 languages x >=9 regions


func _report() -> void:
	print("SG-02: %d controls audited, %d clipped text(s), %d off-screen" % [_checks, _clipped, _offscreen])
	if _checks < MIN_CHECKS:
		_fail("only %d check(s) ran - the gate aborted silently (want >= %d)" % [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> SG-02 PASSED (4 profiles x 2 languages, nothing leaves the viewport, no text squeezed out of its box)")
		get_tree().quit(0)
	else:
		print("==> SG-02 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
