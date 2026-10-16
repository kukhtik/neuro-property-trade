extends Node
## THROWAWAY PROBE (not a gate): SG-02's fit measurement, phone profiles.
## Same two invariants as sg02_fit_gate.gd - nothing leaves the viewport, no text is
## squeezed out of its box - run at widths the layout declares UNSUPPORTED
## (LayoutProfile.MIN_WIDTH = 880): a modern phone is 390-430 CSS px wide.
## Run: godot --headless --path game res://tools/phone_fit_probe.tscn
## Verdict: ==> PHONE PROBE ...

const MainScript := preload("res://main.gd")

const PROFILES := [
	{"label": "390x844", "size": Vector2i(390, 844)},
	{"label": "412x915", "size": Vector2i(412, 915)},
	{"label": "844x390", "size": Vector2i(844, 390)},
]
const ELLIPSIS_ANCESTORS := ["seats", "drawer-seats", "toast", "inspector", "drawer-inspector",
	"rail-left", "rail-right"]
const TEXT_FIT_SKIP := ["RichTextLabel", "TextEdit", "LineEdit", "ItemList", "Tree", "TabBar",
	"ScrollBar", "VScrollBar", "HSlider", "ProgressBar"]

var _launcher = null
var _state := "boot"
var _wait := 8
var _profile_idx := 0
var _fails: Array = []
var _checks := 0
var _clipped := 0
var _offscreen := 0
var _sigs: Array = []      # geometry signatures while waiting for the layout to settle
var _resizes := 0          # attempts to make the root take the profile's size


func _ready() -> void:
	DisplayServer.window_set_size(PROFILES[0].size)
	get_tree().root.size = PROFILES[0].size
	_spawn()
	_state = "boot"
	_wait = 6


func _spawn() -> void:
	I18n.set_locale("ru")
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	match _state:
		"boot":
			_wait -= 1
			if _wait > 0:
				return
			_launcher.call("_autostart")
			_state = "wait_human"
			_wait = 900
		"wait_human":
			_wait -= 1
			if _human_turn() or _wait <= 0:
				if _wait <= 0:
					print("PHONE probe: no human turn seen; scanning the current state")
				_state = "scan"
				_wait = 40
				_sigs.clear()
		"scan":
			# A NUMBER FROM A MID-RELAYOUT FRAME IS NOT A NUMBER. The first run reported
			# 0 findings at 390x844 and 131 at 412x915 - the window was still settling. And
			# a window that never took the requested size gives numbers about ANOTHER window,
			# so the size is re-asserted until the root reports it.
			var want: Vector2i = PROFILES[_profile_idx]["size"]
			if get_tree().root.size != want:
				_resizes += 1
				if _resizes > 90:
					_fail("%s: the root never took the requested size (%dx%d, still %dx%d) - the probe cannot measure this profile"
						% [PROFILES[_profile_idx]["label"], want.x, want.y,
							get_tree().root.size.x, get_tree().root.size.y])
					_advance()
					return
				get_tree().root.size = want
				DisplayServer.window_set_size(want)
				_wait = 4
				_sigs.clear()
				return
			_resizes = 0
			_wait -= 1
			if _wait > 0:
				return
			var sig := _signature()
			_sigs.append(sig)
			if _sigs.size() < 3 or _sigs[-1] != _sigs[-2] or _sigs[-2] != _sigs[-3]:
				if _sigs.size() >= 12:
					print("PHONE %s: the layout never settled (%d tries) - measuring anyway"
						% [PROFILES[_profile_idx]["label"], _sigs.size()])
				else:
					_wait = 10
					return
			_check_profile(PROFILES[_profile_idx])
			_advance()


func _advance() -> void:
	_profile_idx += 1
	if _profile_idx < PROFILES.size():
		get_tree().root.size = PROFILES[_profile_idx].size
		DisplayServer.window_set_size(PROFILES[_profile_idx].size)
		_wait = 40
		_resizes = 0
		_sigs.clear()
		return
	_report()


