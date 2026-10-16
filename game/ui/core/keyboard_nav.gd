extends RefCounted
## PART 3 (the owner's order): play the whole game from the keyboard.
##
## The KEYS themselves live in `bindings.gd` (the one home the settings screen reads); this file is
## the policy - which key reaches which control, and in what order.
##
## WHY NOT JUST `grab_focus()` ON EVERYTHING: Godot's own focus navigation needs every button to be
## focusable, in a sensible ORDER, and the panels rebuild their buttons on every state change - so
## focus is lost on each turn. This is the small policy that solves both: it knows the KEYS, and it
## decides which control gets focus next, independently of Godot's tree order.
##
## It is PURE: it takes a list of controls and returns decisions. No engine, no scene, so the whole
## keyboard model can be tested without a window.
##
## The model, in the owner's words ("альтернативное управление чисто через клавиатуру"):
##   * Tab / Shift+Tab cycle the focusable controls;
##   * arrows move the SPATIAL focus (the next control in that direction on screen);
##   * Enter / Space press the focused control;
##   * a letter hotkey presses a named action directly, wherever the focus is;
##   * Escape leaves the focus.

const Bindings := preload("res://ui/core/bindings.gd")
const I18n := preload("res://i18n/i18n.gd")

## The keys the model owns for NAVIGATION. Anything else belongs to the binding table (`Bindings`),
## which the shell looks up itself - one owner per key, and the arrows are shared with the camera
## under the precedence documented in `game_view._handle_nav_key`.
const NAV_KEYS := [
	KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE,
]

## The hint is BUILT from the binding table, so a rebind cannot leave the text lying. The label and
## the key both come from the one home; this file only formats them.
static func hotkey_hint(bindings: Dictionary = {}) -> String:
	var b: Dictionary = bindings if not bindings.is_empty() else Bindings.defaults()
	var parts: Array = []
	for a in Bindings.ACTIONS:
		var act: String = str(a["act"])
		if str(a["group"]) == "camera":
			continue          # the camera keys are on the board, not on this list
		var key: int = int(b.get(act, int(a["key"])))
		parts.append("%s - %s" % [OS.get_keycode_string(key), I18n.t(Bindings.label_key(act))])
	return ", ".join(parts)


## Is this key one the navigator handles? (The shell asks before its own keys.)
static func owns(keycode: int) -> bool:
	return keycode in NAV_KEYS


## Which control should take focus when `keycode` is pressed, given the current focus and the list of
## focusable controls?
##
## `rects` is a parallel array of each control's global rect (the caller reads them; this stays
## pure). Returns the index into `controls`, or -1 when the key has no navigation meaning.
##
## WHY SPATIAL AND NOT TREE ORDER: the buttons are rebuilt every turn in a different order, so "the
## next child" is not a stable thing to a player - "the button to the right" is. When nothing lies
## in that direction there is no move (-1), so focus does not jump across the screen.
static func next_index(keycode: int, current: int, rects: Array) -> int:
	if rects.is_empty():
		return -1
	match keycode:
		KEY_TAB:
			return (current + 1) % rects.size() if current >= 0 else 0
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if current < 0 or current >= rects.size():
				return 0
			return _spatial(keycode, current, rects)
	return -1


## The nearest control in the pressed direction, or -1 when there is none.
static func _spatial(keycode: int, current: int, rects: Array) -> int:
	var from: Rect2 = rects[current]
	var best := -1
	var best_score := INF
	for i in rects.size():
		if i == current:
			continue
		var to: Rect2 = rects[i]
		var c_from := from.get_center()
		var c_to := to.get_center()
		var d := c_to - c_from
		# the control must lie in the pressed direction; a small tolerance keeps a same-row button
		# (slightly off centre) reachable by LEFT/RIGHT instead of demanding perfect alignment
		var ok := false
		match keycode:
			KEY_LEFT:
				ok = d.x < -1.0
			KEY_RIGHT:
				ok = d.x > 1.0
			KEY_UP:
				ok = d.y < -1.0
			KEY_DOWN:
				ok = d.y > 1.0
		if not ok:
			continue
		# cost: the distance along the pressed axis, plus a heavy penalty for drift off it, so
		# "right" prefers the button beside this one over one far right and far down
		var along := absf(d.x) if (keycode == KEY_LEFT or keycode == KEY_RIGHT) else absf(d.y)
		var across := absf(d.y) if (keycode == KEY_LEFT or keycode == KEY_RIGHT) else absf(d.x)
		var score := along + across * 3.0
		if score < best_score:
			best_score = score
			best = i
	return best


