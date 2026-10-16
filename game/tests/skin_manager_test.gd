extends RefCounted
## Tests for the skin core (SkinManager tokens/slots/metrics/motion/extends and
## the Theme built from it). Headless-safe: SkinManager is pure (no scene nodes).
##
## Owner requirement under test: the UI must be fully replaceable by assets,
## so a skin must resolve through the fallback chain (self -> extends -> built-in)
## and a partial skin must never crash a component.

const SM := preload("res://visual/skin_manager.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")
const PI := preload("res://core/player_identity.gd")

static func test_list() -> Array[String]:
	return ["test_default_skin_loads", "test_neuro_overrides_bg",
		"test_evil_inherits_from_neuro", "test_extends_chain_resolves",
		"test_token_fallback_when_absent", "test_color_token_and_legacy_path",
		"test_player_color_cycles", "test_group_color_fallback",
		"test_tile_color_group_vs_type", "test_size_and_space_tokens",
		"test_shape_and_metric_tokens", "test_motion_tokens_and_profile",
		"test_missing_slot_is_graceful", "test_available_lists_skins",
		"test_theme_builds_from_skin", "test_theme_varies_between_skins",
		"test_chamfer_polygon_shapes", "test_unknown_skin_uses_defaults",
		"test_dotted_slot_id_resolves", "test_dotted_color_tokens_come_from_the_skin",
		"test_metric_not_shadowed_by_fallback", "test_token_path_follows_the_skin",
		"test_motion_not_shadowed_by_fallback", "test_identity_palette_follows_skin",
		"test_r3_body_sizes_clear_the_readability_floor"]

static func test_default_skin_loads() -> String:
	var s = SM.new()
	if not s.load_skin("default"):
		return "default skin failed to load"
	if s.skin_id() != "default":
		return "skin_id should be 'default', got %s" % s.skin_id()
	return ""

static func test_neuro_overrides_bg() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	var bg = s.color("bg")
	if bg != Color("0b0613"):
		return "neuro bg should be #0b0613, got %s" % bg
	return ""

static func test_evil_inherits_from_neuro() -> String:
	var s = SM.new()
	s.load_skin("evil")
	# evil defines bg itself
	if s.color("bg") != Color("080406"):
		return "evil bg should be #080406, got %s" % s.color("bg")
	# ...but inherits group colours from neuro (2 levels up via extends)
	if s.group_color("brown") != Color("8b5a3c"):
		return "evil should inherit neuro's brown, got %s" % s.group_color("brown")
	return ""

static func test_extends_chain_resolves() -> String:
	var s = SM.new()
	s.load_skin("evil")
	# R-3 unified the body sizes across skins: neuro no longer overrides m=13 down from default's
	# 14, so the whole chain resolves to the raised floors. evil inherits from neuro.
	if s.size("m") != 14:
		return "evil should inherit size.m=14 through neuro, got %d" % s.size("m")
	if s.size("s") != 13 or s.size("xs") != 11:
		return "evil should inherit the R-3 floors (s=13, xs=11), got s=%d xs=%d" % [s.size("s"), s.size("xs")]
	return ""

static func test_token_fallback_when_absent() -> String:
	var s = SM.new()
	s.load_skin("default")
	# never defined anywhere -> built-in fallback
	if float(s.token("metrics.corner_ratio", 0.0)) != 1.4:
		return "corner_ratio fallback should be 1.4"
	if str(s.token("nope.whatever", "sentinel")) != "sentinel":
		return "unknown token should return the default"
	return ""

static func test_color_token_and_legacy_path() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	# semantic token path
	if s.color("accent") != Color("ff6fae"):
		return "token color.accent wrong: %s" % s.color("accent")
	# neuro defines no colors.ui.*, so the legacy path must miss cleanly
	if s.color("ui.accent", Color.RED) != Color.RED:
		return "legacy path missing from this skin should return the fallback"
	# ...the legacy layout still works on a skin that ships it (classic)
	var c = SM.new()
	c.load_skin("classic")
	if c.color("ui.accent", Color.BLACK) != Color("4fb3d9"):
		return "legacy colors.ui.accent should resolve on classic, got %s" % c.color("ui.accent", Color.BLACK)
	if c.color("group.brown", Color.BLACK) != Color("6b3a2a"):
		return "legacy colors.group.brown should resolve on classic"
	# truly unknown -> fallback
	if s.color("no.such.color", Color.RED) != Color.RED:
		return "unknown colour should return the fallback"
	return ""