## Geometry of the first N visible controls: identical twice in a row means "laid out".
func _signature() -> String:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return "no-view"
	var parts: Array = []
	_collect(gv, parts)
	return "|".join(parts)


func _collect(node: Node, parts: Array) -> void:
	for child in node.get_children():
		if parts.size() >= 40:
			return
		if child is Control:
			var c := child as Control
			if c.is_visible_in_tree():
				var r := c.get_global_rect()
				parts.append("%s:%d,%d,%d,%d" % [_where(c), int(r.position.x), int(r.position.y),
					int(r.size.x), int(r.size.y)])
		_collect(child, parts)


func _human_turn() -> bool:
	if _launcher == null:
		return false
	var gv = _launcher.get("_game_view")
	if gv == null:
		return false
	var act = gv.find_child("act", true, false)
	return act != null and bool(act.get("_human_now"))


func _check_profile(profile: Dictionary) -> void:
	var label := str(profile["label"])
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("%s: no game view" % label)
		return
	var want: Vector2i = profile["size"]
	var root_size := get_tree().root.size
	var checks_before := _checks
	var off_before := _offscreen
	var clip_before := _clipped
	_walk(gv, label)
	# "measured nothing" must never look like "nothing wrong": print what was audited, and
	# say out loud when the window refused the size we asked for.
	if root_size.x != want.x or root_size.y != want.y:
		_fail("%s: the root did not take the requested size (root %dx%d vs %dx%d) - the numbers below describe another window"
			% [label, root_size.x, root_size.y, want.x, want.y])
	print("PHONE %s: root=%dx%d audited=%d offscreen=%d clipped=%d"
		% [label, root_size.x, root_size.y, _checks - checks_before,
			_offscreen - off_before, _clipped - clip_before])


func _walk(node: Node, label: String) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.is_visible_in_tree() and c.size.x > 0.5 and c.size.y > 0.5:
				_audit(c, label)
		_walk(child, label)


func _audit(c: Control, label: String) -> void:
	_checks += 1
	if not _has_clipping_ancestor(c):
		var r := c.get_global_rect()
		var vs := Vector2(get_tree().root.size)
		if r.position.x < -2.0 or r.position.y < -2.0 or r.end.x > vs.x + 2.0 or r.end.y > vs.y + 2.0:
			_offscreen += 1
			_fail("%s: `%s` leaves the viewport (rect %s vs %s)"
				% [label, _where(c), _rect_str(r), _rect_str(Rect2(Vector2.ZERO, vs))])
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
				_fail("%s: `%s` trims/clips `%s` outside an allowed site" % [label, _where(l), text])
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
		_fail("%s: `%s` clips its text `%s` - %dpx wide, needs %dpx"
			% [label, _where(c), text, int(c.size.x), int(min_w)])


func _skip_text_fit(c: Control) -> bool:
	for cls in TEXT_FIT_SKIP:
		if c.is_class(cls):
			return true
	return not (c is Label or c is Button)


func _has_clipping_ancestor(c: Control) -> bool:
	var p: Node = c.get_parent()
	while p != null and p != _launcher:
		if p is Control and (p as Control).clip_contents:
			return true
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _ellipsis_allowed(node: Control) -> bool:
	var p: Node = node
	while p != null and p != _launcher:
		if String(p.name) in ELLIPSIS_ANCESTORS:
			return true
		p = p.get_parent()
	return false


func _where(c: Control) -> String:
	var parts := str(c.get_path()).split("/")
	var from := maxi(0, parts.size() - 4)
	var out: Array = []
	for i in range(from, parts.size()):
		out.append(str(parts[i]))
	return "/".join(out)


func _rect_str(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]


func _report() -> void:
	print("PHONE PROBE: %d controls audited, %d clipped text(s), %d off-screen" % [_checks, _clipped, _offscreen])
	if _checks < 20:
		_fail("only %d check(s) ran" % _checks)
	if _fails.is_empty():
		print("==> PHONE PROBE PASSED (3 phone profiles, nothing leaves the viewport)")
		get_tree().quit(0)
	else:
		print("==> PHONE PROBE FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
