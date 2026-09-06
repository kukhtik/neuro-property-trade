extends RefCounted
## P1 tests for PlayerIdentity (single source of player color + token).
## Pure static helpers — headless-testable.

static func test_list() -> Array[String]:
	return [
		"test_eight_colors_and_tokens",
		"test_color_of_wraps",
		"test_token_of_wraps",
		"test_token_path_known",
		"test_token_path_unknown_falls_back",
		"test_is_known_token",
		"test_colors_contrast_on_backdrop",
	]

static func _PI():
	return load("res://core/player_identity.gd")

static func test_eight_colors_and_tokens() -> String:
	var PI = _PI()
	if PI.COLORS.size() != 8:
		return "want 8 colors, got %d" % PI.COLORS.size()
	if PI.TOKENS.size() != 8:
		return "want 8 tokens, got %d" % PI.TOKENS.size()
	# tokens must match the SVG assets on disk
	for t in PI.TOKENS:
		if not ResourceLoader.exists("res://assets/tokens/%s.svg" % t):
			return "missing token asset: %s" % t
	return ""

static func test_color_of_wraps() -> String:
	var PI = _PI()
	if PI.color_of(0) != PI.COLORS[0]:
		return "color_of(0) should be COLORS[0]"
	if PI.color_of(8) != PI.COLORS[0]:
		return "color_of(8) should wrap to COLORS[0]"
	if PI.color_of(9) != PI.COLORS[1]:
		return "color_of(9) should wrap to COLORS[1]"
	return ""

static func test_token_of_wraps() -> String:
	var PI = _PI()
	if PI.token_of(0) != PI.TOKENS[0]:
		return "token_of(0) should be TOKENS[0]"
	if PI.token_of(8) != PI.TOKENS[0]:
		return "token_of(8) should wrap to TOKENS[0]"
	return ""

static func test_token_path_known() -> String:
	var PI = _PI()
	if PI.token_path("ship") != "res://assets/tokens/ship.svg":
		return "token_path(ship) wrong: %s" % PI.token_path("ship")
	return ""

static func test_token_path_unknown_falls_back() -> String:
	var PI = _PI()
	if PI.token_path("") != "res://assets/tokens/ship.svg":
		return "empty token should fall back to ship"
	if PI.token_path("bogus") != "res://assets/tokens/ship.svg":
		return "unknown token should fall back to ship"
	return ""

static func test_is_known_token() -> String:
	var PI = _PI()
	if not PI.is_known_token("dog"):
		return "dog should be known"
	if PI.is_known_token("nope"):
		return "nope should be unknown"
	return ""

static func test_colors_contrast_on_backdrop() -> String:
	var PI = _PI()
	var backdrop := Color("16191f")
	for c in PI.COLORS:
		# rough luminance contrast against the dark backdrop
		var lum: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
		if lum < 0.30:
			return "color %s too dark on backdrop (lum %.2f)" % [c.to_html(), lum]
	return ""
