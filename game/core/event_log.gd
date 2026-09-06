## Append-only event log for the authoritative engine. Every state change is
## recorded as a structured entry, which enables replay, deterministic
## analysis, and the stream overlay. Engine writes; nothing else appends.

class_name EventLog
extends RefCounted


signal event_appended(entry: Dictionary)

var _entries: Array[Dictionary] = []


## Append an event. `type` is a short token (e.g. "move", "purchase",
## "rent", "jail"). `data` is a free-form dict of the event's fields.
func append(type: String, data: Dictionary = {}) -> int:
	var index := _entries.size()
	var entry := {"index": index, "type": type, "data": data}
	_entries.append(entry)
	event_appended.emit(entry)
	return index


## All events, in order.
func entries() -> Array[Dictionary]:
	return _entries.duplicate()


## Events of a given type, in order.
func entries_of_type(t: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _entries:
		if e["type"] == t:
			out.append(e)
	return out


## Total count of events.
func size() -> int:
	return _entries.size()


## Clear all events (e.g. a fresh replay session).
func clear() -> void:
	_entries.clear()