static func test_player_color_cycles() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	var pal: Variant = s._lookup("tokens.color.player")
	var n: int = (pal as Array).size() if pal is Array else 0
	if n < 8:
		return "neuro should ship >= 8 player colours for seats 2..8, got %d" % n
	var first = s.player_color(0)
	if s.player_color(n) != first:
		return "player_color should cycle every palette entry (%d)" % n
	if s.player_color(0) == s.player_color(1):
		return "player colours must differ"
	return ""

static func test_group_color_fallback() -> String:
	var s = SM.new()
	s.load_skin("default")
	var g = s.group_color("not-a-group")
	if g != Color.GRAY:
		return "unknown group should be gray, got %s" % g
	return ""

static func test_tile_color_group_vs_type() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	var prop = s.tile_color({"type": "property", "group": "red"})
	if prop != s.group_color("red"):
		return "property tile should use its group colour"
	var tax = s.tile_color({"type": "tax"})
	if tax == prop:
		return "tax tile must not reuse the property colour"
	return ""

## R-3 (master-fix-plan §1, D7): the BODY sizes are the readability floor of the whole UI.
## The defect: the map measured x-height 6-9px in the docks and the console - the base body size
## was 12px, and 10px tokens sat under it. A test that only reads ONE skin would have passed
## before this change on `default` (m=14) while `neuro` rendered 13 - and `neuro` is the skin the
## stream uses, so the check has to walk EVERY skin and every body token.
static func test_r3_body_sizes_clear_the_readability_floor() -> String:
	# the floors the plan names, applied to every skin that ships
	for skin_id in ["default", "neuro", "evil", "classic"]:
		var s = SM.new()
		if not s.load_skin(skin_id):
			return "skin %s failed to load" % skin_id
		if s.size("m") < 14:
			return "skin %s: size.m is %dpx, the R-3 floor is 14" % [skin_id, s.size("m")]
		if s.size("s") < 13:
			return "skin %s: size.s is %dpx, the R-3 floor is 13" % [skin_id, s.size("s")]
		if s.size("xs") < 11:
			return "skin %s: size.xs is %dpx, the R-3 floor is 11" % [skin_id, s.size("xs")]
		# and a skin that declares NOTHING must still resolve to the floors (the built-in path -
		# this is the branch that changing only the skin files would have left behind)
		var miss = SM.new()
		miss.load_skin("does-not-exist")
		if miss.size("xs", -1) < 11 or miss.size("s", -1) < 13 or miss.size("m", -1) < 14:
			return ("the built-in fallback sizes are still small: xs=%d s=%d m=%d"
				% [miss.size("xs", -1), miss.size("s", -1), miss.size("m", -1)])
	return ""


static func test_size_and_space_tokens() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	if s.size("m") != 14:
		return "size.m should be 14 after R-3, got %d" % s.size("m")
	if s.size("nope", 42) != 42:
		return "unknown size should return the fallback"
	if s.space(1) != 4 or s.space(5) != 24:
		return "space steps wrong: %d/%d" % [s.space(1), s.space(5)]
	if s.space(99, -1) != -1:
		return "out-of-range space index should fall back"
	return ""

static func test_shape_and_metric_tokens() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	if s.shape("chamfer") != 9.0:
		return "shape.chamfer should be 9, got %s" % s.shape("chamfer")
	if s.metric("corner_ratio") != 1.4:
		return "corner_ratio should be 1.4, got %s" % s.metric("corner_ratio")
	if s.shape("radius") != 0.0:
		return "radius should be 0 (square, no rounded corners)"
	return ""

static func test_motion_tokens_and_profile() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	if absf(s.motion("step") - 0.19) > 0.001:
		return "motion.step should be 0.19, got %s" % s.motion("step")
	# motion.idle is a dict, not a duration -> fallback wins
	if absf(s.motion("idle", 7.0) - 7.0) > 0.001:
		return "a dict motion token must not be read as a duration"
	if s.motion_profile() != "full":
		return "profile should be 'full', got %s" % s.motion_profile()
	return ""

static func test_missing_slot_is_graceful() -> String:
	var s = SM.new()
	s.load_skin("default")
	var sl = s.slot("board.frame")
	if sl["texture"] != null:
		return "default ships no textures, so the slot must have no texture"
	if not sl.has("margins"):
		return "slot dict must always carry a margins key"
	if s.has_slot("board.frame"):
		return "has_slot should be false when nothing resolves"
	return ""

