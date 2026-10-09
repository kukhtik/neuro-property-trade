extends Node
const MainScript := preload("res://main.gd")
var _n := 0
var _l = null
func _ready() -> void:
	_l = MainScript.new(); add_child(_l)
func _process(_d: float) -> void:
	_n += 1
	if _n == 20 and _l.has_method("_autostart"): _l.call("_autostart")
	if _n == 200:
		var mgr = _l.get("_manager")
		if mgr != null: mgr.set_process(false)
	if _n == 260:
		var img := get_tree().root.get_texture().get_image()
		for p in [Vector2(700,400), Vector2(800,250), Vector2(600,600), Vector2(950,200)]:
			var col := img.get_pixel(int(p.x), int(p.y)).to_html(false)
			print("--- точка %s = #%s ---" % [p, col])
			_hit(get_tree().root, p, 0)
		get_tree().quit(0)
func _hit(n: Node, p: Vector2, d: int) -> void:
	for c in n.get_children():
		if c is Control:
			var ctl: Control = c
			if ctl.get_global_rect().has_point(p) and ctl.visible:
				var extra := ""
				if ctl is ColorRect: extra = " color=%s" % (ctl as ColorRect).color.to_html(false)
				elif ctl is TextureRect: extra = " TEXTURE"
				elif ctl is PanelContainer or ctl is Panel:
					var sb = ctl.get_theme_stylebox("panel")
					if sb is StyleBoxFlat: extra = " bg=%s" % (sb as StyleBoxFlat).bg_color.to_html(false)
				print("   %s%s %s%s" % ["  ".repeat(d), ctl.name, ctl.get_class(), extra])
		_hit(c, p, d + 1)
