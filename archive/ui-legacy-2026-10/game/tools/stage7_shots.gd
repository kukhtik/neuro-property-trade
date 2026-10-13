extends Node
## Stage-7 probe: capture every ROLE in one run and check the frames are sane.
##
## The three executions are independent processes (stage 7 of the UI work), so this
## probe launches each one, lets it draw a real frame, saves the PNG and measures it.
## A screenshot that is all-background, or whose board is not a centred square, means
## the role renders nothing useful — which a passing unit test would never reveal.
##
## Exit 0 = every role produced a usable frame.

const SHOT_DIR := "res://../shots"

var _fail := 0
var _godot := ""


func _ready() -> void:
	print("=== Stage 7 acceptance: every role renders a real frame ===")
	_godot = OS.get_executable_path()
	await _capture("admin", "--admin")
	await _capture("stream", "--stream")
	_finish()


func _finish() -> void:
	print("")
	if _fail > 0:
		print("==> STAGE 7 FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> STAGE 7 PASSED — admin and stream both render a usable frame")
		get_tree().quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


## Launch one role, wait for it to draw, save its frame, and measure it.
func _capture(role: String, flag: String) -> void:
	print("[%s] launching the %s execution" % [role, role])
	var out := _shot_path(role)
	var pid := OS.create_process(_godot, PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"),
		"res://tools/_role_shot.tscn", "--rendering-driver", "opengl3",
		"--resolution", "1440x900", "--", flag, "--out=%s" % out,
	]), false)
	if pid <= 0:
		_bad("the %s process did not start" % role)
		return
	# Wait for the FILE, not for a fixed number of ticks: a second process has to
	# boot a whole launcher and draw 120 frames while the first still holds the GPU,
	# so a count that fits the first role is too short for the second.
	for i in 400:
		await get_tree().create_timer(0.1).timeout
		if FileAccess.file_exists(out):
			break
	OS.kill(pid)
	if not FileAccess.file_exists(out):
		_bad("the %s execution produced no frame" % role)
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(out))
	if img == null:
		_bad("the %s frame could not be read" % role)
		return
	_ok("%s frame saved: %dx%d" % [role, img.get_width(), img.get_height()])
	_check_frame(role, img)


## A frame must not be uniform (a blank window) and its board must read as a centred
## square. This is a behavioural check on the PIXELS, not on the code that drew them.
func _check_frame(role: String, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w < 800 or h < 600:
		_bad("%s frame is too small to judge (%dx%d)" % [role, w, h])
		return
	var bg := img.get_pixel(2, 2)
	var lit := 0
	var total := 0
	for y in range(0, h, 12):
		for x in range(0, w, 12):
			total += 1
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.08:
				lit += 1
	if lit * 100 / maxi(total, 1) < 15:
		_bad("%s frame is nearly blank (%d%% differs from the backdrop)"
			% [role, lit * 100 / maxi(total, 1)])
		return
	_ok("%s frame has content (%d%% of samples differ from the backdrop)"
		% [role, lit * 100 / maxi(total, 1)])


func _shot_path(role: String) -> String:
	# an ABSOLUTE path: a child process resolves res:// against its own root, so a
	# relative one lands somewhere the parent never looks
	var dir := ProjectSettings.globalize_path("res://../shots")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join("%s.png" % role).replace("\\", "/")
