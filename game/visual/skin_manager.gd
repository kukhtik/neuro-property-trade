class_name SkinManager
extends RefCounted
## Asset + theme abstraction layer (skinning). The visual layer NEVER hardcodes
## `res://assets/...` paths, `Color(...)` literals or numeric sizes — it asks
## SkinManager for textures, colors, tokens and metrics resolved from a
## `skin.json` config. Swapping the whole look = replacing the skin directory
## + pointing SkinManager at it (owner requirement: the UI must be fully
## replaceable by assets, with no code edits).
##
## Pure + headless-testable (no scene nodes, no autoload).
##
## Config shape (every section optional; a partial skin is legal):
##   assets      — flat/dotted asset paths (legacy, kept working)
##   colors      — flat/dotted colors (legacy, kept working)
##   proportions — relative dimensions (legacy, kept working)
##   tokens      — semantic tokens: color.*, font.*, size.*, space, shape.*
##   metrics     — board geometry ratios (corner_ratio, band_ratio, ...)
##   slots       — id -> {tex, margins, mode, tint} (9-slice capable)
##   motion      — animation durations + profile
##
## `extends` chains to a parent skin; every miss falls back to the parent and
## finally to the built-in defaults in this file, so a skin can ship one slot
## at a time. A missing slot is a warning, never an error.

## WHICH SKIN THE GAME WEARS.
##
## This was `default` — a grey-blue theme the mockup does not use anywhere. The mockup's own
## theme is `neuro` (violet/pink, accent #ff6fae), and the skin file matches it token for token.
## The comparison harness checked `assets/skins/neuro/skin.json` against the mockup's
## `data-theme="neuro"` block and reported 11/11 tokens with zero delta, while the running game
## painted `default` — so the declared values always agreed and the screen never matched. Same
## mistake as the invisible dialog: measuring the declaration instead of the render.
const DEFAULT_SKIN := "neuro"
const SKINS_DIR := "res://assets/skins/"

## Built-in fallback values — the last link of the fallback chain. A skin that
## ships nothing still renders. Deliberately NOT the Hasbro palette.
const FALLBACK_COLORS := {
	"bg": "#16191f", "surface.1": "#1e242e", "surface.2": "#171c24",
	"surface.3": "#232a35",
	"line": "#39404d", "text": "#e8edf3", "muted": "#8b95a5",
	"accent": "#4fb3d9", "on_accent": "#0c1218", "accent2": "#5fc4ea",
	"money": "#ffd34d", "danger": "#e8615c", "warn": "#e08a3c",
}
const FALLBACK_SIZES := {"xs": 10, "s": 12, "m": 14, "l": 18, "xl": 28}
const FALLBACK_SPACE := [4, 8, 12, 16, 24]
const FALLBACK_SHAPE := {"radius": 0, "chamfer": 9, "line": 1, "line_active": 2}
const FALLBACK_METRICS := {
	"corner_ratio": 1.4, "band_ratio": 0.03, "board_frame": 6, "board_gap": 2,
	"house_size": 0.019, "token_size": 0.027, "icon_size": 0.036,
}
const FALLBACK_MOTION := {
	"step": 0.19, "hop": 0.32, "pop": 0.5, "panel": 0.3, "card": 2.8,
	"dice_roll": 0.85, "profile": "full",
}
## Default player palette (tokens live in the skin, never in code).
const FALLBACK_PLAYERS := ["#ff6fae", "#e8264f", "#5fe3ff", "#b6ff6b", "#ffb020", "#b36bff"]

var _cfg: Dictionary = {}
var _loaded_id := ""
var _chain: Array[Dictionary] = []   # self first, then parents
var _warned_slots := {}              # one push_warning per missing slot


## Load a skin config by id, resolving its `extends` chain. Returns true when
## the requested skin existed (missing keys fall back). Idempotent per id.
## The skin the app is currently wearing.
##
## `DEFAULT_SKIN` is a `const` and cannot change at runtime, so a UI switcher had nothing to
## write to: every widget called `load_skin()` and got `neuro` back. This is that variable.
static var chosen := DEFAULT_SKIN


