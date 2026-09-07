extends RefCounted
## P5 i18n dictionary — engine action names (action.*) keyed by the legal_actions
## action string, plus human-readable phase labels (phase.*). The action panel
## uses its own richer buttons (act.* in data_ui); these cover anywhere an
## internal action/phase id is shown to a human (top bar phase, hints).

const D := {
	# engine action names
	"action.roll":              {"ru": "бросок", "en": "roll"},
	"action.buy":               {"ru": "купить", "en": "buy"},
	"action.pass":              {"ru": "пас", "en": "pass"},
	"action.pay":               {"ru": "оплатить", "en": "pay"},
	"action.use_card":          {"ru": "карта", "en": "use card"},
	"action.build_house":       {"ru": "построить", "en": "build"},
	"action.sell_house":        {"ru": "продать дом", "en": "sell house"},
	"action.mortgage_property": {"ru": "заложить", "en": "mortgage"},
	"action.unmortgage_property": {"ru": "выкупить", "en": "unmortgage"},
	"action.propose_trade":     {"ru": "торг", "en": "trade"},
	"action.respond_trade":     {"ru": "ответить на сделку", "en": "respond to trade"},
	"action.bid":               {"ru": "ставка", "en": "bid"},

	# engine phases (human-readable)
	"phase.SETUP":              {"ru": "Подготовка", "en": "Setup"},
	"phase.TURN_START":         {"ru": "Начало хода", "en": "Turn start"},
	"phase.ROLL_RESOLVE":       {"ru": "Бросок", "en": "Roll"},
	"phase.PURCHASE_WAIT":      {"ru": "Покупка", "en": "Purchase"},
	"phase.AUCTION":            {"ru": "Аукцион", "en": "Auction"},
	"phase.RENT_SETTLE":        {"ru": "Аренда", "en": "Rent"},
	"phase.CARD_WAIT":          {"ru": "Карта", "en": "Card"},
	"phase.JAIL_DECISION":      {"ru": "Тюрьма", "en": "Jail"},
	"phase.END_TURN":           {"ru": "Конец хода", "en": "End turn"},
	"phase.END_GAME":           {"ru": "Игра окончена", "en": "Game over"},
}
