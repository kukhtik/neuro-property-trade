# Licensing

## Mechanics: public domain

The game mechanics of Monopoly (board of 40 spaces, property purchase, rent,
mortgages, houses/hotels, auctions, jail, Chance-like draw decks, bankruptcy)
are **not protectable**:

- The Darrow/Parke Brothers patent expired in 1954.
- *Anti-Monopoly, Inc. v. General Mills Fun Group* (9th Cir. 1979, aff'd 1982)
  confirmed Monopoly-like rules may be freely copied; the protectable asset is
  the trademark, not the rules.
- Games of skill/chance mechanics are functional and not subject to copyright.

We therefore implement the classic mechanics 1:1 where useful for stream
recognition.

## Trademarks: avoid entirely

Never use, in any asset, UI string, code identifier visible in a build, store
page, or stream overlay:

- The word **"MONOPOLY"** or confusable marks, Hasbro logos, the Mr. Monopoly /
  "Rich Uncle Pennybags" character.
- Street/classic field names of the board: Boardwalk, Park Place, Baltic,
  Mediterranean, Marvin Gardens, etc. Different names are required; when in
  doubt rename.
- Card deck names "Chance" / "Community Chest" (registered marks of Hasbro) —
  use originals (e.g. "Event" / "Dilemma").
- Classic token designs (top hat, thimble, Scottie, race car, boot, etc.) and
  the classic board trade dress — use a distinct layout/orientation.

## Naming for this project

Working title: **NEURO PROPERTY TRADE** (stream-facing name TBD with Vedal).
Street names: original set. Tokens: original designs. Money: original currency.

## Neuro SDK / VedalAI

- Neuro SDK is MIT (see upstream LICENSE.md) — integration code we write is ours;
  we must not redistribute SDK sources, only reference/import them.
- Do not copy game assets or code from official VedalAI integration repos
  (neuro-sts2 etc.) — they are reference-only. Our adapter follows the public
  API specification in `API/SPECIFICATION.md` (documentation, freely readable).

## Result

A streamer can monetize streams of this game without Hasbro exposure, provided
no Hasbro trademarks or trade dress are displayed. All content in `game/` must
be original or correctly licensed (CC0 asset packs recorded in `docs/assets.md`).