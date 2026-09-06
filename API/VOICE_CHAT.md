# Voice-chat side-channel (spike)

Status: **SPIKE — validated the vendored SDK module headless (2026-09-06).**
The Neuro SDK already ships a complete voice-chat client; this doc records how
to wire it into the game and what was proven. No game code change was needed
for the spike itself — the module is ready to use.

## What the SDK provides

`game/addons/neuro-sdk/voice/voice_chat.gd` (`class_name NeuroVoiceChat`,
extends `Node`) opens a **second websocket** next to the main Neuro API
connection. It streams each remote player's voice (with attribution) to Neuro
so she can hear them, and receives Neuro's voice to feed into the game's voice
transmit path. It is strictly optional: if the server doesn't support it,
`voice_unavailable` is emitted once and the node stays idle — the game must
work without it.

Key API (from the vendored source):
- `start_voice()` / `stop_voice()` — connect/handshake, and leave.
- `register_speaker(name) -> int` — register a remote player; returns an id to
  tag their audio. Do NOT register Neuro's own player. Name is what her speech
  recognition attributes audio to — use the player's display name.
- `rename_speaker(id, name)` / `unregister_speaker(id)`.
- `send_speaker_audio(id, samples, sample_rate=48000, channels=1)` — send a
  chunk of one speaker's voice. Only call while the player is actually
  transmitting (voice activity / push-to-talk); do not stream silence. Input is
  interleaved PCM at any rate/channels; converted to 48 kHz mono. Recommended
  chunk 20 ms (10–100 ms fine).
- Signals: `voice_ready`, `voice_unavailable(reason)`,
  `speaking_changed(speaking)` (key push-to-talk), `speech_cancelled`,
  `audio_received(samples: PackedFloat32Array)` (Neuro's voice, 48 kHz mono —
  feed into the game's voice transmit path, do NOT play locally).

## Wire protocol / URL derivation

The voice endpoint is derived from `NEURO_SDK_WS_URL` + `NeuroSdkConfig.game`:
- `.../game/<name>` → `.../game/<name>/voice`
- `.../game` → `.../game/<name>/voice`
- bare host → `/game/<name>/voice`
- query params (e.g. `?session=`) are preserved.

Control messages are JSON `{command, game, data?}`; speaker audio is a binary
frame: 1-byte version, 1-byte reserved, 2-byte speaker id, then 48 kHz mono
PCM float32.

## What the spike proved (headless)

`game/tests/voice_test.gd` (7 tests, registered in `run.gd`) loads the vendored
module under `godot --headless --script` and exercises its pure static helpers
— these do NOT touch the SDK autoloads, so they run headless:
- `_derive_voice_url` for all four URL shapes (game-suffix, name-insert,
  bare-host, empty).
- `_to_wire_format` mono-48k passthrough, stereo→mono downmix, and 24k→48k
  resample.

Result: **168 headless tests green, 0 script errors.** The module loads and its
pure logic is correct. The live websocket path (handshake, roster, audio
frames) needs a real Neuro server / mock and is NOT covered headless — same
constraint as the main SDK adapter (class_name globals don't resolve under
`--script`; run a scene + `--import` first, per the Phase-2 tail notes).

## How to wire it into the game (when a voice server exists)

1. Set `NeuroSdkConfig.game` (e.g. `"neuro-property-trade"`) and
   `NEURO_SDK_WS_URL` before the voice node starts.
2. In `main.gd` (or the seat manager), create one `NeuroVoiceChat` node and
   `start_voice()`.
3. For each non-Neuro seat, `register_speaker(seat.name)` and keep the returned
   id; on seat leave, `unregister_speaker(id)`.
4. Feed each speaker's mic audio to `send_speaker_audio(id, ...)` only while
   they're talking; route `audio_received` into the game's voice transmit path.
5. Use `speaking_changed`/`speech_cancelled` to key push-to-talk.

## Deferred / not done

- No live server to test the websocket handshake + audio frames end-to-end.
- No game-side voice capture/playback layer (out of scope for the engine; the
  game is engine-authoritative and voice is a pure side-channel that never
  touches `submit_intent`).
