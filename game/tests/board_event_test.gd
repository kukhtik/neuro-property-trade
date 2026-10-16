extends RefCounted
## E-2 tests (master-fix-plan §2, D10): an EVENT is visible ON THE BOARD.
##
## The defect these exist for: a purchase, a build, an arrest or a bankruptcy left NO trace on the
## board at all. The only feedback was a three-second toast in a side dock - which a viewer watching
## the ring, or a stream's board-only crop, never sees. The centre of the board already had a
## `_banner`, and it showed the current turn and nothing else, so the biggest surface in the game
## was the least informative.
##
## The fix: `BoardScene.show_event(text, color, tile)` queues a message on that banner with a 3s
## auto-hide, and pulses the participating CELL for a second. These tests drive the scene directly -
## no frame loop, no screenshot - because the questions ("is a message on the banner?", "is THIS
## cell pulsing?") are answerable from the object itself, and a screenshot would answer "is there a
## blob" instead.

const BoardScene := preload("res://visual/board_scene.gd")
const PlayerIdentity := preload("res://core/player_identity.gd")
const TileView := preload("res://visual/tile_view.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

## The board needs a real size to lay out (a Control reports 0x0 in a bare tree, and a 0-cell board
## would make every assertion here vacuous).
const SIDE := Vector2(900, 900)


static func test_list() -> Array[String]:
	return [
		"test_event_lands_on_the_banner",
		"test_banner_clears_after_the_hold",
		"test_event_pulses_its_cell",
		"test_cell_without_an_event_does_not_pulse",
		"test_queue_shows_messages_in_order",
		"test_empty_text_is_not_an_event",
	]


## A real board scene, laid out at a real size. The board reads its own tiles from
## res://data/board.json in `_ready()`, so the test does not fabricate a board - it uses the
## shipping one (40 cells), which is also what makes the flash index meaningful.
##
## THE BUILD IS CALLED BY HAND. `_ready()` does not fire for a node that was never added to a tree,
## and this suite runs inside a bare SceneTree - so a test that simply constructed the scene would
## assert against a board whose `_banner` is null and whose `_tiles` is empty, then "pass" every
## negative ("no cell pulses!", "the banner is empty!") for the worst possible reason.
static func _board() -> Control:
	var b: Control = BoardScene.new()
	b.size = SIDE
	b.call("_load_board")
	b.call("_build_centre")
	# `_layout()` is what builds the TileViews; a Control's `resized` signal does not fire for a
	# node outside a sized tree, so the test calls it directly (the same seam the compact gate uses).
	b.call("_layout")
	b.sync({"phase": "TURN_START", "turn_player": 0, "board": [], "players": []}, [_seat(0, "Neuro")], 0)
	return b


## A seat as the board reads it: `.pid`, `.name`, `.color` (PlayerIdentity-assigned, exactly the
## way seat_config assigns them). A bare Dictionary is not enough - the board dereferences these as
## PROPERTIES and a Dictionary has no `.color`, which throws inside sync().
static func _seat(pid: int, name: String) -> Dictionary:
	# a Dictionary also supports attribute access in GDScript for its string keys, so carrying the
	# same three keys IS a seat-shaped value for the board's purposes.
	return {"pid": pid, "name": name, "color": PlayerIdentity.color_of(pid), "input_driver": "LOCAL"}


static func _advance(b: Control, seconds: float, step: float = 0.1) -> void:
	var t := 0.0
	while t < seconds:
		b.call("_tick_events", step)
		t += step


## --- the banner -------------------------------------------------------------------------------

static func test_event_lands_on_the_banner() -> String:
	var b := _board()
	if bool(b.call("event_banner_active")):
		return "a fresh board must not claim an event is showing"
	b.call("show_event", "Neuro купил «Sunset Blvd» за $60", Color(0.4, 0.8, 0.4), 1)
	_advance(b, 0.2)
	if not bool(b.call("event_banner_active")):
		return "show_event() did not put the message on the banner"
	var text := str(b.call("event_banner_text"))
	if text.find("Sunset Blvd") < 0:
		return "the banner must carry the event text, got '%s'" % text
	b.free()
	return ""


static func test_banner_clears_after_the_hold() -> String:
	# The plan requires auto-hide: "очередь сообщений с автоскрытием (3с)". A banner that never
	# clears would hide the turn label forever - the previous behaviour of this very widget.
	var b := _board()
	b.call("show_event", "Neuro купил «Palm Row» за $60", Color(0.4, 0.8, 0.4), 2)
	_advance(b, 3.5)
	if bool(b.call("event_banner_active")):
		return "the message is still on the banner after the 3s hold"
	if str(b.call("event_banner_text")) != "":
		return "event_banner_text() must be empty once the hold expired"
	b.free()
	return ""


static func test_queue_shows_messages_in_order() -> String:
	# Two events in one batch (the engine logs several per step) must not overwrite each other.
	var b := _board()
	b.call("show_event", "первое: Sunset Blvd", Color.WHITE, 1)
	b.call("show_event", "второе: Palm Row", Color.WHITE, 2)
	_advance(b, 0.2)
	var first := str(b.call("event_banner_text"))
	if first.find("первое") < 0:
		return "the queue must show the FIRST message first, got '%s'" % first
	_advance(b, 3.2)
	var second := str(b.call("event_banner_text"))
	if second.find("второе") < 0:
		return "the queue must show the second message after the first expires, got '%s'" % second
	b.free()
	return ""


static func test_empty_text_is_not_an_event() -> String:
	# An event the journal hides (accounting noise) must not blank the banner for 3 seconds.
	var b := _board()
	b.call("show_event", "   ", Color.WHITE, -1)
	_advance(b, 0.2)
	if bool(b.call("event_banner_active")):
		return "an empty message must not take the banner"
	b.free()
	return ""


## --- the cell flash ---------------------------------------------------------------------------

static func test_event_pulses_its_cell() -> String:
	var b := _board()
	if bool(b.call("cell_flashing", 1)):
		return "no cell may pulse before an event"
	b.call("show_event", "Neuro построил дом на Sunset Blvd", Color.WHITE, 1)
	if not bool(b.call("cell_flashing", 1)):
		return "the event's own cell must pulse"
	# and the flash is transient - the plan says 1s, and a permanent ring would be a state, not news
	_advance(b, 1.4)
	if bool(b.call("cell_flashing", 1)):
		return "the flash must expire after ~1s"
	b.free()
	return ""


static func test_cell_without_an_event_does_not_pulse() -> String:
	var b := _board()
	b.call("show_event", "Neuro купил «Sunset Blvd» за $60", Color.WHITE, 1)
	if bool(b.call("cell_flashing", 2)):
		return "an unrelated cell (Palm Row) must NOT pulse for a Sunset Blvd event"
	# and an event with no cell (-1) must not pulse cell 0 by accident
	b.call("show_event", "матч завершён", Color.WHITE, -1)
	if bool(b.call("cell_flashing", 0)):
		return "an event with no cell must not default to pulsing cell 0 (Start)"
	b.free()
	return ""
