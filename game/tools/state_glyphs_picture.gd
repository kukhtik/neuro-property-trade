extends Node
## A PICTURE of the board's new visual grammar: the same cell, six states, side by side.
##
## The unit test pins the grammar as data; the gate STATE-GLYPHS measures it in pixels. This
## probe makes it LOOKABLE: a row of cells - free, owned, one house, three houses, a hotel,
## a mortgage - rendered at a real size and saved as a PNG, so the owner can see the grammar
## without launching the game.
##
## Run: godot --path game --rendering-driver opengl3 res://tools/state_glyphs_picture.tscn
## Verdict: ==> STATE-GLYPHS PICTURE <path>

const TileView := preload("res://visual/tile_view.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

const CELL := 150.0
const CELLS := [
	{"name": "free", "data": {"short": "Cedar Ave", "cost": 100, "type": "property"},
		"entry": {}},
	{"name": "owned", "data": {"short": "Cedar Ave", "cost": 100, "type": "property"},
		"entry": {"owner": 0, "owner_name": "Хост", "owner_color": Color(1.0, 0.44, 0.68)}},
	{"name": "house1", "data": {"short": "Cedar Ave", "cost": 100, "type": "property"},
		"entry": {"owner": 1, "owner_name": "Neuro", "owner_color": Color(0.37, 0.89, 1.0),
			"houses": 1}},
	{"name": "house3", "data": {"short": "Cedar Ave", "cost": 100, "type": "property"},
		"entry": {"owner": 1, "owner_name": "Neuro", "owner_color": Color(0.37, 0.89, 1.0),
			"houses": 3}},
	{"name": "hotel", "data": {"short": "Crest Sq", "cost": 260, "type": "property"},
		"entry": {"owner": 3, "owner_name": "Mira", "owner_color": Color(0.71, 1.0, 0.42),
			"houses": 5}},
	{"name": "mortgage", "data": {"short": "Oak Street", "cost": 140, "type": "property"},
		"entry": {"owner": 2, "owner_name": "evil", "owner_color": Color(0.91, 0.15, 0.31),
			"mortgaged": true}},
]
const CAPTIONS := ["свободна", "владелец", "1 дом", "3 дома", "отель", "в залоге"]


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("==> STATE-GLYPHS PICTURE SKIPPED: no renderer (headless)")
		get_tree().quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	var w := int(CELL * float(CELLS.size())) + 40
	var h := int(CELL) + 90
	DisplayServer.window_set_size(Vector2i(w, h))
	get_tree().root.size = Vector2i(w, h)
	await get_tree().process_frame

	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.024, 0.075)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var row := HBoxContainer.new()
	row.position = Vector2(20, 16)
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	var skin := SkinManager.new()
	for spec in CELLS:
		var tv := TileView.new()
		tv.custom_minimum_size = Vector2(CELL, CELL)
		row.add_child(tv)
		tv.setup(skin, int(spec.get("name", "").length()), spec["data"], CELL, "b", CELL)
		tv.apply(spec["entry"])

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out := "user://state-glyphs.png"
	var err := img.save_png(out)
	if err != OK:
		print("==> STATE-GLYPHS PICTURE FAILED: could not save the frame (%d)" % err)
		get_tree().quit(1)
		return
	print("==> STATE-GLYPHS PICTURE %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)
