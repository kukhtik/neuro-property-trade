extends Node
## ЧТО ВИДИТ ИГРОК: ключ вместо текста или строку.
##
## ЗАЧЕМ ОТДЕЛЬНАЯ ПРОБА: `i18n_probe` проверяет, что все ключи В ТАБЛИЦЕ разворачиваются, и
## проходил зелёным, пока игрок читал на экране `park`, `card`, `bid`. Он не сверяет таблицу со
## списком того, что движок реально присылает. Эта проба идёт обратным путём: берёт каждое
## событие движка, прогоняет через адаптер (который и делает перевод) и падает, если результат
## совпал с ключом.
##
## ЛОВУШКА, стоившая одной недействующей правки: журнал переводит НЕ тип события движка, а SPAN
## адаптера. `free_parking` -> `TYPE_MAP` -> `"park"` -> `I18n.t("event_type.park")`. Ключ
## `event_type.free_parking` не запрашивается никогда.
func _ready() -> void:
	var bad: Array = []
	var src = load("res://ui/core/event_adapter.gd")

	# Каждое событие, которое движок способен записать в лог.
	var engine_types: Array = [
		"setup", "roll", "move", "teleport", "go_bonus", "purchase", "rent", "tax",
		"free_parking", "card_draw", "card_gain", "card_land", "card_null", "jail",
		"auction_start", "auction_bid", "auction_pass", "auction_win", "auction_unwon",
		"build", "sell", "mortgage", "unmortgage", "trade_proposed", "trade",
		"trade_declined", "bankrupt", "winner",
	]
	var ad = src.new()
	var checked := 0
	for t in engine_types:
		var row: Dictionary = ad.adapt({"type": t, "data": {}})
		if row.is_empty():
			continue  # событие намеренно не показывается в журнале
		var span: String = str(row.get("k", ""))
		var full: String = "event_type." + span
		checked += 1
		if not I18n.has(full):
			bad.append("%s -> span '%s' -> НЕТ КЛЮЧА %s" % [t, span, full])
		elif I18n.t(full) == full:
			bad.append("%s -> значение равно ключу: %s" % [t, full])

	# И восемь категорий фильтра: они стоят в выпадающем списке журнала и видны игроку.
	for cat in ["ty.roll", "ty.money", "ty.buy", "ty.auction",
			"ty.build", "ty.card", "ty.trade", "ty.other"]:
		checked += 1
		if not I18n.has(cat):
			bad.append("НЕТ категории фильтра: " + cat)
		elif I18n.t(cat) == cat:
			bad.append("категория равна ключу: " + cat)

	print("проверено строк интерфейса: %d" % checked)
	if bad.is_empty():
		print("JOURNAL TEXT PROBE: ALL PASSED")
		get_tree().quit(0)
		return
	print("JOURNAL TEXT PROBE: FAILED (%d) — игрок увидит ключи:" % bad.size())
	for b in Array(bad).slice(0, 20):
		print("   ", b)
	get_tree().quit(1)
