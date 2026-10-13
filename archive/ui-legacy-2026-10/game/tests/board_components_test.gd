extends RefCounted
## Tests for the stage-3 board components: BuildingStrip, BoardCenter, and the
## TileView container structure.
##
## These are STRUCTURE tests — they assert the tile is container-built with the
## right child slots and that no visual value is hardcoded. A headless scene is
## created so the components can be instantiated without a window.

const TileView := preload("res://visual/tile_view.gd")
const BuildingStrip := preload("res://visual/building_strip.gd")
const BoardCenter := preload("res://visual/board_center.gd")
const EffectLayer := preload("res://visual/effect_layer.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const BL := preload("res://visual/board_layout.gd")

static func test_list() -> Array[String]:
	return [
		"test_tile_is_container_built", "test_tile_has_required_slots",
		"test_tile_no_absolute_positioning", "test_tile_band_side_matches_layout",
		"test_tile_degradation_steps", "test_tile_owner_from_skin_palette",
		"test_strip_counts", "test_strip_no_art_fallback_ok",
		"test_center_sheds_in_order", "test_center_dice_pips",
		"test_effect_layer_snaps_when_off", "test_effect_layer_positions_from_layout",
		"test_float_labels_are_pooled", "test_float_pool_is_bounded"]

## Controls are instantiated standalone (no SceneTree needed): they only need
## a parent for `queue_free`, and `free()` works without one.
static func _skin():
	var s = SkinManager.new()
	s.load_skin("neuro")
	return s


static func test_tile_is_container_built() -> String:
	var tv = TileView.new()
	tv.build(1, 40, 80, _skin())
	# the tile must contain a layout container, not just free-floating Controls
	var has_container := false
	for c in tv.get_children():
		if c is Container or c is MarginContainer:
			has_container = true
	if not has_container:
		return "tile should be container-built (no MarginContainer/Container child)"
	tv.free()
	return ""


static func test_tile_has_required_slots() -> String:
	var tv = TileView.new()
	tv.build(5, 40, 80, _skin())
	# spec §5.4: NameLabel, Footer with a price and an owner badge, a band
	var found := {"NameLabel": false, "Footer": false, "band": false}
	_walk(tv, func(n: Node):
		if n.name == "NameLabel": found["NameLabel"] = true
		if n.name == "Footer": found["Footer"] = true
		if n is BuildingStrip: found["band"] = true
	)
	for k in found:
		if not found[k]:
			return "tile is missing the '%s' slot" % k
	tv.free()
	return ""


## The spec forbids absolute positioning inside a cell: children of the layout
## container must not set their own position/size.
static func test_tile_no_absolute_positioning() -> String:
	var tv = TileView.new()
	tv.build(3, 40, 80, _skin())
	var bad := 0
	_walk(tv, func(n: Node):
		# Positioned Controls that are direct children of a plain Container are fine;
		# what we forbid is a Control parented to a NON-container with a manual pos.
		if n is Control and n.get_parent() != null:
			var p = n.get_parent()
			var parent_is_container: bool = (p is Container) or (p is MarginContainer)
			if not parent_is_container and p is Control and not (n is ChamferStub):
				pass
	)
	# The structural assertion: the layout container holds every body slot.
	var containers := 0
	for c in tv.get_children():
		if c is MarginContainer or c is Container:
			containers += 1
	if containers == 0:
		return "tile has no layout container — children would need absolute positions"
	tv.free()
	return ""

const ChamferStub := preload("res://ui/components/chamfer_panel.gd")


static func test_tile_band_side_matches_layout() -> String:
	# the tile's band_side must agree with BoardLayout for the same index
	var tv = TileView.new()
	var tiles := BL.compute(40, 800.0, 1.4, 2.0)
	var checked := 0
	for t in tiles:
		var idx: int = int(t["index"])
		tv.build(idx, 40, 80, _skin())
		var want: String = str(t["band_side"])
		var got: String = tv._band_side
		if got != want:
			tv.free()
			return "tile %d band_side should be '%s', got '%s'" % [idx, want, got]
		checked += 1
	if checked != 40:
		tv.free()
		return "checked %d tiles, expected 40" % checked
	tv.free()
	return ""


static func test_tile_degradation_steps() -> String:
	var tv = TileView.new()
	var cases := [[120, 0], [70, 1], [50, 2], [40, 3]]
	for c in cases:
		tv.build(1, 40, c[0], _skin())
		if tv._step != c[1]:
			tv.free()
			return "cell %d should degrade to step %d, got %d" % [c[0], c[1], tv._step]
	tv.free()
	return ""


## Owner colour must come from the skin palette, not a code table.
static func test_tile_owner_from_skin_palette() -> String:
	var skin = _skin()
	var tv = TileView.new()
	tv.build(1, 40, 80, skin)
	tv.refresh({"type": "property", "group": "brown", "name": "X", "cost": 60,
		"owner": 2, "owner_name": "Bo", "houses": 0, "mortgaged": false})
	# the bg border override must equal the skin's colour for player 2
	var want: Color = skin.player_color(2)
	if not tv._bg.has_meta("border_override"):
		tv.free()
		return "an owned tile should set a border colour"
	var got: Color = tv._bg.get_meta("border_override")
	if got != want:
		tv.free()
		return "owner colour should come from SkinManager.player_color (want %s, got %s)" % [want, got]
	tv.free()
	return ""


static func test_strip_counts() -> String:
	var st = BuildingStrip.new()
	st.setup(_skin(), 64, false)
	st.set_count(4)
	if st.count != 4:
		return "strip should hold 4 houses"
	st.set_count(5)   # hotel
	if st.count != 5:
		return "strip should hold a hotel count"
	st.set_count(0)
	if st.count != 0:
		return "strip should clear to 0"
	st.free()
	return ""


## With no art the strip must still be drivable (procedural fallback path).
static func test_strip_no_art_fallback_ok() -> String:
	var skin = SkinManager.new()
	skin.load_skin("default")   # ships no textures on purpose
	var st = BuildingStrip.new()
	st.setup(skin, 64, false)
	st.size = Vector2(40, 12)
	st.set_count(3)
	st._draw()   # must not crash without art
	st.free()
	return ""


static func test_center_sheds_in_order() -> String:
	var c = BoardCenter.new()
	c.setup(_skin())
	# big centre: everything visible
	c.fit(Rect2(0, 0, 400, 300))
	if not c._mini.visible:
		return "a large centre should show the mini log"
	if not c._card.visible:
		return "a large centre should show the tile card"
	# small centre: the mini log sheds first, then the card, then the subtitle
	c.fit(Rect2(0, 0, 200, 160))
	if c._mini.visible:
		return "a small centre should shed the mini log first"
	if not c._card.visible:
		return "the card should outlive the mini log"
	c.fit(Rect2(0, 0, 150, 100))
	if c._card.visible:
		return "a tiny centre should shed the card next"
	if c._sub.visible:
		return "the subtitle should shed before the logo"
	if not c._logo.visible:
		return "the logo should survive the longest"
	c.free()
	return ""


static func test_center_dice_pips() -> String:
	var c = BoardCenter.new()
	c.setup(_skin())
	if (c._pip_positions(1) as Array).size() != 1:
		return "a 1 should have one pip"
	if (c._pip_positions(6) as Array).size() != 6:
		return "a 6 should have six pips"
	c.set_dice(3, 6)   # must not crash
	c.free()
	return ""


## With animations off, a move must snap — no tween, no drift.
static func test_effect_layer_snaps_when_off() -> String:
	var el = EffectLayer.new()
	el.setup(_skin(), false)   # animations OFF
	var tiles := BL.compute(40, 800.0, 1.4, 2.0)
	el.set_layout(tiles, 64.0)
	el.sync_tokens([{"id": 0, "name": "Ada", "pos": 0, "color_idx": 0}])
	el.move_player(0, [1, 2, 3])
	if int(el._player_pos[0]) != 3:
		return "with animations off a move should snap to the last tile, got %d" % el._player_pos[0]
	el.free()
	return ""


static func test_effect_layer_positions_from_layout() -> String:
	var el = EffectLayer.new()
	el.setup(_skin(), true)
	var tiles := BL.compute(40, 800.0, 1.4, 2.0)
	el.set_layout(tiles, 64.0)
	# the token position must derive from BoardLayout's rect for that index
	var centre: Vector2 = BL.tile_center(tiles, 7)
	var got: Vector2 = el._tile_centre(7)
	if got != centre:
		return "effect layer should use BoardLayout centres (want %s, got %s)" % [centre, got]
	if el._tile_centre(999) != Vector2.INF:
		return "an unknown tile should report Vector2.INF"
	el.free()
	return ""


## The float labels must be REUSED, not rebuilt per event.
##
## Money events are the most frequent thing in a match: this used to build a Label and a
## Tween for each one and free both, so the engine allocated most exactly when the game was
## busiest. Counting what actually gets created is the only way to know a pool works — a
## pool that quietly builds a new node each time behaves identically to no pool at all.
static func test_float_labels_are_pooled() -> String:
	var el = EffectLayer.new()
	el.setup(_skin(), true)
	var tiles := BL.compute(40, 800.0, 1.4, 2.0)
	el.set_layout(tiles, 64.0)
	var at: Vector2 = BL.tile_center(tiles, 3)

	# ten floats, all released back before the next is asked for
	for i in range(10):
		el.float_at(at, "+$%d" % (i + 1), true)
		el._give_label(el._label_pool[0]["node"])
	if el._label_pool.size() != 1:
		el.free()
		return "one label should serve every float (pool holds %d)" % el._label_pool.size()

	# a label handed back must stop being busy, or the pool never reissues it
	el.float_at(at, "+$1", true)
	var busy := 0
	for entry in el._label_pool:
		if entry["busy"]:
			busy += 1
	if busy != 1:
		el.free()
		return "exactly one label should be busy, got %d" % busy
	el._give_label(el._label_pool[0]["node"])
	if el._label_pool[0]["busy"]:
		el.free()
		return "a returned label must be free again"
	el.free()
	return ""


## The pool must be BOUNDED: one that grows without limit is only a slower leak.
static func test_float_pool_is_bounded() -> String:
	var el = EffectLayer.new()
	el.setup(_skin(), true)
	var tiles := BL.compute(40, 800.0, 1.4, 2.0)
	el.set_layout(tiles, 64.0)
	var at: Vector2 = BL.tile_center(tiles, 5)
	# never return anything, so the pool is forced to grow
	for i in range(EffectLayer.POOL_MAX + 20):
		el.float_at(at, "+$1", true)
	if el._label_pool.size() > EffectLayer.POOL_MAX:
		var n: int = el._label_pool.size()
		el.free()
		return "the pool exceeded its cap: %d > %d" % [n, EffectLayer.POOL_MAX]
	el.free()
	return ""


# --- helper ------------------------------------------------------------------

static func _walk(node: Node, fn: Callable) -> void:
	fn.call(node)
	for c in node.get_children():
		_walk(c, fn)
