extends Node
## SDK adapter orchestrator. Thin Node shell that wires the pure projection /
## renderer / decision-controller to the vendored Godot Neuro SDK.
##
## Responsibilities:
##   - On ready: set the game name, register the STABLE action set once.
##   - On the SDK `connected` signal: re-register actions + re-force (reconnect).
##   - On each engine decision point: project the seat, render markdown, and
##     force the legal actions (priority low, ephemeral context).
##   - Map SDK actions -> engine intents via EngineAction (fail-closed).
##   - Emit engine events to the rest of the game (signals).
##
## Not headless-tested: needs the SDK autoloads + a live websocket. The pure
## logic it calls (projection/renderer/decision_controller) IS headless-tested.

signal events_emitted(events: Array)

const ProjectionScript := preload("res://sdk/projection.gd")
const Renderer := preload("res://sdk/markdown_renderer.gd")
const DecisionController := preload("res://sdk/decision_controller.gd")
const EngineAction := preload("res://sdk/engine_action.gd")

## Map engine action names (from engine.legal_actions) to SDK action names
## (the registered action set). The decision controller returns engine names;
## the SDK registry is keyed by SDK names.
const ENGINE_TO_SDK := {
	"roll": "roll_dice",
	"buy": "buy_property",
	"pass": "pass_on_purchase",
	"bid": "bid_auction",
	"build_house": "build_house",
	"sell_house": "sell_house",
	"mortgage_property": "mortgage_property",
	"unmortgage_property": "unmortgage_property",
	"propose_trade": "propose_trade",
	"respond_trade": "respond_trade",
	"pay": "pay_jail_fine",
	"use_card": "use_jail_card",
}

var engine
var seat_pid: int = -1
var _projection
var _renderer
var _controller
var _window: ActionWindow = null
var _last_decision_key: String = ""
var _awaiting_result: bool = false
var _poll_elapsed: float = 0.0
const POLL_INTERVAL := 0.5

func _ready() -> void:
	NeuroSdkConfig.game = "Neuro Property Trade"
	_projection = ProjectionScript.new()
	_renderer = Renderer.new()
	_controller = DecisionController.new()
	# Re-register + re-force on (re)connect — context survives disconnects.
	Websocket.connected.connect(_on_connected)
	_register_actions()

func _process(delta: float) -> void:
	# Self-driving: poll the engine each tick and force when the decision point
	# changes (or when it becomes this seat's turn). The decision-key guard
	# prevents re-forcing the same decision point (which would cancel/replace
	# the pending force and spam the server).
	_poll_elapsed += delta
	if _poll_elapsed < POLL_INTERVAL:
		return
	_poll_elapsed = 0.0
	_force_if_needed()

func setup(eng, pid: int) -> void:
	engine = eng
	seat_pid = pid

func _on_connected() -> void:
	# The SDK auto-re-registers actions on reconnect (actions/reregister_all),
	# but we also re-force the current decision point so a dropped force is
	# re-sent. Safe: only one force at a time; a new force replaces the old.
	_register_actions()
	_force_if_needed()

## Register the stable action set once. Re-registering a name replaces it.
func _register_actions() -> void:
	if engine == null:
		return
	var actions: Array[NeuroAction] = []
	actions.append(_make_action("roll_dice", "roll", "Roll the dice and move.", {}, _no_params))
	actions.append(_make_action("buy_property", "buy", "Buy the property you landed on.", {}, _no_params))
	actions.append(_make_action("pass_on_purchase", "pass", "Pass on buying the property (or pass in an auction).", {}, _no_params))
	actions.append(_make_action("bid_auction", "bid", "Bid an amount in the auction.", {"amount": {"type": "integer", "minimum": 1}}, _amount_param))
	actions.append(_make_action("build_house", "build_house", "Build a house on a tile you own.", {"tile": {"type": "integer", "minimum": 0, "maximum": 39}}, _tile_param))
	actions.append(_make_action("sell_house", "sell_house", "Sell a house from a tile you own.", {"tile": {"type": "integer", "minimum": 0, "maximum": 39}}, _tile_param))
	actions.append(_make_action("mortgage_property", "mortgage_property", "Mortgage a tile you own.", {"tile": {"type": "integer", "minimum": 0, "maximum": 39}}, _tile_param))
	actions.append(_make_action("unmortgage_property", "unmortgage_property", "Unmortgage a tile you own.", {"tile": {"type": "integer", "minimum": 0, "maximum": 39}}, _tile_param))
	actions.append(_make_action("propose_trade", "propose_trade", "Propose a trade to another player.", {"to": {"type": "integer", "minimum": 0, "maximum": 7}, "give_tiles": {"type": "array", "items": {"type": "integer"}}, "want_tiles": {"type": "array", "items": {"type": "integer"}}, "give_cash": {"type": "integer", "minimum": 0}, "want_cash": {"type": "integer", "minimum": 0}}, _trade_param))
	actions.append(_make_action("respond_trade", "respond_trade", "Accept or decline a pending trade.", {"accept": {"type": "boolean"}}, _accept_param))
	actions.append(_make_action("pay_jail_fine", "pay", "Pay the jail fine to get out of jail.", {}, _no_params))
	actions.append(_make_action("use_jail_card", "use_card", "Use a get-out-of-jail card.", {}, _no_params))
	NeuroActionHandler.register_actions(actions)

