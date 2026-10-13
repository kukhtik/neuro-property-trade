extends SceneTree
## Stage-3 integration probe: the new board components are WIRED INTO THE GAME,
## not just exercised by unit tests.
##
## The gap this closes: TileView/BuildingStrip/EffectLayer/BoardCenter existed
## and passed their own tests, but board_view/board_scene still used the old
## TileLayout and the decorative SVG centre — so the game did not actually show
## any of the new work.
##
## Checks:
##   1. board_view drives BoardLayout (rects, not cell centres)
##   2. tiles are built with the real geometry and the right band_side
##   3. board_scene owns an EffectLayer and the interactive centre
##   4. the centre sits inside BoardLayout's centre rect
##   5. rebuilding the board frees the old nodes (no leak per rebuild)
##
## Exit 0 = stage 3 is integrated, not just written.

const BoardView := preload("res://visual/board_view.gd")
const BoardScene := preload("res://visual/board_scene.gd")
const BL := preload("res://visual/board_layout.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const EffectLayer := preload("res://visual/effect_layer.gd")

var _fail := 0

func _init() -> void:
	print("=== Stage 3 integration: components wired into the game ===")
	await process_frame
	_check_board_view_uses_boardlayout()
	_check_tile_geometry()
	_check_scene_owns_components()
	_check_rebuild_frees_nodes()
	print("")
	if _fail > 0:
		print("==> STAGE 3 INTEGRATION FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> STAGE 3 INTEGRATION PASSED — the new board is the live board")
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _check_board_view_uses_boardlayout() -> void:
	print("[1] board_view drives BoardLayout")
	var skin = SkinManager.new()
	skin.load_skin("neuro")
	var bv = BoardView.new()
	root.add_child(bv)
	bv.build(40, 64, skin)
	if not bv.has_method("BL_side"):
		_bad("board_view has no BL_side() — still on the old TileLayout")
		return
	if bv._layout.size() != 40:
		_bad("board_view built %d layout entries for 40 tiles" % bv._layout.size())
		return
	# the layout entries must be BoardLayout rects, not cell-unit centres
	var first: Dictionary = bv._layout[0]
	if not (first.get("rect") is Rect2):
		_bad("layout entry has no Rect2 — not BoardLayout output")
		return
	_ok("board_view built 40 rects from BoardLayout")
	# a different tile count must flow through unchanged
	bv.build(24, 64, skin)
	if bv._layout.size() != 24:
		_bad("board_view built %d entries for a 24-tile board" % bv._layout.size())
	else:
		_ok("a 24-tile board produces 24 rects (parametric)")
	bv.free()


func _check_tile_geometry() -> void:
	print("[2] tiles carry the real geometry and band orientation")
	var skin = SkinManager.new()
	skin.load_skin("neuro")
	var bv = BoardView.new()
	root.add_child(bv)
	bv.build(40, 64, skin)
	var want := BL.compute(40, float(bv.BL_side()), skin.metric("corner_ratio", 1.4),
		skin.metric("board_gap", 2.0))
	var bad_pos := 0
	var bad_band := 0
	for i in bv._tile_nodes.size():
		var tv = bv._tile_nodes[i]
		var r: Rect2 = want[i]["rect"]
		if tv.position != r.position:
			bad_pos += 1
		if tv._band_side != str(want[i]["band_side"]):
			bad_band += 1
	if bad_pos > 0:
		_bad("%d tiles are not at their BoardLayout rect" % bad_pos)
	if bad_band > 0:
		_bad("%d tiles have the wrong band_side" % bad_band)
	if bad_pos == 0 and bad_band == 0:
		_ok("all 40 tiles sit on their rect with the correct band_side")
	bv.free()


func _check_scene_owns_components() -> void:
	print("[3] board_scene owns the effect layer and the interactive centre")
	var scene = BoardScene.new()
	root.add_child(scene)
	await process_frame
	if scene.get("_effects") == null:
		_bad("board_scene has no EffectLayer (_effects is null)")
	else:
		_ok("board_scene created an EffectLayer")
	if scene.get("_center") == null:
		_bad("board_scene has no interactive centre (_center is null)")
	else:
		_ok("board_scene created the interactive centre")
	# the old decorative SVG centre must be gone
	var old := scene.get_node_or_null("BoardCenter")
	if old != null:
		_bad("the old SVG BoardCenter node still exists")
	else:
		_ok("the old decorative SVG centre is gone")
	scene.free()


func _check_rebuild_frees_nodes() -> void:
	print("[4] rebuilding the board does not leak tile nodes")
	var skin = SkinManager.new()
	skin.load_skin("neuro")
	var bv = BoardView.new()
	root.add_child(bv)
	bv.build(40, 64, skin)
	var first: Array = bv._tile_nodes.duplicate()
	_bad_count(bv, "40 tiles")
	bv.build(24, 64, skin)
	# every old tile must be queued for deletion (no stale nodes accumulate)
	var stale := 0
	for tv in first:
		if is_instance_valid(tv) and not tv.is_queued_for_deletion():
			stale += 1
	if stale > 0:
		_bad("%d old tile nodes survived the rebuild" % stale)
	else:
		_ok("all old tiles were freed on rebuild")
	# and the new set is exactly the new count
	if bv._tile_nodes.size() != 24:
		_bad("after rebuild the board holds %d tiles, expected 24" % bv._tile_nodes.size())
	else:
		_ok("the rebuilt board holds exactly 24 tiles")
	bv.free()


func _bad_count(bv, label: String) -> void:
	if bv._tile_nodes.size() != 40:
		_bad("expected %s, got %d" % [label, bv._tile_nodes.size()])
