extends Control
## Diagonal hatch overlay for a mortgaged tile (spec §4.2). Drawn via _draw
## so it scales with the tile and needs no texture. The stripes are thin
## semi-transparent lines at a 45° angle, ~20% coverage.

const STRIPE_W := 2.0
const STRIPE_GAP := 6.0
const STRIPE_COLOR := Color(0, 0, 0, 0.30)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	# diagonal stripes from top-left to bottom-right
	var step := STRIPE_W + STRIPE_GAP
	var start := -h
	var end := w + h
	var x := start
	while x < end:
		draw_line(Vector2(x, 0), Vector2(x + h, h), STRIPE_COLOR, STRIPE_W)
		x += step
