class_name NeuroActionHandler
extends Node
## Registered actions, PER CONNECTION (multi-SDK).
##
## The vendored handler was ONE global registry keyed by action name: two seats in one process
## overwrote each other's `roll_dice`, and the second seat's action executed on the first seat's
## adapter. Now every connection owns a handler, and the routing key is the connection a message
## arrived on (`set_incoming_conn`, called by CommandHandler - it is created per websocket).
##
## The old static API still works: `handler_for(null)` falls back to the first handler (the
## autoload's), which is exactly the single-SDK path every existing gate uses.

static var _instance: NeuroActionHandler
static var _by_conn: Dictionary = {}      # Node(connection) -> NeuroActionHandler
static var _current_conn: Node = null     # set while an incoming message is being handled

var _conn: Node = null                    # null = the Websocket autoload
var _registered_actions: Array[NeuroAction] = []
var _dying_actions: Array[NeuroAction] = []


func _init(conn: Node = null):
	_conn = conn
	if conn == null:
		_instance = self
	else:
		_by_conn[conn] = self


## The handler that owns `conn` (created on first use). With no argument: the handler for the
## message currently being handled, else the autoload's.
static func handler_for(conn: Node = null) -> NeuroActionHandler:
	var key: Node = conn if conn != null else _current_conn
	if key == null:
		return _instance
	if _by_conn.has(key):
		return _by_conn[key]
	var h := NeuroActionHandler.new(key)
	# The handler must live in the tree: `_notification` and the unregister grace timer both need
	# `get_tree()`. Parenting it to the connection is also the honest structure - the registry
	# belongs to the socket.
	if key is Node and (key as Node).is_inside_tree():
		(key as Node).add_child(h)
		h.name = "ActionRegistry"
	return h


static func set_incoming_conn(conn: Node) -> void:
	_current_conn = conn


## The connection this handler speaks on (the autoload when it has none).
func socket() -> Node:
	return _conn if _conn != null else Websocket


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var array: Array[WsAction] = []
		array.assign(_registered_actions.map(func(action: NeuroAction) -> WsAction: return action.get_ws_action()))
		socket().send_immediate(ActionsUnregister.new(array))


static func get_action(action_name: String) -> NeuroAction:
	var h := handler_for()
	if h == null:
		return null
	var actions: Array = h._registered_actions.filter(func(action: NeuroAction) -> bool: return action.get_name() == action_name)
	if actions.size() == 0:
		return null
	return actions[0]


static func is_recently_unregistered(action_name: String) -> bool:
	var h := handler_for()
	if h == null:
		return false
	return h._dying_actions.any(func(action: NeuroAction) -> bool: return action.get_name() == action_name)


static func register_actions(actions: Array[NeuroAction], conn: Node = null) -> void:
	var h := handler_for(conn)
	h._registered_actions = h._registered_actions.filter(func(old_action: NeuroAction) -> bool: return not actions.any(func(new_action: NeuroAction) -> bool: return old_action.get_name() == new_action.get_name()))
	h._dying_actions = h._dying_actions.filter(func(old_action: NeuroAction) -> bool: return not actions.any(func(new_action: NeuroAction) -> bool: return old_action.get_name() == new_action.get_name()))
	h._registered_actions.append_array(actions)

	var array: Array[WsAction] = []
	array.assign(actions.map(func(action: NeuroAction) -> WsAction: return action.get_ws_action()))
	h.socket().send(ActionsRegister.new(array))


static func unregister_actions(actions: Array[NeuroAction], conn: Node = null) -> void:
	var h := handler_for(conn)
	var actions_to_remove: Array[NeuroAction] = h._registered_actions.filter(func(old_action: NeuroAction) -> bool: return actions.any(func(new_action: NeuroAction) -> bool: return old_action.get_name() == new_action.get_name()))

	h._registered_actions = h._registered_actions.filter(func(old_action: NeuroAction) -> bool: return not actions_to_remove.has(old_action))
	h._dying_actions.append_array(actions_to_remove)

	var array: Array[WsAction] = []
	array.assign(actions_to_remove.map(func(action: NeuroAction) -> WsAction: return action.get_ws_action()))
	h.socket().send(ActionsUnregister.new(array))

	await h.get_tree().create_timer(10).timeout
	h._dying_actions = h._dying_actions.filter(func(action: NeuroAction) -> bool: return actions_to_remove.has(action))


static func resend_registered_actions(conn: Node = null) -> void:
	var h := handler_for(conn)
	var array: Array[WsAction] = []
	array.assign(h._registered_actions.map(func(action: NeuroAction) -> WsAction: return action.get_ws_action()))
	if array.size() > 0:
		h.socket().send(ActionsRegister.new(array))
