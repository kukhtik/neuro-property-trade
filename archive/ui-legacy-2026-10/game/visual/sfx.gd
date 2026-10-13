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

func enabled() -> bool:
	return _enabled

func play_type(t: String) -> void:
	if not _enabled: return
	if not FREQS.has(t): return
	play_tonal(FREQS[t], 0.16)

## P5 SFX: a single short "whoosh" for the dice roll (rising sweep).
func play_dice_whoosh() -> void:
	if not _enabled: return
	_sweep(420.0, 760.0, 0.22, 0.16)

## P5 SFX: a sharp click for each dice bounce during the tumble.
func play_dice_bounce() -> void:
	if not _enabled: return
	play_tonal(1400.0, 0.03)

## P5 SFX: a soft pop for a new toast appearing.
func play_toast_pop() -> void:
	if not _enabled: return
	play_tonal(1180.0, 0.05)

## P5 SFX: a subtle tick when the decision timer changes a second.
func play_timer_tick() -> void:
	if not _enabled: return
	play_tonal(1960.0, 0.02)

func play_tonal(freq: float, dur: float) -> void:
	if _gen == null or not is_playing():
		play()
	var pb: AudioStreamGeneratorPlayback = get_stream_playback()
	if pb == null or not pb.can_push_buffer(pb.get_frames_available()):
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

## P5 SFX: a rising frequency sweep (for the dice whoosh).
func _sweep(f0: float, f1: float, dur: float, amp: float) -> void:
	if _gen == null or not is_playing():
		play()
	var pb: AudioStreamGeneratorPlayback = get_stream_playback()
	if pb == null or not pb.can_push_buffer(pb.get_frames_available()):
		return
	var frames: int = int(dur * _gen.mix_rate)
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		var t := float(i) / frames
		var freq: float = lerpf(f0, f1, t)
		var phase: float = float(i) / _gen.mix_rate * freq * TAU
		var env := 1.0 - t
		var s := sin(phase) * env * amp
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
