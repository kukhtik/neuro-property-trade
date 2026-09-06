extends RefCounted

const BT := preload("res://visual/theme.gd")

static func test_list() -> Array[String]:
	return ["test_every_group_has_color", "test_type_coverage",
			"test_property_uses_group", "test_non_hasbro_hue"]

static func test_every_group_has_color() -> String:
	for g in ["brown", "lightblue", "pink", "orange", "red",
			"yellow", "green", "darkblue"]:
		if not BT.GROUP_COLORS.has(g):
			return "no color for group %s" % g
	return ""

static func test_type_coverage() -> String:
	for t in ["go", "jail", "go_to_jail", "free_parking", "tax",
			"railroad", "utility", "chance", "community", "property"]:
		if not BT.TYPE_COLORS.has(t):
			return "no color for type %s" % t
	return ""

static func test_property_uses_group() -> String:
	var c = BT.tile_color({"type": "property", "group": "red"})
	if c != BT.GROUP_COLORS["red"]:
		return "property should use group color"
	return ""

static func test_non_hasbro_hue() -> String:
	# Red group must NOT be the Hasbro near-pure red (#B22222-ish/classic); assert
	# it's not a bright saturated red.
	var r = BT.GROUP_COLORS["red"]
	if r.r > 0.9 and r.g < 0.2 and r.b < 0.2:
		return "red group too close to Hasbro red: %s" % r
	var c = BT.GROUP_COLORS["darkblue"]
	if c.b > 0.9:
		return "darkblue too close to classic deep-blue: %s" % c
	return ""
