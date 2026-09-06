extends RefCounted
## Renders a projection Dictionary into a markdown string for the SDK context.
## Pure: no engine access, no side effects. Starts sections at "##" (per SDK
## best practices — avoid "#"). Painfully explicit, ~20 items.

func render(proj: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("## Neuro Property Trade — your view")
	lines.append("")
	lines.append("Phase: %s" % proj.get("phase", ""))
	lines.append("It is player %d's turn." % int(proj.get("turn_player", 0)))
	lines.append("")
	lines.append("## Players")
	for p in proj.get("players", []):
		var jail := ""
		if p.get("in_jail", false):
			jail = " (in jail, %d turns)" % int(p.get("jail_turns", 0))
		lines.append("- %s: $%d, tile %d%s" % [p.get("name", "?"), int(p.get("money", 0)), int(p.get("position", 0)), jail])
	lines.append("")
	lines.append("## Board")
	for t in proj.get("board", []):
		var owner := "unowned"
		var o = t.get("owner", -1)
		if o != -1:
			owner = "owned by %d" % int(o)
		var extra := ""
		if int(t.get("houses", 0)) > 0:
			extra = ", %d houses" % int(t.get("houses", 0))
		if t.get("mortgaged", false):
			extra += ", mortgaged"
		lines.append("- %d. %s (%s) %s%s" % [int(t.get("index", 0)), t.get("name", "?"), t.get("type", "?"), owner, extra])
	lines.append("")
	lines.append("## Pending decision")
	var pending = proj.get("pending", {})
	if pending.is_empty():
		lines.append("- none")
	else:
		match pending.get("type", ""):
			"purchase":
				lines.append("- You may buy tile %d or pass." % int(pending.get("tile", -1)))
			"auction":
				lines.append("- Auction on tile %d. Current high: $%d by player %d. You are the bidder." % [int(pending.get("tile", -1)), int(pending.get("high", 0)), int(pending.get("high_player", -1))])
			"trade":
				lines.append("- Trade proposed by player %d to player %d." % [int(pending.get("proposer", -1)), int(pending.get("recipient", -1))])
			_:
				lines.append("- %s" % str(pending))
	lines.append("")
	lines.append("## Your legal actions")
	var legal = proj.get("legal", [])
	if legal.is_empty():
		lines.append("- none (not your turn)")
	else:
		for a in legal:
			lines.append("- %s" % a)
	lines.append("")
	lines.append("## Your private info")
	var priv = proj.get("private", {})
	lines.append("- get-out-of-jail cards: %d" % int(priv.get("get_out_of_jail_cards", 0)))
	return "\n".join(lines)

## Spectator markdown — same public view as render() but omits the private
## "Your private info" block (a spectator must never see hidden info).
func render_spectator(proj: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("## Neuro Property Trade — stream view")
	lines.append("")
	lines.append("Phase: %s" % proj.get("phase", ""))
	lines.append("It is player %d's turn." % int(proj.get("turn_player", 0)))
	lines.append("")
	lines.append("## Players")
	for p in proj.get("players", []):
		var jail := ""
		if p.get("in_jail", false):
			jail = " (in jail, %d turns)" % int(p.get("jail_turns", 0))
		lines.append("- %s: $%d, tile %d%s" % [p.get("name", "?"), int(p.get("money", 0)), int(p.get("position", 0)), jail])
	lines.append("")
	lines.append("## Board")
	for t in proj.get("board", []):
		var owner := "unowned"
		var o = t.get("owner", -1)
		if o != -1:
			owner = "owned by %d" % int(o)
		var extra := ""
		if int(t.get("houses", 0)) > 0:
			extra = ", %d houses" % int(t.get("houses", 0))
		if t.get("mortgaged", false):
			extra += ", mortgaged"
		lines.append("- %d. %s (%s) %s%s" % [int(t.get("index", 0)), t.get("name", "?"), t.get("type", "?"), owner, extra])
	lines.append("")
	lines.append("## Pending decision")
	var pending = proj.get("pending", {})
	if pending.is_empty():
		lines.append("- none")
	else:
		lines.append("- %s" % str(pending))
	# intentionally NO "Your private info" section for spectators
	return "\n".join(lines)
