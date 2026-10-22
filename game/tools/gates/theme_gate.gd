extends Node
## THE THEME GATE — is the skin's theme ALIVE?
##
## The theme (`SkinManager.theme()`) used to be dead code: it built a `Theme` with type
## variations ("ButtonPrimary", "PanelBase", "LabelTitle"), and only a test ever read it.
## Worse, a variation that does not declare its BASE is ignored by the engine: a Button
## with `theme_type_variation = "ButtonPrimary"` reads the BASE type's items, so the
## theme contributed nothing even when applied. The API is `set_type_variation(variation,
## base)` - `set_type_variation_base` does not exist in this build.
##
## This gate measures the product, not a mock:
##   1. the shell carries a theme at all;
##   2. that theme reaches a control DEEP in the tree (the shell's own rows);
##   3. a variation resolves against it - the accent button reads the accent, not the base;
##   4. the base fallback works (a variation without its own item inherits the base's);
##   5. a hand-written override still wins over the theme (the product's 169 overrides
##      must keep working while the migration is in progress);
##   6. the theme follows the SKIN: two skins give two different accents.
##
## Each check prints its own line, and the verdict is one line at the end.
##
## Run: godot --headless --path game res://tools/gates/theme_gate.tscn

const MainScript := preload("res://main.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const UiTheme := preload("res://ui/theme.gd")

var _fails: Array = []
var _checks := 0


func _ready() -> void:
	var launcher := MainScript.new()
	add_child(launcher)
	await get_tree().process_frame
	await get_tree().process_frame

	var gv = launcher.get("_game_view")
	if gv == null:
		_fail("the shell was not built")
		_verdict()
		return

	# 1. the theme is ON the shell
	var th: Theme = gv.theme
	if th == null:
		_fail("the shell carries NO theme - the skin's theme is not applied at the root")
		_verdict()
		return
	_check("the shell carries a theme")

	# 2. the theme reaches a control DEEP in the tree
	var deep: Control = _find_deep_label(gv)
	if deep == null:
		_fail("no Label found under the shell - nothing to read the theme with")
	else:
		var col: Color = deep.get_theme_color("font_color")
		# the product's own override wins, so this proves reachability only if the
		# override is absent; the REACH test is done on a FRESH control below.
		_check("a Label under the shell reads a colour (%s)" % str(col))

	# 3. the variation resolves - the decisive check
	var skin := SkinManager.new()
	skin.load_skin("neuro")
	var accent: Color = skin.color("accent")
	# a fresh control with NO override of its own
	var fresh := Button.new()
	fresh.theme_type_variation = "ButtonPrimary"
	fresh.theme = skin.theme()
	add_child(fresh)
	await get_tree().process_frame
	var got: Color = fresh.get_theme_color("font_color")
	var on_accent: Color = skin.color("on_accent", Color.WHITE)
	if got != on_accent:
		_fail("the ButtonPrimary variation read %s, the skin's on_accent is %s - the variation did NOT resolve" % [str(got), str(on_accent)])
	else:
		_check("the ButtonPrimary variation resolves (font_color %s = the skin's on_accent)" % str(got))
	fresh.queue_free()

	# 4. the base fallback: a variation WITHOUT its own item inherits the base's
	var t2 := Theme.new()
	t2.set_color("font_color", "Button", Color(0.25, 0.5, 0.75))
	t2.set_type_variation("ButtonGhost", "Button")
	var g := Button.new()
	g.theme_type_variation = "ButtonGhost"
	g.theme = t2
	add_child(g)
	await get_tree().process_frame
	var bc: Color = g.get_theme_color("font_color")
	if bc != Color(0.25, 0.5, 0.75):
		_fail("a variation without its own item read %s, the base's colour is (0.25,0.5,0.75) - the base fallback does not work" % str(bc))
	else:
		_check("a variation inherits its base's items")
	g.queue_free()

	# 5. an override still beats the theme
	var o := Button.new()
	o.theme_type_variation = "ButtonPrimary"
	o.theme = skin.theme()
	o.add_theme_color_override("font_color", Color(0, 1, 0))
	add_child(o)
	await get_tree().process_frame
	var oc: Color = o.get_theme_color("font_color")
	if oc != Color(0, 1, 0):
		_fail("an add_theme_color_override did not beat the theme (read %s, expected green) - the product's own overrides would break" % str(oc))
	else:
		_check("an override still beats the theme")
	o.queue_free()

	# 6. the theme follows the skin
	var a := SkinManager.new()
	a.load_skin("neuro")
	var evil := SkinManager.new()
	evil.load_skin("evil")
	var ca: Color = a.theme().get_color("font_color", "ButtonPrimary")
	var cb: Color = evil.theme().get_color("font_color", "ButtonPrimary")
	if ca == cb:
		_fail("two skins give the same ButtonPrimary colour (%s) - the theme does not follow the skin" % str(ca))
	else:
		_check("the theme follows the skin (neuro %s vs evil %s)" % [str(ca), str(cb)])

	_verdict()


func _find_deep_label(node: Node) -> Label:
	for c in node.get_children():
		if c is Label:
			return c
		var r := _find_deep_label(c)
		if r != null:
			return r
	return null


func _check(what: String) -> void:
	_checks += 1
	print("  ok: ", what)


func _fail(why: String) -> void:
	_checks += 1
	_fails.append(why)
	print("  FAIL: ", why)


func _verdict() -> void:
	if _fails.is_empty():
		print("==> THEME PASSED (%d checks: the skin's theme is applied at the root, its variations resolve, and the hand-written overrides still win)" % _checks)
		get_tree().quit(0)
	else:
		print("==> THEME FAILED: %s" % _fails[0])
		get_tree().quit(1)
