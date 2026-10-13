class_name PlayerIdentity
extends RefCounted
## Single source of player color + token (spec §4.1). Kills the 4 duplicated
## color arrays that used to live in seat_config / settings_overlay / board_view
## / tile_view. Every consumer (tile owner marker, token halo, players panel,
## top bar turn chip) reads color/token from here (or from a Seat whose
## color/token_id were assigned from here), so the owner marker, the piece and
## the list row can never disagree.
##
## 8 high-contrast colors on the #16191f backdrop + 8 unique token ids matching
## the SVG assets in game/assets/tokens/. A new player takes the next free
## color/token (never repeated within a match).

const COLORS := [
	Color("e0524a"), Color("4fa3e0"), Color("4fbf74"), Color("e8c545"),
	Color("a86ee0"), Color("e58a3c"), Color("46c8b8"), Color("d46a9e"),
]

## Token ids in the canonical order (matches game/assets/tokens/*.svg).
const TOKENS := [
	"ship", "top_hat", "dog", "cat", "race_car", "boot", "iron", "wheelbarrow",
]

## The ACTIVE palette. Starts as the built-in eight; the app seeds it from the
## chosen skin (SkinManager.sync_identity_palette) so the owner marker on a tile,
## the piece's halo, the seat row and the journal's name all read ONE value
## (P-2 / F-06). Never touched by the engine: seat colours are cosmetic and stay
## out of snapshots, so replays stay byte-stable under any skin.
static var _palette: Array = COLORS.duplicate()

## Replace the active palette (only Color entries are accepted; empty is ignored
## so a skin-less environment keeps the built-in eight).
static func set_palette(colors: Array) -> void:
	var clean: Array = []
	for c in colors:
		if c is Color:
			clean.append(c)
	if not clean.is_empty():
		_palette = clean

static func palette() -> Array:
	return _palette

## Color for a player index (wraps after the ACTIVE palette's size).
static func color_of(pid: int) -> Color:
	return _palette[posmod(pid, _palette.size())]

## Token id for a player index (wraps after 8).
static func token_of(pid: int) -> String:
	return TOKENS[pid % TOKENS.size()]

## True when the token id is one of the known assets.
static func is_known_token(token_id: String) -> bool:
	return TOKENS.has(token_id.strip_edges())
