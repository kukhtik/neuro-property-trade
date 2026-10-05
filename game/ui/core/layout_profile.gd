class_name LayoutProfile
extends RefCounted
## Picks a responsive layout profile from the window size. Thresholds live here
## (or in the skin), never inside a component.
##
## Profiles (spec §5.1, owner: windows below 880 px are unsupported):
##   wide     >= 1600 wide
##   desktop  >= 1280
##   compact  < 1280 or <= 700 tall
##
## Panels auto-collapse to a rail below the thresholds; a manual collapse is
## kept until the profile threshold is crossed.
##
## Pure + headless-testable.

const WIDE := "wide"
const DESKTOP := "desktop"
const COMPACT := "compact"

const MIN_WIDTH := 880
const WIDE_MIN := 1600
const DESKTOP_MIN := 1280
const COMPACT_HEIGHT := 700

## Auto-collapse rails.
const RAIL_LEFT_BELOW := 1000
const RAIL_RIGHT_BELOW := 1180
const RAIL_WIDTH := 46

## Panel widths per profile (spec §5.1).
const LEFT_W := {WIDE: 272, DESKTOP: 240, COMPACT: 240}
const RIGHT_W := {WIDE: 340, DESKTOP: 300, COMPACT: 300}

var id := DESKTOP
var screen := Vector2i(1440, 900)


static func for_screen(size: Vector2i) -> LayoutProfile:
	var p := LayoutProfile.new()
	p.screen = size
	if size.x < DESKTOP_MIN or size.y <= COMPACT_HEIGHT:
		p.id = COMPACT
	elif size.x >= WIDE_MIN:
		p.id = WIDE
	else:
		p.id = DESKTOP
	return p


func is_compact() -> bool:
	return id == COMPACT


## Should the left players panel auto-collapse to a rail?
func rail_left() -> bool:
	return screen.x < RAIL_LEFT_BELOW


## Should the right journal panel auto-collapse to a rail?
func rail_right() -> bool:
	return screen.x < RAIL_RIGHT_BELOW


func left_width() -> int:
	return LEFT_W.get(id, 240)


func right_width() -> int:
	return RIGHT_W.get(id, 300)


## TopBar / BottomBar heights (compact trims both).
func top_height() -> int:
	return 38 if is_compact() else 46


func bottom_height(stream: bool = false) -> int:
	if stream:
		return 76 if is_compact() else 92
	return 56 if is_compact() else 72


## Text scale trim for compact (one step down).
func text_scale() -> float:
	return 0.92 if is_compact() else 1.0


## Below the minimum supported width the layout is not guaranteed.
func is_supported() -> bool:
	return screen.x >= MIN_WIDTH


## Tile-label degradation step: 0 = full, 3 = name hidden (tile inspector
## carries it instead). Thresholds are px of cell width.
static func label_step(cell_width: float) -> int:
	if cell_width >= 78.0:
		return 0
	if cell_width >= 60.0:
		return 1   # price hidden
	if cell_width >= 44.0:
		return 2   # smaller font
	return 3       # corner labels and name hidden
