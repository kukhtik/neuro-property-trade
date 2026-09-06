# Game Concept Specification — Multi-seat Mode Architecture

Status: DRAFT · Date: 2026-09-06
Owner: this repo, profile `monopoly`.
Related: `docs/plan.md` (phases), `docs/licensing.md` (naming constraints).

This spec fixes the game concept decisions made before any implementation:
the seat model, full game-config schema, admin console, and the three mode
variants (full-network / chat-driven / local). It is the authoritative
reference for the rules engine and lobby work.

---

## 1. One engine, many seat drivers

The engine is **unaware** of whether a seat is a human, the chat, or an AI.
Every seat is `{ name, character, input_driver }`. The input driver
determines *how* intents reach the validator; the engine itself only sees
validated intents against authoritative state. This makes the three variants
(remote humans / chat-driven seat / local) three seat-driver configurations,
not three separate games.

Seat drivers (planned):

| Driver | Description | When used |
|---|---|---|
| `LOCAL` | Input from the host machine (host plays, or guests share one screen) | Default first mode; streamer itself |
| `CHAT` | A collective Twitch seat driven by viewer votes/commands | Viewer-participation mode |
| `REMOTE` | A full networked human client (WebGL browser) | Later phase — added as another driver, post-MVP |
| `sdk` | Neuro and/or Evil via Neuro SDK (characterId `neuro` / `evil`) | AI seats |
| `admin` | Hidden host-side console (Vedal): state edits, unblocking, debug | Always present on host |

Rule: **an AI seat is just a seat whose input arrives over the SDK with a
deadline.** Every driver (LOCAL/CHAT/REMOTE/SDK) pushes intents into the same
validator. REMOTE is built last and adds a network transport ring over the
same engine — no engine changes required.

---

## 2. Full game-config schema

The lobby writes a `GameSettings` object that the engine consumes. Settings
are grouped into five blocks. Each has a default (the `DEFAULT` column) so a
session can start with zero configuration. Flags marked `[SPLIT]` are
acknowledged design decisions that still need a final call.

### Block 1 — Seats & composition
| Setting | Options | DEFAULT |
|---|---|---|
| `seat_count` | 2–8 | 4 |
| `seat_assignments` | per seat: `LOCAL` / `CHAT` / `REMOTE` / `sdk:neuro` / `sdk:evil` | mixed |
| per-seat: `name`, `token_color`, `token_id` | free / palette / original tokens | auto |
| `starting_order` | random / manual / arrival | random |

### Block 2 — Base economy (classic)
| Setting | Options | DEFAULT |
|---|---|---|
| `starting_cash` | 1000–5000 | 1500 |
| `go_bonus` | on / off / amount | on (200) |
| `jail_rule` | 3 turns then pay / 3 turns or roll doubles / both | both |
| `free_parking` | off (house rule) / on (collects fines) | off |
| `doubles` | on / off | on |
| `triple_doubles_to_jail` | on / off | on |
| `bankruptcy` | normal transfer / transfer-to-creditor | normal |

### Block 3 — Property ops
| Setting | Options | DEFAULT |
|---|---|---|
| `auctions_on_refusal` | on / off | on |
| `auction_condition` | "no buyer → auction" / "not bought → auction" | not-bought |
| `housing` | on / off | on |
| `even_build` | on / off | on |
| `monopoly_rent_x2` | on / off | on |
| `mortgage` | on / off | on |
| `mortgage_loan_pct`, `mortgage_repay_pct` | numeric | 50 / 110 |
| `trades` | on / off | on |
| `trade_window` | between turns only / any time | any time |
| `trade_cash_limit` | unlimited / capped [SPLIT] | unlimited |

### Block 4 — Decks & theme
| Setting | Options | DEFAULT |
|---|---|---|
| `deck_pairs` | 2 decks ("event" style), 16–30 cards each, original names | default |
| `theme_preset` | classic / neon-city / space / custom (board.json) | classic |
| `deck_shuffle` | per round / per game | per game |
| `card_effects` | predefined set (original, non-Hasbro) | default |

