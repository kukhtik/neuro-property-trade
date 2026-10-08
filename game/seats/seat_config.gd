extends RefCounted
## Builds an Array[Seat] from GameSettings Block 1, and resolves a raw seat
## assignment to a runtime driver. This resolve_driver function is the SINGLE
## place the future multi-SDK-connection support changes.
##
## P1: colors + tokens come from PlayerIdentity (single source). A seat's
## color/token_id are assigned from PlayerIdentity so the owner marker, the
## piece halo and the players-panel row can never disagree.

const PI := preload("res://core/player_identity.gd")
const Persona := preload("res://seats/ai_persona.gd")

static func from_settings(settings) -> Array:
	var n: int = settings.seat_count
	if n < 2:
		n = 4
	var seats: Array = []
	var assignments: Array = settings.seat_assignments
	var seen_sdk := false
	for i in n:
		var s = load("res://seats/seat.gd").new(i)
		var driver_label: String = ""
		if i < assignments.size():
			var a: Dictionary = assignments[i]
			driver_label = str(a.get("driver", ""))
			s.name = str(a.get("name", "Seat #%d" % (i + 1)))
			s.color = _color_from_name(str(a.get("token_color", "")), PI.color_of(i))
			s.token_id = str(a.get("token_id", PI.token_of(i)))
		else:
			var drv: String = "AI"
			if i == 0:
				drv = "LOCAL"
			driver_label = drv
			s.name = "Host" if i == 0 else "AI Seat #%d" % (i + 1)
			s.color = PI.color_of(i)
			s.token_id = PI.token_of(i)
		s.driver_label = driver_label
		s.input_driver = resolve_driver(driver_label, seen_sdk)
		# the character: an explicit choice wins, otherwise rotate by seat index so
		# an unconfigured match is never four clones (which produced a dead economy)
		var picked := ""
		if i < assignments.size():
			picked = str((assignments[i] as Dictionary).get("persona", ""))
		if picked == "" or not Persona.has(picked):
			picked = Persona.default_for_index(i)
		s.persona = picked
		if s.input_driver == "SDK":
			seen_sdk = true
		seats.append(s)
	# starting_order random: shuffle by a re-seeded Rng. A zero rng_seed is
	# treated as "not set" (matches the engine), so we keep insertion order —
	# non-deterministic shuffling would make the default layout unstable.
	if settings.starting_order == "random" and settings.rng_seed != 0:
		var RngScript = load("res://core/rng.gd")
		var r = RngScript.new()
		r.seed_rng(settings.rng_seed)
		for i in range(n - 1, 0, -1):
			var j: int = r.int_range(0, i)
			var tmp = seats[i]
			seats[i] = seats[j]
			seats[j] = tmp
		for i in n:
			seats[i].pid = i
	return seats

static func resolve_driver(driver_label: String, sdk_already_used: bool) -> String:
	var label: String = String(driver_label).to_lower()
	if label == "local":
		return "LOCAL"
	if label == "chat":
		return "CHAT"
	if label == "admin":
		return "ADMIN"
	if label == "remote" or label.begins_with("remote:"):
		# A browser seat. The host must ALSO mint a token and start the server;
		# resolve_driver only names the driver, it does not wire the socket.
		return "REMOTE"
	if label == "ai":
		return "AI"
	if label.begins_with("sdk:") or label == "sdk":
		# Only ONE SDK connection is supported in-process (the vendored SDK is
		# a single global singleton). Additional SDK seats fall back to the
		# internal AI driver so the game stays playable.
		return "AI" if sdk_already_used else "SDK"
	return "AI"   # unknown assignment -> safe internal AI

static func _color_from_name(c: String, fallback: Color) -> Color:
	var name := c.to_lower()
	match name:
		"red": return Color(1, 0.3, 0.3)
		"blue": return Color(0.35, 0.6, 1)
		"green": return Color(0.4, 0.9, 0.4)
		"yellow": return Color(1, 0.85, 0.3)
		"purple": return Color(0.75, 0.5, 1)
		"orange": return Color(1, 0.6, 0.2)
		"cyan": return Color(0.4, 0.9, 0.95)
		_: return fallback
