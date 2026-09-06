extends Node
## Local seat driver — a human at the host machine. It waits; intents arrive
## asynchronously via seat_manager.push_intent (a UI/input calls that). No
## auto-advance here — the seat manager's timeout enforces auto-pass.

var engine
var seat

func setup(eng, s) -> void:
	engine = eng
	seat = s
