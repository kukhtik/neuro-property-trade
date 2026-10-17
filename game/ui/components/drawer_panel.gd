class_name DrawerPanel
extends PanelContainer
## The compact profile's drawer (v3 mockup `.drawer`): a 320px panel that slides in beside
## the rail, over the stage, and holds one dock's content. The rail itself stays visible —
## a second click on it closes the drawer — and the × in the drawer's header does the same.
##
## This is what the mockup does in the compact profile INSTEAD of expanding a dock in
## place: expanding a 268px dock on an 1100px window would eat a third of the board, which
## is exactly the complaint the rails were invented for.

signal closed

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

const W := 320

var _slot: MarginContainer
var _title: Label


func _init() -> void:
	name = "drawer"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 12)
	add_child(m)
	var v := UiTheme.vbox(8)
	m.add_child(v)

	var head := UiTheme.hbox(8)
	_title = UiTheme.label("", 13, UiTheme.COL().accent)
	_title.name = "DrawerTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := UiTheme.button(I18n.t("ui.close"), I18n.t("settings.close_tip"))
	x.name = "DrawerClose"
	x.custom_minimum_size = Vector2(28, 24)
	x.connect("pressed", Callable(self, "close"))
	head.add_child(x)
	v.add_child(head)

	_slot = MarginContainer.new()
	_slot.name = "DrawerBody"
	_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_slot)


## Set the header title (safe to call again — the drawer is reused for both docks).
func set_title_key(key: String) -> void:
	if _title == null:
		return
	_title.text = I18n.t(key)
	I18n.key_on(_title, key)


## Move a panel's content into the drawer. The panel keeps its own reference, so putting it
## back later is the caller's `take()` + `reparent()`.
func put(c: Control) -> void:
	c.reparent(_slot, false)
	c.visible = true


## Hand the content back (removed from the drawer, not freed).
func take() -> Control:
	for ch in _slot.get_children():
		if ch is Control:
			_slot.remove_child(ch)
			return ch
	return null


func close() -> void:
	closed.emit()
