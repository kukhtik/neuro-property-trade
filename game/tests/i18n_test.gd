extends RefCounted

const I := preload("res://i18n/i18n.gd")

static func test_list() -> Array[String]:
	return ["test_both_locales_present", "test_substitution", "test_missing_key_sentinel",
			"test_locale_switch", "test_every_entry_is_dict_ru_en",
			"test_en_has_no_cyrillic"]

# Every key must resolve to a string in BOTH locales.
static func test_both_locales_present() -> String:
	for key in _keys():
		if I.t(key).begins_with("{%"):  # ru missing
			return "RU missing key %s" % key
		I.set_locale("en")
		if I.t(key).begins_with("{%"):
			return "EN missing key %s" % key
		I.set_locale("ru")
	return ""

static func test_substitution() -> String:
	# positional %s format applied to the current-locale string
	var t: String = I.t("plr.pos_tiles", ["GO", 3])
	if t != "@ GO · 3 тайл.":
		return "expected '@ GO · 3 тайл.', got '%s'" % t
	return ""

static func test_missing_key_sentinel() -> String:
	if I.t("nope.does_not_exist") != "{nope.does_not_exist}":
		return "missing key should return sentinel"
	if I.t("nope.does_not_exist") == "nope.does_not_exist":
		return "sentinel should include braces (probe relies on it)"
	return ""

static func test_locale_switch() -> String:
	I.set_locale("en")
	var en: String = I.t("action.roll")
	I.set_locale("ru")
	var ru: String = I.t("action.roll")
	if en.find("roll") < 0:
		return "EN roll should contain 'roll', got '%s'" % en
	if ru.find("бросок") < 0:
		return "RU roll should contain 'бросок', got '%s'" % ru
	return ""

static func test_every_entry_is_dict_ru_en() -> String:
	# every data entry must be a {ru,en} dict (not a bare string) so we never
	# ship an untranslated locale
	var bad: Array[String] = []
	for key in _keys():
		var e: Dictionary = _entry(key)
		if not (e.has("ru") and e.has("en")):
			bad.append(key)
	if bad.size() > 0:
		return "entries missing ru/en: %s" % ", ".join(bad)
	return ""

static func test_en_has_no_cyrillic() -> String:
	# Every EN-rendered string must be free of Cyrillic (a classic i18n bug —
	# a value copied from the RU field). Iterate the merged dict in EN.
	for key in _keys():
		I.set_locale("en")
		var s: String = I.t(key)
		if _has_cyrillic(s):
			return "EN string has Cyrillic for key %s: '%s'" % [key, s]
		I.set_locale("ru")
	return ""

# ----------------------------------------------------------------- helpers ---

static func _keys() -> Array[String]:
	var out: Array[String] = []
	# access the merged data via the public accessor: I has no public dict
	# accessor that is stable, so re-derive from the data files listed here.
	for path in ["res://i18n/data_ui.gd", "res://i18n/data_settings.gd",
			"res://i18n/data_action.gd", "res://i18n/data_event.gd",
			"res://i18n/data_admin.gd"]:
		var mod: GDScript = load(path)
		out.append_array(mod.get("D").keys())
	return out

static func _entry(key: String) -> Dictionary:
	for path in ["res://i18n/data_ui.gd", "res://i18n/data_settings.gd",
			"res://i18n/data_action.gd", "res://i18n/data_event.gd",
			"res://i18n/data_admin.gd"]:
		var mod: GDScript = load(path)
		if (mod.get("D") as Dictionary).has(key):
			return (mod.get("D") as Dictionary)[key]
	return {}

static func _has_cyrillic(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false
