class_name UiProfile
extends RefCounted
## Which execution the UI is running as. NOT a toggle inside the app — the owner
## decision is that roles are chosen at LAUNCH (see docs/ui_migration_notes §9):
##
##   player  — WebUI, a seat plays locally (the web export)
##   stream  — the OBS window: spectator data only, no input, large type
##   admin   — the host application: full input + admin tools, and a switch to
##             hide the admin chrome so the same window can be streamed
##
## Components never test the role; they read this profile. Adding a fourth role
## must not require touching a component.
##
## Pure + headless-testable.

const PLAYER := "player"
const STREAM := "stream"
const ADMIN := "admin"

var id := PLAYER
var input_enabled := true
var data_source := "player"     # "player" | "spectator" | "admin"
var text_scale := 1.0
var shows_actions := true       # bottom action bar
var shows_lower_third := false  # stream event plate
var shows_admin_tools := false
var shows_journal := true
var header_full := true
var shows_role_badge := true    # read-only role indicator (replaces the mock's switcher)


## Build a profile by id, or infer one from the runtime.
static func for_id(profile_id: String) -> UiProfile:
	var p := UiProfile.new()
	match profile_id:
		STREAM:
			p.id = STREAM
			p.input_enabled = false
			p.data_source = "spectator"
			p.text_scale = 1.15
			p.shows_actions = false
			p.shows_lower_third = true
			p.header_full = false
		ADMIN:
			p.id = ADMIN
			p.data_source = "admin"
			p.shows_admin_tools = true
		_:
			p.id = PLAYER
	return p


## Infer the role at launch from the platform/CLI (owner: one application).
## Flags: --stream, --admin. A web build defaults to the player (WebUI).
static func infer(is_web: bool, flags: Array) -> UiProfile:
	var has := func(f: String) -> bool: return flags.has(f)
	if has.call("--admin"):
		return for_id(ADMIN)
	if has.call("--stream"):
		return for_id(STREAM)
	if is_web:
		return for_id(PLAYER)
	# A desktop launch without a flag is the host: admin-capable, but it may
	# still hide its admin chrome for streaming.
	return for_id(ADMIN)
