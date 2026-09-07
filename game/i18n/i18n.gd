class_name I18n
extends RefCounted
## Dict-based localization (spec §9, P5). A flat dictionary KEY -> {ru, en} is
## merged from per-domain data files at first use. `t(key, named)` returns the
## current-locale string with `{{name}}` substitutions; `set_locale` emits
## `locale_changed` so every panel retranslates in place (no scene rebuild).
##
## Pure + headless-testable (no imports, no autoload). Static methods only;
## the signal lives on a lazily-created singleton instance because GDScript
## static classes cannot declare signals.
##
## Controls are localized via metadata: set `i18n_key` (text) and/or
## `i18n_tip` (tooltip_text) on a Control, then call `I18n.relabel(root)` on
## locale change — it walks the tree and re-applies both. Dynamic dropdowns /
## templates that embed values get a per-file `retranslate()` that calls `t()`
## explicitly. `UiTheme.label_key/button_key` set the metadata at build time.

## Languages supported, in OptionButton order (must match settings.language).
const LOCALES := ["ru", "en"]

## Ordered list of per-domain data scripts that each expose a `const D` dict.
const _FILES := [
	"res://i18n/data_ui.gd",
	"res://i18n/data_settings.gd",
	"res://i18n/data_action.gd",
	"res://i18n/data_event.gd",
	"res://i18n/data_admin.gd",
]

static var current: String = "ru"

static var _data: Dictionary = {}
static var _loaded := false
static var _singleton: I18n = null

## Signal so panels can react to language changes without polling.
signal locale_changed(locale: String)

static func inst() -> I18n:
	if _singleton == null:
		_singleton = I18n.new()
	return _singleton

## Ensure the merged dictionary is loaded (idempotent; merged once).
static func _ensure() -> void:
	if _loaded:
		return
	for path in _FILES:
		var mod: GDScript = load(path)
		if mod == null:
			push_error("I18n: cannot load %s" % path)
			continue
		var d: Variant = mod.get("D")
		if d is Dictionary:
			_data.merge(d, true)
	_loaded = true

## Translate `key` in the current locale. `vals` applies the locale string's
## GDScript `%` format (pass an Array, or a bare value for a single `%s`),
## or performs `{{name}}` substitution when a Dictionary is passed. A missing
## key returns `{%key%}` — the p5 probe relies on this sentinel to catch any
## raw/uncollected screen string.
static func t(key: String, vals: Variant = null) -> String:
	_ensure()
	var e: Variant = _data.get(key, null)
	if e == null:
		return "{%s}" % key
	var s: String
	if e is String:
		s = e
	else:
		var ent: Dictionary = e
		s = str(ent.get(current, ent.get("ru", key)))
	if vals == null:
		return s
	if vals is Dictionary:
		for k in vals:
			s = s.replace("{{" + str(k) + "}}", str(vals[k]))
		return s
	return s % vals

## Test/read helper: is `key` present in the merged dictionary?
static func has(key: String) -> bool:
	_ensure()
	return _data.has(key)

## Total count of collected keys (probe sanity).
static func key_count() -> int:
	_ensure()
	return _data.size()

## Switch locale and notify every panel. `ru` | `en`. No-op if unchanged.
static func set_locale(l: String) -> void:
	if current == l or not LOCALES.has(l):
		return
	current = l
	inst().locale_changed.emit(l)

## Set `i18n_key` metadata (drives `.text` on a future relabel pass).
static func key_on(node: Control, key: String) -> Control:
	node.set_meta("i18n_key", key)
	return node

## Set `i18n_tip` metadata (drives `.tooltip_text`).
static func tip_on(node: Control, key: String) -> Control:
	node.set_meta("i18n_tip", key)
	return node

## Walk the node tree under `root`; for any Control carrying `i18n_key` update
## `.text`, and for `i18n_tip` update `.tooltip_text`. Call on locale change.
static func relabel(root: Node) -> void:
	_relabel_node(root)

static func _relabel_node(n: Node) -> void:
	if n is Control:
		var c := n as Control
		if c.has_meta("i18n_key"):
			c.text = t(str(c.get_meta("i18n_key")))
		if c.has_meta("i18n_tip"):
			c.tooltip_text = t(str(c.get_meta("i18n_tip")))
	for ch in n.get_children():
		_relabel_node(ch)
