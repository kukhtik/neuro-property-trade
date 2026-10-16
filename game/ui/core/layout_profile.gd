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
## Below this the two side DOCKS give way to 48px RAILS (owner's relayout, 16.10 evening).
##
## Not a taste: the board is height-limited at every profile but the narrowest, so the 612px the two
## docks take is mostly width the board could not use - while at 1000x650 the docks starve it to a
## 328px square (30px cells) where rails leave 490px (45px cells). Measured before choosing.
const RAILS_BELOW := 1500

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


## Below the minimum supported width the layout is not guaranteed.
func is_supported() -> bool:
	return screen.x >= MIN_WIDTH


## REMOVED (R-3, master-fix-plan §1): `text_scale() == 0.92 in compact` lived here with ZERO
## consumers - the same dead-ladder shape as `label_step` before R-1 (tested in ui_core_test,
## consumed by nobody). It is not re-wired: the owner's rule is "крупно, но не слишком", which
## forbids shrinking text on a small window; the compact profile trims CONTENT (steps hidden,
## brand hidden, ticker instead of the dock toast), never the type size. The stream profile's
## 1.15 growth lives in UiProfile.text_scale, which is the one that has a consumer.


## Tile-label degradation step. Thresholds are px of cell width.
##
## THE OWNER'S RULE (16.10, evening): A CELL IS NEVER BLANK. He reported "клетки почему-то пустые
## вообще" and the live tree agreed - at 1440x900 the board was 796x449 (NOT square: the console ate
## 362px), so every cell was 41px, every cell fell past the old step 3, the NAME was hidden by design
## and the 12 non-property cells (Start, Jail, Chest, Fortune, Tax) additionally have no price - they
## rendered as 40x40 EMPTY squares. The board's own data was fine; the layout starved it.
##
## So the ladder no longer has a "hide the name" rung. The steps still shed SECONDARY detail (the
## price, the house squares) as a cell tightens, because a name is the cell's identity and a price is
## an attribute of it - but the name stays to the last step, and step 3 now means "smallest type",
## not "silent". The floor is deliberately BELOW any board the layout can produce (the smallest
## supported profile gives ~53px cells after the relayout), so it is a guard against a future
## regression, not a rung anyone reaches today.
static func label_step(cell_width: float) -> int:
	if cell_width >= 78.0:
		return 0
	if cell_width >= 60.0:
		return 1   # house squares give way to the textual counter
	if cell_width >= 44.0:
		return 2   # price hidden, the name still carries the cell
	return 3       # smallest type: name KEPT (never hidden), price hidden


## A cell must never render with nothing on it. One place states it, so the tiles, the gate and the
## tests agree: at this size and above, a ring cell always shows a name.
const CELL_NAME_ALWAYS_MIN := 24.0


## THE GLANCE FLOOR (docs/program.md P1.1, owner correction of 16.10).
##
## The stream promise is a picture drawn at a native large resolution that a viewer watches on a
## phone. What the viewer must grasp from ONE glance - whose turn it is, what is happening, the
## money, the journal heading - is therefore judged by its EFFECTIVE size after the frame is scaled
## down to a phone:
##
##     effective_px = frame_px * (PHONE_CSS_WIDTH / frame_width)
##
## With a 390px phone and a 1920px frame the factor is 390/1920 = 0.203, so 12 legible px on the
## phone need ~59px in the frame. That is a LAYOUT value (it depends only on the frame size), which
## is why it lives here and not in a role profile: the owner's rule is that scale is a property of
## the resolution, identical for the player, the broadcast and the web.
##
## HOWEVER - measured 2026-10-16, and this is why these helpers have NO consumer yet: applying the
## floor to the shell at ANY normal window breaks it. Scaling the header and journal text to ~60px
## at 1440x900 turned SG-01 red (`header height 166.0 != 56`) and SG-02 red (`needs 2028px in a
## 1440px frame`, 670 findings). And the promise itself is self-defeating at large frames: a 13px
## label reads 3.5px on a phone from a 1440 frame, 2.6px from 1920, 1.3px from 3840 - because the
## frame is scaled down by exactly the factor the text would have to grow by. So "readable from a
## phone" and "native large resolution" pull against each other, and no uniform text scale settles
## it. The measurement (STREAM-READ, quarantine) reports the number honestly; what to DO about the
## promise is a product decision, deliberately NOT taken by guessing here.
##
## Kept (not deleted) because the arithmetic and the phone width are the single home of the rule:
## the gate and the product must agree on what 12px-on-a-phone means. Do not wire this into a
## component until the product decision is made.
const PHONE_CSS_WIDTH := 390.0
const GLANCE_MIN_PHONE_PX := 12.0     # what must survive the shrink (the gate's floor, one home)
const GLANCE_FRAME_WIDTH := 1920.0    # the frame the floor was derived at (docs/program.md P1.1)


## The in-frame px a glance label would need so that it is >= GLANCE_MIN_PHONE_PX on a phone, for the
## frame width given. Scales with the frame: a 2560 frame would need proportionally more. NOT wired
## into the shell - see the note above. The consumer TODAY is the STREAM-READ gate, which judges its
## measurement against GLANCE_MIN_PHONE_PX and reports this floor, so the gate and the product cannot
## drift about what "legible on a phone" means.
static func glance_floor_px(frame_width: float = GLANCE_FRAME_WIDTH) -> float:
	if frame_width <= 0.0:
		frame_width = GLANCE_FRAME_WIDTH
	return GLANCE_MIN_PHONE_PX * frame_width / PHONE_CSS_WIDTH
