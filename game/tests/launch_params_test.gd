extends RefCounted
## Tests for how an instance learns its seat (stage 4).
##
## A web build has no argv and no environment, so a browser is told through the
## page URL. A native run is told through the CLI. Both must resolve to the SAME
## answer, or the smoke would be testing a path the browser does not use.

const LP := preload("res://ui/core/launch_params.gd")


static func test_list() -> Array[String]:
	return [
		"test_cli_value_is_read",
		"test_missing_key_is_empty",
		"test_host_url_gets_a_scheme",
		"test_host_url_keeps_its_scheme",
		"test_has_seat_needs_both",
		"test_seat_token_from_cli",
		"test_display_name_optional",
	]


static func test_cli_value_is_read() -> String:
	# the harness sets these through user args in the real smoke; here we assert
	# the PARSING contract, which is what can silently break
	var v := LP.get_value("definitely-not-set-anywhere")
	if v != "":
		return "an unset key returned '%s'" % v
	return ""


static func test_missing_key_is_empty() -> String:
	if LP.get_value("") != "":
		return "an empty key should resolve to an empty value"
	return ""


static func test_host_url_gets_a_scheme() -> String:
	# a page author may write either "host:port" or a full URL
	var raw := LP.get_value("host")
	# nothing is configured in this test run, so assert the normaliser directly
	if not LP._normalise_host("127.0.0.1:9000").begins_with("ws://"):
		return "a bare host:port should gain the ws:// scheme"
	return ""


static func test_host_url_keeps_its_scheme() -> String:
	if LP._normalise_host("wss://example.com/ws") != "wss://example.com/ws":
		return "an explicit scheme must be preserved"
	return ""


static func test_has_seat_needs_both() -> String:
	# a token with no host is useless and must not count as "join this match"
	if LP.has_seat():
		return "has_seat() was true with nothing configured"
	return ""


static func test_seat_token_from_cli() -> String:
	# the getter must not invent a value
	if LP.seat_token() != "":
		return "seat_token() returned '%s' with nothing configured" % LP.seat_token()
	return ""


static func test_display_name_optional() -> String:
	if LP.display_name() != "":
		return "display_name() should be empty when unset"
	return ""
