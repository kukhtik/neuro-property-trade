extends NeuroAction
## A single SDK action mapped to an engine intent. Parameterized by the SDK
## action name, the engine action name, and a params extractor. Thin Node
## shell over the pure engine — not headless-tested (needs the SDK autoloads).
##
## Flow (fail-closed, result-before-execute):
##   _validate_action -> adapter.try_submit() -> engine.submit_intent()
##   - ok:false -> ExecutionResult.failure(reason + legal) — no execute, SDK
##     sends the failure result and Neuro auto-retries the force.
##   - ok:true  -> store events in state, ExecutionResult.success() — SDK sends
##     the success result, then _execute_action emits the events. The engine
##     change is already applied atomically by submit_intent.

var _adapter
var _sdk_name: String
var _engine_action: String
var _description: String
var _params: Callable   # (IncomingData) -> Dictionary

func _init(window: ActionWindow, adapter, sdk_name: String, engine_action: String, description: String, params: Callable):
	super(window)
	_adapter = adapter
	_sdk_name = sdk_name
	_engine_action = engine_action
	_description = description
	_params = params

func _get_name() -> String:
	return _sdk_name

func _get_description() -> String:
	return _description

func _get_schema() -> Dictionary:
	# Free-form object schema; the engine validates and lists legal options in
	# the failure message (per SDK best practices for changing option sets).
	return JsonUtils.wrap_schema({}, false)

func _validate_action(data: IncomingData, state: Dictionary) -> ExecutionResult:
	var params: Dictionary = _params.call(data)
	var result: Dictionary = _adapter.try_submit(_engine_action, params)
	if not result.get("ok", false):
		var msg: String = result.get("reason", "action rejected")
		var legal: Array = result.get("legal", [])
		if legal.size() > 0:
			msg += " Legal options: " + ", ".join(legal)
		return ExecutionResult.failure(msg)
	state["_events"] = result.get("events", [])
	return ExecutionResult.success()

func _execute_action(state: Dictionary) -> void:
	_adapter.emit_events(state.get("_events", []))
