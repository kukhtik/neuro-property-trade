extends RefCounted
## One seat's configuration (pure data). The engine is seat-agnostic; this
## describes who drives the seat (LOCAL human / CHAT / SDK AI / internal AI).

var pid: int = 0
var name: String = ""
var input_driver: String = "AI"     # LOCAL | CHAT | SDK | AI | ADMIN
var driver_label: String = ""       # raw assignment for display/routing, e.g. "sdk:neuro"
var color: Color = Color.WHITE
var token_id: String = ""
var away: bool = false              # flagged true once auto-passed (spec §3)
var decision_waiting: float = 0.0   # seconds at the current decision point

func _init(p: int = 0) -> void:
	pid = p
