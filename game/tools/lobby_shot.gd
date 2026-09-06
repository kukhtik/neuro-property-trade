extends Node
const MainScript := preload("res://main.gd")
func _ready() -> void:
	var l = MainScript.new()
	add_child(l)
	for _i in 20: await get_tree().process_frame
	var vp := get_tree().root
	for _i in 6: await get_tree().process_frame
	var img := vp.get_texture().get_image()
	img.save_png("ui_lobby.png")
	print("SAVED ui_lobby.png ", img.get_width(), "x", img.get_height())
	get_tree().quit(0)
