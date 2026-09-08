class_name SkinManager
extends RefCounted
## Asset + theme abstraction layer (skinning). The visual layer NEVER hardcodes
## `res://assets/...` paths or `Color(...)` literals — it asks SkinManager for
## textures and colors, which are resolved from a `skin.json` config. Swapping
## the whole look = replacing the skin directory + pointing SkinManager at it.
##
## Pure + headless-testable (no scene nodes). `load_skin(skin_id)` reads
## `res://assets/skins/<id>/skin.json`; `texture(key)` / `color(key)` resolve
## entries with a code-built fallback (null / a default) so a missing asset
## never crashes the game.

const DEFAULT_SKIN := "classic"

var _cfg: Dictionary = {}
var _loaded_id := ""

## Load a skin config by id. Returns true on success (falls back to defaults
## for missing keys). Idempotent per id.
func load_skin(skin_id: String = DEFAULT_SKIN) -> bool:
	if _loaded_id == skin_id and not _cfg.is_empty():
		return true
	var path := "res://assets/skins/%s/skin.json" % skin_id
	if not ResourceLoader.exists(path):
		push_warning("SkinManager: skin '%s' not found at %s" % [skin_id, path])
		_cfg = {}
		_loaded_id = skin_id
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_cfg = {}
		_loaded_id = skin_id
		return false
	_cfg = JSON.parse_string(f.get_as_text())
	_loaded_id = skin_id
	return _cfg is Dictionary

## Resolve a texture by dotted key (e.g. "tile_bg", "corner_icons.go",
## "houses.house", "tokens.ship"). Returns null if missing.
func texture(key: String) -> Texture2D:
	var p := _lookup_path(key)
	if p == "":
		return null
	if ResourceLoader.exists(p):
		return load(p)
	return null

## Resolve an asset path by dotted key. Returns "" if missing.
func path(key: String) -> String:
	return _lookup_path(key)

## Resolve a color by dotted key (e.g. "group.brown", "ui.accent",
## "tile_text"). Returns a default (white) if missing.
func color(key: String, fallback: Color = Color.WHITE) -> Color:
	var v: Variant = _lookup(key)
	if v == null:
		return fallback
	if v is Color:
		return v
	if v is String:
		var s := str(v)
		if s.begins_with("#"):
			s = s.substr(1)
		if s.length() == 6:
			return Color.html(s)
	return fallback

## A proportion (0..1) by dotted key, with a fallback.
func proportion(key: String, fallback: float = 0.25) -> float:
	var v: Variant = _lookup("proportions." + key)
	if v == null:
		return fallback
	return float(v)

## An integer proportion/constant by dotted key.
func int_proportion(key: String, fallback: int = 0) -> int:
	return int(proportion(key, float(fallback)))

## The compact-mode cell threshold.
func compact_threshold() -> int:
	return int_proportion("compact_threshold", 44)

## Dotted-key lookup into the nested config.
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
