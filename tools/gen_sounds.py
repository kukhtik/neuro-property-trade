#!/usr/bin/env python3
"""Procedurally synthesise the game's sound effects into game/assets/audio/*.wav.

WHY SYNTHESIS (owner's decision, docs/tracks/2026-10-20-three-tracks.md §7 B2): the repository
shipped with ZERO audio files. Bringing in external samples is a licensing question and an
external blocker; `wave` + `struct` from the standard library is neither. The sounds are short,
quiet and deliberately "technical" - a dice click, a coin, a low buzz - not music.

Nothing here plays at load time: SoundManager (game/audio/sound_manager.gd) loads the WAV by
name, so replacing any file with a real recording needs NO code change.

Format: 22050 Hz, mono, 16-bit PCM, peak about -10 dBFS (quiet by design; the SFX bus adds
another -3 dB). Deterministic: the noise source is a seeded Mersenne Twister, so re-running this
script reproduces the same bytes and the gate that counts plays stays stable.

Usage:  python tools/gen_sounds.py        # rewrites game/assets/audio/*.wav
"""

import math
import os
import random
import struct
import wave

RATE = 22050
PEAK = 0.30                      # what every sound is normalised to (quiet on purpose)
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "..", "game", "assets", "audio"))
_rng = random.Random(0x5EED)     # fixed seed: the same bytes on every machine


# --- primitives -------------------------------------------------------------------------------
def _tau():
    return 2.0 * math.pi


def tone(freq, t, shape="sine"):
    """One sample of a waveform at `t` seconds."""
    phase = _tau() * freq * t
    if shape == "sine":
        return math.sin(phase)
    if shape == "tri":
        return 2.0 / math.pi * math.asin(max(-1.0, min(1.0, math.sin(phase))))
    if shape == "soft_square":                      # odd harmonics only, gentle edges
        return sum(math.sin(phase * h) / h for h in (1, 3, 5)) * 0.75
    if shape == "bell":                             # fundamental + a quiet 2nd/3rd harmonic
        return math.sin(phase) + 0.35 * math.sin(2 * phase) + 0.12 * math.sin(3 * phase)
    return math.sin(phase)


def sweep(f0, f1, t, dur, shape="sine"):
    """A linear frequency glide from f0 to f1 over `dur` seconds (phase-integrated)."""
    k = (f1 - f0) / max(dur, 1e-6)
    phase = _tau() * (f0 * t + 0.5 * k * t * t)
    if shape == "tri":
        return 2.0 / math.pi * math.asin(max(-1.0, min(1.0, math.sin(phase))))
    return math.sin(phase)


def _noise_burst(n, decay, low, amp, rng):
    """A decaying noise burst, one-pole low-passed so it reads as a click, not as hiss."""
    out = []
    state = 0.0
    for i in range(n):
        state += low * (rng.uniform(-1.0, 1.0) - state)
        out.append(state * amp * math.exp(-i / (RATE * decay)))
    return out


def _mix(*layers):
    """Sum equal-or-unequal length layers into one list of floats."""
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def _pad(samples, n):
    return samples + [0.0] * max(0, n - len(samples))


def _decay(n, tau, amp=1.0, attack=0.004):
    """Exponential decay with a short attack, so nothing starts with a click."""
    a_n = max(1, int(attack * RATE))
    out = []
    for i in range(n):
        e = math.exp(-i / (RATE * tau))
        if i < a_n:
            e *= i / a_n
        out.append(amp * e)
    return out


def _apply(samples, envelope):
    return [s * envelope[i] for i, s in enumerate(samples[:len(envelope)])]


def _to_seconds(dur, fn):
    n = int(dur * RATE)
    return [fn(i / RATE) for i in range(n)]


# --- the sounds -------------------------------------------------------------------------------
def s_dice():
    """Two dry clicks and a low thump: dice landing on the tray."""
    n = int(0.30 * RATE)
    out = [0.0] * n
    for start, amp in ((0, 1.0), (int(0.115 * RATE), 0.85), (int(0.20 * RATE), 0.45)):
        burst = _noise_burst(int(0.05 * RATE), 0.010, 0.75, amp, _rng)
        for i, v in enumerate(burst):
            if start + i < n:
                out[start + i] += v * 0.9
    thump = _apply(_to_seconds(0.14, lambda t: tone(120, t)), _decay(int(0.14 * RATE), 0.035, 0.5))
    return _mix(out, _pad(thump, n))


def s_toast():
    """A soft two-note blip: something happened, look at it."""
    n = int(0.17 * RATE)
    a = _apply(_to_seconds(0.07, lambda t: tone(659.25, t)), _decay(int(0.07 * RATE), 0.030, 0.8))
    b = _apply(_to_seconds(0.11, lambda t: tone(987.77, t, "bell")),
               _decay(int(0.11 * RATE), 0.045, 0.6))
    return _mix(_pad(a, n), [0.0] * int(0.06 * RATE) + b)


def s_tick():
    """The clock: one short high click per second."""
    n = int(0.05 * RATE)
    return _apply(_to_seconds(0.05, lambda t: tone(1400, t)), _decay(n, 0.008, 0.7, 0.001))


