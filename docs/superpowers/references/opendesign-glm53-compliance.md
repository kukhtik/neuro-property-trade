# Соответствие прототипа glm53 требованиям (game-concept-spec)

Прототип `npt-glm53-uiux-0004/game-board.html` — это **UI/UX-эталон и визуальный
референс**, НЕ полная реализация движка. Ниже — сверка его настроек с 5 блоками
`docs/specs/game-concept-spec.md`. Прототип покрывает большинство настроек, но
часть блоков упрощена/отсутствует — это ожидаемо для прототипа и НЕ является
дефектом переноса (в Godot реализуется полная схема).

## Block 1 — Seats & composition
| Спека | Прототип | Статус |
|---|---|---|
| seat_count 2–8 | 2–8 (add/remove, max 8) | ✅ |
| seat_assignments LOCAL/CHAT/REMOTE/sdk:neuro/sdk:evil | LOCAL, AI, CHAT, sdk:neuro, sdk:evil | ✅ (REMOTE — post-MVP, в спеке тоже) |
| per-seat name/token_color/token_id | name, token, color | ✅ |
| starting_order random/manual/arrival | random/manual | ⚠️ нет `arrival` |

## Block 2 — Base economy
| Спека | Прототип | Статус |
|---|---|---|
| starting_cash 1000–5000 | capital (number) | ✅ |
| go_bonus on/off/amount | goBonus (number) | ✅ |
| jail_rule 3turns-pay / 3turns-or-doubles / both | jailRule select (both/fine/card) | ✅ |
| free_parking off/on | parking switch | ✅ |
| doubles on/off | doubles switch | ✅ |
| triple_doubles_to_jail | dblJail switch | ✅ |
| bankruptcy normal/transfer-to-creditor | — | ❌ отсутствует |

## Block 3 — Property ops
| Спека | Прототип | Статус |
|---|---|---|
| auctions_on_refusal | auctions switch | ✅ |
| auction_condition | — | ❌ отсутствует |
| housing | housing switch | ✅ |
| even_build | evenBuild switch | ✅ |
| monopoly_rent_x2 | monopolyX2 switch | ✅ |
| mortgage | mortgage switch | ✅ |
| mortgage_loan_pct / repay_pct | mortgagePct / repayPct | ✅ |
| trades | trades switch | ✅ |
| trade_window | — | ❌ отсутствует |
| trade_cash_limit | — | ❌ отсутствует |

## Block 4 — Decks & theme
| Спека | Прототип | Статус |
|---|---|---|
| deck_pairs (2 decks, 16–30 cards) | — (Chance/Community захардкожены) | ❌ |
| theme_preset classic/neon/space/custom | — (только density в UI) | ❌ |
| deck_shuffle per-round/per-game | — | ❌ |
| card_effects predefined set | — (захардкожены) | ❌ |

## Block 5 — Tempo, stream, AI
| Спека | Прототип | Статус |
|---|---|---|
| turn_timer off/15/30/60 | turnTimer (0/15/30/60/120) | ✅ |
| auction_timer off/10/20 | auctionTimer (10/15/30/60) | ✅ |
| timeout_action auto-pass/mark-away | timeout (auto/away) | ✅ |
| chat_mode majority/first/mod-weight | — | ❌ отсутствует |
| ai_aggression 0–100 | aiAggr slider | ✅ |
| evil_enabled on/off | sdk:evil как драйвер (не отдельный тумблер) | ⚠️ |
| rng_seed manual/random | seed (0 = random) | ✅ |
| spectacle on/off | cinema switch | ✅ |
| event_overlay on/off | journOverlay switch | ✅ |

## Дополнительно в прототипе (сверх спеки)
- `tilesCount` 16–64 (кратно 4) — параметрическая доска (совпадает с P6 Godot)
- `density` normal/compact — тема плотности
- пресеты Классика/Быстрая/Хардкор
- `lang` RU/EN мгновенно

## Итог
Прототип покрывает **~70%** настроек спеки. Отсутствуют: `bankruptcy` mode,
`auction_condition`, `trade_window`, `trade_cash_limit`, весь Block 4 (decks/theme),
`chat_mode`. Это ожидаемо — прототип это визуальный эталон, а не движок.
В Godot реализуется полная схема из спеки (см. `docs/specs/game-concept-spec.md`),
прототип используется только как ориентир по цветам/пропорциям/структуре окон.
