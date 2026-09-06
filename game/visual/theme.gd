class_name BoardTheme
extends RefCounted
## Original color theme — deliberately NOT the Hasbro palette (docs/licensing).
## Pure data so the visual test can assert coverage and non-Hasbro hue.

const GROUP_COLORS := {
	"brown":     Color("6b3a2a"),   # umber
	"lightblue": Color("7bb8d4"),   # muted sky
	"pink":      Color("d98aa8"),   # rose
	"orange":    Color("e08a3c"),   # amber
	"red":       Color("b3403d"),   # brick
	"yellow":    Color("d9c44a"),   # ochre
	"green":     Color("3f8f5f"),   # moss
	"darkblue":  Color("2f4a7a"),   # navy
}

const TYPE_COLORS := {
	"go":            Color("3f8f5f"),
	"jail":          Color("8a8f9a"),
	"go_to_jail":    Color("8a8f9a"),
	"free_parking":  Color("5a6a4a"),
	"tax":           Color("6a3a3a"),
	"railroad":      Color("4a4a4a"),
	"utility":       Color("3a6a7a"),
	"chance":        Color("a05a2a"),
	"community":     Color("7a9a4a"),
	"property":      Color("c8ccd4"),   # base; overridden by GROUP_COLORS
}

## Return the fill color for a tile entry (from a projection tile dict).
## Property -> group color; everything else -> type color.
static func tile_color(tile: Dictionary) -> Color:
	var t: String = tile.get("type", "property")
	if t == "property":
		var g: String = tile.get("group", "")
		return GROUP_COLORS.get(g, TYPE_COLORS["property"])
	return TYPE_COLORS.get(t, Color.WHITE)
