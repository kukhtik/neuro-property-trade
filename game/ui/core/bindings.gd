extends RefCounted
## KEY BINDINGS — the ONE home for every rebindable key, and the source the settings screen reads.
##
## WHY THIS EXISTS: before it, the keys lived in three places that could not agree - the constants in
## `game_view._unhandled_key_input`, the `HOTKEYS` table in `keyboard_nav.gd` (which the tooltip hint
## printed) and the assertions in the HG-13 gate. A settings screen over any one of them would have
## shown a key that did not work: the screen would LIE about exactly the thing it exists to change.
##
## So the table below is the truth, `game_view` looks keys up in it, the hint prints from it, and a
## test walks every action to prove the three agree.
##
## Pure + headless-testable: no scene, no engine.

const ACT_BUY := "buy"
const ACT_END_TURN := "end_turn"
const ACT_ROLL := "roll"
const ACT_TRADE := "trade"
const ACT_BUILD := "build"
const ACT_MORTGAGE := "mortgage"
const ACT_PANELS := "panels"
const ACT_SETTINGS := "settings"
const ACT_CAM_LEFT := "cam_left"
const ACT_CAM_RIGHT := "cam_right"
const ACT_CAM_UP := "cam_up"
const ACT_CAM_DOWN := "cam_down"
const ACT_ZOOM_IN := "zoom_in"
const ACT_ZOOM_OUT := "zoom_out"
const ACT_FOLLOW := "follow"

## Every rebindable action, in the order the settings screen lists them, with the key it ships with.
## `game` = it acts on the match (a player's turn), `camera` = it moves the board view, `ui` = it
## affects the interface. The group is what the screen groups rows by, nothing more.
const ACTIONS := [
	{"act": ACT_ROLL, "key": KEY_SPACE, "group": "game"},
	{"act": ACT_BUY, "key": KEY_B, "group": "game"},
	{"act": ACT_END_TURN, "key": KEY_N, "group": "game"},
	{"act": ACT_TRADE, "key": KEY_T, "group": "game"},
	{"act": ACT_BUILD, "key": KEY_H, "group": "game"},
	{"act": ACT_MORTGAGE, "key": KEY_M, "group": "game"},
	{"act": ACT_PANELS, "key": KEY_P, "group": "ui"},
	{"act": ACT_SETTINGS, "key": KEY_F1, "group": "ui"},
	{"act": ACT_FOLLOW, "key": KEY_F, "group": "camera"},
	{"act": ACT_CAM_LEFT, "key": KEY_LEFT, "group": "camera"},
	{"act": ACT_CAM_RIGHT, "key": KEY_RIGHT, "group": "camera"},
	{"act": ACT_CAM_UP, "key": KEY_UP, "group": "camera"},
	{"act": ACT_CAM_DOWN, "key": KEY_DOWN, "group": "camera"},
	{"act": ACT_ZOOM_IN, "key": KEY_EQUAL, "group": "camera"},
	{"act": ACT_ZOOM_OUT, "key": KEY_MINUS, "group": "camera"},
]

## The keys that were hard-coded before this existed. They keep working for anyone who bound them
## by muscle memory, and the settings screen shows them as the ship defaults.
const SHIPPED := {
	ACT_BUY: KEY_B,
	ACT_END_TURN: KEY_N,
	ACT_PANELS: KEY_H,
}

## The one key the camera's follow toggle answers to. It is a FIXED key rather than a rebindable
## action because `board_camera.handle_key` owns it internally; the binding table routes its action
## here. Kept as a named constant so there is no second literal to drift.
const KEY_FOR_FOLLOW := KEY_F

## Where the user's overrides are stored. `user://` survives a rebuild, which is what a binding is
## for - the same file shape as the other saved settings.
const SAVE_PATH := "user://bindings.json"


## Read the saved overrides. A missing or corrupt file yields {} - the shipped keys - never a crash
## and never a half-applied table.
static func load_saved() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


## Persist the overrides. Only keys that DIFFER from the shipped defaults are written, so a future
## change to a default reaches players who never touched it.
static func save_saved(bindings: Dictionary) -> bool:
	var d := defaults()
	var over := {}
	for act in bindings.keys():
		if int(bindings[act]) != int(d.get(act, 0)):
			over[str(act)] = int(bindings[act])
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(over))
	return true


## The whole table as {act: keycode}, the shape the shell looks things up in.
static func defaults() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[str(a["act"])] = int(a["key"])
	return out


## The keys the user actually has: the defaults with their saved overrides applied. `saved` is the
## dictionary loaded from disk; unknown actions and nonsense keycodes are ignored rather than
## trusted (a corrupt file must not make the game unplayable).
static func resolved(saved: Dictionary) -> Dictionary:
	var out := defaults()
	for act in saved.keys():
		var k: String = str(act)
		if not out.has(k):
			continue
		var v: int = int(saved[act])
		if v <= 0:
			continue
		out[k] = v
	return out


## The action a keycode is bound to, or "" - the shell's one lookup. Built from the RESOLVED table
## so a rebind takes effect immediately.
static func action_for(bindings: Dictionary, keycode: int) -> String:
	for act in bindings.keys():
		if int(bindings[act]) == keycode:
			return str(act)
	return ""


## A human label for an action, from the i18n catalog (the screen and the tests read the same key).
static func label_key(act: String) -> String:
	return "bind." + act


## The group an action belongs to, for the screen's sections. Unknown actions land in "ui".
static func group_of(act: String) -> String:
	for a in ACTIONS:
		if str(a["act"]) == act:
			return str(a["group"])
	return "ui"


## Is this keycode already taken by another action? Returns the holder, or "" when it is free.
## The screen refuses a duplicate rather than silently giving two actions one key.
static func holder_of(bindings: Dictionary, keycode: int, except_act: String = "") -> String:
	for act in bindings.keys():
		if str(act) == except_act:
			continue
		if int(bindings[act]) == keycode:
			return str(act)
	return ""


## Apply one rebind, returning a NEW table (the caller decides when to save). A key already held by
## another action SWAPS the two, so the player never ends up with two actions on one key or with an
## action that has no key at all.
static func rebind(bindings: Dictionary, act: String, keycode: int) -> Dictionary:
	var out := bindings.duplicate()
	if keycode <= 0:
		return out
	var previous: int = int(out.get(act, 0))
	var holder := holder_of(out, keycode, act)
	if holder != "":
		# swap: the other action takes the key this one is giving up
		out[holder] = previous
	out[act] = keycode
	return out


## Back to the shipped keys.
static func reset_one(bindings: Dictionary, act: String) -> Dictionary:
	var out := bindings.duplicate()
	var d := defaults()
	if d.has(act):
		out[act] = int(d[act])
	return out
