extends RefCounted
## E-1 tests (master-fix-plan §2, D8/D9): a TRADE tells the reader WHAT is being traded.
##
## The defect these exist for: the incoming-trade sheet rendered the composition as a COUNT -
## "Даёт: $200 + 2 тайл(а)   ·   Просит: $150 + 0 тайл(а)" - and the journal line named only the
## partner ("предлагает сделку: Neuro"). A player was therefore asked to ACCEPT or DECLINE a deal
## whose contents they were never shown. "2 tiles" is the same sentence for a brown and a
## dark-blue; tiles are not interchangeable, so the count carries no information at all.
##
## These tests read the composition the way a player does - as TEXT - and refuse a number where a
## name belongs. They deliberately FAIL on the old rendering, which is the whole point.

const AdapterScript := preload("res://ui/core/event_adapter.gd")
const JournalLinesScript := preload("res://ui/core/journal_lines.gd")
const I18n := preload("res://i18n/i18n.gd")
const ModalHost := preload("res://ui/modal_host.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

const TILES := {1: "Sunset Blvd", 6: "Palm Row", 11: "Nob Hills", 24: "Harbor Stn"}
const NAMES := {0: "Neuro", 1: "Host"}


static func test_list() -> Array[String]:
	return [
		"test_adapter_carries_the_trade_composition",
		"test_journal_trade_offer_names_the_tiles",
		"test_journal_completed_trade_names_both_sides",
		"test_journal_trade_never_prints_a_bare_count",
		"test_journal_trade_nothing_side_reads_as_words",
		"test_modal_trade_response_names_every_tile",
	]


static func _ctx() -> Dictionary:
	return {
		"names": NAMES,
		"colors": {0: Color(1, 0, 0), 1: Color(0, 0, 1)},
		"tiles": TILES,
		"dim": Color(0.5, 0.5, 0.5),
	}


## --- the adapter must not throw the composition away -----------------------------------------

static func test_adapter_carries_the_trade_composition() -> String:
	# The engine logs both tile lists and both cash amounts; the UI used to drop them. If the
	# adapter stops carrying them the journal and the modal go silent TOGETHER, so this is the
	# first thing to pin.
	var a = AdapterSheet()
	var row: Dictionary = a.adapt({"type": "trade_proposed", "data": {
		"proposer": 0, "to": 1,
		"give_tiles": [24], "give_cash": 200,
		"want_tiles": [6, 11], "want_cash": 0,
	}})
	if row.is_empty():
		return "the adapter dropped a trade_proposed event entirely"
	if not (row.get("giv", []) as Array).has(24):
		return "give_tiles did not survive adaptation: %s" % str(row.get("giv"))
	if (row.get("wnt", []) as Array).size() != 2:
		return "want_tiles should carry 2 indices, got %s" % str(row.get("wnt"))
	if int(row.get("gvc", -1)) != 200:
		return "give_cash should be 200, got %s" % str(row.get("gvc"))
	if int(row.get("wnc", -1)) != 0:
		return "want_cash should be 0, got %s" % str(row.get("wnc"))
	return ""


## The adapter is instantiated through a helper so a rename of the class cannot break the test.
static func AdapterSheet():
	return AdapterScript.new()


## --- the journal must name the tiles ----------------------------------------------------------

static func test_journal_trade_offer_names_the_tiles() -> String:
	var jl = JournalLinesScript.new()
	jl.reset()
	var line: Dictionary = jl.line_for({"type": "trade_proposed", "data": {
		"proposer": 0, "to": 1,
		"give_tiles": [24], "give_cash": 200,
		"want_tiles": [6], "want_cash": 0,
	}}, _ctx())
	if line.is_empty():
		return "a trade offer must appear in the journal"
	var t := str(line["text"])
	# the ONE thing this line exists to answer
	if t.find("Harbor Stn") < 0:
		return "the offer must name the tile it gives (Harbor Stn); got '%s'" % t
	if t.find("Palm Row") < 0:
		return "the offer must name the tile it asks for (Palm Row); got '%s'" % t
	if t.find("Host") < 0:
		# the line names the RECIPIENT ("offers a trade to X"); the proposer is carried by the
		# line's own `who` column in their seat colour, so naming them again would be the duplicate
		# the WHO column exists to avoid.
		return "the offer must name its recipient (Host); got '%s'" % t
	return ""


static func test_journal_completed_trade_names_both_sides() -> String:
	var jl = JournalLinesScript.new()
	jl.reset()
	var line: Dictionary = jl.line_for({"type": "trade", "data": {
		"proposer": 0, "recipient": 1,
		"give_tiles": [24], "give_cash": 150,
		"want_tiles": [11], "want_cash": 0,
	}}, _ctx())
	if line.is_empty():
		return "a completed trade must appear in the journal"
	var t := str(line["text"])
	for want in ["Harbor Stn", "Nob Hills", "150", "Neuro", "Host"]:
		if t.find(want) < 0:
			return "the completed trade line must carry '%s'; got '%s'" % [want, t]
	return ""


static func test_journal_trade_never_prints_a_bare_count() -> String:
	# THE REGRESSION: the old line was "предлагает сделку: Neuro" (partner only, no composition).
	# A line with an arrow but no NAMES would be the same defect wearing a new shape - so the test
	# demands at least one tile name whenever the event carried tiles.
	var jl = JournalLinesScript.new()
	jl.reset()
	var line: Dictionary = jl.line_for({"type": "trade_proposed", "data": {
		"proposer": 0, "to": 1,
		"give_tiles": [1], "give_cash": 0,
		"want_tiles": [6], "want_cash": 0,
	}}, _ctx())
	var t := str(line.get("text", ""))
	if t.find("Sunset Blvd") < 0 or t.find("Palm Row") < 0:
		return "a trade line carrying tiles must name them all; got '%s'" % t
	if t.find(" тайл") >= 0 or t.find("tile(") >= 0 or t.find("tiles") >= 0:
		return "the count wording survived into the line; got '%s'" % t
	return ""


static func test_journal_trade_nothing_side_reads_as_words() -> String:
	# A one-sided offer ($200 for nothing) must read as a sentence, not as "$200 ⇄ " with a hole.
	var jl = JournalLinesScript.new()
	jl.reset()
	var line: Dictionary = jl.line_for({"type": "trade_proposed", "data": {
		"proposer": 0, "to": 1,
		"give_tiles": [], "give_cash": 0,
		"want_tiles": [6], "want_cash": 0,
	}}, _ctx())
	var t := str(line.get("text", ""))
	var nothing := I18n.t("trade.nothing")
	if t.find(nothing) < 0:
		return "an empty side must read as '%s'; got '%s'" % [nothing, t]
	return ""


## --- the modal must name the tiles ------------------------------------------------------------

static func test_modal_trade_response_names_every_tile() -> String:
	# The sheet the player answers from. Built for real (a Control), then its text is READ BACK -
	# a constant can be right while the widget ignores it.
	I18n.set_locale("ru")
	var mh = ModalHost.new()
	var skin := SkinManager.new()
	skin.load_skin()
	mh.show_trade_response({
		"pending": {"type": "trade", "proposer": 0, "recipient": 1,
			"give_tiles": [24], "give_cash": 200,
			"want_tiles": [6, 11], "want_cash": 0},
		"board": [
			{"index": 24, "name": "Harbor Station", "short": "Harbor Stn"},
			{"index": 6, "name": "Palm Row", "short": "Palm Row"},
			{"index": 11, "name": "Nob Hills", "short": "Nob Hills"},
		],
	}, [{"pid": 0, "name": "Neuro"}, {"pid": 1, "name": "Host"}])
	var seen := ""
	for c in mh.get_children():
		seen += _all_text(c) + "\n"
	mh.free()
	for want in ["Harbor Stn", "Palm Row", "Nob Hills", "200"]:
		if seen.find(want) < 0:
			return "the trade sheet must show '%s'; it rendered:\n%s" % [want, seen.strip_edges()]
	# and the COUNT wording must be gone: "0 тайл" is the defect this replaces
	if seen.find(" тайл") >= 0:
		return "the sheet still counts tiles instead of naming them:\n%s" % seen.strip_edges()
	return ""


## Every Label's text under a node, newline-separated. Used instead of a screenshot: the question
## is what STRING the widget carries, and the engine answers that directly.
static func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += str((n as Label).text) + "\n"
	elif n is RichTextLabel:
		out += str((n as RichTextLabel).text) + "\n"
	elif n is Button:
		out += str((n as Button).text) + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out
