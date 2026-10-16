extends RefCounted
## E-4 tests (master-fix-plan §2, D12): an AUCTION is visible on the sheet AND on the board.
##
## The defect these exist for: the auction modal showed the lot, the standing bid and the leader -
## and no clock at all. A bidder was told the price to beat but not how long they had to beat it,
## which is the only other thing an auction is about. Worse, the plate that would tell a SPECTATOR
## an auction was even running did not exist: someone watching the board saw the same turn label as
## during any other phase, so the most dramatic moment in the game was invisible from the ring.
##
## The data was never missing. `seat_manager` already fills timer_window / timer_elapsed /
## timer_active for whatever seat holds the decision, and during an auction that is the
## auction_timer - so the sheet needed a render, not new plumbing.

const ModalHost := preload("res://ui/modal_host.gd")
const BoardScene := preload("res://visual/board_scene.gd")
const I18n := preload("res://i18n/i18n.gd")

const SEATS := [
	{"pid": 0, "name": "Neuro", "color": Color(0.4, 0.6, 0.9), "input_driver": "SDK"},
	{"pid": 1, "name": "Host", "color": Color(0.9, 0.6, 0.4), "input_driver": "LOCAL"},
]
const BOARD := [
	{"index": 24, "name": "Harbor Station", "short": "Harbor Stn", "cost": 200},
]


static func test_list() -> Array[String]:
	return [
		"test_sheet_shows_the_timer_when_the_clock_runs",
		"test_sheet_counts_down_not_up",
		"test_sheet_says_so_when_there_is_no_clock",
		"test_board_plate_names_the_lot_and_the_leader",
		"test_board_plate_updates_on_a_new_bid",
	]


static func _auction_proj(high: int, leader: int, window: float, elapsed: float) -> Dictionary:
	return {
		"phase": "AUCTION",
		"board": BOARD,
		"timer_window": window,
		"timer_elapsed": elapsed,
		"timer_active": window > 0.0,
		"pending": {"type": "auction", "tile": 24, "high": high, "high_player": leader, "bidder": 0},
	}


static func _texts(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(str((n as Label).text))
	elif n is Button:
		out.append(str((n as Button).text))
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


static func _has_name(n: Node, want: String) -> bool:
	if str(n.name) == want:
		return true
	for c in n.get_children():
		if _has_name(c, want):
			return true
	return false


## --- the sheet --------------------------------------------------------------------------------

static func test_sheet_shows_the_timer_when_the_clock_runs() -> String:
	I18n.set_locale("ru")
	var mh = ModalHost.new()
	mh.show_auction(_auction_proj(300, 1, 15.0, 3.0), SEATS, 0)
	if not _has_name(mh, "auction-timer"):
		return "an auction with a running clock must show a timer"
	# the remaining time must be on screen as a number a bidder can act on
	var joined := " ".join(_texts(mh))
	mh.free()
	if joined.find("12") < 0:
		return "with a 15s window and 3s elapsed the sheet must say 12s left; it rendered: %s" % joined
	return ""


static func test_sheet_counts_down_not_up() -> String:
	# The regression this guards: rendering `timer_elapsed` (which GROWS) instead of the remainder
	# reads plausibly on every individual frame and is wrong on all of them. Two moments, two numbers.
	I18n.set_locale("ru")
	var a = ModalHost.new()
	a.show_auction(_auction_proj(300, 1, 20.0, 2.0), SEATS, 0)
	var first := " ".join(_texts(a))
	a.free()
	var b = ModalHost.new()
	b.show_auction(_auction_proj(300, 1, 20.0, 15.0), SEATS, 0)
	var second := " ".join(_texts(b))
	b.free()
	if first == second:
		return "the clock reads the same at 2s and 15s elapsed - it is showing elapsed, not remaining"
	if first.find("18") < 0:
		return "20s window at 2s elapsed must read 18s left; got: %s" % first
	if second.find("5") < 0:
		return "20s window at 15s elapsed must read 5s left; got: %s" % second
	return ""


static func test_sheet_says_so_when_there_is_no_clock() -> String:
	# auction_timer = 0 is the engine's own "no limit" value. The sheet must say that in words rather
	# than showing a ring frozen at zero, which reads as "time is up".
	I18n.set_locale("ru")
	var mh = ModalHost.new()
	mh.show_auction(_auction_proj(0, -1, 0.0, 0.0), SEATS, 0)
	if _has_name(mh, "auction-timer"):
		mh.free()
		return "an auction with no clock must NOT show a timer ring"
	var joined := " ".join(_texts(mh))
	mh.free()
	if joined.find(I18n.t("modal.auction_no_timer")) < 0:
		return "the sheet must say the auction has no time limit; it rendered: %s" % joined
	return ""


## --- the board plate --------------------------------------------------------------------------

static func _board() -> Control:
	var b: Control = BoardScene.new()
	b.size = Vector2(900, 900)
	b.call("_load_board")
	b.call("_build_centre")
	b.call("_layout")
	return b


static func test_board_plate_names_the_lot_and_the_leader() -> String:
	# A spectator watching the RING must be able to tell an auction is running and who leads it.
	var b := _board()
	b.sync(_auction_proj(300, 1, 15.0, 1.0), SEATS, 0)
	var plate := str(b.get("_banner").text)
	# the plate names the lot by its FULL name: the centre of the board has room for it, and the
	# short form exists only because a 65px cell does not.
	if plate.find("Harbor Station") < 0:
		b.free()
		return "the auction plate must name the lot; got '%s'" % plate
	if plate.find("300") < 0:
		b.free()
		return "the auction plate must carry the standing bid; got '%s'" % plate
	if plate.find("Host") < 0:
		b.free()
		return "the auction plate must name the leading bidder; got '%s'" % plate
	b.free()
	return ""


static func test_board_plate_updates_on_a_new_bid() -> String:
	# "обновляется каждым bid" - a plate frozen at the opening price is worse than none, because it
	# looks live.
	var b := _board()
	b.sync(_auction_proj(150, 0, 15.0, 1.0), SEATS, 0)
	var first := str(b.get("_banner").text)
	b.sync(_auction_proj(420, 1, 15.0, 4.0), SEATS, 0)
	var second := str(b.get("_banner").text)
	b.free()
	if first.find("150") < 0:
		return "the plate must show the first bid (150); got '%s'" % first
	if second.find("420") < 0:
		return "the plate must follow the new bid (420); got '%s'" % second
	if first == second:
		return "the plate did not change when the bid did"
	return ""
