extends Node
## Does the new paint layer actually produce the textures the mockup calls for?
const SkinPaint := preload("res://visual/skin_paint.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
func _ready() -> void:
	var sk = SkinManager.new(); sk.load_skin("neuro")
	var st = SkinPaint.stage_texture(sk, Vector2(64, 40))
	print("stage tex: %s %s" % [st, st.get_size()])
	var fr = SkinPaint.frame_texture(sk, Vector2(64, 64))
	print("frame tex: %s %s" % [fr, fr.get_size()])
	var im = fr.get_image()
	print("  corner TL: %s" % im.get_pixel(1, 1))
	print("  corner BR: %s" % im.get_pixel(62, 62))
	var band = SkinPaint.band_texture(Color("#ff6fae"))
	print("band: %s  top=%s mid=%s bot=%s" % [band.get_size(),
		band.get_image().get_pixel(2,0), band.get_image().get_pixel(2,4),
		band.get_image().get_pixel(2,7)])
	var sweep = SkinPaint.sweep_texture(sk, 300)
	print("sweep: %s" % sweep.get_size())
	get_tree().quit(0)