static func test_available_lists_skins() -> String:
	var s = SM.new()
	var ids := s.available()
	for want in ["default", "neuro", "evil"]:
		if not ids.has(want):
			return "available() must list '%s', got %s" % [want, str(ids)]
	return ""

static func test_theme_builds_from_skin() -> String:
	var s = SM.new()
	s.load_skin("neuro")
	var th = s.theme()
	if th == null:
		return "theme() returned null"
	if str(th.get_type_variation_base("ButtonPrimary")) != "":
		pass   # variations are declared by the component side; just ensure no crash
	var col = th.get_color("font_color", "ButtonPrimary")
	if col != Color("2a0618"):
		return "ButtonPrimary font should be on_accent (#2a0618), got %s" % col
	if th.default_font_size != 14:
		return "theme default font size should follow size.m (14), got %d" % th.default_font_size
	var sb = th.get_stylebox("normal", "ButtonPrimary")
	if not (sb is StyleBoxFlat):
		return "ButtonPrimary normal stylebox should be a StyleBoxFlat"
	return ""

static func test_theme_varies_between_skins() -> String:
	var a = SM.new(); a.load_skin("neuro")
	var b = SM.new(); b.load_skin("evil")
	var ca = a.theme().get_color("font_color", "ButtonPrimary")
	var cb = b.theme().get_color("font_color", "ButtonPrimary")
	if ca == cb:
		return "swapping the skin must change the theme (on_accent identical: %s)" % ca
	return ""

static func test_chamfer_polygon_shapes() -> String:
	var o := Vector2.ZERO
	var sz := Vector2(100, 50)
	# no chamfer -> a plain rectangle (4 points)
	var rect = Chamfer._polygon(o, sz, 0.0, "tr")
	if rect.size() != 4:
		return "zero chamfer should give a 4-point rectangle, got %d" % rect.size()
	# a cut corner replaces one corner with two points -> 5 points
	for corner in ["tr", "tl", "br", "bl"]:
		var poly = Chamfer._polygon(o, sz, 10.0, corner)
		if poly.size() != 5:
			return "chamfer '%s' should give 5 points, got %d" % [corner, poly.size()]
	return ""

static func test_unknown_skin_uses_defaults() -> String:
	var s = SM.new()
	if s.load_skin("does-not-exist"):
		return "loading a missing skin should report false"
	# despite the miss, tokens must still resolve from built-ins
	if s.size("m", -1) != 14:
		return "built-in size.m should be 14, got %d" % s.size("m", -1)
	if s.color("bg", Color.BLACK) != Color("16191f"):
		return "built-in bg should still resolve, got %s" % s.color("bg", Color.BLACK)
	return ""

## Regression: slot ids contain dots ("board.frame"), so they must be matched
## as flat keys — a dotted _lookup would split them into a non-existent path.
## A COLOUR token's name may itself contain a dot: `surface.1`, `surface.2`, `board.bg2`,
## `ev.text`. `_lookup` walks a path by splitting it on dots, so `tokens.color.surface.1` looked
## for a nested `surface` object that does not exist, found nothing, and every one of these
## tokens fell through to `FALLBACK_COLORS`. Those defaults are the `default` skin's values, so
## the game wore `neuro`'s background and accent with `default`'s panels, surfaces and borders.
##
## ONE skin cannot detect this. The fallback equals `default`'s own value, so a `default`-only
## assertion passes with or without the bug. It takes a second skin whose value DIFFERS to prove
## the number came out of the file at all.
static func test_dotted_color_tokens_come_from_the_skin() -> String:
	var s = SM.new()
	if not s.load_skin("neuro"):
		return "neuro did not load"
	var n := s.color("surface.1").to_html(false)
	if n != "130b1f":
		return "neuro surface.1 must be #130b1f from the file, got #%s (the fallback is #1e242e)" % n
	if s.color("line").to_html(false) != "3b2a5e":
		return "neuro line must be #3b2a5e, got #%s" % s.color("line").to_html(false)
	if not s.load_skin("default"):
		return "default did not load"
	if s.color("surface.1").to_html(false) != "1e242e":
		return "default surface.1 must be #1e242e, got #%s" % s.color("surface.1").to_html(false)
	# a name no skin ships must still be graceful, not an error
	if s.load_skin("neuro") and s.color("surface.9").to_html(false) == "":
		return "an absent dotted token should fall back, not vanish"
	return ""


