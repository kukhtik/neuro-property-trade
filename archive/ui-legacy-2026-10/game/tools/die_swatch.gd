extends Node2D
## Scratch diagnostic: does a bare Chamfer paint its fill with a dice token?
## Paints a Chamfer with fill_token dice_bg at the die's real size, then reads the pixels.

const SM := preload("res://visual/skin_manager.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")

var _n := 0
var _ch: Control

func _ready() -> void:
	var s := SM.new()
	s.load_skin("neuro")
	_ch = Chamfer.new()
	_ch.set_skin(s)
	_ch.fill_token = "dice_bg"
	_ch.border_token = "dice_ink"
	_ch.cut = "none"
	_ch.size = Vector2(38, 48)
	_ch.position = Vector2(50, 50)
	add_child(_ch)

	# second control: EXACTLY the board_center dice pattern — a plain Control that draws
	# itself through the `draw` signal callback. Does this pattern paint at all?
	var die := Control.new()
	die.size = Vector2(38, 38)
	die.position = Vector2(200, 100)
	die.set_meta("value", 4)
	die.draw.connect(_draw_die_probe.bind(die))
	add_child(die)
	print("SWATCH skin dice_bg=%s fill_token=%s" % [str(s.color("dice_bg")), str(_ch.get("fill_token"))])


func _draw_die_probe(holder: Control) -> void:
	var v: int = int(holder.get_meta("value", 1))
	var s: Vector2 = holder.size
	var side: float = maxf(4.0, minf(s.x, s.y))
	var base := Rect2((s - Vector2(side, side)) * 0.5, Vector2(side, side))
	holder.draw_rect(base, Color(0.95, 0.96, 0.98))
	var col := Color(0.09, 0.10, 0.12)
	for p in [[0, 0], [2, 0], [0, 2], [2, 2]]:
		var c := base.position + Vector2(4 + (float(p[0]) + 0.5) * 10, 4 + (float(p[1]) + 0.5) * 10)
		holder.draw_circle(c, 3.1, col)

func _process(_dt: float) -> void:
	_n += 1
	if _n == 20:
		var img := get_viewport().get_texture().get_image()
		img.save_png("C:/Users/Nitro/Desktop/neuro-property-trade/build/cap/swatch.png")
		for xy in [[60, 60], [69, 70], [80, 90]]:
			var p := img.get_pixel(xy[0], xy[1])
			print("SWATCH px %d,%d = %s" % [xy[0], xy[1], str(p)])
		for xy in [[210, 110], [220, 118], [205, 105]]:
			var p2 := img.get_pixel(xy[0], xy[1])
			print("SWATCH die px %d,%d = %s" % [xy[0], xy[1], str(p2)])
		print("SWATCH size=%s visible=%s" % [str(_ch.size), str(_ch.is_visible_in_tree())])
		get_tree().quit(0)