def s_buy():
    """A purchase: two rising notes, coin-like."""
    n = int(0.34 * RATE)
    a = _apply(_to_seconds(0.09, lambda t: tone(880, t, "bell")), _decay(int(0.09 * RATE), 0.040, 0.7))
    b = _apply(_to_seconds(0.24, lambda t: tone(1318.5, t, "bell")),
               _decay(int(0.24 * RATE), 0.075, 0.65))
    return _mix(_pad(a, n), [0.0] * int(0.08 * RATE) + b)


def s_bid():
    """An auction bid: one short upward glide."""
    n = int(0.18 * RATE)
    return _apply(_to_seconds(0.18, lambda t: sweep(420, 720, t, 0.18)),
                  _decay(n, 0.055, 0.7))


def s_mortgage():
    """Money leaving: a downward glide, no edge."""
    n = int(0.30 * RATE)
    return _apply(_to_seconds(0.30, lambda t: sweep(340, 160, t, 0.30, "tri")),
                  _decay(n, 0.10, 0.65))


def s_jail():
    """The cell door: inharmonic partials plus a noise strike."""
    n = int(0.38 * RATE)
    env = _decay(n, 0.085, 1.0, 0.002)
    body = _to_seconds(0.38, lambda t: (0.55 * tone(196, t) + 0.30 * tone(427, t)
                                        + 0.18 * tone(731, t) + 0.10 * tone(1093, t)))
    hit = _pad(_noise_burst(int(0.05 * RATE), 0.008, 0.9, 1.0, _rng), n)
    return _apply(_mix(body, hit), env)


def s_card():
    """A card: a paper swish and a soft pip."""
    n = int(0.24 * RATE)
    swish = _noise_burst(n, 0.055, 0.30, 0.8, _rng)
    pip = _pad(_apply(_to_seconds(0.08, lambda t: tone(560, t)),
                      _decay(int(0.08 * RATE), 0.025, 0.45)), n)
    return _mix(swish, pip)


def s_turn():
    """Somebody's turn starts: a quiet mid note."""
    n = int(0.13 * RATE)
    return _apply(_to_seconds(0.13, lambda t: tone(523.25, t)), _decay(n, 0.040, 0.6))


def s_game_over():
    """The match ends: three notes, the last one held."""
    n = int(0.72 * RATE)
    out = [0.0] * n
    notes = ((0.00, 523.25), (0.16, 659.25), (0.32, 783.99))
    for start, f in notes:
        seg = _apply(_to_seconds(0.36, lambda t, f=f: tone(f, t, "bell")),
                     _decay(int(0.36 * RATE), 0.11, 0.55))
        for i, v in enumerate(seg):
            if int(start * RATE) + i < n:
                out[int(start * RATE) + i] += v
    return out


def s_error():
    """A refusal: two low buzzes, deliberately not shrill."""
    n = int(0.26 * RATE)
    out = [0.0] * n
    for start in (0, int(0.13 * RATE)):
        seg = _apply(_to_seconds(0.09, lambda t: tone(150, t, "soft_square")),
                     _decay(int(0.09 * RATE), 0.030, 0.55))
        for i, v in enumerate(seg):
            if start + i < n:
                out[start + i] += v
    return out


def s_skin():
    """A skin change: a short bright shimmer."""
    n = int(0.20 * RATE)
    a = _to_seconds(0.20, lambda t: sweep(1150, 1800, t, 0.20))
    b = _to_seconds(0.20, lambda t: sweep(1180, 1840, t, 0.20))
    return _apply(_mix(a, b), _decay(n, 0.050, 0.35))


SOUNDS = {
    "dice": s_dice,
    "toast": s_toast,
    "tick": s_tick,
    "buy": s_buy,
    "bid": s_bid,
    "mortgage": s_mortgage,
    "jail": s_jail,
    "card": s_card,
    "turn": s_turn,
    "game_over": s_game_over,
    "error": s_error,
    "skin": s_skin,
}


# --- writing ----------------------------------------------------------------------------------
def _normalise(samples, peak=PEAK, fade_ms=3.0):
    top = max((abs(s) for s in samples), default=0.0)
    if top <= 0.0:
        return samples
    gain = peak / top
    out = [s * gain for s in samples]
    # 3 ms fade in/out: a WAV that starts or ends on a non-zero sample pops on some drivers
    f = max(1, int(RATE * fade_ms / 1000.0))
    for i in range(min(f, len(out))):
        k = i / f
        out[i] *= k
        out[-1 - i] *= k
    return out


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for name, fn in SOUNDS.items():
        samples = _normalise(fn())
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, samples)
        size = os.path.getsize(path)
        total += size
        print("%-10s %5d samples  %6d bytes  %s" % (name, len(samples), size,
                                                    os.path.relpath(path, OUT_DIR)))
    print("wrote %d files, %d bytes total into %s" % (len(SOUNDS), total, OUT_DIR))


if __name__ == "__main__":
    main()
