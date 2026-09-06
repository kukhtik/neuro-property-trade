class_name Sfx
extends AudioStreamPlayer
## Procedural SFX — AudioStreamGenerator, no asset files. A short tone blip per
## event type. Cosmetic; if playback can't push a buffer we just skip (the
## engine never waits on audio).

const FREQS := {
	"roll":       660.0,
	"move":       520.0,
	"buy":        820.0,
	"purchase":   820.0,
	"pay":        300.0,
	"rent":       300.0,
	"tax":        300.0,
	"build":      700.0,
	"sell":       620.0,
	"card":       560.0,
	"card_draw":  560.0,
	"jail":       220.0,
	"bankrupt":   150.0,
	"winner":     990.0,
	"go_bonus":   880.0,
	"auction_win": 760.0,
}

var _gen: AudioStreamGenerator
var _enabled := true

func _ready() -> void:
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = 22050
	_gen.buffer_length = 0.2
	stream = _gen

func set_enabled(on: bool) -> void:
	_enabled = on

func play_type(t: String) -> void:
	if not _enabled: return
	if not FREQS.has(t): return
	play_tonal(FREQS[t], 0.16)

func play_tonal(freq: float, dur: float) -> void:
	if _gen == null or not playing:
		play()
	var pb: AudioStreamGeneratorPlayback = _gen.get_playback()
	if pb == null or not pb.can_push_buffer(_gen.get_frames_available()):
		return
	var frames: int = int(dur * _gen.mix_rate)
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		var phase := float(i) / _gen.mix_rate * freq * TAU
		var env := 1.0 - float(i) / frames
		var s := sin(phase) * env * 0.18
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