static func test_dotted_slot_id_resolves() -> String:
	var s = SM.new()
	if not s.load_skin("_stress"):
		return "stress-skin (test fixture) did not load"
	var sl = s.slot("board.frame")
	if sl["texture"] == null:
		return "dotted slot id 'board.frame' did not resolve to a texture"
	if not (sl["margins"] as Array).size() == 4:
		return "9-slice margins lost for 'board.frame'"
	if not s.has_slot("board.frame"):
		return "has_slot must be true for a resolvable dotted id"
	# an id nothing ships must stay graceful
	if s.slot("deck.chance")["texture"] != null:
		return "unshipped slot should be null"
	return ""

## Regression: a skin's own metric must win over the built-in fallback, which
## previously shadowed it because the fallback was consulted first.
static func test_metric_not_shadowed_by_fallback() -> String:
	var s = SM.new()
	s.load_skin("_stress")
	if absf(s.metric("corner_ratio") - 1.1) > 0.0001:
		return "stress corner_ratio should be 1.1, got %s" % s.metric("corner_ratio")
	if not s.metric("board_frame") == 14.0:
		return "stress board_frame should be 14, got %s" % s.metric("board_frame")
	return ""

## Regression: same shadowing bug on motion tokens.
static func test_motion_not_shadowed_by_fallback() -> String:
	var s = SM.new()
	s.load_skin("_stress")
	if absf(s.motion("step") - 0.05) > 0.0001:
		return "stress motion.step should be 0.05, got %s" % s.motion("step")
	if s.motion_profile() != "reduced":
		return "stress profile should be 'reduced', got %s" % s.motion_profile()
	return ""


## Token icons are the thing a themed board most wants to redraw, and their folder used to be a
## literal in `core`. A skin must be able to point `asset.tokens` somewhere else, and a seat with
## a bad id must still get a path that EXISTS.
static func test_token_path_follows_the_skin() -> String:
	var s = SM.new()
	s.load_skin("default")
	if s.token_path("ship") != "res://assets/tokens/ship.svg":
		return "default folder wrong: %s" % s.token_path("ship")
	if s.token_path("") != "res://assets/tokens/ship.svg":
		return "empty id must fall back to the first token, got %s" % s.token_path("")
	if s.token_path("bogus") != "res://assets/tokens/ship.svg":
		return "unknown id must fall back, got %s" % s.token_path("bogus")
	# A SKIN MUST BE ABLE TO REDIRECT ITS ICONS. This is the whole point of reading the folder
	# from the skin instead of a literal in `core`: the icons are what a themed board most wants
	# to redraw, and until now a skin could restyle every surface and still be stuck with these.
	var cfg: Dictionary = s._cfg.duplicate(true)
	cfg["tokens"]["asset"] = {"tokens": "res://assets/skins/evil/tokens"}
	s._cfg = cfg
	if not s.token_path("cat").begins_with("res://assets/skins/evil/"):
		return "a skin must be able to redirect its token folder, got %s" % s.token_path("cat")
	return ""


## The app seeds PlayerIdentity from the active skin (main calls
## SkinManager.sync_identity_palette at launch and on every skin switch). If that link
## breaks, the owner marker on a tile keeps the PREVIOUS skin's colours while the piece
## and the seat row move with the new one — the four-way colour drift P-2 closed.
## Restores the built-in palette so later modules still test the default state.
static func test_identity_palette_follows_skin() -> String:
	var sm = SM.new()
	sm.load_skin("neuro")
	var neuro_first: Color = sm.player_color(0)
	# the app path itself: chosen is "neuro" for the whole suite
	SM.sync_identity_palette()
	if PI.color_of(0) != neuro_first:
		PI.set_palette(PI.COLORS)
		return "sync_identity_palette must seed the identity palette from the chosen skin"
	# a live SWITCH moves the palette with it
	sm.load_skin("default")
	var def_first: Color = sm.player_color(0)
	if def_first == neuro_first:
		PI.set_palette(PI.COLORS)
		return "neuro and default palettes must differ for this check to mean anything"
	PI.set_palette(sm.player_palette())
	if PI.color_of(0) != def_first:
		PI.set_palette(PI.COLORS)
		return "identity palette should follow a skin switch"
	# an empty palette must not wipe the identity colours
	PI.set_palette([])
	if PI.color_of(0) != def_first:
		PI.set_palette(PI.COLORS)
		return "an empty palette must be ignored"
	PI.set_palette(PI.COLORS)
	return ""
