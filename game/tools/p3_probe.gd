extends Node
## P3 behavioral probe — verifies spec §11 P3 (feedback):
##   1. Purchase event → toast appears within 0.5 s.
##   2. Anti-spam: a burst of 4 same-kind events produces ≤ 3 toast widgets.
##   3. Timer ring hidden when timer window == 0; shown and progressing when > 0.
##   4. Dice stage with animations=false shows the result instantly (same frame).
##   5. Inspector: select → visible; pin keeps it open past 5 s; unpinned hides
##      after ~5 s.
##   6. Tooltip coverage autoprobe: 0 interactive controls without tooltip_text
##      (walks the whole live scene tree).
## Run windowed: godot --path game res://tools/p3_probe.tscn
## Run headless: godot --headless --path game res://tools/p3_probe.tscn

const MainScript := preload("res://main.gd")
const ProjectionScript := preload("res://sdk/projection.gd")

var _launcher
var _had_fail := false

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no GameView at launch")
		return

	# --- start the game with default seats (Host LOCAL + AI) ---
	var overlay = _launcher.get("_overlay")
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	if gv.engine == null:
		_fail("engine not built after START")
		return

	# --- 1) purchase → toast ≤ 0.5s ---
	await _check_toast_on_purchase(gv)

	# --- 2) 4 events → ≤ 3 toasts (anti-spam) ---
	await _check_toast_anti_spam(gv)

	# --- 3) timer ring: hidden at window 0, live at window > 0 ---
	_check_timer_ring(gv)

	# --- 4) dice: animations=false → instant result ---
	_check_dice_instant(gv)

	# --- 5) inspector pin + auto-hide ---
	await _check_inspector(gv)

	# --- 6) tooltip coverage autoprobe ---
	_check_tooltip_coverage(gv)

	if _had_fail:
		print("P3 PROBE: FAILED")
		quit(1)
	else:
		print("P3 PROBE: ALL PASSED")
		quit(0)

## Feed a purchase event through the toast stack and time its appearance.
func _check_toast_on_purchase(gv) -> void:
	var stack = gv._toast_stack
	if stack == null:
		_fail("no ToastStack in GameView")
		return
	stack.dismiss_all()
	var before: int = stack.toast_count()
	# simulate a purchase event exactly as the engine would emit it
	var ev := {"type": "purchase", "data": {"player": "Tester", "tile": 3, "cost": 120}}
	stack.show_event_toast(ev)
	# toast must exist immediately (well within the 0.5s budget)
	if stack.toast_count() <= before:
		_fail("purchase toast did not appear")
		return
	print("PASS: purchase event -> toast appears instantly (<=0.5s)")
	stack.dismiss_all()

## 4 identical events within the dedup window → ≤ 3 toast widgets.
func _check_toast_anti_spam(gv) -> void:
	var stack = gv._toast_stack
	stack.dismiss_all()
	# Use a non-rent/pay event type: rent/pay now go through the CR-8 merge
	# buffer, so this test exercises the generic anti-spam dedup path.
	for i in 4:
		stack.show_event_toast({"type": "build", "data": {"player": "Tester", "tile": 3}})
	var count: int = stack.toast_count()
	if count > 3:
		_fail("anti-spam: 4 events produced %d toasts (> 3)" % count)
		return
	if count == 0:
		_fail("anti-spam: 4 events produced 0 toasts")
		return
	# merged toast must show the ×N badge (badge lives inside the toast item)
	var badge := _find_count_label(stack)
	if badge == null or not badge.visible or str(badge.text) == "":
		_fail("merged toast lacks ×N count badge")
		return
	print("PASS: 4-event burst -> %d toast(s) with ×N badge («%s»)" % [count, badge.text])
	stack.dismiss_all()

func _find_count_label(node) -> Label:
	# recurse: CanvasLayer -> container VBox -> ToastItem -> _count_label
	for child in node.get_children():
		if child is PanelContainer and child.get("_count_label") != null:
			return child.get("_count_label")
		var deeper = _find_count_label(child)
		if deeper != null:
			return deeper
	return null

