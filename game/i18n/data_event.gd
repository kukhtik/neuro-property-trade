extends RefCounted
## P5 i18n dictionary — event-message domain (event.*). Used by
## EventMessages.describe (journal + event overlay) and by ToastStack's
## show_event_toast. Keys map 1:1 to engine event `type` values.

const D := {
	"event.roll":       {"ru": "%s бросает %d+%d", "en": "%s rolls %d+%d"},
	"event.move":       {"ru": "%s двигается → %d", "en": "%s moves → %d"},
	"event.land":       {"ru": "%s приземляется на клетку %d", "en": "%s lands on tile %d"},
	"event.purchase":   {"ru": "%s покупает клетку %d ($%d)", "en": "%s buys tile %d ($%d)"},
	"event.pass":       {"ru": "%s пропускает клетку %d", "en": "%s passes tile %d"},
	"event.pay":        {"ru": "%s платит $%d", "en": "%s pays $%d"},
	"event.rent":       {"ru": "%s платит аренду", "en": "%s pays rent"},
	"event.build":      {"ru": "%s строит на клетке %d", "en": "%s builds on tile %d"},
	"event.sell":       {"ru": "%s продаёт с клетки %d", "en": "%s sells from tile %d"},
	"event.mortgage":   {"ru": "%s закладывает клетку %d", "en": "%s mortgages tile %d"},
	"event.bankrupt":   {"ru": "%s банкротится", "en": "%s is bankrupt"},
	"event.jail":       {"ru": "%s попадает в тюрьму", "en": "%s goes to jail"},
	"event.go_bonus":   {"ru": "%s получает бонус GO", "en": "%s collects GO bonus"},
	"event.tax":        {"ru": "%s платит налог", "en": "%s pays tax"},
	"event.card_draw":  {"ru": "%s тянет карту", "en": "%s draws a card"},
	"event.card_land":  {"ru": "%s карта → клетка %d", "en": "%s card → tile %d"},
	"event.winner":     {"ru": "%s ПОБЕДИЛ!", "en": "%s WINS!"},
	"event.trade":      {"ru": "сделка завершена", "en": "trade complete"},
	"event.auction_win": {"ru": "%s выигрывает аукцион клетки %d", "en": "%s wins auction of tile %d"},
	"event.auction_start": {"ru": "аукцион начинается на клетке %d", "en": "auction starts on tile %d"},
	"event.admin_override": {"ru": "админ: %s", "en": "admin: %s"},
	"event.tile_name":  {"ru": "тайл %d", "en": "tile %d"},

	# toast-specific (event <type> messages shown as toasts/banners)
	"toast.purchase":  {"ru": "%s купил «%s» за $%d", "en": "%s bought «%s» for $%d"},
	"toast.pass":      {"ru": "%s не купил «%s»", "en": "%s did not buy «%s»"},
	"toast.pay":       {"ru": "%s заплатил $%d", "en": "%s paid $%d"},
	"toast.rent":      {"ru": "%s заплатил аренду", "en": "%s paid rent"},
	"toast.build":     {"ru": "%s построил на «%s»", "en": "%s built on «%s»"},
	"toast.sell":      {"ru": "%s продал с «%s»", "en": "%s sold from «%s»"},
	"toast.mortgage":  {"ru": "%s заложил «%s»", "en": "%s mortgaged «%s»"},
	"toast.bankrupt":  {"ru": "%s обанкротился!", "en": "%s went bankrupt!"},
	"toast.jail":      {"ru": "%s попал в тюрьму", "en": "%s went to jail"},
	"toast.go_bonus":  {"ru": "%s получает бонус GO", "en": "%s gets GO bonus"},
	"toast.tax":       {"ru": "%s заплатил налог", "en": "%s paid tax"},
	"toast.winner":    {"ru": "%s ПОБЕДИЛ!", "en": "%s WINS!"},
	"toast.trade":     {"ru": "Сделка завершена", "en": "Trade complete"},
	"toast.auction_win": {"ru": "%s выиграл аукцион «%s»", "en": "%s won auction of «%s»"},
	"toast.auction_start": {"ru": "Аукцион: «%s»", "en": "Auction: «%s»"},
	"toast.admin_override": {"ru": "Админ: %s", "en": "Admin: %s"},
	"toast.rematch":   {"ru": "РЕВАНШ", "en": "REMATCH"},
}
