extends RefCounted
## Thin file-I/O wrapper over engine.to_snapshot()/from_snapshot(). The
## snapshot logic itself lives in engine.gd; this only persists as JSON.

static func save(path: String, engine) -> bool:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(engine.to_snapshot(), "\t"))
	f.close()
	return true

static func load(path: String):
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return null
	var d: Dictionary = parsed
	if d.is_empty():
		return null
	# from_snapshot is a non-static engine method; call it on an instance.
	var E = load("res://core/engine.gd")
	return E.new().from_snapshot(d)