func load_skin(skin_id: String = "") -> bool:
	# an empty id means "whatever is chosen" — that keeps every existing `load_skin()` call site
	# working, and gives a switcher one place to write.
	if skin_id == "":
		skin_id = chosen
	if _loaded_id == skin_id and not _cfg.is_empty():
		return true
	_warned_slots.clear()
	_chain.clear()
	_cfg = {}
	_loaded_id = skin_id

	var visited := {}
	var current := skin_id
	var ok := false
	while current != "" and not visited.has(current):
		visited[current] = true
		var cfg := _read_skin(current)
		if cfg.is_empty():
			break
		_chain.append(cfg)
		if current == skin_id:
			ok = true
		current = str(cfg.get("extends", ""))
	# `_cfg` is the merged view (nearest skin wins), so the legacy `_lookup`
	# helpers keep returning the effective value.
	_cfg = {}
	# `_deep_merge(a, b)` keeps a's values and only fills keys a LACKS. The chain
	# is [self, parent, ...], so folding forward puts the skin in first and the
	# parent only supplies what the skin left out — the skin wins.
	for cfg in _chain:
		_cfg = _deep_merge(_cfg, cfg)
	if not ok:
		push_warning("SkinManager: skin '%s' not found; using built-in defaults" % skin_id)
	return ok


## Read one skin.json raw. Empty dict when absent or malformed.
func _read_skin(skin_id: String) -> Dictionary:
	var path := SKINS_DIR + skin_id + "/skin.json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("SkinManager: %s is not a JSON object" % path)
	return {}


## Recursive merge: `b` fills keys `a` does not already define.
func _deep_merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if out.has(k) and out[k] is Dictionary and b[k] is Dictionary:
			out[k] = _deep_merge(out[k], b[k])
		elif not out.has(k):
			out[k] = b[k]
	return out


func skin_id() -> String:
	return _loaded_id


## All skin ids on disk (directories containing a skin.json).
func available() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(SKINS_DIR)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if FileAccess.file_exists(SKINS_DIR + sub + "/skin.json"):
			out.append(sub)
	return out


# --- Token access -------------------------------------------------------------

## Resolve a semantic token by dotted path: "color.accent", "size.m",
## "shape.chamfer", "space" (array), "metrics.corner_ratio".
func token(path: String, default = null) -> Variant:
	if path == "":
		return default
	if path == "space":   # bare array in the config
		var sp: Variant = _lookup("tokens.space")
		if sp is Array and (sp as Array).size() > 0:
			return sp
		return FALLBACK_SPACE if default == null else default
	var v: Variant = _lookup("tokens." + path)
	if v != null:
		return v
	# A TOKEN NAME MAY CONTAIN DOTS. `surface.1`, `surface.2`, `board.bg2` and `ev.text` are
	# SINGLE keys in the skin file, not nested objects — but `_lookup` splits the path on dots
	# and walks it, so it looked for `tokens.color.surface.1`, found no `surface`, and returned
	# null. Every one of those tokens then fell through to `FALLBACK_COLORS` — which holds the
	# values of the `default` skin. With `neuro` loaded the background and accent came from the
	# skin while every panel, surface and border came from another theme's defaults: the game
	# wore half of each palette at once, which is exactly what "выглядит не так" looked like.
	# Look the remainder up as one key inside its namespace before giving up on it.
	var dot := path.find(".")
	if dot > 0:
		var ns_dict: Variant = _lookup("tokens." + path.substr(0, dot))
		if ns_dict is Dictionary:
			var rest := path.substr(dot + 1)
			if (ns_dict as Dictionary).has(rest):
				return (ns_dict as Dictionary)[rest]
	var parts := path.split(".", false, 1)
	if parts.size() == 2:
		var ns := parts[0]
		var key := parts[1]
		match ns:
			"color":
				if FALLBACK_COLORS.has(key):
					return FALLBACK_COLORS[key]
			"size":
				if FALLBACK_SIZES.has(key):
					return FALLBACK_SIZES[key]
			"shape":
				if FALLBACK_SHAPE.has(key):
					return FALLBACK_SHAPE[key]
			"metrics":
				if FALLBACK_METRICS.has(key):
					return FALLBACK_METRICS[key]
			"motion":
				if FALLBACK_MOTION.has(key):
					return FALLBACK_MOTION[key]
	return default


## An integer size token (size.m -> 14).
func size(name: String, fallback: int = 14) -> int:
	var v: Variant = token("size." + name, null)
	if v == null:
		return fallback
	return int(v)


## A spacing step by 1-based index (space.1 == space[0]).
func space(index: int, fallback: int = 8) -> int:
	var sp: Variant = token("space", FALLBACK_SPACE)
	if sp is Array and index >= 1 and index <= (sp as Array).size():
		return int((sp as Array)[index - 1])
	return fallback


## A shape token (chamfer/radius/line/line_active).
func shape(name: String, fallback: float = 0.0) -> float:
	return float(token("shape." + name, fallback))


## A board metric ratio (corner_ratio, band_ratio, board_frame, ...).
func metric(name: String, fallback: float = 0.0) -> float:
	var v: Variant = _lookup("metrics." + name)
	if v == null:
		v = _lookup("tokens.metrics." + name)
	if v == null:
		v = _lookup("proportions." + name)
	if v == null:
		return float(FALLBACK_METRICS.get(name, fallback))
	return float(v)


