extends RefCounted
## PART 3 (the owner's order): play the whole game from the keyboard.
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

## The keys the model owns. Anything else is somebody else's (the shell's) key: one owner per key.
const NAV_KEYS := [
	KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE,
]

## The order hotkeys are offered in the help line, so the hint and the handler cannot drift.
const HOTKEYS := [
	{"key": KEY_B, "act": "buy", "label": "buy"},
	{"key": KEY_N, "act": "end_turn", "label": "end turn"},
	{"key": KEY_H, "act": "__panels", "label": "panels"},
]


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


## The hotkey table as one human line, for the help text and the settings sheet. Built from HOTKEYS
## so a rebinding cannot leave the hint lying.
static func hotkey_hint() -> String:
	var parts: Array = []
	for h in HOTKEYS:
		parts.append("%s - %s" % [OS.get_keycode_string(int(h["key"])), str(h["label"])])
	return ", ".join(parts)
