extends CanvasLayer
## A tiny performance read-out, always on top, drawn by the engine itself.
##
## WHY THIS EXISTS: performance cannot be judged by eye ("it feels smooth"), and the desktop build
## has no console unless launched from one. This puts the number the GPU actually achieved on the
## screen, next to memory use and the frame count, so anyone can tell whether a build is fit to
## play — and so a probe can read the same number out of the render.
##
## Off unless asked for: `--perf` on the command line, or `perf` in the settings.

const UiTheme := preload("res://ui/theme.gd")

var _lbl_fps: Label
var _lbl_ms: Label
var _lbl_mem: Label
var _lbl_geo: Label
var _frames := 0
var _elapsed := 0.0
var _fps := 0.0
var _worst_ms := 0.0
var _say := true
var _log_dir := ""
var _perf_log_started := false


func _init() -> void:
	layer = 120          # above the modal host (60) and the toast, above everything
	name = "PerfOverlay"


func _ready() -> void:
	var col := Color(0.6, 1.0, 0.75)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	m.add_theme_constant_override("margin_top", 56)
	m.add_theme_constant_override("margin_right", 8)
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(v)
	_lbl_fps = _make(v, col)
	_lbl_ms = _make(v, col)
	_lbl_mem = _make(v, col)
	_lbl_geo = _make(v, col)


func _make(parent: Control, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	# the worst single frame of the last second is what a player feels as a stutter, not the mean
	if delta > _worst_ms:
		_worst_ms = delta
	if _elapsed < 0.5:
		return
	_fps = float(_frames) / _elapsed
	_frames = 0
	_elapsed = 0.0
	# `get_static_memory_usage` is the ALLOCATOR's counters and reads 0 in a release build;
	# Performance gives the working set, which is the number a player cares about.
	var mem := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var vp := get_viewport().get_visible_rect().size
	_say = not _say   # write every other sample: once a second is plenty
	# AND TO A FILE, not only to the screen: a screen cannot be captured from a session with no
	# desktop (CI, an SSH run, a probe), and performance that cannot be measured cannot be tuned.
	# "PERF" is a single stable line so any harness can grep it. It USED to go to stdout as well —
	# which turned every captured run log into 146 PERF lines out of 160. The samples live in
	# `perf.log` next to the role log now: one file for numbers, the other for events.
	if _say:
		_append_perf("PERF fps=%d max_ms=%.1f mem=%dMB viewport=%dx%d" % [int(round(_fps)), _worst_ms, int(mem), int(vp.x), int(vp.y)])
	_lbl_fps.text = "FPS %d" % int(round(_fps))
	if _fps < 30.0:
		_lbl_fps.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	elif _fps < 50.0:
		_lbl_fps.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	_lbl_ms.text = "max %.1f ms" % _worst_ms
	_worst_ms = 0.0
	_lbl_mem.text = "MEM %d MB" % int(mem)
	_lbl_geo.text = "%dx%d" % [int(vp.x), int(vp.y)]
	# the same number a probe reads from the render
	set_meta("fps", _fps)
	set_meta("mem_mb", mem)


## Where perf.log lives: the same directory the role logs go to (--log-dir), else user://.
func set_log_dir(dir: String) -> void:
	_log_dir = dir


## Append one sample to perf.log. Truncated on the first write of a session: the file is THIS
## run's history, and appending across runs would grow without bound — the same complaint the
## stdout stream produced, one file over.
func _append_perf(line: String) -> void:
	var dir := _log_dir
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	var path := dir.path_join("perf.log")
	var f: FileAccess = null
	if _perf_log_started:
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return   # nowhere to write (a read-only sandbox): the on-screen read-out still works
	f.store_line(line)
	f.close()
	_perf_log_started = true
