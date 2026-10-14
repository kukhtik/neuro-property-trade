extends Control
## The screen shown to the HOST after "Создать партию для друзей".
##
## RESTORED FROM archive/ui-legacy-2026-10 with the join lobby: the v3 swap left
## `main._on_host_invite` as a `push_warning`, so "Создать партию для друзей" opened nothing and
## no invitation could be sent at all.
##
## It exists because the invitation is not one string: every friend needs the SAME address but
## their OWN token, and both are minted when the match starts. Printing them to a console is
## useless to a person — this puts a copy-ready link per friend on screen, and a copy button,
## so hosting a game is a click rather than a hunt through stdout.
##
## THE LINK IS THE WHOLE INVITATION. A friend opens it and lands in the join lobby; they never see
## a token, never open a terminal, and never install anything — a browser is enough.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

signal closed

var _address := ""
var _links: Array[String] = []
var _rows := VBoxContainer.new()
var _addr_lbl: Label
var _hint: Label


func _init() -> void:
	name = "HostInvite"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.skin().color("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var card := UiTheme.vbox(12, 24)
	card.custom_minimum_size.x = 620
	centre.add_child(card)

	var title := UiTheme.label(I18n.t("invite.title"), 24, UiTheme.COL().text)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(title)

	_addr_lbl = UiTheme.label("", 13, UiTheme.COL().accent2)
	_addr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_addr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_addr_lbl)

	card.add_child(_rows)

	_hint = UiTheme.label_wrap(I18n.t("invite.hint"), 12, UiTheme.COL().text_dim)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_hint)

	var close := UiTheme.button(I18n.t("invite.close"))
	close.connect("pressed", Callable(self, "_on_close"))
	card.add_child(close)


## Fill the screen from what the host actually bound and minted.
## `seat_links` maps seat index -> full URL.
func set_invitation(address: String, seat_links: Array) -> void:
	_address = address
	_links.clear()
	for l in seat_links:
		_links.append(String(l))
	_addr_lbl.text = address
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var i := 0
	for link in _links:
		i += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var num := UiTheme.label("%d." % i, 13, UiTheme.COL().text_dim)
		num.custom_minimum_size.x = 22
		row.add_child(num)
		# the link itself: selectable so it can be copied by hand when the button cannot reach
		# the clipboard (a headless or remote session has no clipboard at all). SELECTABLE MEANS
		# RichTextLabel — `selection_enabled` does not exist on Label, and setting it there threw
		# a SCRIPT ERROR on every row while the text stayed unselectable (SG-07 caught it).
		var lbl := UiTheme.selectable_text(link, 12, UiTheme.COL().text)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var copy := UiTheme.button(I18n.t("invite.copy"))
		copy.custom_minimum_size.x = 96
		copy.connect("pressed", Callable(self, "_on_copy").bind(link))
		row.add_child(copy)
		_rows.add_child(row)


func _on_copy(link: String) -> void:
	DisplayServer.clipboard_set(link)
	# say it worked: a copy button that does nothing visible is indistinguishable from a broken one.
	# The confirmation is a label on the row itself — the screen has no Toast node and does not
	# need one for a single message.
	_flash(I18n.t("invite.copied"))


## Briefly show a confirmation under the links, then clear it.
func _flash(msg: String) -> void:
	_hint.text = msg
	_hint.add_theme_color_override("font_color", UiTheme.COL().accent2)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(_hint):
		_hint.text = I18n.t("invite.hint")
		_hint.add_theme_color_override("font_color", UiTheme.COL().text_dim)


func _on_close() -> void:
	closed.emit()
	queue_free()
