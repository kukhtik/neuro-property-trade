extends Control
## The screen a friend sees when they open the invitation link.
##
## RESTORED FROM archive/ui-legacy-2026-10 (the v3 swap left `main.gd` only pushing a warning:
## "join-by-link is not wired in the v3 interface yet", so opening an invitation link showed a
## dead shell that quietly refused to connect - the browser e2e measured joined=False on every
## tool). The seams it uses (`LaunchParams`, `RemoteSession`) did not change with the swap, so
## the screen comes back as it was, minus the parts of the old signal contract that are gone.
##
## WHY THIS EXISTS: joining a match used to be a command line — `--seat=<token> --host=ws://…`.
## That is fine for a smoke and useless for a person: the host had to find each token, and every
## friend had to open a terminal and paste a flag string without a typo. Now the host shares a
## link, the friend opens it, and this screen does the rest: it reads the seat and address out of
## the URL, connects, and reports what is happening while it does.
##
## THE TOKEN IS THE INVITATION. It is not shown back in full and it is not logged here — whoever
## holds it takes that seat, so it is treated like a password rather than a room number.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const LaunchParams := preload("res://ui/core/launch_params.gd")
const RemoteSession := preload("res://ui/remote_session.gd")

signal joined(pid: int)
signal gave_up(reason: String)

var _title: Label
var _status: Label
var _detail: Label
var _spinner: Label
var _retry: Button
var _session
var _dots := 0
var _elapsed := 0.0
## How long we wait before telling the player plainly that it is not working.
const GIVE_UP_AFTER := 20.0


func _init() -> void:
	name = "JoinLobby"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.skin().color("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# centred column; the frame sizes itself to the content, so no absolute pixels
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var card := UiTheme.vbox(14, 26)
	card.custom_minimum_size.x = 420
	centre.add_child(card)

	_title = UiTheme.label(I18n.t("join.title"), 26, UiTheme.COL().text)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_title)

	_spinner = UiTheme.label("•", 22, UiTheme.COL().accent)
	_spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spinner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_spinner)

	_status = UiTheme.label_wrap(I18n.t("join.connecting"), 15, UiTheme.COL().text)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_status)

	# the address, so a player can SEE where it is connecting to when it does not work
	_detail = UiTheme.label_wrap("", 12, UiTheme.COL().text_dim)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_detail)

	_retry = UiTheme.button(I18n.t("join.retry"))
	_retry.visible = false
	_retry.connect("pressed", Callable(self, "_on_retry"))
	card.add_child(_retry)


func _ready() -> void:
	var url: String = LaunchParams.host_url()
	var tok: String = LaunchParams.seat_token()
	if url == "" or tok == "":
		_standalone()
		return
	_detail.text = url
	_connect_to(url, tok)


## No invitation in the URL: this is the game opened normally. Say so rather than spinning
## forever on a connection that was never going to be attempted.
func _standalone() -> void:
	_status.text = I18n.t("join.no_invite")
	_spinner.visible = false
	_detail.text = ""
	_retry.visible = false
	gave_up.emit("no invitation")


func _connect_to(url: String, tok: String) -> void:
	# PRINT, not just state: a browser player has no console window and no log file, so without
	# this a failure to connect is invisible — the screen spins and nothing says why.
	print("JOIN_LOBBY connecting to %s (seat %s…)" % [url, tok.substr(0, 6)])
	_session = RemoteSession.new()
	_session.name = "JoinSession"
	add_child(_session)
	_session.joined.connect(_on_joined)
	_session.connection_lost.connect(_on_lost)
	# A CLIENT HAS NO ENGINE: the host owns the state, so the only thing this screen waits for is
	# the verdict that the seat was accepted.
	_session.join(url, tok)


func _process(delta: float) -> void:
	if not _spinner.visible:
		return
	_elapsed += delta
	if _elapsed >= GIVE_UP_AFTER and _retry.visible == false:
		_stall()
	_dots = int(_elapsed * 2.0) % 4
	_spinner.text = "•" + ".".repeat(_dots)


func _on_joined(pid: int) -> void:
	print("JOIN_LOBBY joined pid=%d" % pid)
	_spinner.text = "+"
	_spinner.add_theme_color_override("font_color", UiTheme.COL().accent2)
	_status.text = I18n.t("join.joined")
	joined.emit(pid)


## The host stopped answering. Say what to check instead of leaving the spinner going.
## (RemoteSession's `connection_lost` carries no reason since the v3 swap — the reason this
## screen used to print came from an older signal signature.)
func _on_lost() -> void:
	print("JOIN_LOBBY connection lost")
	_stall()


func _stall(reason: String = "") -> void:
	_spinner.visible = false
	_status.text = I18n.t("join.failed")
	_detail.text = reason if reason != "" else _detail.text
	_retry.visible = true
	gave_up.emit(reason)


func _on_retry() -> void:
	_retry.visible = false
	_spinner.visible = true
	_elapsed = 0.0
	_status.text = I18n.t("join.connecting")
	if _session != null and is_instance_valid(_session):
		_session.queue_free()
		_session = null
	var url: String = LaunchParams.host_url()
	var tok: String = LaunchParams.seat_token()
	if url != "" and tok != "":
		_connect_to(url, tok)
