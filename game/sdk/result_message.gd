extends RefCounted
## The SUCCESS MESSAGE of an action result.
##
## BEST_PRACTICES.md, "Action Results": "On success, use the `message` to describe any state
## that changed as a result of her action that would be helpful for her to know (e.g. the card
## she drew, the new board state). If nothing meaningful changed, omit it."
##
## Until this existed the adapter answered `ExecutionResult.success()` with an EMPTY message -
## the one point where this integration did not follow the published guidance.
##
## Pure: it reads the engine's events and the projection, returns a string, mutates nothing.
## That is also why it is a separate module: the adapter is a Node that cannot be built
## headless (the SDK's `Websocket` autoload does not resolve in --script mode), so a rule
## that must be TESTED cannot live there.
##
## The wording is deliberately short and uses the same tile names and seat names the model
## already sees in the projection, so the result and the journal speak one language.

## Build the message for a successful action. Returns "" when there is nothing to describe
## (the caller then sends a success result with an empty message, which is what the spec
## asks for: "if nothing meaningful changed, omit it").
func build(engine, proj: Dictionary, events: Array) -> String:
	if engine == null or events.is_empty():
		return ""
	var names: Dictionary = {}
	for p in proj.get("players", []):
		# the projection names the seat by its INDEX in the players array, not by "pid"
		names[int(p.get("index", -1))] = str(p.get("name", "?"))
	var lines: Array[String] = []
	for ev in events:
		var e: Dictionary = ev
		var etype: String = str(e.get("type", ""))
		if etype == "":
			continue
		var line := _describe(etype, e.get("data", {}), names, proj)
		if line != "":
			lines.append(line)
	if lines.is_empty():
		return ""
	var out := ""
	# The LAST three lines: what just happened, not the whole history.
	for i in range(maxi(0, lines.size() - 3), lines.size()):
		if out != "":
			out += " "
		out += lines[i]
	# What she may do now - the same legal set the next force will carry.
	var legal: Array = proj.get("legal", [])
	if legal.size() > 0:
		out += " Now legal: " + ", ".join(legal)
	return out


## One engine event -> one human sentence. The vocabulary is the same the journal uses.
func _describe(etype: String, data: Dictionary, names: Dictionary, proj: Dictionary) -> String:
	var tile_name := _tile_name(int(data.get("tile", -1)), proj)
	var amount: int = int(data.get("amount", data.get("cost", 0)))
	match etype:
		"roll":
			return "You rolled %d+%d." % [int(data.get("a", 0)), int(data.get("b", 0))]
		"move":
			return "You moved to %s." % tile_name
		"purchase":
			return "You bought %s for $%d." % [tile_name, int(data.get("cost", 0))]
		"pass":
			return "You passed on %s." % tile_name
		"pass_on_purchase":
			return "You passed on %s; it went to auction." % tile_name
		"rent":
			return "You paid $%d rent on %s." % [int(data.get("amount", 0)), tile_name]
		"tax":
			return "You paid $%d tax." % int(data.get("amount", 0))
		"build":
			return "You built on %s." % tile_name
		"sell":
			return "You sold a house on %s." % tile_name
		"mortgage":
			return "You mortgaged %s." % tile_name
		"unmortgage":
			return "You unmortgaged %s." % tile_name
		"jail":
			return "You went to jail."
		"card_draw", "card_gain", "card_land", "card_null":
			return "You drew a card."
		"auction_start":
			return "The auction for %s started." % tile_name
		"auction_bid":
			return "The bid for %s is $%d." % [tile_name, int(data.get("amount", 0))]
		"auction_win":
			return "You won %s at auction for $%d." % [tile_name, int(data.get("amount", 0))]
		"trade":
			return "The trade went through."
		"trade_declined":
			return "The trade was declined."
		"bankrupt":
			return "%s went bankrupt." % str(names.get(int(data.get("player", -1)), "A player"))
		"go_bonus":
			return "You collected the $%d start bonus." % int(data.get("amount", 0))
	return ""


func _tile_name(index: int, proj: Dictionary) -> String:
	if index < 0:
		return "the tile"
	for t in proj.get("board", []):
		if int(t.get("index", -1)) == index:
			return str(t.get("name", "the tile"))
	return "the tile"
