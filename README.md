# Neuro Property Trade

Standalone property-trading board game (classic Monopoly mechanics, original theme)
built for [Neuro-sama](https://twitch.tv/vedal987) integration via the
[Neuro SDK](https://github.com/VedalAI/neuro-sdk).

Target: multi-seat play — Neuro, Evil Neuro and human players at the same board,
with the game fully under its own rules engine's control (AI players submit
intents; the engine validates and executes them; the AI can never corrupt state).

## Why standalone

- Monopoly **mechanics are public domain** (patent expired; see `docs/licensing.md`).
  Hasbro trademarks are NOT used: original name, street names, tokens and art.
- Full control over game state → clean, reliable Neuro state-reads and action
  validation without reverse-engineering a commercial title.
- Sits in the gap Vedal described as "intellectually challenging work" for the
  community, after his internal AI started handling routine game-integration mods.

## Stack

- **Godot 4.x** (2D board, WebGL export) + official [Godot Neuro SDK](https://github.com/VedalAI/neuro-sdk/tree/main/Godot)
- Rules engine in GDScript, deterministic, unit-tested headless
- Seats: human players (local/remote) + AI seats (`neuro`, `evil`) via SDK
- Optional voice-chat side-channel (`API/VOICE_CHAT.md`) for table talk

## Repo layout

```
game/            Godot 4 project (scenes, engine, UI)
neuro/           Neuro SDK adapter: state projection, actions, force windows
docs/            Licensing, feasibility plan, decision records
tests/           Headless engine tests + Randy integration harness
```

## Status

Phase 0 — scaffolding. See `docs/plan.md`.

## License

Code: MIT. Game content: original, non-Hasbro. "Monopoly" is referenced
descriptively only. See `docs/licensing.md`.