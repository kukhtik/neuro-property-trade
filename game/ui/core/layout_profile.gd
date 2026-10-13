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

## Auto-collapse rails: the v3 mockup rails BOTH docks on the compact profile.
const RAIL_WIDTH := 48

## Panel widths per profile (v3 mockup: --dock-l 268 / --dock-l-wide 280; --dock-r 344 /
## --dock-r-wide 380).
const LEFT_W := {WIDE: 280, DESKTOP: 268, COMPACT: 240}
const RIGHT_W := {WIDE: 380, DESKTOP: 344, COMPACT: 300}

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
## v3 mockup: the compact profile (x < 1280 or h <= 700) turns BOTH docks into rails;
## wider windows keep both docks open.
func rail_left() -> bool:
	return is_compact()


## Should the right journal panel auto-collapse to a rail?
func rail_right() -> bool:
	return is_compact()


func left_width() -> int:
	return LEFT_W.get(id, 240)


func right_width() -> int:
	return RIGHT_W.get(id, 300)


## TopBar / console heights. The v3 mockup keeps the header at 56 (--hdr-h) and the console
## at 96 (--cons-h) in every profile — the compact profile trims their CONTENT, not their
## height (steps hidden, brand name hidden, ticker instead of the dock toast host).
func top_height() -> int:
	return 56


func bottom_height(stream: bool = false) -> int:
	if stream:
		return 76 if is_compact() else 92
	return 96


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