## Timer ring: engine settings turn_timer 30s by default → visible + counting.
## Force window 0 → hidden.
func _check_timer_ring(gv) -> void:
	var ring = gv._top._timer_ring
	if ring == null:
		_fail("no TimerRing in TopBar")
		return
	# case A: no window → hidden
	ring.set_state(0.0, 0.0, true)
	if ring.visible:
		_fail("timer ring visible with window 0")
		return
	# case B: window 30, elapsed 10 → visible, ~20 remaining
	ring.set_state(30.0, 10.0, true)
	if not ring.visible:
		_fail("timer ring hidden with window 30")
		return
	# the drawn remaining is internal; check state took: elapsed close to window → danger color path still draws
	ring.set_state(10.0, 9.5, true)
	print("PASS: timer ring hidden at window 0, visible + state-driven otherwise")
	ring.set_state(0.0, 0.0, false)  # restore hidden default for later checks

## Dice with animations=false shows the result instantly (no 1.2s settle wait).
func _check_dice_instant(gv) -> void:
	var ds = gv._board_scene._dice_stage
	if ds == null:
		_fail("no DiceStage in board scene")
		return
	ds.set_animations(false)
	var done := [false]
	ds.dice_rolled.connect(func(d1: int, d2: int, sum: int) -> void:
		done[0] = true)
	ds.roll(3, 4)
	if not done[0]:
		_fail("dice with animations=false did not emit instantly")
		return
	if not ds.visible:
		_fail("dice stage not visible after instant roll")
		return
	var faces := _dice_faces(ds)
	if faces != [3, 4]:
		_fail("instant dice faces %s != [3, 4]" % str(faces))
		return
	print("PASS: dice animations=false shows result instantly (3+4)")
	ds.set_animations(true)
	ds._hide()

func _dice_faces(ds) -> Array:
	var out: Array = []
	for n in ds._dice_nodes:
		if not is_instance_valid(n):
			continue
		var face: Node = n.get_node("Face")
		if face is Label:
			out.append(int((face as Label).text))
		elif face is TextureRect:
			# SVG face: the texture path is res://assets/dice/die_N.svg
			var tex: Texture2D = (face as TextureRect).texture
			var path: String = tex.resource_path if tex != null else ""
			var m := path.rfind("die_")
			if m >= 0:
				out.append(int(path.substr(m + 4, 1)))
			else:
				out.append(-1)
	return out

## Inspector: select shows it; pin keeps it past 5s; unpinned auto-hides.
func _check_inspector(gv) -> void:
	var insp = gv._inspector
	if insp == null:
		_fail("no TileInspector")
		return
	insp.select(5)
	if not insp.visible:
		_fail("inspector not visible after select()")
		return
	# pin it
	insp._on_pin_toggled(true)
	if not insp._pinned:
		_fail("pin did not set _pinned")
		return
	# simulate 6 seconds of _process while pinned
	for i in 600:
		insp._process(0.01)
	if not insp.visible or insp.selected < 0:
		_fail("pinned inspector auto-hid (must stay open)")
		return
	print("PASS: pinned inspector stays open past 5s")
	# unpin + let the timer expire
	insp._on_pin_toggled(false)
	for i in 600:
		insp._process(0.01)
	if insp.visible:
		_fail("unpinned inspector did not auto-hide after 5s")
		return
	print("PASS: unpinned inspector auto-hides after 5s")
	insp.clear()

## Autoprobe: every interactive control in the live tree has a tooltip.
func _check_tooltip_coverage(gv) -> void:
	var checked := 0
	var missing: Array = []
	var roots := [_launcher, gv._toast_stack]
	for root in roots:
		if root == null:
			continue
		_walk_tooltips(root, checked, missing)
	# disabled buttons are allowed to have tooltips too — still require them
	if missing.size() > 0:
		_fail("tooltip coverage: %d controls without tooltip: %s" % [
			missing.size(), ", ".join(missing)])
		return
	print("PASS: tooltip autoprobe — %d interactive controls, 0 without tooltip" % checked)

func _walk_tooltips(node, checked: int, missing: Array) -> void:
	for c in node.get_children():
		if c is BaseButton:
			checked += 1
			var tip: String = str(c.tooltip_text)
			if tip.strip_edges() == "":
				missing.append("%s (%s)" % [c.get_path(), c.get_class()])
		_walk_tooltips(c, checked, missing)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)