## An animation duration token. A dict value (e.g. motion.idle) is not a
## duration, so the fallback wins.
func motion(name: String, fallback: float = 0.3) -> float:
	var v: Variant = _lookup("motion." + name)
	if v == null:
		v = _lookup("tokens.motion." + name)
	if v == null or v is Dictionary:
		return float(FALLBACK_MOTION.get(name, fallback))
	return float(v)


## The motion profile: "full" | "reduced" | "off".
func motion_profile() -> String:
	var v: Variant = _lookup("motion.profile")
	if v == null:
		v = _lookup("tokens.motion.profile")
	if v == null:
		return str(FALLBACK_MOTION["profile"])
	return str(v)


# --- Colors -------------------------------------------------------------------

## Resolve a color by token path ("accent") or legacy dotted path
## ("group.brown", "ui.accent"). Returns the fallback when missing.
func color(name: String, fallback: Color = Color.WHITE) -> Color:
	var tok: Variant = token("color." + name, null)
	var c := _as_color(tok)
	if c.a >= 0.0:
		return c
	var legacy: Variant = _lookup("colors." + name)
	var lc := _as_color(legacy)
	if lc.a >= 0.0:
		return lc
	return fallback


## Parse a hex string / Color into a Color; Color(0,0,0,-1) when invalid.
func _as_color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is String:
		var s := str(v)
		if s.begins_with("#"):
			s = s.substr(1)
		if s.length() == 6 or s.length() == 8:
			return Color.html(s)
	return Color(0, 0, 0, -1)


## Player palette color by index, cycling.
func player_color(idx: int) -> Color:
	var arr: Variant = token("color.player", null)
	if not (arr is Array) or (arr as Array).is_empty():
		arr = FALLBACK_PLAYERS
	var a: Array = arr
	return _as_color(a[posmod(idx, a.size())])


## Group color (brown/lightblue/...); gray when the skin does not define it.
func group_color(group: String) -> Color:
	var c := _as_color(_lookup("colors.group." + group))
	if c.a >= 0.0:
		return c
	var t := _as_color(_lookup("tokens.color.group." + group))
	if t.a >= 0.0:
		return t
	return Color.GRAY


## Tile fill: property -> group color, else the type color.
func tile_color(tile: Dictionary) -> Color:
	var t: String = str(tile.get("type", "property"))
	if t == "property":
		return group_color(str(tile.get("group", "")))
	var c := _as_color(_lookup("colors.type." + t))
	if c.a >= 0.0:
		return c
	return Color.WHITE


# --- Slots (assets, with 9-slice support) -------------------------------------

## Resolve an asset slot. Returns {texture|null, path, margins, mode, tint}.
## A missing slot yields texture=null so the component draws procedurally —
## one warning per slot id, not per call.
func slot(id: String) -> Dictionary:
	var s: Variant = _slot_entry(id)
	if not (s is Dictionary):
		var legacy := path(id)   # legacy assets.* resolution
		if legacy != "" and ResourceLoader.exists(legacy):
			return {"texture": load(legacy), "path": legacy, "margins": [], "mode": "stretch", "tint": Color.WHITE}
		if not _warned_slots.has(id):
			_warned_slots[id] = true
			push_warning("SkinManager: slot '%s' missing; procedural fallback" % id)
		return {"texture": null, "path": "", "margins": [], "mode": "stretch", "tint": Color.WHITE}
	var sd: Dictionary = s
	var p: String = str(sd.get("tex", ""))
	var tex: Texture2D = null
	if p != "":
		var full := p if p.begins_with("res://") else SKINS_DIR + _loaded_id + "/" + p
		if ResourceLoader.exists(full):
			tex = load(full)
		else:
			push_warning("SkinManager: slot '%s' points at a missing file: %s" % [id, full])
	var tint := _as_color(sd.get("tint", null))
	return {
		"texture": tex,
		"path": p,
		"margins": sd.get("margins", []),
		"mode": str(sd.get("mode", "stretch")),
		"tint": tint if tint.a >= 0.0 else Color.WHITE,
	}


## True when the slot resolves to a real texture (used by the stress-skin check).
func has_slot(id: String) -> bool:
	var v: Variant = _slot_entry(id)
	if v is Dictionary and str((v as Dictionary).get("tex", "")) != "":
		return true
	var p := path(id)
	return p != "" and ResourceLoader.exists(p)


## Resolve one entry of the `slots` map. Slot ids contain dots
## ("board.frame", "tile.bg.property"), so a plain dotted `_lookup` would split
## them into a non-existent nested path — match the flat key instead, then
## accept a nested spelling too.
func _slot_entry(id: String) -> Variant:
	var slots: Variant = _lookup("slots")
	if not (slots is Dictionary):
		return null
	var m: Dictionary = slots
	if m.has(id):
		return m[id]
	return _lookup("slots." + id)