func _make_action(sdk_name: String, engine_action: String, description: String, schema: Dictionary, params: Callable) -> NeuroAction:
	return EngineAction.new(_window, self, sdk_name, engine_action, description, schema, params)

## Force the current decision point for this seat, if it is their turn and the
## decision point has changed since the last force.
func _force_if_needed() -> void:
	if engine == null or seat_pid < 0:
		return
	# Don't send a new force while the previous one is still awaiting a result
	# (Randy/Neuro queue or drop a force that arrives mid-result; this caused
	# stalls). The flag is cleared in emit_events when the action executes.
	if _awaiting_result:
		return
	var proj: Dictionary = _projection.for_player(engine, seat_pid)
	var decision: Dictionary = _controller.decide(engine, seat_pid, proj)
	if not decision.get("force", false):
		_last_decision_key = ""
		return
	# Decision key: phase + turn_player + pending bidder/tile. Re-forcing the
	# same key would cancel/replace the pending force and spam the server.
	var key: String = "%s|%d|%s" % [engine.phase, engine.turn_player, str(proj.get("pending", {}))]
	if key == _last_decision_key:
		return
	_last_decision_key = key
	_awaiting_result = true
	var markdown: String = _renderer.render(proj)
	# Build a fresh ActionWindow for this decision point.
	if _window != null:
		_window.queue_free()
	_window = ActionWindow.new(self)
	_window.set_force(
		float(engine.settings.turn_timer),
		decision.get("query", ""),
		markdown,
		decision.get("ephemeral_context", true),
		ActionsForce.Priority.LOW
	)
	for name in decision.get("actions", []):
		var sdk_name: String = ENGINE_TO_SDK.get(name, name)
		var action: NeuroAction = NeuroActionHandler.get_action(sdk_name)
		if action != null:
			_window.add_action(action)
	_window.register()

## Called by EngineAction._validate_action. Fail-closed: submit_intent is
## atomic — on ok:false it mutates nothing.
func try_submit(engine_action: String, params: Dictionary) -> Dictionary:
	if engine == null:
		return {"ok": false, "reason": "engine not ready", "legal": [], "events": []}
	var result: Dictionary = engine.submit_intent(seat_pid, engine_action, params)
	# On failure the SDK sends the failure result and Neuro auto-retries the
	# force. Clear the awaiting-result gate so the retry (and future forces)
	# aren't blocked. On success emit_events clears it too.
	if not result.get("ok", false):
		_awaiting_result = false
	return result

func emit_events(events: Array) -> void:
	# An action executed — the decision point has advanced. Reset the guard so
	# the next poll forces the NEW decision point (a fresh turn/phase). Without
	# this, a full turn cycle back to the same key (e.g. TURN_START|0) would be
	# wrongly suppressed by the decision-key guard.
	_last_decision_key = ""
	_awaiting_result = false
	events_emitted.emit(events)

# --- param extractors (IncomingData -> Dictionary) ---

func _no_params(data: IncomingData) -> Dictionary:
	return {}

func _amount_param(data: IncomingData) -> Dictionary:
	return {"amount": data.get_int("amount", 0)}

func _tile_param(data: IncomingData) -> Dictionary:
	return {"tile": data.get_int("tile", -1)}

func _trade_param(data: IncomingData) -> Dictionary:
	return {
		"to": data.get_int("to", -1),
		"give_tiles": data.get_array("give_tiles", []),
		"want_tiles": data.get_array("want_tiles", []),
		"give_cash": data.get_int("give_cash", 0),
		"want_cash": data.get_int("want_cash", 0),
	}

func _accept_param(data: IncomingData) -> Dictionary:
	return {"accept": data.get_boolean("accept", false)}
