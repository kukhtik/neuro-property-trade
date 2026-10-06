extends RefCounted
## Tests for the tile palette — now sourced from the SKIN, not a code table.
##
## This file used to test BoardTheme (visual/theme.gd), a second palette that
## duplicated what the skin already says. BoardTheme is gone: the skin is the
## single source of visual truth, so these checks run against SkinManager.
## The licensing check (no Hasbro trade dress) is preserved in intent.

const SM := preload("res://visual/skin_manager.gd")

const GROUPS := ["brown", "lightblue", "pink", "orange", "red", "yellow", "green", "darkblue"]
const TYPES := ["go", "jail", "go_to_jail", "free_parking", "tax",
	"railroad", "utility", "chance", "community", "property"]

static func test_list() -> Array[String]:
	return ["test_every_group_has_color", "test_type_coverage",
			"test_property_uses_group", "test_non_hasbro_hue",
			"test_group_color_differs_per_group", "test_boardtheme_is_gone"]


static func _skin():
	var s = SM.new()
	s.load_skin("neuro")
	return s


static func test_every_group_has_color() -> String:
	var s = _skin()
	for g in GROUPS:
		if s.group_color(g) == Color.GRAY:
			return "no color for group %s" % g
	return ""


static func test_type_coverage() -> String:
	# a property takes its group colour; every other type must resolve to a
	# real colour rather than the white fallback
	var s = _skin()
	for t in TYPES:
		if t == "property":
			continue
		var c: Color = s.tile_color({"type": t})
		if c == Color.GRAY:
			return "type %s has no colour" % t
	return ""


static func test_property_uses_group() -> String:
	var s = _skin()
	var c: Color = s.tile_color({"type": "property", "group": "red"})
	if c != s.group_color("red"):
		return "property should use its group colour"
	return ""


static func test_group_color_differs_per_group() -> String:
	# a palette where two groups share a colour would make the board unreadable
	var s = _skin()
	var seen := {}
	for g in GROUPS:
		var c: Color = s.group_color(g)
		if seen.has(c):
			return "groups %s and %s share the colour %s" % [seen[c], g, c]
		seen[c] = g
	return ""


static func test_non_hasbro_hue() -> String:
	# The red group must NOT be the Hasbro near-pure red, and darkblue must not
	# be the classic deep blue (docs/licensing: original trade dress).
	var s = _skin()
	var r: Color = s.group_color("red")
	if r.r > 0.9 and r.g < 0.2 and r.b < 0.2:
		return "red group too close to Hasbro red: %s" % r
	var b: Color = s.group_color("darkblue")
	if b.b > 0.9:
		return "darkblue too close to classic deep-blue: %s" % b
	return ""


static func test_boardtheme_is_gone() -> String:
	# visual/theme.gd was a second palette duplicating the skin. If it returns,
	# the "one source of visual truth" rule is broken again.
	if ResourceLoader.exists("res://visual/theme.gd"):
		return "visual/theme.gd still exists — it duplicates SkinManager"
	return ""