### Block 5 — Tempo, stream, AI
| Setting | Options | DEFAULT |
|---|---|---|
| `turn_timer` | off / 15s / 30s / 60s | 30s |
| `auction_timer` | off / 10s / 20s | 15s |
| `timeout_action` | auto-pass / mark-away | auto-pass **[REVISED]** |
| `chat_mode` | majority vote / first-command / moderator-weight | majority |
| `ai_aggression` | per AI seat: 0–100 (trade/aggression style) | 50 |
| `evil_enabled` | on / off (separate toggle) | off |
| `rng_seed` | manual (deterministic replay) / random | random |
| `spectacle` (auto-focus camera, highlight active player) | on / off | on |
| `event_overlay` (event log on stream overlay) | on / off | on |

Post-MVP / deferred (kept in the schema, not in MVP):
- `fast_forward` animation skip; buy-on-credit-instead-of-mortgage rule;
  trade-cash cap final rule.

---

## 3. Timeout & auto-pass **[REVISED]**

On timeout of any non-local seat (human away/hung, SDK not answering), the
engine executes **auto-pass** so the match never hangs:
- `LOCAL`/`CHAT`/`REMOTE`: auto-pass = skip that decision (pass on purchase,
  no bid, end turn) and flag the seat "away".
- `sdk`: give the force-window one short retry, then auto-pass.
Default: auto-pass. Stream never stalls. `timeout_action` in the schema above
reflects this; "mark-away" is a secondary option.

---

## 4. Vedal's admin console

A separate class of seat (`admin`): **host-side, local, always present.**
No network channel, no spooﬁng surface in MVP. Later a token-guarded remote
panel is possible, but not MVP.

Two hard rules:
1. **Admin edits go through the authoritative engine too** — every
   `admin_override` is validated, executed, and written to the same event log.
   Determinism and replay-by-seed survive even after manual intervention.
2. Admin is local to the host: hidden panel (hotkey, e.g. F12) on the hosting
   machine.

Tools (grouped):

A — Unblocking (most common on stream):
- force pass turn for a stuck seat; force a roll for a stuck decision;
- reset a seat to "awaiting turn"; roll back to the nearest decision point.

B — State editing (debug / scenario):
- set balance, teleport a token, set dice (force doubles);
- grant/revoke property, houses/hotels; mortgage/unmortgage;
- change phase/turn/order; insert/remove a deck card;
- tweak a tile's cost/rent live.

C — Diagnostics & replay:
- live state dump (balances, positions, holdings) as a table;
- snapshot export/import (restore "this exact state");
- event-log filter by player/tile/type;
- force-window viewer (what the SDK sees — inspect the projection);
- redo a turn with a given seed.

D — Stream control (spectacle mode):
- pause/resume, restart match; freeze timers mid-banter;
- camera zoom / disable animations for speed.

---

## 5. How a match is run (stream view)

- Host runs the engine + renders the board; the board is captured into OBS —
  that IS the stream picture.
- AI seats play by intents over SDK; viewers watch the AI's moves and chat.
- **Board on stream — browser (WebGL)** is the preferred option: the same URL
  serves the streamer's board and (post-MVP) human clients. Native window
  capture is the fallback pending a WebGL/SDK POC (Phase 2).
- Humans join via a short room code (Jackbox-style) to take a free seat
  (post-MVP for REMOTE; in MVP, LOCAL/CHAT cover viewer participation).

---

## 6. Development order (orchestration notes)

- First playable sessions run on `LOCAL` (host) + `CHAT` (viewers) + AI
  (Neuro/Evil). REMOTE is added later over the same engine.
- The full config schema is implemented even if some options are exercised
  later; defaults keep the MVP simple.
- See `docs/plan.md` for phase/test-ladder details.
