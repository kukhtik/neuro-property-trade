# Licensing

## Mechanics: public domain

The game mechanics of Monopoly (board of 40 spaces, property purchase, rent,
mortgages, houses/hotels, auctions, jail, Chance-like draw decks, bankruptcy)
are **not protectable**:

- The Darrow/Parke Brothers patent expired in 1954.
- The rules of a game are ideas, not expression: 17 U.S.C. § 102(b) says
  "in no case copyright protection for an idea, procedure, process, system,
  method of operation or concept, regardless of the form in which it is
  described, explained or illustrated", and *Baker v. Selden* (1866) applied
  that to a bookkeeping system. A board game's mechanics — a 40-space board,
  buying, rent, mortgages, houses, auctions, jail, draw decks, bankruptcy —
  are a "concept, regardless of the form in which it is described, explained
  or illustrated": they are not protectable, and the mechanics of an existing
  game may be re-implemented freely.
- *Anti-Monopoly, Inc. v. General Mills Fun Group*, 611 F.2d 296 (9th Cir.
  1979), is often cited here. Read it for what it decided: the court
  **REVERSED AND REMANDED** the district court's findings on the validity of
  the MONOPOLY **trademark**, and held that MONOPOLY had become generic for
  the game. It is not authority for copying game mechanics — it is a
  trademark case. Cite *Baker v. Selden* and § 102(b) for the mechanics, and
  this case only for the trademark point.
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

- Neuro SDK is MIT (see upstream `LICENSE.md`) — integration code we write is ours.
- **We DO redistribute the SDK sources**, because the Godot SDK has to be vendored to
  work offline in a build: `game/addons/neuro-sdk/` is a copy of
  `VedalAI/neuro-sdk` at a pinned commit. MIT permits this provided the copyright
  notice travels with the copy — so `game/addons/neuro-sdk/LICENSE.md` is the
  upstream notice, verbatim, and it must stay next to the code it covers. The
  earlier wording here ("we must not redistribute SDK sources, only reference
  them") contradicted what the repository actually did, and contradicted the
  MIT terms the vendored copy is distributed under.
- Do not copy game assets or code from official VedalAI integration repos
  (neuro-sts2 etc.) — they are reference-only. Our adapter follows the public
  API specification in `API/SPECIFICATION.md` (documentation, freely readable).

## Result

A streamer can monetize streams of this game without Hasbro exposure, provided
no Hasbro trademarks or trade dress are displayed. All content in `game/` must
be original or correctly licensed (CC0 asset packs recorded in `docs/assets.md`).