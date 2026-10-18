class_name ActionWindow
extends Node

enum State {
	STATE_BUILDING,
	STATE_REGISTERED,
	STATE_FORCED,
	STATE_ENDED
}
var _state: State = State.STATE_BUILDING
## MULTI-SDK: which connection this window speaks on. null = the Websocket autoload (single-SDK).
var conn: Node = null
var _force_enabled: bool = false
var _force_timeout: float
var _action_force_query: String
var _action_force_state: String
var _action_force_ephemeral_context: bool
var _action_force_priority: ActionsForce.Priority
var _end_enabled: bool = false
var _end_timeout: float
var _actions: Array[NeuroAction] = []
var _context_enabled: bool = false
var _context_message: String
var _context_silent: bool
var _timer: float = 0

func _init(parent: Node):
	parent.add_child(self)

func set_force(timeout: float, query: String, state: String, ephemeral_context: bool = false, priority: ActionsForce.Priority = ActionsForce.Priority.LOW) -> void:
	if !_validate_frozen():
		return

	_force_enabled = true
	_force_timeout = timeout
	_action_force_query = query
	_action_force_state = state
	_action_force_ephemeral_context = ephemeral_context
	_action_force_priority = priority

func set_end(end_timeout: float) -> void:
	if !_validate_frozen():
		return

	_end_enabled = true
	_end_timeout = end_timeout

func set_context(message: String, silent: bool = false) -> void:
	if !_validate_frozen():
		return

	_context_enabled = true
	_context_message = message
	_context_silent = silent

func add_action(action: NeuroAction) -> void:
	if !_validate_frozen():
		return

	if action.can_be_used():
		_actions.append(action)

func register() -> void:
	if _state != State.STATE_BUILDING:
		push_error("Cannot register an ActionWindow more than once.")
		return

	if _actions.size() == 0:
		push_error("Cannot register an ActionWindow with no actions.")
		return

	if _context_enabled:
		Context.send(_context_message, _context_silent, conn)
	# MULTI-SDK: register on THIS window's connection, not on the autoload's
	NeuroActionHandler.register_actions(_actions, conn)

	_state = State.STATE_REGISTERED

	# NPT PATCH (invite now, not after the clock runs out). Upstream waits `_force_timeout` before
	# sending the force, so a seat was invited to its own turn EXACTLY `turn_timer` seconds late - with
	# the default 30s clock a Neuro player was asked "your move?" half a minute after the move began,
	# which the owner could see in the demo. A timeout of 0 now means "force in the frame you register";
	# what happens if no answer arrives is still owned by the match clock (sdk_adapter's own fallback
	# at 1x/2x window), not by this timer.
	if _force_enabled and _force_timeout <= 0.0:
		_state = State.STATE_FORCED
		_force_enabled = false
		_send_force()

func result(execution_result: ExecutionResult) -> ExecutionResult:
	if _state == State.STATE_BUILDING:
		push_error("Cannot handle a result before registering.")
	elif _state == State.STATE_ENDED:
		push_error("Cannot handle a result after the ActionWindow has ended.")
	elif execution_result.successful:
		_end()
	elif _state == State.STATE_FORCED:
		pass #_send_force(); # Neuro is now responsible for retrying failed action forces

	return execution_result

func _validate_frozen() -> bool:
	if _state != State.STATE_BUILDING:
		push_error("Tried to mutate action after it was registered")
		return false
	return true

func _process(delta: float) -> void:
	# STATE_FORCED keeps ticking: an immediate force (timeout 0 above) must still honour an end timer.
	if _state != State.STATE_REGISTERED and _state != State.STATE_FORCED:
		return

	_timer += delta

	if _force_enabled and _timer >= _force_timeout:
		_state = State.STATE_FORCED
		_force_enabled = false
		_send_force()

	if _end_enabled and _timer >= _end_timeout:
		_end()

func _send_force() -> void:
	var array: Array[String] = []
	array.assign(_actions.map(func(action: NeuroAction) -> String: return action.get_name()))
	# MULTI-SDK: the force goes out on THIS seat's connection (null = the autoload).
	(conn if conn != null else Websocket).send(ActionsForce.new(_action_force_query, _action_force_state, _action_force_ephemeral_context, array, _action_force_priority))

func _end() -> void:
	NeuroActionHandler.unregister_actions(_actions, conn)
	_end_enabled = false
	_state = State.STATE_ENDED
	queue_free()
