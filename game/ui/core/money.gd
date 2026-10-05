class_name Money
extends RefCounted
## Single place for formatting money and names, so no component concatenates
## strings by hand (spec §9.3). Symbol and separators come from the skin/locale.
##
## Pure + headless-testable.

const DEFAULT_SYMBOL := "$"

var symbol := DEFAULT_SYMBOL
var grouping := true


static func make(sym: String = DEFAULT_SYMBOL, group: bool = true) -> Money:
	var m := Money.new()
	m.symbol = sym
	m.grouping = group
	return m


## "$1,500" / "-$50". Negative amounts put the sign before the symbol.
func amount(value: int) -> String:
	var abs_val: int = absi(value)
	var digits := _group(abs_val)
	return ("-%s%s" % [symbol, digits]) if value < 0 else ("%s%s" % [symbol, digits])


## "+$200" / "-$50" — for cash-change floats.
func signed(value: int) -> String:
	if value >= 0:
		return "+" + amount(value)
	return amount(value)


## "$1.5K" for cramped spaces (tile price pills).
func compact(value: int) -> String:
	var abs_val: int = absi(value)
	var s: String
	if abs_val >= 1000000:
		s = "%s%sM" % [symbol, _trim(abs_val / 1000000.0)]
	elif abs_val >= 10000:
		s = "%s%sK" % [symbol, _trim(abs_val / 1000.0)]
	else:
		s = amount(value)
	return s


## A player's display name, trimmed to `max_len` with a stable fallback.
func name_of(value: String, max_len: int = 0) -> String:
	var n := value.strip_edges()
	if n == "":
		n = "?"
	if max_len > 0 and n.length() > max_len:
		n = n.substr(0, max_len - 1) + "…"
	return n


func _group(v: int) -> String:
	var s := str(v)
	if not grouping or s.length() <= 3:
		return s
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _trim(v: float) -> String:
	var s := "%.1f" % v
	return s.trim_suffix(".0")
