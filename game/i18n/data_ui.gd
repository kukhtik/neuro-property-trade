extends RefCounted
## P5 i18n dictionary — UI-domain keys (ui.*). Merged by i18n.gd.
## `const D` is the single exported key dict. Do NOT edit after merge is stable
## without updating the EN string alongside RU.

const D := {
	# ---- general / common ----
	"ui.ok":            {"ru": "OK", "en": "OK"},
	"ui.cancel":        {"ru": "Отмена", "en": "Cancel"},
	"ui.close":         {"ru": "Закрыть", "en": "Close"},
	# ICON-ONLY CONTROLS BECOME WORDS (owner, 17.10: no glyphs at all). The captions the
	# close / remove / pin buttons now carry.
	"ui.close_tip":     {"ru": "Закрыть это окно", "en": "Close this window"},
	"settings.remove":  {"ru": "Убрать", "en": "Remove"},
	"ins.pin":          {"ru": "Закрепить", "en": "Pin"},
	"ui.reset":         {"ru": "сброс", "en": "reset"},
	"ui.back":          {"ru": "НАЗАД", "en": "BACK"},
	"ui.players":       {"ru": "ИГРОКИ", "en": "PLAYERS"},
	"ui.language":      {"ru": "Язык", "en": "Language"},
	"ui.starting_order": {"ru": "Нач. порядок:", "en": "Start order:"},
	"ui.host_role":     {"ru": "Роль хоста:", "en": "Host role:"},


	# ---- statistics block (the mockup's #stat) ----
	# `#stat` in the mockup is houses / hotels / mortgaged, not round / pot / owned:
	#   hs.filter(h => h < 5).reduce(...)        -> houses on the board
	#   hs.filter(h => h == 5).length            -> hotels
	#   Object.values(V.mort).filter(Boolean)    -> mortgaged
	# The old three were never in the design. Values match `k.h1` / `k.ht` / `k.mort`.
	# The header's own block (`#steps`, `#cRound`, `#cPot` in the mockup)
	"ph.0":             {"ru": "Бросок", "en": "Roll"},
	"ph.1":             {"ru": "Ход", "en": "Move"},
	"ph.2":             {"ru": "Покупка", "en": "Purchase"},
	"ph.3":             {"ru": "Конец", "en": "End"},
	"top.round":        {"ru": "РАУНД", "en": "ROUND"},
	"top.pot":          {"ru": "БАНК ПАРКОВКИ", "en": "PARKING POT"},
	"stat.houses":      {"ru": "1 дом", "en": "1 house"},
	"stat.hotels":      {"ru": "Отель", "en": "Hotel"},
	"stat.mortgaged":   {"ru": "В залоге", "en": "Mortgaged"},
	# ---- design v3 (design/coverage.md §4): proposed keys, now shipping ----
	# NOTE: three keys below were REFERENCED by the v3 shell from the swap on and never written,
	# so the player read `{plr.jail}` / `{stat.round}` / `{top.decision}` (found by the HG-09
	# gate; the audit listed the same three plus the two over.* keys, which are now satisfied by
	# the already-present modal.game_over/modal.winner).
	"plr.jail":         {"ru": "ТЮРЬМА", "en": "JAIL"},
	"stat.round":       {"ru": "РАУНД", "en": "ROUND"},
	"top.decision":     {"ru": "РЕШЕНИЕ", "en": "DECISION"},
	# GLOBAL PAUSE chip: the same word on every screen while the match is stopped
	"top.paused":       {"ru": "ПАУЗА", "en": "PAUSED"},
	# `plr.owned` is used as a chip WITH the tile count; it was a bare label, so every repaint
	# raised "not all arguments converted" and the count never appeared.
	"plr.owned":        {"ru": "В собственности: %d", "en": "Owned: %d"},
	"plr.owned_tip":    {"ru": "Доля клеток доски, находящихся в собственности игроков.", "en": "Share of board tiles owned by players."},
	"plr.jail_tip":     {"ru": "Попытки выйти из тюрьмы.", "en": "Attempts to leave jail."},
	"act.timer_tip":    {"ru": "Осталось времени на решение.", "en": "Time left for the decision."},
	"act.observer_note": {"ru": "Паузы нет — матч живёт по таймерам.", "en": "No pause — the match runs on its timers."},
	"jrn.empty_title":  {"ru": "Пока пусто", "en": "Nothing yet"},
	"jrn.empty_body":   {"ru": "События появятся, когда партия начнётся. Нажмите «НАЧАТЬ ПАРТИЮ» внизу.", "en": "Events appear once the match starts. Press “START MATCH” below."},
	"die.doubles":      {"ru": "ДУБЛЬ", "en": "DOUBLE"},
	"top.wait_sdk":     {"ru": "ожидание Neuro…", "en": "awaiting Neuro…"},

	# ---- top bar ----
	"top.title":            {"ru": "NEURO PROPERTY TRADE", "en": "NEURO PROPERTY TRADE"},
	"top.turn":             {"ru": "ХОД: ", "en": "TURN: "},
	"top.phase":            {"ru": "ФАЗА: ", "en": "PHASE: "},
	# THE ENGINE'S PHASE NAMES WERE NEVER TRANSLATED. Both the header and the action bar build
	# them as `I18n.t("phase." + phase)` and fall back to the raw enum when the key is missing —
	# and every key was missing, so a Russian player watched `TURN_START` and `PURCHASE_WAIT` in
	# the status line. The fallback is right (an unknown phase must still render something), but
	# it was covering for a table that had never been written.
	"phase.SETUP":          {"ru": "Подготовка", "en": "Setup"},
	"phase.TURN_START":     {"ru": "Начало хода", "en": "Turn start"},
	"phase.ROLL_RESOLVE":   {"ru": "Бросок", "en": "Roll"},
	"phase.PURCHASE_WAIT":  {"ru": "Покупка", "en": "Purchase"},
	"phase.AUCTION":        {"ru": "Аукцион", "en": "Auction"},
	"phase.RENT_SETTLE":    {"ru": "Аренда", "en": "Rent"},
	"phase.CARD_WAIT":      {"ru": "Карта", "en": "Card"},
	"phase.JAIL_DECISION":  {"ru": "Тюрьма", "en": "Jail"},
	"phase.END_TURN":       {"ru": "Конец хода", "en": "End of turn"},
	"phase.END_GAME":       {"ru": "Конец игры", "en": "Game over"},
	# --- the join lobby: what a friend sees after opening the invitation link ---
	# --- the host's invitation screen ---
	"invite.title":  {"ru": "Партия создана — отправьте ссылку друзьям", "en": "Match created — send the link to your friends"},
	"invite.copy":   {"ru": "Копировать", "en": "Copy"},
	"invite.copied": {"ru": "Ссылка скопирована", "en": "Link copied"},
	"invite.close":  {"ru": "Закрыть", "en": "Close"},
	"invite.hint":   {"ru": "Каждому другу — СВОЯ ссылка. Он открывает её в браузере и сразу попадает в игру: ничего устанавливать не нужно. Ссылка действует только для этой партии.", "en": "EACH friend gets their OWN link. They open it in a browser and are in the game: nothing to install. The link is valid for this match only."},
	"settings.host_btn": {"ru": "Создать партию для друзей", "en": "Host a match for friends"},
	"settings.host_tip": {"ru": "Поднимает сервер, открывает его для других машин и показывает ссылки-приглашения", "en": "Opens the server to other machines and shows invitation links"},
	"join.title":       {"ru": "Neuro Property Trade", "en": "Neuro Property Trade"},
	"join.connecting":  {"ru": "Подключаемся к партии…", "en": "Joining the match…"},
	"join.joined":      {"ru": "Вы в игре! Ожидайте своего хода.", "en": "You are in! Wait for your turn."},
	"join.failed":      {"ru": "Не удалось подключиться", "en": "Could not connect"},
	"join.retry":       {"ru": "Попробовать снова", "en": "Try again"},
	"join.no_invite":   {"ru": "Это обычный запуск игры. Чтобы играть с друзьями, откройте ссылку-приглашение от ведущего.", "en": "This is a normal launch. To play with friends, open the invitation link from the host."},
	"top.cold":             {"ru": "до старта", "en": "not started"},
	"top.settings_tip":     {"ru": "Открыть настройки и правила игры", "en": "Open settings and game rules"},
	# the mockup has a `RU / EN` control in the header; `I18n` already switched languages,
	# but only from inside the settings dialog
	"top.skin_tip":         {"ru": "Тема оформления", "en": "Interface theme"},
	"top.lang_tip":         {"ru": "Язык интерфейса", "en": "Interface language"},
	"top.restart_tip":      {"ru": "Пересобрать партию с новым сидом (рестарт)", "en": "Rebuild the match with a new seed (restart)"},
	"top.panels_tip":       {"ru": "Скрыть или показать боковые панели", "en": "Hide or show the side panels"},
	# THE HEADER CONTROLS READ AS WORDS (owner, 17.10: "значки не используем впринципе ... нужны
	# нормальные читаемые надписи"). Short enough to sit in the 56px bar, long enough to be understood.
	"top.settings":         {"ru": "Настройки", "en": "Settings"},
	"top.panels":           {"ru": "Панели", "en": "Panels"},
	"top.restart":          {"ru": "Заново", "en": "Restart"},
	"top.skin":             {"ru": "Тема", "en": "Theme"},
	"top.lang":             {"ru": "Язык", "en": "Language"},
	# PART 4 — bindings. One label per rebindable action, plus the screen's own furniture. The screen
	# reads these by `Bindings.label_key(act)`, so a new action cannot ship without its strings.
	"bind.buy":             {"ru": "Купить", "en": "Buy"},
	"bind.end_turn":        {"ru": "Завершить ход", "en": "End turn"},
	"bind.roll":            {"ru": "Бросок кубиков", "en": "Roll the dice"},
	"bind.trade":           {"ru": "Предложить сделку", "en": "Propose a trade"},
	"bind.build":           {"ru": "Построить дом", "en": "Build a house"},
	"bind.mortgage":        {"ru": "Заложить / выкупить", "en": "Mortgage / redeem"},
	"bind.panels":          {"ru": "Показать/скрыть панели", "en": "Show/hide the panels"},
	"bind.settings":        {"ru": "Открыть настройки", "en": "Open settings"},
	"bind.follow":          {"ru": "Следить за ходом", "en": "Follow the turn"},
	"bind.cam_left":        {"ru": "Камера влево", "en": "Camera left"},
	"bind.cam_right":       {"ru": "Камера вправо", "en": "Camera right"},
	"bind.cam_up":          {"ru": "Камера вверх", "en": "Camera up"},
	"bind.cam_down":        {"ru": "Камера вниз", "en": "Camera down"},
	"bind.zoom_in":         {"ru": "Приблизить", "en": "Zoom in"},
	"bind.zoom_out":        {"ru": "Отдалить", "en": "Zoom out"},
	"bind.group.game":      {"ru": "В игре", "en": "In game"},
	"bind.group.ui":        {"ru": "Интерфейс", "en": "Interface"},
	"bind.group.camera":    {"ru": "Камера", "en": "Camera"},
	"bind.press":           {"ru": "Нажмите клавишу…", "en": "Press a key…"},
	"bind.taken":           {"ru": "Клавиша занята: %s", "en": "Key already taken: %s"},
	"bind.reset":           {"ru": "Сбросить", "en": "Reset"},
	"bind.reset_all":       {"ru": "Сбросить всё", "en": "Reset all"},
	"bind.reset_tip":       {"ru": "Вернуть эту клавишу по умолчанию", "en": "Return this key to its default"},
	"bind.reset_all_tip":   {"ru": "Вернуть все клавиши по умолчанию", "en": "Return every key to its default"},
	"bind.row_tip":         {"ru": "Нажмите, чтобы назначить другую клавишу", "en": "Click to assign another key"},
	"bind.hint":            {"ru": "Клик по строке — назначить клавишу; Esc — отмена", "en": "Click a row to assign a key; Esc cancels"},
	"top.eye_tip":          {"ru": "Режим наблюдателя: вернуться к настройкам матча (места без LOCAL играют сами)", "en": "Observer mode: return to match settings (seats without LOCAL play themselves)"},
	"top.admin_hint":       {"ru": "F12 — админ", "en": "F12 — admin"},

	# ---- AI characters (per seat; see seats/ai_persona.gd) ----
	"persona.tycoon":    {"ru": "Магнат", "en": "Tycoon"},
	"persona.cautious":  {"ru": "Осторожный", "en": "Cautious"},
	"persona.collector": {"ru": "Коллекционер", "en": "Collector"},
	"persona.miser":     {"ru": "Скряга", "en": "Miser"},
	"persona.aggressor": {"ru": "Агрессор", "en": "Aggressor"},
	"persona.random":    {"ru": "Случайный", "en": "Random"},
	"settings.persona":     {"ru": "Характер", "en": "Character"},
	"settings.persona_tip": {"ru": "Как этот ИИ-игрок себя ведёт: покупает, ставит на аукционе, торгует.",
		"en": "How this AI player behaves: buying, bidding, trading."},

	# ---- execution roles (read-only badge; the role is chosen at launch) ----
	"mode.player":      {"ru": "ИГРОК", "en": "PLAYER"},
	"mode.stream":      {"ru": "ЭФИР", "en": "LIVE"},
	"mode.admin":       {"ru": "АДМИН", "en": "ADMIN"},

	# ---- players panel ----
	"plr.cold":             {"ru": "Партия ещё не начата", "en": "Match not started yet"},
	"plr.pos_tiles":        {"ru": "@ %s · %d тайл.", "en": "@ %s · %d tiles."},
	"plr.auto_pass":        {"ru": "авто-пас", "en": "auto-pass"},
	"plr.bankrupt":         {"ru": "БАНКРОТ", "en": "BANKRUPT"},
	"plr.active":           {"ru": "» ход", "en": "» turn"},
	"plr.tooltip":          {"ru": "Игрок: %s\nДрайвер: %s\nДеньги: $%d\nПозиция: %s\nТайлы: %d\nДома: %d · Залоги: %d", "en": "Player: %s\nDriver: %s\nCash: $%d\nPosition: %s\nTiles: %d\nHouses: %d · Mortgaged: %d"},

	# ---- action panel ----
	"act.cold_status":      {"ru": "Партия ещё не начата", "en": "Match not started yet"},
	"act.start_btn":        {"ru": "»  НАЧАТЬ ПАРТИЮ", "en": "»  START MATCH"},
	"act.start_tip":        {"ru": "Открыть настройки и начать партию", "en": "Open settings and start the match"},
	"act.ai_status":        {"ru": "%s: управляется ИИ — ход выполняется автоматически", "en": "%s: AI-controlled — turn runs automatically"},
	"act.human_status":     {"ru": "%s  ·  ваш ход — выберите действие", "en": "%s  ·  your turn — pick an action"},
	"act.observer_timer":   {"ru": " · авто-через 0:%02d", "en": " · auto in 0:%02d"},
	"act.observer_sdk":     {"ru": " · ожидание Neuro…", "en": " · awaiting Neuro…"},
	"act.observer_status":  {"ru": "ход: %s · решение за %s%s%s", "en": "turn: %s · decision for %s%s%s"},
	# buttons
	"act.roll":             {"ru": "Бросок", "en": "Roll"},
	"act.roll_tip":         {"ru": "Бросить кубики и передвинуть фишку на выпавшее число клеток", "en": "Roll the dice and move the token by the rolled count"},
	"act.buy":              {"ru": "Купить", "en": "Buy"},
	# the mockup prints the price on the button itself (`a.buy|Купить ¤{a}`)
	"act.buy_price":        {"ru": "Купить $%d", "en": "Buy $%d"},
	"act.buy_tip":          {"ru": "Купить эту клетку за указанную цену", "en": "Buy this tile at the listed price"},
	"act.pass":             {"ru": "Отказ", "en": "Decline"},
	"act.no_buy":           {"ru": "Отказ", "en": "Decline"},
	"act.pass_tip":         {"ru": "Не покупать клетку — она уйдёт на аукцион", "en": "Do not buy this tile — it goes to auction"},
	"act.bid":              {"ru": "СТАВКА", "en": "BID"},
	"act.bid_tip":          {"ru": "Сделать ставку на аукционе за эту клетку", "en": "Place a bid in the auction for this tile"},
	"act.pay":              {"ru": "ОПЛАТИТЬ $%d", "en": "PAY $%d"},
	"act.pay_tip":          {"ru": "Заплатить штраф и выйти из тюрьмы", "en": "Pay the fine and leave jail"},
	"act.use_card":         {"ru": "КАРТА выхода", "en": "Jail card"},
	"act.use_card_tip":     {"ru": "Использовать карту «Выход из тюрьмы»", "en": "Use the get-out-of-jail card"},
	"act.build":            {"ru": "Строить", "en": "Build"},
	"act.build_tip":        {"ru": "Построить дом на выбранной клетке (нужна вся группа)", "en": "Build a house on the selected tile (needs the whole group)"},
	"act.sell":             {"ru": "Продать дом", "en": "Sell house"},
	"act.sell_tip":         {"ru": "Продать дом с выбранной клетки", "en": "Sell a house from the selected tile"},
	"act.mortgage":         {"ru": "Залог", "en": "Mortgage"},
	"act.mortgage_tip":     {"ru": "Заложить клетку и получить 50% её стоимости", "en": "Mortgage the tile for 50% of its value"},
	"act.unmortgage":       {"ru": "ВЫКУПИТЬ", "en": "UNMORTGAGE"},
	"act.unmortgage_tip":   {"ru": "Выкупить заложенную клетку (110% стоимости)", "en": "Unmortgage the tile (110% of value)"},
	"act.trade":            {"ru": "Торг", "en": "Trade"},
	"act.trade_tip":        {"ru": "Предложить сделку другому игроку (тайлы и/или деньги)", "en": "Propose a trade to another player (tiles and/or cash)"},
	"act.respond_trade":    {"ru": "ОТВЕТИТЬ на сделку", "en": "RESPOND to trade"},
	"act.respond_trade_tip": {"ru": "Принять или отклонить входящее предложение сделки", "en": "Accept or decline the incoming trade offer"},
	# contextual hints
	"act.hint_purchase":    {"ru": "Можно купить «%s» за $%d или не покупать", "en": "Can buy «%s» for $%d or not buy"},
	"act.hint_auction":     {"ru": "Аукцион — текущая ставка $%d", "en": "Auction — current bid $%d"},
	"act.hint_auction_first": {"ru": "Аукцион — сделайте первую ставку", "en": "Auction — place the first bid"},
	"act.hint_trade":       {"ru": "Входящее предложение — принять или отклонить", "en": "Incoming offer — accept or decline"},

	# ---- tile inspector ----
	"ins.title":            {"ru": "КЛЕТКА", "en": "TILE"},
	"ins.pin_tip":          {"ru": "Закрепить справку (не скрывать автоматически)", "en": "Pin this inspector (keep it open)"},
	"ins.close_tip":        {"ru": "Закрыть справку по клетке", "en": "Close the tile inspector"},
	"ins.placeholder":      {"ru": "Кликните по тайлу доски", "en": "Click a board tile"},
	"ins.free":             {"ru": "— свободен", "en": "— unowned"},
	"ins.owner":            {"ru": "владелец: ", "en": "owner: "},
	"ins.house":            {"ru": " · дом: %s", "en": " · house: %s"},
	"ins.hotel":            {"ru": "HOTEL", "en": "HOTEL"},
	"ins.mortgaged":        {"ru": " · ЗАЛОЖЕН", "en": " · MORTGAGED"},
	"ins.body":             {"ru": "«%s»  %s%s\nцена $%d · аренда $%d · %s%s", "en": "«%s»  %s%s\nprice $%d · rent $%d · %s%s"},
	# the inspector's price/rent row captions: `_fact_row(box, "ins.price")` asks for them by
	# VARIABLE, so the static key scan cannot see them - and once they were removed as
	# "duplicates", every selected tile showed the sentinel `{ins.price}:` (found by SG-08's
	# live walk, 2026-10-14).
	"ins.price":            {"ru": "цена", "en": "price"},
	"ins.rent":             {"ru": "аренда", "en": "rent"},
	# E-3/D11: the rent row says "сейчас" when the LIVE rent differs from the card's base value - the
	# game charges for houses and for a monopoly, and a player comparing plots needs to know which
	# number they are looking at. Plus the tile tooltip's own fragments.
	"ins.rent_now":         {"ru": "аренда сейчас", "en": "rent now"},
	"tip.cost":             {"ru": "цена $%d", "en": "price $%d"},
	"tip.rent":             {"ru": "аренда $%d", "en": "rent $%d"},
	"tip.rent_houses":      {"ru": "аренда $%d (%d дом.)", "en": "rent $%d (%d houses)"},
	"tip.rent_hotel":       {"ru": "аренда $%d (отель)", "en": "rent $%d (hotel)"},

	# ---- journal ----
	"jrn.title":            {"ru": "◊ ХОД СОБЫТИЙ", "en": "◊ EVENT LOG"},
	"jrn.player_lbl":       {"ru": "игрок", "en": "player"},
	"jrn.type_lbl":         {"ru": "тип", "en": "type"},
	# The journal's filter categories — the mockup's `ty.*`, eight of them, not the raw engine
	# event types. `fl.player` / `fl.type` are the dropdowns' first entries.
	"fl.player":            {"ru": "Все игроки", "en": "All players"},
	"fl.type":              {"ru": "Все типы", "en": "All types"},
	"ty.roll":              {"ru": "Броски", "en": "Rolls"},
	"ty.money":             {"ru": "Деньги", "en": "Money"},
	"ty.buy":               {"ru": "Покупки", "en": "Purchases"},
	"ty.auction":           {"ru": "Аукционы", "en": "Auctions"},
	"ty.build":             {"ru": "Стройка и залог", "en": "Build and mortgage"},
	"ty.card":              {"ru": "Карты", "en": "Cards"},
	"ty.trade":             {"ru": "Торги", "en": "Trades"},
	"ty.other":             {"ru": "Прочее", "en": "Other"},
	"jrn.all":              {"ru": "все", "en": "all"},
	"jrn.count_tip":        {"ru": "Сколько событий показано из общего числа в журнале.", "en": "How many events are shown vs the total in the log."},
	"jrn.player_tip":       {"ru": "Фильтр журнала по игроку", "en": "Filter the log by player"},
	"jrn.player_filter_tip": {"ru": "Показывать события только этого игрока (или всех).", "en": "Show events for this player only (or all)."},
	"jrn.type_tip":         {"ru": "Фильтр журнала по типу события", "en": "Filter the log by event type"},
	"jrn.type_filter_tip":  {"ru": "Показывать события только этого типа (или все).", "en": "Show events of this type only (or all)."},
	"jrn.money_tip":        {"ru": "Показывать только события, связанные с деньгами (покупки, аренда, налоги, выплаты).", "en": "Show only money-related events (purchases, rent, taxes, payments)."},
	"jrn.export_tip":       {"ru": "Экспортировать весь журнал в JSONL-файл (user://journal_export.jsonl)", "en": "Export the full log to a JSONL file (user://journal_export.jsonl)"},

	# ---- game_view / modals messages ----
	"gv.rejected_title":    {"ru": "Действие отклонено", "en": "Action rejected"},
	"gv.rejected_body":     {"ru": "Причина: %s", "en": "Reason: %s"},
	"gv.select_tile":       {"ru": "Выберите тайл", "en": "Select a tile"},
	"gv.select_tile_body":  {"ru": "Кликните по тайлу на доске, который хотите изменить.", "en": "Click the board tile you want to change."},
	"gv.journal_export_ok_title": {"ru": "Журнал экспортирован", "en": "Journal exported"},
	"gv.journal_export_ok_body":  {"ru": "Файл: %s", "en": "File: %s"},
	"gv.journal_export_fail_title": {"ru": "Экспорт журнала", "en": "Journal export"},
	"gv.journal_export_fail_body":  {"ru": "Не удалось записать файл.", "en": "Could not write the file."},

	# ---- modal_host ----
	"modal.build_title":    {"ru": "СТРОЙКА / ЗАЛОГ", "en": "BUILD / MORTGAGE"},
	"modal.tile_header":    {"ru": "Тайл: «%s» (%d)", "en": "Tile: «%s» (%d)"},
	"modal.house_cost":     {"ru": "Дом: %s  ·  стоимость дома $%s", "en": "House: %s  ·  house cost $%s"},
	"modal.trade_title":    {"ru": "ТОРГ", "en": "TRADE"},
	"modal.recipient":      {"ru": "Получатель:", "en": "Recipient:"},
	"modal.recipient_tip":  {"ru": "Кому вы предлагаете сделку.", "en": "Who you propose the trade to."},
	"modal.give_hint":      {"ru": "Даёте (ваши тайлы выбирайте кликом по доске):", "en": "You give (pick your tiles by clicking the board):"},
	"modal.give_placeholder": {"ru": "— выберите:  [ СТРОЙКА/ЗАЛОГ выбирает тайл ]", "en": "— select:  [ BUILD/MORTGAGE selects a tile ]"},
	"modal.want_hint":      {"ru": "Просите (его тайлы):", "en": "You ask (their tiles):"},
	"modal.want_placeholder": {"ru": "— укажите тайлы / деньги ниже", "en": "— specify tiles / cash below"},
	"modal.give_cash":      {"ru": "Даю $", "en": "Give $"},
	"modal.give_cash_tip":  {"ru": "Сколько денег вы отдаёте в сделке.", "en": "How much cash you give in the trade."},
	"modal.want_cash":      {"ru": "Хочу $", "en": "Want $"},
	"modal.want_cash_tip":  {"ru": "Сколько денег вы просите в сделке.", "en": "How much cash you ask in the trade."},
	"modal.offer":          {"ru": "ПРЕДЛОЖИТЬ", "en": "PROPOSE"},
	"modal.offer_tip":      {"ru": "Отправить это предложение выбранному игроку", "en": "Send this offer to the selected player"},
	"modal.cancel_tip":     {"ru": "Закрыть окно без отправки", "en": "Close without sending"},
	"modal.trade_response": {"ru": "ВХОДЯЩАЯ СДЕЛКА", "en": "INCOMING TRADE"},
	"modal.trade_offers":   {"ru": "%s предлагает %s:", "en": "%s offers %s:"},
	# E-1/D8: the old key counted tiles ("$%d + %d тайл(а)") and was the reason a player was asked
	# to decide a deal they could not read. Replaced by the two block headers below, each followed
	# by the actual NAMES from the projection board.
	"modal.trade_gives":    {"ru": "Отдаёт:", "en": "Gives:"},
	"modal.trade_asks":     {"ru": "Просит:", "en": "Asks:"},
	"modal.accept":         {"ru": "ПРИНЯТЬ", "en": "ACCEPT"},
	"modal.accept_tip":     {"ru": "Принять предложение — обмен выполнится", "en": "Accept the offer — the trade will execute"},
	"modal.decline":        {"ru": "ОТКЛОНИТЬ", "en": "DECLINE"},
	"modal.decline_tip":    {"ru": "Отклонить предложение — сделка не состоится", "en": "Decline the offer — the trade will not happen"},
	"modal.auction_timer":   {"ru": "%dс", "en": "%ds"},
	"modal.auction_no_timer": {"ru": "без ограничения времени", "en": "no time limit"},
	"board.auction_plate":   {"ru": "АУКЦИОН · %s", "en": "AUCTION · %s"},
	"board.auction_plate_bid": {"ru": "АУКЦИОН · %s · $%d · лидер %s", "en": "AUCTION · %s · $%d · %s leads"},
	"modal.auction_title":   {"ru": "АУКЦИОН", "en": "AUCTION"},
	"modal.lot_name":       {"ru": "Лот: «%s»", "en": "Lot: «%s»"},
	"modal.auction_high":   {"ru": "Текущая ставка: $%d", "en": "Current bid: $%d"},
	"modal.auction_none":   {"ru": "Ставок ещё нет", "en": "No bids yet"},
	"modal.auction_leader": {"ru": "Лидирует: %s", "en": "Leading: %s"},
	"modal.auction_watch":  {"ru": "Наблюдение за торгами (ставки публичны)", "en": "Spectating the auction (bids are public)"},
	"modal.no_tiles":       {"ru": "нет тайлов", "en": "no tiles"},
	"modal.empty_offer":    {"ru": "Предложение недопустимо: выберите тайлы или укажите сумму", "en": "Offer is not valid: pick tiles or enter an amount"},
	"modal.bid_lbl":        {"ru": "Ставка $", "en": "Bid $"},
	"modal.bid_tip":        {"ru": "Ваша ставка. Должна быть выше текущей.", "en": "Your bid. Must be higher than the current one."},
	# pre-checked before the engine is even asked: the same refusal, one round trip earlier
	"modal.bid_too_low":    {"ru": "Ставка должна быть выше текущей ($%d)", "en": "The bid must exceed the current one ($%d)"},
	"modal.bid_no_funds":   {"ru": "Недостаточно денег для такой ставки", "en": "Not enough cash for that bid"},
	"modal.trade_no_funds": {"ru": "Недостаточно денег для этой сделки", "en": "Not enough cash for this trade"},
	"modal.trade_bad_recipient": {"ru": "Сначала выберите, кому предлагаете", "en": "Pick who the offer goes to first"},
	"modal.bid_btn":        {"ru": "СТАВКА", "en": "BID"},
	"modal.bid_btn_tip":    {"ru": "Сделать ставку на эту клетку", "en": "Place a bid on this tile"},
	"modal.pass_btn":       {"ru": "ПАСС", "en": "PASS"},
	"modal.pass_tip":       {"ru": "Выйти из аукциона — больше не участвуете в этом лоте", "en": "Leave the auction — you no longer participate in this lot"},
	"modal.msg_ok_tip":     {"ru": "Закрыть это сообщение", "en": "Close this message"},
	"modal.game_over":      {"ru": "ПАРТИЯ ОКОНЧЕНА", "en": "MATCH OVER"},
	"modal.winner":         {"ru": "Победитель: %s", "en": "Winner: %s"},
	"modal.stats":          {"ru": "Ходов: %d   ·   Игроков: %d   ·   Капитал: $%d", "en": "Turns: %d   ·   Players: %d   ·   Capital: $%d"},
	"modal.rematch":        {"ru": "РЕВАНШ", "en": "REMATCH"},
	"modal.rematch_tip":    {"ru": "Начать новую партию с теми же настройками", "en": "Start a new match with the same settings"},
	"modal.settings":       {"ru": "НАСТРОЙКИ", "en": "SETTINGS"},
	"modal.settings_tip":   {"ru": "Открыть настройки матча", "en": "Open match settings"},
	"modal.sound_title":    {"ru": "ЗВУК", "en": "SOUND"},
	"modal.sound_tip":      {"ru": "Включить/выключить звук: %s", "en": "Toggle sound: %s"},
	"modal.rules_btn":      {"ru": "ПРАВИЛА", "en": "RULES"},
	"modal.rules_tip":      {"ru": "Показать полные правила игры по текущим настройкам", "en": "Show full game rules for the current settings"},
	"modal.close_btn":      {"ru": "ЗАКРЫТЬ", "en": "CLOSE"},
	"modal.settings_panel_tip": {"ru": "Закрыть окно настроек", "en": "Close the settings window"},
	"modal.rules_back_tip": {"ru": "Вернуться к настройкам", "en": "Back to settings"},
	"modal.banner_action_tip": {"ru": "Действие баннера", "en": "Banner action"},

	# ---- toast ----
	"toast.dismiss_tip":    {"ru": "Закрыть", "en": "Close"},

	# ---- turn panno (brief §4.1: the ring's centre carries the turn, not decoration) ----
	# The four zone captions are WORDS (R-9: no glyphs, no abbreviations a player must guess).
	"panno.roll":    {"ru": "БРОСОК", "en": "ROLL"},
	# B1 «кольцо во весь кадр»: the four corners are SCREENS carrying the glance layer (R-7). Each
	# line is one fact at a time, words first, and the frame takes the value: a corner is 320x190 and
	# a 50px line is 12.19px when the same frame is seen 390 wide.
	"glance.turn":   {"ru": "ХОД: %s", "en": "TURN: %s"},
	"glance.phase":  {"ru": "ФАЗА:
%s", "en": "PHASE:
%s"},
	"glance.bank":   {"ru": "БАНК %s", "en": "BANK %s"},
	"glance.round":  {"ru": "РАУНД %s", "en": "ROUND %s"},
	"panno.event":   {"ru": "СОБЫТИЕ", "en": "EVENT"},
	"panno.players": {"ru": "ИГРОКИ", "en": "PLAYERS"},
	"panno.journal": {"ru": "ЖУРНАЛ", "en": "LOG"},
	# One row of the panno's player zone: cash is a separate value, this is what they own.
	"panno.owns":    {"ru": "владений %d · домов %d", "en": "owns %d · houses %d"},
	# The journal zone is 169 px tall: with an empty tail it would be a caption over a hole (R-3
	# measured it: 1 line). These two sentences are TRUE at match start - they are the zone's own
	# explanation, and the first real event replaces them.
	"panno.jrn_start": {"ru": "Партия начата · все на старте", "en": "Match started · everyone at GO"},
	"panno.jrn_hint":  {"ru": "Бросок открывает ход", "en": "A roll opens the turn"},
}
