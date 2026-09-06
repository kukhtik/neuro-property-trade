extends RefCounted
## Spike probe: can we load the vendored NeuroVoiceChat module headless and
## exercise its pure static helpers (_derive_voice_url, _to_wire_format)?
## These don't touch the SDK autoloads, so they should run under --script.

static func test_list() -> Array[String]:
	return [
		"test_derive_voice_url_game_suffix",
		"test_derive_voice_url_game_name_insert",
		"test_derive_voice_url_bare_host",
		"test_derive_voice_url_empty",
		"test_to_wire_format_mono_48k_passthrough",
		"test_to_wire_format_stereo_downmix",
		"test_to_wire_format_resample",
	]

static func _voice() -> Dictionary:
	var V = load("res://addons/neuro-sdk/voice/voice_chat.gd")
	return {"v": V}

static func test_derive_voice_url_game_suffix() -> String:
	var v = _voice()["v"]
	# .../game/<name> -> .../game/<name>/voice
	var got = v._derive_voice_url("ws://localhost:8000/game/neuro", "neuro")
	if got != "ws://localhost:8000/game/neuro/voice":
		return "expected .../game/neuro/voice, got %s" % got
	return ""

static func test_derive_voice_url_game_name_insert() -> String:
	var v = _voice()["v"]
	# .../game (no name) -> .../game/<name>/voice
	var got = v._derive_voice_url("ws://localhost:8000/game", "neuro")
	if got != "ws://localhost:8000/game/neuro/voice":
		return "expected .../game/neuro/voice, got %s" % got
	return ""

static func test_derive_voice_url_bare_host() -> String:
	var v = _voice()["v"]
	# bare host -> /game/<name>/voice
	var got = v._derive_voice_url("ws://localhost:8000", "neuro")
	if got != "ws://localhost:8000/game/neuro/voice":
		return "expected ws://localhost:8000/game/neuro/voice, got %s" % got
	return ""

static func test_derive_voice_url_empty() -> String:
	var v = _voice()["v"]
	if v._derive_voice_url("", "neuro") != "":
		return "empty base should return empty"
	if v._derive_voice_url("ws://x", "") != "":
		return "empty game should return empty"
	return ""

static func test_to_wire_format_mono_48k_passthrough() -> String:
	var v = _voice()["v"]
	var samples := PackedFloat32Array([0.1, -0.2, 0.3])
	var out = v._to_wire_format(samples, 48000, 1)
	if out.size() != 3:
		return "48k mono should pass through, got %d samples" % out.size()
	if absf(out[0] - 0.1) > 0.0001:
		return "sample 0 changed: %f" % out[0]
	return ""

static func test_to_wire_format_stereo_downmix() -> String:
	var v = _voice()["v"]
	# stereo 48k -> mono 48k, average of channels
	var samples := PackedFloat32Array([0.2, 0.4, -0.2, -0.4])
	var out = v._to_wire_format(samples, 48000, 2)
	if out.size() != 2:
		return "stereo 2 frames should downmix to 2 mono, got %d" % out.size()
	if absf(out[0] - 0.3) > 0.0001:
		return "downmix frame0 should be 0.3, got %f" % out[0]
	return ""

static func test_to_wire_format_resample() -> String:
	var v = _voice()["v"]
	# 24k mono -> 48k mono doubles length
	var samples := PackedFloat32Array([0.0, 1.0])
	var out = v._to_wire_format(samples, 24000, 1)
	if out.size() != 4:
		return "24k->48k should double to 4 samples, got %d" % out.size()
	return ""