# --- Legacy accessors (kept: existing call sites depend on them) --------------

## Resolve a texture by dotted key (e.g. "tile_bg", "corner_icons.go"). Prefers
## a slot, then a legacy assets.* path.
func texture(key: String) -> Texture2D:
	var sl := slot(key)
	if sl["texture"] != null:
		return sl["texture"]
	var p := _lookup_path(key)
	if p == "":
		return null
	if ResourceLoader.exists(p):
		return load(p)
	return null


## Resolve an asset path by dotted key. Returns "" if missing.
func path(key: String) -> String:
	return _lookup_path(key)


## A proportion (0..1) by dotted key, with a fallback.
func proportion(key: String, fallback: float = 0.25) -> float:
	return metric(key, fallback)


## An integer proportion/constant by dotted key.
func int_proportion(key: String, fallback: int = 0) -> int:
	return int(metric(key, float(fallback)))


## The compact-mode cell threshold.
func compact_threshold() -> int:
	return int(proportion("compact_threshold", 44))


# --- Theme --------------------------------------------------------------------

## Build the single project Theme from this skin. Components use these as theme
## type variations instead of per-node overrides, so swapping the skin
## restyles everything at once.
func theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = size("m", 14)

	var font_ui := _font("ui")
	if font_ui != null:
		th.default_font = font_ui

	var text := color("text")
	var muted := color("muted")
	var accent := color("accent")
	var on_accent := color("on_accent")
	var line := color("line")
	var s1 := color("surface.1")
	var s2 := color("surface.2")
	var noline := Color(0, 0, 0, 0)

	for panel_variant in ["PanelBase", "PanelRail", "ModalFrame", "PlayerCard", "JournalRow", "ToastBg"]:
		th.set_stylebox("panel", panel_variant, _flat(s1, line, int(shape("line", 1.0))))
	th.set_stylebox("panel", "PanelHeader", _flat(s2, line, int(shape("line", 1.0))))
	th.set_stylebox("panel", "PlayerCardActive", _flat(s2, accent, int(shape("line_active", 2.0))))
	th.set_stylebox("panel", "JournalRowHL", _flat(s2, noline, 0))

	for variant in ["ButtonBase", "ChipBase", "TabButton", "SegmentButton"]:
		var w := int(shape("line", 1.0))
		th.set_stylebox("normal", variant, _flat(s2, line, w))
		th.set_stylebox("hover", variant, _flat(s1, accent, w))
		th.set_stylebox("pressed", variant, _flat(s1, accent, int(shape("line_active", 2.0))))
		th.set_stylebox("disabled", variant, _flat(s2, line, w))
		th.set_color("font_color", variant, text)

	var w2 := int(shape("line_active", 2.0))
	th.set_stylebox("normal", "ButtonPrimary", _flat(accent, accent, 1))
	th.set_stylebox("hover", "ButtonPrimary", _flat(color("accent2", accent), accent, w2))
	th.set_stylebox("pressed", "ButtonPrimary", _flat(accent, accent, w2))
	th.set_color("font_color", "ButtonPrimary", on_accent)

	th.set_color("font_color", "Label", text)
	th.set_color("font_color", "LabelMuted", muted)
	th.set_color("font_color", "LabelTitle", text)
	th.set_color("font_color", "LabelMoney", color("money", text))
	for lbl in ["Label", "LabelMuted", "LabelTitle", "LabelMoney"]:
		th.set_font_size("font_size", lbl, size("m", 14))
	return th


## Resolve a skin font file, or null (the caller/system falls back).
func _font(name: String) -> FontFile:
	var p: String = str(token("font." + name, ""))
	if p == "":
		return null
	var full := p if p.begins_with("res://") else SKINS_DIR + _loaded_id + "/" + p
	if not ResourceLoader.exists(full):
		return null
	var f = load(full)
	return f if f is FontFile else null


func _flat(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(w)
	var r := int(shape("radius", 0.0))
	b.corner_radius_top_left = r
	b.corner_radius_top_right = r
	b.corner_radius_bottom_left = r
	b.corner_radius_bottom_right = r
	return b


# --- Internals ----------------------------------------------------------------

## Dotted-key lookup into the merged config.
func _lookup(key: String):
	var parts := key.split(".")
	var cur: Variant = _cfg
	for p in parts:
		if cur is Dictionary and (cur as Dictionary).has(p):
			cur = (cur as Dictionary)[p]
		else:
			return null
	return cur


## Resolve an asset path by dotted key (assets.*).
func _lookup_path(key: String) -> String:
	var v: Variant = _lookup("assets." + key)
	if v == null:
		return ""
	return str(v)
