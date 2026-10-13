extends Node
## F-48/F-52 measured on the REAL overlay (the one the app opens on first run, not a
## synthetic instance): every settings FIELD row carries its "applies live / needs
## restart" tag, and every interactive field carries a tooltip.
## Run: godot --path game res://tools/settings_tags_probe.tscn

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

var _had_fail := false

func _ready() -> void:
	get_tree().root.size = Vector2i(1440, 900)
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 20:
		await get_tree().process_frame
	var overlay = launcher.get("_overlay")
	if overlay == null or not overlay.visible:
		_fail("the settings overlay should be open on first run"); return

	var tags: Array = []
	_collect_tags(overlay, tags)
	if tags.is_empty():
		_fail("no tag labels in the overlay"); return
	var live_text: String = I18n.t("settings.tag_live")
	var restart_text: String = I18n.t("settings.tag_restart")
	var bad := 0
	for t in tags:
		if t != live_text and t != restart_text:
			bad += 1
	if bad > 0:
		_fail("%d tag(s) are neither live nor restart" % bad); return
	if tags.size() < 26:
		_fail("expected >= 26 tagged field rows, found %d" % tags.size()); return
	print("PASS: %d settings fields carry live/restart tags" % tags.size())

	# every interactive FIELD has a tooltip (F-52)
	var offenders: Array = []
	_walk_fields(overlay, offenders)
	if not offenders.is_empty():
		_fail("fields without tooltips: %s" % ", ".join(offenders.slice(0, 4))); return
	print("PASS: every interactive settings field carries a tooltip")

	if _had_fail:
		quit(1)
	else:
		print("SETTINGS TAGS PROBE: ALL PASSED")
		quit(0)

func _collect_tags(n: Node, out: Array) -> void:
	if n is Label and str(n.name) == "Tag":
		out.append(str(n.text))
	for c in n.get_children():
		_collect_tags(c, out)

func _walk_fields(n: Node, offenders: Array) -> void:
	if n is SpinBox or n is CheckButton or n is OptionButton:
		if str((n as Control).tooltip_text).strip_edges() == "":
			offenders.append("%s(%s)" % [n.get_class(), n.get_path()])
	for c in n.get_children():
		_walk_fields(c, offenders)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)
	quit(1)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
