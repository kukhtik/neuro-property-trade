/* ============================================================================
   NPT UI v3 — "Broadcast Table" prototype logic (proto.js)
   ----------------------------------------------------------------------------
   The prototype is DATA-DRIVEN and DERIVED, never hand-typed:
     · board tiles, costs, groups      ← game/data/board.json        (data.js)
     · every string                     ← game/i18n/data_*.gd        (data.js)
     · palettes, sizes, motion         ← game/assets/skins/*.json    (built CSS)
   New UI strings the design needs that the game does not ship yet live in
   design/strings_proposed.json (NPT_PROPOSED) and are listed in coverage.md.

   Interactive scenes: each entry of SCENES is a demo snapshot; buttons inside
   the console/modals then walk the demo forward (roll → move → purchase →
   auction, trades, building, jail …). The probe strip is scaffolding — it is
   NOT part of the design and is excluded from the text-role audit.
   ========================================================================= */
(function () {
  "use strict";

  var D = window.NPT_DATA || { board: { tiles: [] }, i18n: {}, skins: {} };
  var PROP = window.NPT_PROPOSED || {};
  var TILES = D.board.tiles || [];
  var N = TILES.length || 40;
  var TOKENS = ["top_hat", "cat", "ship", "race_car", "dog", "boot", "iron", "wheelbarrow"];
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  /* ------------------------------------------------------------------ i18n */
  function dict(key) {
    return D.i18n[key] || PROP[key] || null;
  }
  function t(key, params) {
    var e = dict(key);
    if (!e) return "{%" + key + "%}";           /* the game's own sentinel */
    var s = e[state.locale] || e.ru || key;
    if (params == null) return s;
    if (Array.isArray(params)) {
      var i = 0;
      s = s.replace(/%(?:0(\d))?([sd])/g, function (_, w, kind) {
        var v = params[i++];
        if (v == null) return kind === "d" ? "0" : "";
        v = String(v);
        if (w) while (v.length < +w) v = "0" + v;
        return v;
      });
    } else {
      Object.keys(params).forEach(function (k) {
        s = s.split("{{" + k + "}}").join(String(params[k]));
      });
    }
    return s;
  }
  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : "&quot;";
    });
  }
  var money = function (n) { return "$" + n; };

  /* ----------------------------------------------------------------- state */
  var state = {
    locale: "ru", theme: "neuro", profile: "desktop", anim: true, observer: false,
    scene: "turn-human", drawer: "", sound: true, modal: null, overlay: null,
    settingsTab: "players", adminTab: "quick", joinState: "connecting",
    round: 7, pot: 240, turn: 1, step: 0,
    timer: 12, timerMax: 30,
    dice: { d1: 5, d2: 3, doubles: false, rolled: true, third: false },
    set: {
      starting_cash: 1500, go_bonus: 200, jail_rule: "both", jail_fine: 50,
      free_parking: true, doubles: true, triple_doubles_to_jail: true,
      auctions_on_refusal: true, housing: true, even_build: true,
      monopoly_rent_x2: true, mortgage: true, mortgage_loan_pct: 50,
      mortgage_repay_pct: 110, trades: true, round_limit: 0,
      turn_timer: 30, auction_timer: 15, timeout_action: "auto-pass",
      ai_aggression: 50, rng_seed: 0, tile_count: 40, sound: true,
      animations: true, spectacle: false, event_overlay: true,
      starting_order: "random", host_playing: true,
    },
    seats: [
      { id: 0, name: "Host", driver: "LOCAL", token: "top_hat", color: 0, money: 1215, pos: 6, jail: 0, attempts: 0, bankrupt: false, away: false, tiles: 2, houses: 0, mortgaged: 0, card: false, persona: null },
      { id: 1, name: "Neuro", driver: "sdk_neuro", token: "cat", color: 2, money: 980, pos: 24, jail: 0, attempts: 0, bankrupt: false, away: false, tiles: 3, houses: 1, mortgaged: 0, card: false, persona: null },
      { id: 2, name: "evil", driver: "sdk_evil", token: "ship", color: 1, money: 640, pos: 10, jail: 1, attempts: 2, bankrupt: false, away: false, tiles: 1, houses: 0, mortgaged: 0, card: false, persona: null },
      { id: 3, name: "Mira", driver: "AI", token: "race_car", color: 3, money: 1500, pos: 33, jail: 0, attempts: 0, bankrupt: false, away: false, tiles: 2, houses: 0, mortgaged: 1, card: false, persona: "tycoon" },
    ],
    owners: { 3: 0, 6: 0, 8: 1, 9: 1, 11: 2, 26: 3, 27: 3, 37: 1 },
    houses: { 3: 1, 8: 2, 27: 1 },
    mortgage: { 26: true, 11: true },
    log: [],
    adminLog: [],
    toast: [],
    insTile: 6, insPinned: true,
    selTile: 6,
    auction: { tile: 6, bid: 180, leader: 2, bids: [140, 160, 180], mine: true, timer: 8 },
    trade: { to: 1, giveCash: 150, wantCash: 0, giveTiles: [3], wantTiles: [] },
    lastRollLine: "",
    followed: null,
  };

  function seat(i) { return state.seats[i]; }
  function colorVar(s) { return "var(--p" + (s.color % 8) + ")"; }
  function tileOf(i) { return TILES[i] || { name: "?", short: "?", type: "property" }; }
  function tileName(i) { return tileOf(i).name; }

  /* ------------------------------------------------------------------ log */
  var clock = 0;
  function addLog(kind, p, params) {
    clock += 1;
    state.log.push({ kind: kind, p: p, params: params || [], tm: clock, cats: CATS[kind] || ["other"] });
  }
  var CATS = {
    roll: ["roll"], buy: ["buy", "money"], pass: ["buy"], rent: ["money"], tax: ["money"],
    pay: ["money"], go: ["money"], build: ["build", "money"], sell: ["build", "money"],
    mort: ["build", "money"], unmort: ["build", "money"], card: ["card"], jail: ["other"],
    aucstart: ["auction"], bid: ["auction"], aucwin: ["auction"], trade: ["trade"],
    trdoffer: ["trade"], trdno: ["trade"], over: ["other"], bank: ["money"],
    start: ["other"], admin: ["other"], park: ["money"],
  };
  /* kind → [i18n key, params(seat idx, ...)] — every fragment is a real key */
  function lineFor(e) {
    var p = e.p, name = p == null ? "" : seat(p).name;
    switch (e.kind) {
      case "roll": return { txt: t("event.roll", [name, e.params[0], e.params[1]]), tag: "event_type.roll" };
      case "buy": return { txt: t("toast.purchase", [name, tileName(e.params[0]), e.params[1]]), tag: "event_type.buy" };
      case "pass": return { txt: t("toast.pass", [name, tileName(e.params[0])]), tag: "event_type.pass_on_purchase" };
      case "rent": return { txt: t("event.pay", [name, e.params[0]]), tag: "event_type.rent" };
      case "tax": return { txt: t("event.pay", [name, e.params[0]]), tag: "event_type.tax" };
      case "pay": return { txt: t("event.pay", [name, e.params[0]]), tag: "event_type.pay" };
      case "go": return { txt: t("toast.go_bonus", [name]), tag: "event_type.go" };
      case "build": return { txt: t("toast.build", [name, tileName(e.params[0])]), tag: "event_type.build" };
      case "sell": return { txt: t("toast.sell", [name, tileName(e.params[0])]), tag: "event_type.sell" };
      case "mort": return { txt: t("toast.mortgage", [name, tileName(e.params[0])]), tag: "event_type.mort" };
      case "unmort": return { txt: name + " · " + t("event_type.unmort") + " · «" + tileName(e.params[0]) + "»", tag: "event_type.unmort" };
      case "card": return { txt: t("event.card_draw", [name]), tag: "event_type.card" };
      case "jail": return { txt: t("toast.jail", [name]), tag: "event_type.jail" };
      case "aucstart": return { txt: t("toast.auction_start", [tileName(e.params[0])]), tag: "event_type.aucstart" };
      case "bid": return { txt: name + " · " + t("modal.bid_lbl") + e.params[0], tag: "event_type.bid" };
      case "aucwin": return { txt: t("toast.auction_win", [name, tileName(e.params[0])]), tag: "event_type.aucwin" };
      case "trade": return { txt: t("event.trade"), tag: "event_type.trade" };
      case "trdoffer": return { txt: t("modal.trade_offers", [name, seat(e.params[0]).name]), tag: "event_type.trdoffer" };
      case "trdno": return { txt: name + " · " + t("event_type.trdno"), tag: "event_type.trdno" };
      case "bank": return { txt: t("toast.bankrupt", [name]), tag: "event_type.bank" };
      case "over": return { txt: t("event.winner", [name]), tag: "event_type.over" };
      case "start": return { txt: t("event_type.start") + " — " + t("top.title"), tag: "event_type.start" };
      case "admin": return { txt: t("toast.admin_override", [e.params[0]]), tag: "event_type.admin_override" };
      default: return { txt: name, tag: "event_type." + e.kind };
    }
  }
  function seedLog() {
    addLog("start", null, []);
    addLog("roll", 0, [4, 2]); addLog("buy", 0, [3, 60]);
    addLog("roll", 1, [3, 3]); addLog("buy", 1, [8, 100]);
    addLog("roll", 2, [6, 1]); addLog("rent", 2, [14]);
    addLog("roll", 3, [2, 4]); addLog("buy", 3, [26, 260]);
    addLog("go", 0, []);
    addLog("roll", 1, [5, 4]); addLog("rent", 1, [22]);
    addLog("card", 2, []); addLog("tax", 2, [200]);
    addLog("roll", 3, [1, 1]); addLog("build", 3, [27]);
    addLog("aucstart", null, [6]);
    addLog("bid", 0, [140]); addLog("bid", 1, [160]); addLog("bid", 2, [180]);
    addLog("aucwin", 1, [6]);
    addLog("trdoffer", 3, [1]); addLog("trdno", 1, []); addLog("trade", 3, []);
    addLog("roll", 0, [3, 5]); addLog("mort", 2, [11]);
    addLog("jail", 2, []);
    addLog("roll", 1, [2, 3]); addLog("rent", 1, [18]);
    addLog("roll", 3, [4, 4]); addLog("sell", 3, [27]);
  }

  /* ---------------------------------------------------------------- colours */
  function themeVars() { return getComputedStyle(app); }

  /* ------------------------------------------------------------------ toast */
  var toastQueue = [];
  function pushToast(kind, html, automs) {
    state.toast.push({ kind: kind, html: html, at: Date.now() });
    if (state.toast.length > 3) state.toast.shift();
    renderToast();
    setTimeout(function () {
      state.toast = state.toast.filter(function (x) { return Date.now() - x.at < (automs || 4600); });
      renderToast();
    }, automs || 4600);
  }
  function renderToast() {
    var host = $("#toast");
    host.innerHTML = "";
    state.toast.slice(-3).forEach(function (to) {
      var el = document.createElement("div");
      el.className = "toast toast--" + to.kind;
      el.innerHTML =
        '<span class="toast__bar"></span>' +
        '<span class="toast__body"><span class="toast__text t-para">' + to.html + "</span></span>" +
        '<button class="toast__x" data-i18n-tip="toast.dismiss_tip" aria-label="close"><svg width="12" height="12"><use href="#ui-x"/></svg></button>';
      el.querySelector(".toast__x").addEventListener("click", function () {
        state.toast = state.toast.filter(function (x) { return x !== to; });
        renderToast();
      });
      host.appendChild(el);
    });
    /* compact: the newest toast becomes the console ticker (never over board) */
    var tk = $("#ticker");
    if (state.toast.length && state.profile === "compact") {
      tk.classList.add("on");
      tk.style.setProperty("--tc", "var(--tc-" + state.toast[state.toast.length - 1].kind + ")");
      $("#tickerText").innerHTML = state.toast[state.toast.length - 1].html;
      $("#tickerMore").textContent = state.toast.length > 1 ? "+" + (state.toast.length - 1) : "";
    } else {
      tk.classList.remove("on");
    }
  }

  /* ------------------------------------------------------------- board/tiles */
  function tileSide(i) {
    if (i <= 10) return { side: "b", col: 10 - i, row: 10 };
    if (i <= 20) return { side: "l", col: 0, row: 10 - (i - 10) };
    if (i <= 30) return { side: "t", col: i - 20, row: 0 };
    return { side: "r", col: 10, row: i - 30 };
  }
  function iconFor(tp) {
    if (tp === "go") return "go_arrow";
    if (tp === "jail") return "jail";
    if (tp === "go_to_jail") return "go_to_jail";
    if (tp === "free_parking") return "free_parking";
    if (tp === "tax") return "tax";
    if (tp === "railroad") return "railroad";
    if (tp === "utility") return "utility";
    if (tp === "chance") return "chance";
    if (tp === "community") return "community_chest";
    return null;
  }
  function renderBoard() {
    var board = $("#board");
    $$(".tile", board).forEach(function (n) { n.remove(); });
    TILES.forEach(function (tile, i) {
      var pos = tileSide(i);
      var el = document.createElement("div");
      el.className = "tile";
      el.dataset.i = i;
      el.dataset.side = pos.side;
      el.dataset.type = tile.type;
      el.style.left = (pos.col * 100 / 11) + "%";
      el.style.top = (pos.row * 100 / 11) + "%";
      var owner = state.owners[i];
      var hs = state.houses[i] || 0;
      var mort = !!state.mortgage[i];
      var icon = iconFor(tile.type);
      var inner = "";
      if (tile.group) { el.style.setProperty("--band", "var(--g-" + tile.group + ")"); }
      if (icon) inner += '<svg class="tile__icon" width="46%" height="46%" viewBox="0 0 32 32"><use href="#as-' + icon + '"/></svg>';
      inner += '<span class="tile__name t-para">' + esc(tile.short || tile.name) + "</span>";
      if (tile.cost) inner += '<span class="tile__price num t-value">' + money(tile.cost) + "</span>";
      if (hs > 0) {
        inner += '<span class="tile__houses t-value' + (hs === 5 ? " hotel" : "") + '" data-i18n-tip="stat.houses">';
        for (var k = 0; k < Math.min(hs, 4); k++) inner += "<i></i>";
        if (hs === 5) inner += "<i></i>";
        inner += "</span>";
      }
      if (owner != null) {
        el.classList.add("owned");
        el.style.setProperty("--oc", colorVar(seat(owner)));
        inner += '<span class="tile__owner t-value" title="">' + esc(seat(owner).name[0]) + "</span>";
      }
      if (mort) el.classList.add("mortgaged");
      if (i === state.selTile) el.classList.add("sel");
      var band = tile.group ? '<span class="tile__band"></span>' : "";
      el.innerHTML = band + '<span class="tile__in">' + inner + "</span>";
      el.addEventListener("click", function () {
        state.selTile = i; state.insTile = i; state.insPinned = true; renderBoard(); renderInspector();
      });
      board.insertBefore(el, $("#center"));
    });
    var cell = board.clientWidth / 11;
    board.classList.toggle("compact-cells", cell < 44);
    $$(".tile", board).forEach(function (n) { n.classList.toggle("tile--compact", cell < 44); });
    renderTokens();
  }
  function renderTokens() {
    var board = $("#board");
    $$(".token", board).forEach(function (n) { n.remove(); });
    var byTile = {};
    state.seats.forEach(function (s) { if (!s.bankrupt) (byTile[s.pos] = byTile[s.pos] || []).push(s); });
    Object.keys(byTile).forEach(function (ti) {
      var arr = byTile[ti], pos = tileSide(+ti);
      arr.forEach(function (s, j) {
        var ang = arr.length > 1 ? (-60 + 120 * (j / (arr.length - 1))) * Math.PI / 180 : 0;
        var r = arr.length > 1 ? 2.9 : 0;
        var cx = (pos.col + 0.5) * 100 / 11 + r * Math.cos(ang);
        var cy = (pos.row + 0.5) * 100 / 11 + r * Math.sin(ang);
        var el = document.createElement("div");
        el.className = "token" + (s.jail ? " injail" : "");
        el.dataset.seat = s.id;
        el.style.left = cx + "%";
        el.style.top = cy + "%";
        el.style.setProperty("--pc", colorVar(s));
        el.innerHTML = '<span class="halo2"></span><svg viewBox="0 0 64 64"><use href="#as-' + s.token + '"/></svg>';
        board.appendChild(el);
      });
    });
  }

  /* ----------------------------------------------------------------- centre */
  function renderCenter() {
    var c = $("#center");
    var scn = state.scene;
    var html = "";
    if (scn === "cold") {
      html = '<div class="watermark"><span class="wm1 t-value">NEURO<br>PROPERTY TRADE</span><span class="wm2 t-value">' + esc(t("top.cold")) + "</span></div>";
    } else if (scn === "purchase" || scn === "trade-in" || scn === "auction" || scn === "auction-watch") {
      var tile = scn.indexOf("auction") === 0 ? state.auction.tile : state.selTile;
      var who = scn.indexOf("auction") === 0 ? state.auction.leader : state.turn;
      html =
        '<div class="dcard ch-sm">' +
        '<span class="nm t-value">' + esc(tileName(tile)) + "</span>" +
        '<span class="pr num t-value">' + money(tileOf(tile).cost || 0) + "</span>" +
        '<span class="who t-value"><span class="halo3"></span>' +
        esc(t("act.observer_status", [t(scn.indexOf("auction") === 0 ? "phase.AUCTION" : "phase.PURCHASE_WAIT"), seat(who).name, "", ""])) +
        "</span></div>";
    } else if (scn === "move" || scn === "turn-human" || scn === "jail") {
      html = diceHTML();
    } else if (scn === "ai" || scn === "neuro") {
      html = diceHTML() + '<div class="dcard ch-sm t-value">' + esc(t("act.ai_status", [seat(state.turn).name])) + "</div>";
    } else if (scn === "win") {
      html = '<div class="banner banner--ok t-value">' + esc(t("toast.winner", [seat(1).name])) + "</div>";
    } else if (scn === "toasts" || scn === "reject") {
      html = diceHTML();
    } else {
      html = '<div class="watermark"><span class="wm1 t-value">NEURO<br>PROPERTY TRADE</span><span class="wm2 t-value">' + esc(t("top.title").replace("● ", "")) + "</span></div>";
    }
    if (scn === "purchase") {
      html = '<div class="banner t-value">' + esc(t("toast.purchase", [seat(state.turn).name, tileName(state.selTile), tileOf(state.selTile).cost])) + "</div>" + html;
    }
    if (scn === "auction" || scn === "auction-watch") {
      html = '<div class="banner t-value">' + esc(t("toast.auction_start", [tileName(state.auction.tile)])) + "</div>" + html;
    }
    if (scn === "jail") {
      html = '<div class="banner banner--danger t-value">' + esc(t("toast.jail", [seat(2).name])) + "</div>" + html;
    }
    if (scn === "move" || scn === "turn-human" || scn === "jail" || scn === "ai" || scn === "neuro") {
      /* last-roll line stays after the animation (F-30) */
    }
    c.innerHTML = html;
    if ($(".dicetray")) {
      $(".dicetray").classList.toggle("rolling", !!state.rolling);
    }
  }
  function diceHTML() {
    var d = state.dice;
    var s = '<div class="dicetray">';
    s += '<svg class="die" width="' + Math.round(state.boardPx ? state.boardPx / 11 * 0.62 : 40) + '" height="' + Math.round(state.boardPx ? state.boardPx / 11 * 0.62 : 40) + '" viewBox="0 0 64 64"><use href="#as-die_' + d.d1 + '"/></svg>';
    s += '<svg class="die" width="' + Math.round(state.boardPx ? state.boardPx / 11 * 0.62 : 40) + '" height="' + Math.round(state.boardPx ? state.boardPx / 11 * 0.62 : 40) + '" viewBox="0 0 64 64"><use href="#as-die_' + d.d2 + '"/></svg>';
    if (d.rolled) s += '<span class="dice-sum t-value">' + (d.d1 + d.d2) + "</span>";
    if (d.doubles) s += '<span class="dbl t-value" data-i18n="die.doubles">' + esc(t("die.doubles")) + "</span>";
    if (d.third) s += '<span class="dbl tojail t-value">→ ' + esc(t("phase.JAIL_DECISION")) + "</span>";
    s += "</div>";
    return s;
  }

  /* ---------------------------------------------------------------- seats */
  function seatCard(s, compactMode) {
    var active = s.id === state.turn && state.scene !== "cold" && state.scene !== "win";
    var cls = "pcard" + (active ? " active" : "") + (s.bankrupt ? " bankrupt" : "") + (s.away ? " away" : "");
    var pos = tileName(s.pos);
    var chips = "";
    chips += '<span class="chip t-value" data-i18n-tip="stat.houses"><svg width="9" height="9"><use href="#as-house"/></svg>' + s.houses + "</span>";
    if (s.mortgaged) chips += '<span class="chip t-value" data-i18n-tip="stat.mortgaged">⚖ ' + s.mortgaged + "</span>";
    if (s.jail) chips += '<span class="chip chip--jail t-value" data-i18n-tip="plr.jail_tip">×' + s.attempts + "</span>";
    if (s.away) chips += '<span class="chip t-value">' + esc(t("plr.auto_pass")) + "</span>";
    if (s.card) chips += '<span class="chip t-value" data-i18n-tip="act.use_card">🔑</span>';
    if (active) chips += '<span class="chip t-value" data-i18n="plr.active"></span>';
    if (s.bankrupt) chips += '<span class="chip t-value" data-i18n="plr.bankrupt"></span>';
    return '<div class="' + cls + '" data-seat="' + s.id + '" data-i18n-tip="plr.tooltip">' +
      '<span class="pcard__av" style="--pc:' + colorVar(s) + '"><span class="halo"></span><svg viewBox="0 0 64 64"><use href="#as-' + s.token + '"/></svg></span>' +
      '<span class="pcard__name t-value">' + esc(s.name) + "</span>" +
      '<span class="pcard__money num t-value">' + money(s.money) + "</span>" +
      '<span class="pcard__pos t-value">' + esc(t("plr.pos_tiles", [pos, s.tiles])) + "</span>" +
      '<span class="pcard__chips">' + chips + "</span>" +
      "</div>";
  }
  function renderSeats() {
    var count = state.seats.filter(function (s) { return !s.bankrupt; }).length;
    $("#seatsCount").textContent = count;
    var html = state.scene === "cold"
      ? '<div class="emptynote"><span class="caps t-value" data-i18n="plr.cold">' + esc(t("plr.cold")) + '</span><span class="t-para" data-i18n="act.start_tip">' + esc(t("act.start_tip")) + "</span></div>"
      : state.seats.map(function (s) { return seatCard(s); }).join("");
    $("#seatsList").innerHTML = html;
    $("#drawerSeatsList").innerHTML = html;
    $("#seatsList").querySelectorAll(".pcard").forEach(bindSeatClick);
    $("#drawerSeatsList").querySelectorAll(".pcard").forEach(bindSeatClick);

    var hs = 0, ht = 0, mt = 0;
    Object.keys(state.houses).forEach(function (k) { if (state.houses[k] === 5) ht++; else hs += state.houses[k]; });
    mt = Object.keys(state.mortgage).length;
    var stat = function (k, v) {
      return '<div class="statcell"><div class="v num t-value">' + v + '</div><div class="k t-value" data-i18n="' + k + '">' + esc(t(k)) + "</div></div>";
    };
    var sh = stat("stat.houses", hs) + stat("stat.hotels", ht) + stat("stat.mortgaged", mt);
    $("#seatsStats").innerHTML = sh;
    $("#drawerSeatsStats").innerHTML = sh;

    var owned = Object.keys(state.owners).length;
    var segs = state.seats.map(function (s) {
      var c = Object.keys(state.owners).filter(function (k) { return state.owners[k] === s.id; }).length;
      return c ? '<i style="width:' + (c / N * 100) + "%;background:" + colorVar(s) + '"></i>' : "";
    }).join("");
    $("#seatsOwn").innerHTML =
      '<div class="ownbar__track">' + segs + "</div>" +
      '<div class="ownbar__legend t-value" data-i18n-tip="plr.owned_tip"><span data-i18n="plr.owned">' + esc(t("plr.owned")) + "</span>" +
      '<span class="num">' + owned + "/" + N + "</span></div>";
  }
  function bindSeatClick(n) {
    n.addEventListener("click", function () {
      var id = +n.dataset.seat;
      state.followed = state.followed === id ? null : id;
      state.selTile = seat(id).pos; state.insTile = state.selTile;
      renderBoard(); renderInspector();
      pushToast("ok", t("gv.select_tile") + " «" + esc(tileName(state.selTile)) + "»");
    });
  }

  /* ----------------------------------------------------------------- journal */
  function renderJournalList(host) {
    var flP = $("#flPlayer").value, flT = $("#flType").value, flM = $("#flMoney").checked;
    var rows = state.log.filter(function (e) {
      if (flP !== "" && String(e.p) !== flP) return false;
      if (flT !== "" && e.cats.indexOf(flT) < 0) return false;
      if (flM && e.cats.indexOf("money") < 0) return false;
      return true;
    });
    var html = "";
    rows.slice(-120).forEach(function (e) {
      var L = lineFor(e);
      var who = e.p == null ? "" : '<span class="jrow__who" style="color:' + colorVar(seat(e.p)) + '">' + esc(seat(e.p).name) + "</span>";
      var txt = esc(L.txt);
      /* the name is already inside the template — colour its first occurrence */
      if (e.p != null) {
        var re = new RegExp(esc(seat(e.p).name).replace(/[-\/\\^$*+?.()|[\]{}]/g, "\\$&"));
        txt = txt.replace(re, who);
      }
      html += '<div class="jrow' + (e.cats.indexOf("money") >= 0 ? " jrow--money" : "") + '">' +
        '<span class="jrow__t num t-value">' + timeOf(e.tm) + "</span>" +
        '<span class="jrow__body"><span class="jrow__who"></span><span class="jrow__text t-para">' + txt + "</span></span>" +
        '<span class="jrow__tag t-value" data-i18n="' + L.tag + '">' + esc(t(L.tag)) + "</span></div>";
    });
    if (!rows.length) {
      html = '<div class="jrn-empty"><span class="caps t-value" data-i18n="jrn.empty_title">' + esc(t("jrn.empty_title")) + "</span>" +
        '<span class="t-para" data-i18n="jrn.empty_body">' + esc(t("jrn.empty_body")) + "</span></div>";
    }
    host.innerHTML = html;
    host.scrollTop = host.scrollHeight;
    $("#jrnCount").textContent = rows.length + "/" + state.log.length;
  }
  function timeOf(m) {
    var h = 12 + Math.floor((4 + m) / 60), mm = (4 + m) % 60;
    return h + ":" + (mm < 10 ? "0" + mm : mm);
  }
  function renderJournal() {
    renderJournalList($("#jrnList"));
    renderJournalList($("#drawerJrnList"));
  }

  /* --------------------------------------------------------------- inspector */
  function renderInspector() {
    var i = state.insTile, tile = tileOf(i), owner = state.owners[i];
    var b = $("#insBody");
    if (i == null) {
      b.innerHTML = '<div class="ins-empty t-para" data-i18n="ins.placeholder">' + esc(t("ins.placeholder")) + "</div>";
      return;
    }
    var hs = state.houses[i] || 0, mort = !!state.mortgage[i];
    var flags = "";
    if (hs) flags += '<span class="chip t-value">' + esc(t("ins.house", [hs === 5 ? t("ins.hotel") : hs])) + "</span>";
    if (mort) flags += '<span class="chip t-value" data-i18n="ins.mortgaged">' + esc(t("ins.mortgaged")) + "</span>";
    var ownerRow = owner == null
      ? '<span class="t-value" data-i18n="ins.free">' + esc(t("ins.free")) + "</span>"
      : '<span class="t-value"><span data-i18n="ins.owner">' + esc(t("ins.owner")) + "</span><b style='color:" + colorVar(seat(owner)) + "'>" + esc(seat(owner).name) + "</b></span>";
    var acts = '<div class="ins-acts">' +
      '<button class="btn t-value" data-i18n="act.build" data-i18n-tip="act.build_tip" ' + (owner === 0 ? "" : "disabled") + ">" + esc(t("act.build")) + "</button>" +
      '<button class="btn t-value" data-i18n="act.sell" data-i18n-tip="act.sell_tip" ' + (owner === 0 && hs > 0 ? "" : "disabled") + ">" + esc(t("act.sell")) + "</button>" +
      '<button class="btn t-value" data-i18n="act.mortgage" data-i18n-tip="act.mortgage_tip" ' + (owner === 0 && !mort ? "" : "disabled") + ">" + esc(t("act.mortgage")) + "</button>" +
      '<button class="btn t-value" data-i18n="act.unmortgage" data-i18n-tip="act.unmortgage_tip" ' + (owner === 0 && mort ? "" : "disabled") + ">" + esc(t("act.unmortgage")) + "</button>" +
      "</div>";
    var rent = tile.rent_set || tile.rent || tile.rent_1 || 0;
    b.innerHTML =
      '<div class="ins-name"><span class="n t-value">' + esc(tile.name) + "</span>" +
      '<span class="ins-type"><span class="ins-band" style="--band:var(--g-' + (tile.group || "brown") + ')"></span>' +
      '<span class="mut t-value">' + esc(tile.group ? tile.group : (tile.type || "")) + "</span></span></div>" +
      '<div class="ins-rows">' +
      (tile.cost ? '<span class="r"><span class="k t-value" data-i18n="ins.price">' + esc(t("ins.price")) + ':</span><span class="v num t-value">' + money(tile.cost) + "</span></span>" : "") +
      (rent ? '<span class="r"><span class="k t-value" data-i18n="ins.rent">' + esc(t("ins.rent")) + ':</span><span class="v num t-value">' + money(rent) + "</span></span>" : "") +
      '<span class="r"><span class="k t-value" data-i18n="ins.owner">' + esc(t("ins.owner")) + "</span>" + ownerRow + "</span>" +
      "</div>" +
      '<div class="ins-flags">' + flags + "</div>" + acts;
    b.querySelectorAll(".btn").forEach(function (btn, ix) {
      btn.addEventListener("click", function () {
        if (ix === 0) { state.houses[i] = Math.min(5, (state.houses[i] || 0) + 1); addLog("build", 0, [i]); pushToast("ok", t("toast.build", [seat(0).name, tileName(i)])); }
        if (ix === 1) { state.houses[i] = Math.max(0, (state.houses[i] || 0) - 1); addLog("sell", 0, [i]); pushToast("warn", t("toast.sell", [seat(0).name, tileName(i)])); }
        if (ix === 2) { state.mortgage[i] = true; addLog("mort", 0, [i]); pushToast("warn", t("toast.mortgage", [seat(0).name, tileName(i)])); }
        if (ix === 3) { delete state.mortgage[i]; addLog("unmort", 0, [i]); pushToast("ok", seat(0).name + " · " + t("event_type.unmort") + " · «" + tileName(i) + "»"); }
        renderBoard(); renderInspector(); renderJournal(); renderSeats();
      });
    });
  }

  /* ------------------------------------------------------------- header etc. */
  function renderHeader() {
    var s = seat(state.turn);
    var cold = state.scene === "cold";
    $("#turnName").textContent = cold ? "—" : s.name;
    $("#turnName").style.color = cold ? "var(--mu)" : colorVar(s);
    $("#turnPhase").textContent = cold ? t("top.cold") : t("phase." + phaseKey());
    var steps = $$("#turnSteps i");
    steps.forEach(function (el, ix) { el.classList.toggle("on", ix <= state.step); });
    $("#hdrRound").textContent = state.round;
    $("#hdrRoundWrap").style.display = state.set.round_limit ? "" : "";
    $("#hdrPotWrap").style.display = state.set.free_parking ? "" : "none";
    $("#hdrPot").textContent = money(state.pot);
    $("#roleBadge").textContent = state.scene === "admin" ? t("mode.admin") : t("mode.player");
    $("#turnAv").innerHTML = cold ? "" :
      '<span class="halo" style="--turn-c:' + colorVar(s) + '"></span><svg viewBox="0 0 64 64" style="color:' + colorVar(s) + '"><use href="#as-' + s.token + '"/></svg>';

    /* decision zone: timer only when a limit exists; SDK seat → waiting, not a countdown */
    var dz = $("#decision");
    dz.innerHTML = "";
    if (!cold) {
      if (state.scene === "neuro") {
        dz.innerHTML = '<span class="wait t-value"><span class="dots"><i></i><i></i><i></i></span>' +
          esc(t("act.observer_sdk").replace(/^ · /, "")) + "</span>";
      } else if (state.scene === "ai") {
        dz.innerHTML = '<span class="wait t-value">' + esc(t("plr.auto_pass")) + "</span>";
      } else if (state.set.turn_timer > 0 && ["turn-human", "purchase", "move", "auction", "auction-watch", "trade-in", "jail", "build"].indexOf(state.scene) >= 0) {
        var p = state.timer / state.timerMax;
        var col = p > 0.6 ? "var(--good)" : p > 0.3 ? "var(--warn)" : "var(--bad)";
        dz.innerHTML = '<span class="timerring" data-i18n-tip="act.timer_tip" style="--ring-p:' + p.toFixed(2) + ";--ring-c:" + col + '"><span class="num t-value">' + state.timer + "</span></span>";
      }
    }
  }
  function phaseKey() {
    var map = {
      cold: "SETUP", "turn-human": "TURN_START", move: "ROLL_RESOLVE", purchase: "PURCHASE_WAIT",
      auction: "AUCTION", "auction-watch": "AUCTION", "trade-in": "CARD_WAIT", build: "TURN_START",
      jail: "JAIL_DECISION", ai: "ROLL_RESOLVE", neuro: "ROLL_RESOLVE", reject: "TURN_START",
      win: "END_GAME", observer: "TURN_START", compact: "TURN_START", toasts: "TURN_START", empty: "SETUP",
    };
    return map[state.scene] || "TURN_START";
  }

  /* --------------------------------------------------------------- console */
  function promptFor() {
    var s = seat(state.turn);
    switch (state.scene) {
      case "cold": return t("act.cold_status");
      case "purchase": return t("act.hint_purchase", [tileName(state.selTile), tileOf(state.selTile).cost]);
      case "auction": return t("act.hint_auction", [state.auction.bid]);
      case "auction-watch": return t("act.hint_auction", [state.auction.bid]);
      case "trade-in": return t("act.hint_trade");
      case "ai": return t("act.ai_status", [s.name]);
      case "neuro": return t("act.ai_status", [s.name]);
      case "observer": return t("act.observer_status", [t("phase.TURN_START"), s.name,
        state.set.turn_timer > 0 ? t("act.observer_timer", [state.timer]) : "", ""]);
      default: return t("act.human_status", [s.name]);
    }
  }
  function btn(html, cls, tip, hot, dis, act) {
    return '<button class="btn ' + (cls || "") + '"' + (act ? ' data-act="' + act + '"' : "") +
      (tip ? ' data-tip="' + esc(t(tip)) + '"' : "") + (dis ? " disabled" : "") + ">" +
      html + (hot ? " <kbd>" + hot + "</kbd>" : "") + "</button>";
  }
  function renderConsole() {
    var r2 = $("#actRow2"), s = seat(state.turn);
    var html = "";
    var scn = state.scene;
    if (scn === "cold") {
      html = btn(esc(t("act.start_btn")), "btn--primary ch-sm", "act.start_tip", null, false, "start");
    } else if (scn === "observer") {
      /* no action buttons at all (F-56); the honest note sits where buttons would be (F-58) */
      html = '<span class="lastroll t-value mut">' + esc(t("act.observer_note")) + "</span>";
    } else if (scn === "win") {
      html = btn(esc(t("modal.rematch")), "btn--primary ch-sm", "modal.rematch_tip", null, false, "rematch") +
        btn(esc(t("modal.settings")), "ch-sm", "modal.settings_tip", null, false, "settings");
    } else if (scn === "ai" || scn === "neuro") {
      html = '<span class="lastroll t-value mut">' + esc(t("act.ai_status", [s.name])) + "</span>";
    } else {
      if (scn === "jail") {
        html += btn(esc(t("act.roll")), "ch-sm", "act.roll_tip", null, false, "roll") +
          btn(esc(t("act.pay", [state.set.jail_fine])), "ch-sm", "act.pay_tip", null, false, "pay") +
          btn(esc(t("act.use_card")), "ch-sm", "act.use_card_tip", null, false, "card") +
          btn(esc(t("act.end_turn")), "ch-sm", "act.end_turn_tip", "N", false, "end");
      } else {
        if (scn === "turn-human" || scn === "move") html += btn(esc(t("act.roll")), "btn--primary ch-sm", "act.roll_tip", "R", false, "roll");
        if (scn === "purchase") {
          html += btn(esc(t("act.buy_price", [tileOf(state.selTile).cost])), "btn--primary ch-sm", "act.buy_tip", "B", false, "buy") +
            btn(esc(t("act.no_buy")), "ch-sm", "act.pass_tip", null, false, "pass");
        }
        if (scn === "auction") {
          html += btn(esc(t("act.bid")), "btn--primary ch-sm", "act.bid_tip", null, false, "bid") +
            btn(esc(t("modal.pass_btn")), "ch-sm", "modal.pass_tip", null, false, "pass");
        }
        if (scn === "trade-in") html += btn(esc(t("act.respond_trade")), "btn--primary ch-sm", "act.respond_trade_tip", null, false, "respond");
        if (scn === "build" || scn === "turn-human" || scn === "move") html += btn(esc(t("act.end_turn")), "ch-sm", "act.end_turn_tip", "N", false, "end");
      }
      /* secondary row: real, visible, tooltipped — never micro-links in a corner (P-7) */
      html += '<span class="sp" data-grow></span>' +
        btn(esc(t("act.trade")), "btn--ghost t-value", "act.trade_tip", null, false, "trade") +
        btn(esc(t("act.build")), "btn--ghost t-value", "act.build_tip", null, false, "build") +
        btn(esc(t("act.mortgage")), "btn--ghost t-value", "act.mortgage_tip", null, false, "build") +
        btn(esc(t("act.sell")), "btn--ghost t-value", "act.sell_tip", null, false, "build");
    }
    r2.innerHTML = html;
    wireConsole();

    $("#actPrompt").innerHTML = esc(promptFor());
    var lr = $("#actLastRoll");
    lr.innerHTML = state.dice.rolled && scn !== "cold"
      ? '<svg width="12" height="12"><use href="#as-die_' + state.dice.d1 + '"/></svg> ' + state.dice.d1 + "+" + state.dice.d2 + "=<span class='res'>" + (state.dice.d1 + state.dice.d2) + "</span>"
      : "";
  }
  function wireConsole() {
    $$("#actRow2 .btn").forEach(function (b) {
      b.addEventListener("click", function () {
        switch (b.dataset.act) {
          case "roll": return doRoll();
          case "buy": return doBuy();
          case "pass": return doPass();
          case "end": return doEndTurn();
          case "start": return openSettings("players");
          case "bid": return doBid();
          case "respond": return scene("trade-in");
          case "trade": return openTrade();
          case "build": return openBuild();
          case "pay": return doJailPay();
          case "card": return doJailCard();
          case "rematch": return scene("turn-human");
          case "settings": return openSettings("players");
        }
      });
    });
  }

  /* ---------------------------------------------------------- demo actions */
  function doRoll() {
    var s = seat(state.turn);
    if (state.scene === "jail") {
      s.attempts += 1;
      if (s.attempts >= 3) {
        s.jail = 0; s.attempts = 0; state.dice = { d1: 4, d2: 2, doubles: false, rolled: true };
        pushToast("warn", t("toast.pay", [s.name, 50]) + " · " + t("phase.JAIL_DECISION"));
        s.money -= 50; addLog("pay", s.id, [50]);
      } else {
        pushToast("bad", t("toast.jail", [s.name]) + " ×" + s.attempts);
      }
      renderAll(); return;
    }
    state.rolling = true; renderCenter();
    setTimeout(function () {
      var d1 = 1 + Math.floor(Math.random() * 6), d2 = 1 + Math.floor(Math.random() * 6);
      state.dice = { d1: d1, d2: d2, doubles: d1 === d2, rolled: true, third: false };
      state.rolling = false;
      addLog("roll", state.turn, [d1, d2]);
      pushToast("ok", t("event.roll", [s.name, d1, d2]));
      var target = s.pos + d1 + d2;
      if (target >= N) { s.money += state.set.go_bonus; addLog("go", s.id, []); }
      s.pos = target % N;
      renderAll();
      setTimeout(function () {
        var tile = tileOf(s.pos);
        if (tile.type === "property" && state.owners[s.pos] == null && s.id === 0) {
          scene("purchase");
        } else if (tile.type === "go_to_jail") {
          s.pos = 10; s.jail = 1; s.attempts = 0; addLog("jail", s.id, []); pushToast("bad", t("toast.jail", [s.name]));
          scene("turn-human");
        } else {
          scene("turn-human");
        }
      }, 700);
    }, 900);
  }
  function doBuy() {
    var s = seat(state.turn), cost = tileOf(state.selTile).cost;
    state.owners[state.selTile] = s.id; s.money -= cost; s.tiles += 1;
    addLog("buy", s.id, [state.selTile, cost]);
    pushToast("money", t("toast.purchase", [s.name, tileName(state.selTile), cost]));
    scene("turn-human");
  }
  function doPass() {
    var s = seat(state.turn);
    if (state.scene === "purchase") {
      addLog("pass", s.id, [state.selTile]);
      pushToast("warn", t("toast.pass", [s.name, tileName(state.selTile)]));
      scene("auction");
    }
  }
  function doEndTurn() {
    state.turn = (state.turn + 1) % state.seats.length;
    state.dice = { d1: 1 + Math.floor(Math.random() * 6), d2: 1 + Math.floor(Math.random() * 6), doubles: false, rolled: false };
    if (state.turn === 0) state.round += 1;
    state.step = 0;
    if (state.turn !== 0) scene("ai");
    else scene("turn-human");
  }
  function doBid() {
    var a = state.auction;
    a.bid += 20; a.bids.push(a.bid); a.leader = state.turn;
    addLog("bid", state.turn, [a.bid]);
    pushToast("money", seat(state.turn).name + " · " + t("modal.bid_lbl") + a.bid);
    renderCenter(); renderModal();
    setTimeout(function () {
      a.bid += 20; a.bids.push(a.bid); a.leader = 1;
      renderCenter(); renderModal();
    }, 900);
    setTimeout(function () {
      pushToast("ok", t("toast.auction_win", [seat(1).name, tileName(a.tile)]));
      state.owners[a.tile] = 1; addLog("aucwin", 1, [a.tile]);
      scene("turn-human");
    }, 2200);
  }

  /* ------------------------------------------------------------- overlays */
  function openSettings(tab) {
    state.overlay = "settings"; state.settingsTab = tab || "players";
    $("#ovSettings").classList.add("on");
    renderSettings();
  }
  function closeOverlay() {
    state.overlay = null; state.modal = null;
    $$(".ov").forEach(function (o) { o.classList.remove("on"); });
    $("#modal").classList.remove("on"); $("#modal").innerHTML = "";
  }
  function renderSettings() {
    $$("#setTabs .tab").forEach(function (b) { b.classList.toggle("on", b.dataset.pane === state.settingsTab); });
    $$(".pane", $("#ovSettings")).forEach(function (p) { p.classList.remove("on"); });
    $("#pane" + state.settingsTab[0].toUpperCase() + state.settingsTab.slice(1)).classList.add("on");
    buildPanePlayers(); buildPaneRules(); buildPaneTempo(); buildPaneIface(); buildPaneData();
    var inGame = state.scene !== "cold";
    var prim = $("#btnSetPrimary");
    prim.textContent = inGame ? t("settings.apply_btn") : t("settings.start_btn");
    prim.dataset.tip = t(inGame ? "settings.apply_tip" : "settings.start_tip");
    $("#setStatus").textContent = "";
  }
  function field(labelKey, tipKey, ctl, tag) {
    return '<div class="field"><span class="k t-value" data-i18n-tip="' + tipKey + '">' + esc(t(labelKey)) + "</span>" +
      '<span class="ctl">' + ctl + "</span>" +
      '<span class="tag t-value ' + (tag === "live" ? "tag--live" : "tag--restart") + '">' + esc(t(tag === "live" ? "settings.tag_live" : "settings.tag_restart")) + "</span></div>";
  }
  function seg(key, opts, cur) {
    return '<span class="seg" data-key="' + key + '">' + opts.map(function (o) {
      var label = (typeof o.k === "string" && dict(o.k)) ? t(o.k) : String(o.k);
      return '<button class="' + (o.v === cur ? "on" : "") + '" data-v="' + o.v + '">' + esc(label) + "</button>";
    }).join("") + "</span>";
  }
  function sw(key, on) { return '<span class="sw' + (on ? " on" : "") + '" data-key="' + key + '"><i></i></span>'; }
  function buildPanePlayers() {
    var p = $("#panePlayers");
    var html = '<div class="ph caps t-value" data-i18n="settings.roles_label">' + esc(t("settings.roles_label")) + "</div>";
    html += field("ui.host_role", "settings.host_role_tip", seg("host_playing", [{ v: 1, k: "settings.host_playing" }, { v: 0, k: "settings.host_obs" }], state.set.host_playing ? 1 : 0), "restart");
    html += field("ui.starting_order", "settings.starting_order_tip", seg("starting_order", [{ v: "random", k: "settings.order_random" }, { v: "manual", k: "settings.order_manual" }], state.set.starting_order), "restart");
    html += '<div class="ph caps t-value">' + esc(t("settings.players_lbl")) + " · " + esc(t("settings.seat_count", [state.seats.length])) + "</div>";
    state.seats.forEach(function (s, ix) {
      html += '<div class="seatrow' + (s.name === "" ? " invalid" : "") + '">' +
        '<span class="idx num t-value">' + (ix + 1) + "</span>" +
        '<span class="ctl" style="gap:8px"><span class="av" style="--pc:' + colorVar(s) + '"><span class="halo"></span><svg viewBox="0 0 64 64"><use href="#as-' + s.token + '"/></svg></span>' +
        '<select class="inp t-value" data-seat-driver="' + ix + '" data-i18n-tip="settings.driver_tip">' +
        ["LOCAL", "AI", "CHAT", "sdk_neuro", "sdk_evil"].map(function (d) {
          return '<option value="' + d + '"' + (d === s.driver ? " selected" : "") + ">" + esc(t("settings.driver." + d.toLowerCase().replace("sdk_", "sdk_"))) + "</option>";
        }).join("") + "</select></span>" +
        '<input class="inp t-value" data-seat-name="' + ix + '" value="' + esc(s.name) + '" data-i18n-tip="settings.name_tip">' +
        '<select class="inp t-value" data-seat-token="' + ix + '" data-i18n-tip="settings.token_tip">' +
        TOKENS.map(function (tk) { return '<option value="' + tk + '"' + (tk === s.token ? " selected" : "") + ">" + tk + "</option>"; }).join("") + "</select>" +
        '<span class="ctl"><span class="ins-band" style="--band:' + colorVar(s) + '"></span>' +
        (s.driver === "AI" ? '<select class="inp t-value" data-i18n-tip="settings.persona_tip"><option>' + esc(t("persona." + (s.persona || "random"))) + "</option></select>" : "") + "</span>" +
        '<button class="rm" data-seat-rm="' + ix + '" data-i18n-tip="settings.remove_tip"><svg width="12" height="12"><use href="#ui-x"/></svg></button>' +
        "</div>";
    });
    html += '<div class="presets">' +
      '<button class="btn btn--ghost t-value" data-i18n="settings.add_player" data-i18n-tip="settings.add_player_tip">' + esc(t("settings.add_player")) + "</button>" +
      '<button class="btn btn--ghost t-value" data-i18n="settings.host_btn" data-i18n-tip="settings.host_tip">' + esc(t("settings.host_btn")) + "</button></div>";
    html += '<div class="warnline t-para" data-i18n="settings.err_min2">' + esc(t("settings.err_min2")) + "</div>";
    p.innerHTML = html;
  }
  function buildPaneRules() {
    var f = [
      ["settings.starting_cash", "settings.starting_cash_tip", "num", "starting_cash", "restart", 1500],
      ["settings.go_bonus", "settings.go_bonus_tip", "num", "go_bonus", "restart", 200],
      ["settings.jail_rule", "settings.jail_rule_tip", "seg", "jail_rule", "restart", [{ v: "both", k: "settings.jail_both" }, { v: "fine", k: "settings.jail_fine_only" }, { v: "card", k: "settings.jail_card_only" }]],
      ["settings.jail_fine", "settings.jail_fine_tip", "num", "jail_fine", "restart", 50],
      ["settings.free_parking", "settings.free_parking_tip", "sw", "free_parking", "restart", true],
      ["settings.doubles_lbl", "settings.doubles_tip", "sw", "doubles", "restart", true],
      ["settings.triple_doubles_lbl", "settings.triple_doubles_tip", "sw", "triple_doubles_to_jail", "restart", true],
      ["settings.auctions", "settings.auctions_tip", "sw", "auctions_on_refusal", "restart", true],
      ["settings.housing_lbl", "settings.housing_tip", "sw", "housing", "restart", true],
      ["settings.even_build_lbl", "settings.even_build_tip", "sw", "even_build", "restart", true],
      ["settings.monopoly_x2_lbl", "settings.monopoly_x2_tip", "sw", "monopoly_rent_x2", "restart", true],
      ["settings.mortgage_lbl", "settings.mortgage_tip", "sw", "mortgage", "restart", true],
      ["settings.loan_pct", "settings.loan_pct_tip", "num", "mortgage_loan_pct", "restart", 50],
      ["settings.repay_pct", "settings.repay_pct_tip", "num", "mortgage_repay_pct", "restart", 110],
      ["settings.trades_lbl", "settings.trades_tip", "sw", "trades", "restart", true],
      ["settings.round_limit", "settings.round_limit_tip", "num", "round_limit", "restart", 0],
      ["settings.ai_aggression", "settings.ai_aggression_tip", "slide", "ai_aggression", "restart", 50],
    ];
    var html = f.map(function (r) {
      var key = r[0], tip = r[1], kind = r[2], sk = r[3], tag = r[4], def = r[5];
      var cur = state.set[sk];
      var ctl;
      if (kind === "num") ctl = '<input class="inp num t-value" data-set="' + sk + '" value="' + cur + '" style="width:76px">';
      else if (kind === "seg") ctl = seg(sk, def, cur);
      else if (kind === "sw") ctl = sw(sk, !!cur);
      else ctl = '<input type="range" class="slider" data-set="' + sk + '" min="0" max="100" value="' + cur + '"><span class="num t-value">' + cur + "</span>";
      return field(key, tip, ctl, tag);
    }).join("");
    $("#paneRules").innerHTML = html;
  }
  function buildPaneTempo() {
    var html = "";
    html += field("settings.turn_timer", "settings.turn_timer_tip", seg("turn_timer", [{ v: 0, k: "settings.no_limit" }, { v: 15, k: 15 }, { v: 30, k: 30 }, { v: 60, k: 60 }], state.set.turn_timer), "live");
    html += field("settings.auction_timer", "settings.auction_timer_tip", seg("auction_timer", [{ v: 0, k: "settings.no_limit" }, { v: 10, k: 10 }, { v: 15, k: 15 }, { v: 30, k: 30 }], state.set.auction_timer), "live");
    html += field("settings.timeout", "settings.timeout_tip", seg("timeout_action", [{ v: "auto-pass", k: "settings.timeout_auto_pass" }, { v: "away", k: "settings.timeout_away" }], state.set.timeout_action), "live");
    $("#paneTempo").innerHTML = html;
  }
  function buildPaneIface() {
    var html = "";
    html += field("settings.animations_lbl", "settings.animations_tip", sw("animations", state.set.animations), "live");
    html += field("settings.event_overlay_lbl", "settings.event_overlay_tip", sw("event_overlay", state.set.event_overlay), "live");
    html += field("settings.spectacle_lbl", "settings.spectacle_tip", sw("spectacle", state.set.spectacle), "live");
    html += field("settings.sound_lbl", "settings.sound_tip", sw("sound", state.set.sound), "live");
    html += field("ui.language", "settings.language_tip", seg("language", [{ v: "ru", k: "ui.language" }, { v: "en", k: "settings.lang_en" }], state.locale === "ru" ? "ru" : "en"), "live");
    html += field("top.skin_tip", "top.skin_tip", seg("skin", Object.keys(D.skins || {}).filter(function (s) { return s.indexOf("_") !== 0; }).map(function (s) {
      return { v: s, k: (D.skins[s].name_ru || s) };
    }), state.theme), "live");
    $("#paneIface").innerHTML = html;
  }
  function buildPaneData() {
    var html = '<div class="presets"><span class="ph caps t-value" data-i18n="settings.presets_lbl">' + esc(t("settings.presets_lbl")) + "</span>" +
      ["classic", "fast", "hard"].map(function (p) {
        return '<button class="btn btn--ghost t-value" data-preset="' + p + '" data-i18n-tip="settings.preset_' + p + '_tip">' + esc(t("settings.preset_" + p)) + "</button>";
      }).join("") + "</div>";
    html += field("settings.rng_seed", "settings.rng_seed_tip", '<input class="inp num t-value" data-set="rng_seed" value="' + state.set.rng_seed + '" style="width:96px">', "restart");
    html += field("settings.tile_count", "settings.tile_count_tip", seg("tile_count", [{ v: 16, k: 16 }, { v: 24, k: 24 }, { v: 40, k: 40 }, { v: 64, k: 64 }], state.set.tile_count), "restart");
    html += '<div class="hint t-para">' + esc(t("settings.tile_count_tip")) + "</div>";
    $("#paneData").innerHTML = html;
  }
  function openRules() { state.overlay = "rules"; $("#ovRules").classList.add("on"); renderRules(); }
  function renderRules() {
    var s = state.set, on = function (b) { return t(b ? "rules.on" : "rules.off"); };
    var jailWord = t(s.jail_rule === "both" ? "settings.jail_both" : s.jail_rule === "fine" ? "settings.jail_fine_only" : "settings.jail_card_only");
    var lines = [
      t("rules.starting_cash", [s.starting_cash]),
      t("rules.go_bonus", [s.go_bonus]),
      t("rules.jail", [jailWord, s.jail_fine]),
      t("rules.free_parking", [on(s.free_parking)]),
      t("rules.doubles", [on(s.doubles)]),
      t("rules.triple_doubles", [on(s.triple_doubles_to_jail)]),
      t("rules.auctions", [on(s.auctions_on_refusal)]),
      t("rules.housing", [on(s.housing)]),
      t("rules.even_build", [on(s.even_build)]),
      t("rules.monopoly_x2", [on(s.monopoly_rent_x2)]),
      t("rules.mortgage", [on(s.mortgage), s.mortgage_loan_pct, s.mortgage_repay_pct]),
      t("rules.trades", [on(s.trades)]),
      t("rules.round_limit", [s.round_limit ? String(s.round_limit) : t("rules.round_limit_off")]),
      t("rules.turn_timer", [s.turn_timer]),
      t("rules.auction_timer", [s.auction_timer]),
      t("rules.timeout", [t(s.timeout_action === "auto-pass" ? "settings.timeout_auto_pass" : "settings.timeout_away")]),
      t("rules.ai_aggression", [s.ai_aggression]),
    ];
    $("#rulesBody").innerHTML = lines.map(function (l) {
      return '<div class="r"><span class="v t-para">' + esc(l) + "</span></div>";
    }).join("");
  }
  function openAdmin(tab) {
    state.overlay = "admin"; state.adminTab = tab || "quick";
    $("#ovAdmin").classList.add("on");
    renderAdmin();
  }
  function renderAdmin() {
    $$("#admTabs .tab").forEach(function (b) { b.classList.toggle("on", b.dataset.pane === state.adminTab); });
    $$(".pane", $("#ovAdmin")).forEach(function (p) { p.classList.remove("on"); });
    $("#adm" + state.adminTab[0].toUpperCase() + state.adminTab.slice(1)).classList.add("on");
    var q = $("#admQuick");
    var qbtn = function (k, tip) { return '<button class="btn ch-sm t-value" data-tip="' + esc(t(tip)) + '">' + esc(t(k)) + "</button>"; };
    q.innerHTML = '<div class="ph caps t-value" data-i18n="admin.quick_hint">' + esc(t("admin.quick_hint")) + "</div>" +
      '<div class="presets">' + qbtn("admin.quick_force_roll", "admin.quick_force_roll_tip") +
      qbtn("admin.quick_force_pass", "admin.quick_force_pass_tip") +
      qbtn("admin.quick_rollback", "admin.quick_rollback_tip") + "</div>" +
      '<div class="kv"><span class="k t-value">' + esc(t("admin.quick_summary")) + "</span><span class='num t-value'>" +
      esc(t("phase." + phaseKey()) + " · " + seat(state.turn).name + " · r" + state.round) + "</span></div>";
    q.querySelectorAll(".btn").forEach(function (b) {
      b.addEventListener("click", function () {
        state.adminLog.push(t("toast.admin_override", [b.textContent]));
        addLog("admin", null, [b.textContent]);
        $("#admStatus").textContent = t("admin.ok"); $("#admStatus").className = "status t-value ok";
        renderJournal();
      });
    });
    $("#admState").innerHTML =
      '<div class="kv">' +
      '<span class="k t-value" data-i18n="admin.quick_summary">' + esc(t("admin.quick_summary")) + "</span><span class='v t-value'>" + esc(seat(state.turn).name + " · " + t("phase." + phaseKey())) + "</span>" +
      '<span class="k t-value">' + esc(t("top.round")) + '</span><span class="v num t-value">' + state.round + "</span>" +
      '<span class="k t-value">' + esc(t("top.pot")) + '</span><span class="v num t-value">' + money(state.pot) + "</span></div>" +
      '<div class="presets"><button class="btn btn--ghost t-value" data-i18n-tip="admin.copy_dump_tip">' + esc(t("admin.copy_dump")) + "</button>" +
      '<button class="btn btn--ghost t-value" data-i18n-tip="admin.save_snap_tip">' + esc(t("admin.save_snap")) + "</button>" +
      '<button class="btn btn--ghost t-value btn--danger" data-i18n-tip="admin.load_snap_tip">' + esc(t("admin.load_snap")) + "</button></div>" +
      '<textarea class="dump" readonly>' + esc(JSON.stringify({ round: state.round, turn: seat(state.turn).name, phase: phaseKey(), pot: state.pot }, null, 1)) + "</textarea>";
    $("#admEvents").innerHTML = '<div class="filters"><select class="inp t-value" data-i18n-tip="admin.ev_filter_tip"><option>' + esc(t("admin.ev_all_types")) + "</option></select>" +
      '<span class="sp" data-grow style="flex:1"></span><label class="t-value">' + esc(t("admin.ev_type_lbl")) + "</label>" +
      '<button class="iconbtn" data-i18n-tip="admin.ev_export_tip"><svg width="14" height="14"><use href="#ui-dl"/></svg></button></div>' +
      '<div class="adm-feed" id="admFeed"></div>';
    var feed = $("#admFeed");
    if (feed) renderJournalList(feed);
    var ops = ["op_set_balance", "op_teleport", "op_force_dice", "op_grant", "op_revoke", "op_set_houses",
      "op_set_mortgage", "op_tweak_tile", "op_deck_insert", "op_deck_remove", "op_set_go_jail", "op_reorder", "op_redo_turn"];
    $("#admEdits").innerHTML =
      '<div class="adm-edits"><div class="adm-ops" id="admOps">' +
      '<input class="inp t-value" id="admSearch" placeholder="' + esc(t("admin.search_ph")) + '" data-i18n-tip="admin.search_tip" style="margin-bottom:6px">' +
      ops.map(function (o, ix) {
        return '<button class="adm-op t-value' + (ix === 0 ? " on" : "") + '" data-op="' + o + '">' + esc(t("admin." + o)) + "</button>";
      }).join("") + "</div><div class='adm-form' id='admForm'></div></div>";
    var form = $("#admForm");
    function opForm(o) {
      var tileField = '<span class="r"><span class="k t-value">' + esc(t("admin.lbl_tile")) + '</span><span class="v"><select class="inp t-value">' +
        TILES.map(function (tl, i) { return "<option>" + i + " · " + esc(tl.short) + "</option>"; }).join("") + "</select></span></span>";
      var amt = '<span class="r"><span class="k t-value">' + esc(t("admin.lbl_amount")) + '</span><span class="v"><input class="inp num t-value" value="200" style="width:86px"></span></span>';
      var cnt = '<span class="r"><span class="k t-value">' + esc(t("admin.lbl_count")) + '</span><span class="v"><input class="inp num t-value" value="1" style="width:60px"></span></span>';
      var seed = '<span class="r"><span class="k t-value">' + esc(t("admin.lbl_seed")) + '</span><span class="v"><input class="inp num t-value" value="' + state.set.rng_seed + '" style="width:86px"></span></span>';
      var deck = '<span class="r"><span class="k t-value">' + esc(t("admin.deck_chance")) + '</span><span class="v"><input class="inp t-value" placeholder="' + esc(t("admin.card_name_ph")) + '" style="width:220px"></span></span>';
      var byOp = {
        op_set_balance: amt, op_teleport: tileField, op_force_dice: '<span class="r"><span class="k t-value">' + esc(t("admin.lbl_value")) + '</span><span class="v"><input class="inp num t-value" value="6" style="width:60px"><input class="inp num t-value" value="6" style="width:60px;margin-left:6px"></span></span>',
        op_grant: tileField, op_revoke: tileField, op_set_houses: tileField + cnt, op_set_mortgage: tileField,
        op_tweak_tile: tileField, op_deck_insert: deck, op_deck_remove: deck, op_set_go_jail: "",
        op_reorder: '<span class="r"><span class="k t-value">' + esc(t("admin.order_ph")) + '</span><span class="v"><input class="inp t-value" value="0,1,2,3" style="width:160px"></span></span>',
        op_redo_turn: "",
      };
      form.innerHTML = '<div class="ph caps t-value">' + esc(t("admin." + o)) + "</div>" +
        '<div class="kv">' + (byOp[o] || "") + "</div>" +
        '<div class="presets"><button class="btn btn--primary ch-sm t-value" id="admApply">' + esc(t("admin.apply_btn")) + "</button>" +
        '<button class="btn btn--ghost t-value">' + esc(t("ui.cancel")) + "</button></div>" +
        '<div class="adm-res t-value" id="admRes"></div>' +
        '<div class="hint t-para">' + esc(t("admin." + o + "_tip")) + "</div>";
      var apply = $("#admApply");
      apply.addEventListener("click", function () {
        var res = $("#admRes");
        res.textContent = t("admin.ok") + " · " + b.textContent;
        res.className = "adm-res t-value";
        $("#admStatus").textContent = t("admin.ok"); $("#admStatus").className = "status t-value ok";
        state.adminLog.push(b.textContent); addLog("admin", null, [b.textContent]); renderJournal();
      });
    }
    var b;
    $$("#admOps .adm-op").forEach(function (ob) {
      ob.addEventListener("click", function () {
        $$("#admOps .adm-op").forEach(function (x) { x.classList.remove("on"); });
        ob.classList.add("on"); b = ob; opForm(ob.dataset.op);
      });
    });
    b = $("#admOps .adm-op"); opForm(b.dataset.op);
    $("#admStatus").textContent = t("admin.edits_note");
  }

  /* ---------------------------------------------------------------- modals */
  function modalShell(title, body, footer) {
    return '<div class="scrim" data-close></div><div class="modal ch">' +
      '<div class="modal-h"><span class="title t-value">' + esc(title) + "</span><span class='sp' data-grow></span>" +
      '<button class="iconbtn" data-close aria-label="close"><svg width="14" height="14"><use href="#ui-x"/></svg></button></div>' +
      '<div class="modal-b">' + body + "</div>" +
      '<div class="modal-f">' + footer + "</div></div>";
  }
  function openModal(kind, extra) {
    state.modal = kind;
    var m = $("#modal"); m.classList.add("on");
    var body = "", foot = "", title = "";
    if (kind === "auction") {
      var a = state.auction, mine = extra !== "watch";
      title = t("modal.auction_title");
      body = '<span class="sub t-value">' + esc(t("modal.lot_name", [tileName(a.tile)])) + "</span>" +
        '<span class="bigbid t-value">' + money(a.bid) + "</span>" +
        '<span class="sub t-value">' + esc(a.bids.length ? t("modal.auction_leader", [seat(a.leader).name]) + " · " + t("modal.auction_high", [a.bid]) : t("modal.auction_none")) + "</span>" +
        '<span class="tilesel">' + a.bids.slice(-4).map(function (b) { return '<span class="tilechip t-value num">' + money(b) + "</span>"; }).join("") + "</span>" +
        (mine ? "" : '<span class="sub t-para">' + esc(t("modal.auction_watch")) + "</span>");
      foot = mine
        ? '<span class="num t-value"><input class="inp num t-value" value="' + (a.bid + 20) + '" style="width:96px"></span>' +
          btn(esc(t("modal.bid_btn")), "btn--primary ch-sm", "modal.bid_btn_tip") +
          btn(esc(t("modal.pass_btn")), "ch-sm", "modal.pass_tip")
        : btn(esc(t("ui.close")), "btn--ghost t-value");
    } else if (kind === "trade") {
      title = t("modal.trade_title");
      var tr = state.trade;
      var chip = function (i, on) {
        var t2 = tileOf(i);
        return '<button class="tilechip' + (on ? " selected" : "") + ' t-value" data-tile="' + i + '"><span class="band" style="--band:var(--g-' + (t2.group || "brown") + ')"></span>' + esc(t2.short) + "</button>";
      };
      var mineTiles = Object.keys(state.owners).filter(function (i) { return state.owners[i] === 0; }).map(function (i) { return chip(i, tr.giveTiles.indexOf(+i) >= 0); }).join("") || '<span class="sub t-value">' + esc(t("modal.no_tiles")) + "</span>";
      var theirTiles = Object.keys(state.owners).filter(function (i) { return state.owners[i] === tr.to; }).map(function (i) { return chip(i, tr.wantTiles.indexOf(+i) >= 0); }).join("") || '<span class="sub t-value">' + esc(t("modal.no_tiles")) + "</span>";
      body = '<span class="sub t-value">' + esc(t("modal.recipient")) + "</span>" +
        '<select class="inp t-value" data-i18n-tip="modal.recipient_tip">' +
        state.seats.filter(function (x) { return x.id !== 0; }).map(function (x) { return "<option" + (x.id === tr.to ? " selected" : "") + ">" + esc(x.name) + "</option>"; }).join("") + "</select>" +
        '<div class="trade-cols"><div class="trade-col"><span class="head caps t-value">' + esc(t("modal.give_hint")) + '</span><span class="tilesel">' + mineTiles + "</span>" +
        '<span class="sub t-value"><input class="inp num t-value" value="' + tr.giveCash + '" style="width:86px">' + " " + esc(t("modal.give_cash")) + "</span></div>" +
        '<div class="trade-col"><span class="head caps t-value">' + esc(t("modal.want_hint")) + '</span><span class="tilesel">' + theirTiles + "</span>" +
        '<span class="sub t-value"><input class="inp num t-value" value="' + tr.wantCash + '" style="width:86px">' + " " + esc(t("modal.want_cash")) + "</span></div></div>";
      foot = btn(esc(t("modal.offer")), "btn--primary ch-sm", "modal.offer_tip") + btn(esc(t("ui.cancel")), "ch-sm", "modal.cancel_tip");
    } else if (kind === "trade-in") {
      title = t("modal.trade_response");
      body = '<span class="sub t-value">' + esc(t("modal.trade_offers", [seat(3).name, seat(0).name])) + "</span>" +
        '<span class="t-value">' + esc(t("modal.trade_terms", [150, 1, 0, 0])) + "</span>" +
        '<span class="tilesel"><span class="tilechip t-value"><span class="band" style="--band:var(--g-red)"></span>' + esc(tileOf(21).short) + "</span></span>";
      foot = btn(esc(t("modal.accept")), "btn--accept ch-sm", "modal.accept_tip") + btn(esc(t("modal.decline")), "ch-sm", "modal.decline_tip");
    } else if (kind === "build") {
      var tile = tileOf(state.selTile);
      title = t("modal.build_title");
      body = '<span class="sub t-value">' + esc(t("modal.tile_header", [tile.name, state.selTile])) + "</span>" +
        '<span class="t-value">' + esc(t("modal.house_cost", [(state.houses[state.selTile] || 0), tile.house_cost || 0])) + "</span>" +
        '<span class="tilesel">' + '<span class="tilechip t-value">' + esc(t("act.build")) + "</span>" + '<span class="tilechip t-value">' + esc(t("act.mortgage")) + "</span></span>";
      foot = btn(esc(t("ui.close")), "btn--ghost t-value");
    } else if (kind === "confirm") {
      title = extra === "load" ? t("admin.confirm_snap") : t("admin.confirm_op");
      body = '<span class="t-para">' + esc(t("admin.confirm_dlg")) + "</span>";
      foot = btn(esc(t("admin.confirm_yes")), "btn--danger ch-sm") + btn(esc(t("admin.confirm_no")), "ch-sm");
    } else if (kind === "over") {
      title = t("modal.game_over");
      body = '<span class="winner-name t-value">' + esc(seat(1).name) + "</span>" +
        '<span class="sub t-value">' + esc(t("modal.winner", [seat(1).name])) + "</span>" +
        '<span class="stats-line num t-value">' + esc(t("modal.stats", [87, 4, seat(1).money + 3480])) + "</span>";
      foot = btn(esc(t("modal.rematch")), "btn--primary ch-sm", "modal.rematch_tip") + btn(esc(t("modal.settings")), "ch-sm", "modal.settings_tip");
    } else if (kind === "message") {
      title = extra.title; body = '<span class="t-para">' + esc(extra.body) + "</span>";
      foot = btn(esc(t("ui.ok")), "btn--ghost t-value", "modal.msg_ok_tip");
    }
    m.innerHTML = modalShell(title, body, foot);
    m.querySelectorAll("[data-close]").forEach(function (x) { x.addEventListener("click", closeModal); });
    m.querySelectorAll(".btn").forEach(function (b2) {
      b2.addEventListener("click", function () {
        var lb = b2.textContent.trim();
        if (lb === t("modal.bid_btn")) { doBid(); return; }
        if (lb === t("modal.pass_btn")) { closeModal(); scene("auction-watch"); return; }
        if (lb === t("modal.accept")) { addLog("trade", 3, []); pushToast("ok", t("event.trade")); closeModal(); scene("turn-human"); return; }
        if (lb === t("modal.decline")) { addLog("trdno", 3, []); pushToast("warn", seat(3).name + " · " + t("event_type.trdno")); closeModal(); scene("turn-human"); return; }
        if (lb === t("modal.offer")) { addLog("trdoffer", 0, [state.trade.to]); pushToast("ok", t("modal.trade_offers", [seat(0).name, seat(state.trade.to).name])); closeModal(); scene("turn-human"); return; }
        if (lb === t("modal.rematch")) { closeModal(); scene("turn-human"); return; }
        if (lb === t("modal.settings")) { closeModal(); openSettings("players"); return; }
        closeModal();
      });
    });
  }
  function closeModal() { state.modal = null; var m = $("#modal"); m.classList.remove("on"); m.innerHTML = ""; }
  function openTrade() { openModal("trade"); }
  function openBuild() {
    state.insTile = state.selTile;
    state.insPinned = true;
    renderInspector();
    openModal("build");
  }
  function doJailPay() {
    var s = seat(state.turn);
    s.jail = 0; s.attempts = 0; s.money -= state.set.jail_fine;
    addLog("pay", s.id, [state.set.jail_fine]);
    pushToast("money", t("event.pay", [s.name, state.set.jail_fine]));
    scene("turn-human");
  }
  function doJailCard() {
    var s = seat(state.turn);
    s.jail = 0; s.attempts = 0; s.card = false;
    pushToast("ok", t("act.use_card") + " · " + s.name);
    scene("turn-human");
  }

  /* ------------------------------------------------------------ invite/join */
  function renderInvite() {
    var rows = state.seats.filter(function (s) { return s.id !== 0; }).map(function (s) {
      var url = "http://127.0.0.1:7456/?seat=" + (1000 + s.id) + "&host=ws://192.168.1.40:9001";
      return '<div class="invite-row"><span class="av" style="--pc:' + colorVar(s) + '"><span class="halo"></span><svg viewBox="0 0 64 64"><use href="#as-' + s.token + '"/></svg></span>' +
        '<span class="t-value">' + esc(s.name) + "</span>" +
        '<span class="url t-value">' + esc(url) + "</span>" +
        '<button class="btn btn--ghost t-value" data-copy="' + esc(url) + '">' + esc(t("invite.copy")) + "</button></div>";
    }).join("");
    $("#inviteList").innerHTML = rows;
    $$("#inviteList [data-copy]").forEach(function (b) {
      b.addEventListener("click", function () {
        try { navigator.clipboard && navigator.clipboard.writeText(b.dataset.copy); } catch (e) { /* standalone file */ }
        pushToast("ok", t("invite.copied"));
      });
    });
  }
  function renderJoin() {
    var st = state.joinState, h = $("#joinState");
    if (st === "connecting") h.innerHTML = '<span class="spinner"></span><span class="t-value">' + esc(t("join.connecting")) + "</span>";
    if (st === "joined") h.innerHTML = '<span class="t-value" style="color:var(--good)">' + esc(t("join.joined")) + "</span>";
    if (st === "failed") h.innerHTML = '<span class="t-value" style="color:var(--bad)">' + esc(t("join.failed")) + "</span>" +
      '<button class="btn ch-sm t-value">' + esc(t("join.retry")) + "</button>";
    if (st === "none") h.innerHTML = '<span class="t-para">' + esc(t("join.no_invite")) + "</span>";
  }

  /* -------------------------------------------------------------- rails/drawer */
  function renderRails() {
    var l = state.seats.map(function (s) {
      var cls = "rav" + (s.id === state.turn ? " active" : "");
      return '<span class="' + cls + '" style="--pc:' + colorVar(s) + '" data-rail-seat="' + s.id + '"><span class="halo"></span><svg viewBox="0 0 64 64"><use href="#as-' + s.token + '"/></svg></span>';
    }).join("");
    $("#rail-l").innerHTML = l;
    $$("#rail-l .rav").forEach(function (r) {
      r.addEventListener("click", function () { openDrawer(state.drawer === "l" ? "" : "l"); renderSeats(); });
    });
    var unread = state.log.length;
    $("#rail-r").innerHTML =
      '<button class="rbtn" data-rail="r" aria-label="journal"><svg width="16" height="16"><use href="#ui-chart"/></svg><span class="badge">&nbsp;</span></button>' +
      '<button class="rbtn" data-rail="insp" aria-label="inspector"><svg width="16" height="16"><use href="#ui-search"/></svg></button>';
    $$("#rail-r .rbtn").forEach(function (b) {
      b.querySelectorAll(".badge").forEach(function (bd) { bd.textContent = unread > 99 ? "99" : unread; });
      b.addEventListener("click", function () { openDrawer(state.drawer === "r" ? "" : "r"); renderJournal(); });
    });
  }
  function openDrawer(which) {
    state.drawer = which;
    app.dataset.drawer = which;
    if (which === "l") $("#drawerL").scrollTop = 0;
  }

  /* ------------------------------------------------------------- scene manager */
  function setTheme(th) {
    state.theme = th;
    app.dataset.theme = th;
    document.documentElement.dataset.theme = th;   /* the :root[data-theme] palette blocks */
  }
  function setLocale(loc) {
    state.locale = loc;
    app.dataset.locale = loc;
    relabel(app);
    renderAll();                                  /* composite lines re-derived (P-11) */
  }
  function relabel(root) {
    $$("[data-i18n]", root).forEach(function (n) { n.textContent = t(n.dataset.i18n); });
    $$("[data-i18n-tip]", root).forEach(function (n) { n.dataset.tip = t(n.dataset.i18nTip); });
  }
  function computeProfile() {
    var w = app.clientWidth, h = app.clientHeight;
    state.profile = w >= 1600 ? "wide" : (w >= 1280 && h > 700 ? "desktop" : "compact");
    app.dataset.profile = state.profile;
    var stageRect = $("#stage");
    var px = Math.min(stageRect.clientWidth, stageRect.clientHeight) - 2;
    state.boardPx = px;
    $("#board").style.setProperty("--board", px + "px");
    renderBoard();
    $("#app").style.minWidth = "880px"; $("#app").style.minHeight = "600px";
  }
  function scene(id) {
    state.scene = id;
    app.dataset.scene = id;
    state.toast = [];
    closeModal();
    if (id !== "settings" && id !== "rules" && id !== "admin" && id !== "invite" && id !== "join") {
      if (state.overlay) closeOverlay();
    }
    switch (id) {
      case "cold":
        state.turn = 0; state.round = 1; state.dice = { d1: 6, d2: 6, doubles: false, rolled: false };
        state.owners = {}; state.houses = {}; state.mortgage = {};
        state.log = [];
        state.pot = 0;
        break;
      case "observer":
        state.observer = true; app.dataset.observer = "on"; state.turn = 1;
        break;
      case "auction":
        openModal("auction"); break;
      case "auction-watch":
        openModal("auction", "watch"); break;
      case "trade":
        openModal("trade"); break;
      case "trade-in":
        openModal("trade-in"); break;
      case "build":
        openModal("build"); state.insTile = state.selTile; state.insPinned = true; break;
      case "win":
        openModal("over"); break;
      case "reject":
        pushToast("bad", t("gv.rejected_title") + " — " + t("gv.rejected_body", [t("act.pass_tip")]));
        break;
      case "toasts":
        pushToast("money", t("toast.purchase", [seat(1).name, tileName(6), 100]));
        pushToast("bad", t("toast.jail", [seat(2).name]));
        pushToast("money", t("toast.rent_merged", [seat(3).name, 48, 2]));
        break;
      case "empty":
        state.log = [];
        state.insTile = null;
        state.owners = {}; state.houses = {}; state.mortgage = {};
        break;
      case "settings": openSettings("players"); break;
      case "rules": openRules(); break;
      case "admin": openAdmin("quick"); break;
      case "invite": state.overlay = "invite"; $("#ovInvite").classList.add("on"); renderInvite(); break;
      case "join": state.overlay = "join"; $("#ovJoin").classList.add("on"); state.joinState = "connecting"; renderJoin();
        clearTimeout(state._joinT);
        state._joinT = setTimeout(function () { state.joinState = "failed"; renderJoin(); }, 2600);
        break;
      default: break;
    }
    if (id !== "observer" && id !== "join") { state.observer = false; app.dataset.observer = "off"; }
    if (["turn-human", "move", "purchase", "build"].indexOf(id) >= 0) state.turn = 0;
    if (id === "jail") { state.turn = 2; }
    if (id === "ai" || id === "neuro") state.turn = 1;
    renderAll();
  }

  /* ----------------------------------------------------------------- render */
  var app = $("#app");
  function renderAll() {
    renderBoard();
    renderHeader();
    renderSeats();
    renderJournal();
    renderInspector();
    renderConsole();
    renderCenter();
    renderRails();
    renderToast();
    if (state.profile === "compact") renderRails();
  }
  function wireGlobal() {
    $("#btnSettings").addEventListener("click", function () { openSettings("players"); });
    $("#btnRules").addEventListener("click", openRules);
    $("#btnRestart").addEventListener("click", function () {
      openModal("confirm", "restart");
    });
    $("#btnLang").addEventListener("click", function () { setLocale(state.locale === "ru" ? "en" : "ru"); });
    $("#btnSkin").addEventListener("click", function () {
      var order = ["neuro", "evil", "default"];
      setTheme(order[(order.indexOf(state.theme) + 1) % order.length]);
      pushToast("ok", t("top.skin_tip") + ": " + state.theme);
    });
    $("#btnSound").addEventListener("click", function () {
      state.sound = !state.sound; state.set.sound = state.sound;
      $("#btnSound").classList.toggle("on", state.sound);
      pushToast("ok", t("modal.sound_tip", [t("settings." + (state.sound ? "sound_lbl" : "sound_lbl"))]));
    });
    $("#btnObserver").addEventListener("click", function () { scene(state.scene === "observer" ? "turn-human" : "observer"); });
    $("#btnAdmin").addEventListener("click", function () { openAdmin("quick"); });
    $("#btnSetClose").addEventListener("click", function () { closeOverlay(); if (state.scene === "settings") scene("turn-human"); });
    $("#btnSetReset").addEventListener("click", function () { pushToast("warn", t("settings.reset_tip")); });
    $("#btnSetRules").addEventListener("click", openRules);
    $("#btnSetPrimary").addEventListener("click", function () {
      closeOverlay();
      pushToast("ok", t("settings.start_tip"));
      scene("turn-human");
    });
    $$("#setTabs .tab").forEach(function (b) {
      b.addEventListener("click", function () { state.settingsTab = b.dataset.pane; renderSettings(); });
    });
    $("#ovSettings").addEventListener("click", function (e) { if (e.target === this) closeOverlay(); });
    $("#ovRules").addEventListener("click", function (e) { if (e.target === this) closeOverlay(); });
    $("#ovAdmin").addEventListener("click", function (e) { if (e.target === this) closeOverlay(); });
    $("#btnRulesBack").addEventListener("click", function () { closeOverlay(); if (state.scene === "rules") scene("turn-human"); });
    $("#btnSetClose"); /* no-op */
    $("#btnAdmClose").addEventListener("click", function () { closeOverlay(); if (state.scene === "admin") scene("turn-human"); });
    $$("#admTabs .tab").forEach(function (b) {
      b.addEventListener("click", function () { state.adminTab = b.dataset.pane; renderAdmin(); });
    });
    $("#btnInviteClose").addEventListener("click", function () { closeOverlay(); if (state.scene === "invite") scene("turn-human"); });
    $("#btnJrnExport").addEventListener("click", function () {
      var blob = new Blob([state.log.map(function (e) { return JSON.stringify(e); }).join("\n")], { type: "application/x-jsonl" });
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob); a.download = "journal_export.jsonl"; a.click();
      pushToast("ok", t("gv.journal_export_ok_title") + " — " + t("gv.journal_export_ok_body", [a.download]));
    });
    $("#btnInsClose").addEventListener("click", function () { state.insTile = null; renderInspector(); });
    $("#btnInsPin").addEventListener("click", function () { state.insPinned = !state.insPinned; $("#btnInsPin").classList.toggle("on", state.insPinned); });
    $$("[data-drawer-close]").forEach(function (b) { b.addEventListener("click", function () { openDrawer(""); }); });
    $("#flPlayer").addEventListener("change", renderJournal);
    $("#flType").addEventListener("change", renderJournal);
    $("#flMoney").addEventListener("change", renderJournal);

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        if (state.modal) return closeModal();
        if (state.overlay) return closeOverlay();
        if (state.drawer) return openDrawer("");
        return;
      }
      var k = e.key.toUpperCase();
      if (k === "B" && state.scene === "purchase") doBuy();
      if (k === "N" && (state.scene === "turn-human" || state.scene === "build" || state.scene === "move")) doEndTurn();
      if (e.key === "F1") { e.preventDefault(); openSettings("players"); }
      if (e.key === "F2") { e.preventDefault(); openRules(); }
      if (e.key === "F12") { e.preventDefault(); openAdmin("quick"); }
    });
    window.addEventListener("resize", function () { sizeApp(); });
  }

  /* --------------------------------------------------------------- size/zoom */
  var PRE = { "1440": [1440, 900], "1280": [1280, 720], "880": [880, 600], fluid: null };
  function sizeApp(preset, fit) {
    state.preset = preset != null ? preset : state.preset || "1440";
    state.fit = fit != null ? fit : state.fit !== false;
    var wrap = $("#appwrap");
    var p = PRE[state.preset];
    if (p) { app.style.width = p[0] + "px"; app.style.height = p[1] + "px"; }
    else {
      var f = $("#frame").getBoundingClientRect();
      app.style.width = Math.max(880, Math.floor(f.width) - 16) + "px";
      app.style.height = Math.max(600, Math.floor(f.height) - 16) + "px";
    }
    var aw = app.offsetWidth, ah = app.offsetHeight;
    var s = 1;
    if (state.fit) {
      var fr = $("#frame").getBoundingClientRect();
      s = Math.min(1, (fr.width - 16) / aw, (fr.height - 16) / ah);
    }
    app.style.transform = "scale(" + s + ")";
    wrap.style.width = Math.round(aw * s) + "px";
    wrap.style.height = Math.round(ah * s) + "px";
    computeProfile();
    renderAll();
  }

  /* ---------------------------------------------------------------- the probe */
  var SCENES = [
    ["cold", "Холодная"], ["settings", "Настройки"], ["turn-human", "Ход человека"],
    ["move", "Движение"], ["purchase", "Покупка"], ["auction", "Аукцион · свой"],
    ["auction-watch", "Аукцион · наблюдение"], ["trade", "Торг: составить"], ["trade-in", "Входящая сделка"],
    ["build", "Стройка/залог"], ["jail", "Тюрьма"], ["ai", "Ход ИИ"], ["neuro", "Ожидание Neuro"],
    ["reject", "Отказ движка"], ["win", "Конец игры"], ["observer", "Наблюдатель"],
    ["compact", "880×600"], ["rules", "Правила"], ["invite", "Приглашение"], ["join", "Лобби"],
    ["toasts", "Тосты"], ["empty", "Пустые состояния"], ["admin", "Админ"],
  ];
  function buildProbe() {
    var bar = $("#pbar");
    var html = '<span class="plabel">прототип · состояния</span>';
    html += SCENES.map(function (s) { return '<button data-scn="' + s[0] + '">' + s[1] + "</button>"; }).join("");
    html += '<span class="plabel">тема</span>' +
      ["neuro", "evil", "default"].map(function (x) { return '<button data-thm="' + x + '">' + x + "</button>"; }).join("");
    html += '<span class="plabel">язык</span><button data-loc="ru">RU</button><button data-loc="en">EN</button>';
    html += '<span class="plabel">окно</span>' +
      '<button data-pre="1440">1440×900</button><button data-pre="1280">1280×720</button>' +
      '<button data-pre="880">880×600</button><button data-pre="fluid">fluid</button>' +
      '<button data-fit="1">fit</button>';
    html += '<span class="plabel">аудит</span><span class="audit" id="auditOut">…</span>';
    bar.innerHTML = html;
    bar.querySelectorAll("[data-scn]").forEach(function (b) {
      b.addEventListener("click", function () {
        var id = b.dataset.scn;
        if (id === "compact") sizeApp("880");
        if (id === "join" && state.scene === "join") {
          var order = ["connecting", "joined", "failed", "none"];
          state.joinState = order[(order.indexOf(state.joinState) + 1) % order.length];
          renderJoin();
        } else {
          scene(id);
        }
        syncProbe();
      });
    });
    bar.querySelectorAll("[data-thm]").forEach(function (b) { b.addEventListener("click", function () { setTheme(b.dataset.thm); syncProbe(); }); });
    bar.querySelectorAll("[data-loc]").forEach(function (b) { b.addEventListener("click", function () { setLocale(b.dataset.loc); syncProbe(); }); });
    bar.querySelectorAll("[data-pre]").forEach(function (b) { b.addEventListener("click", function () { sizeApp(b.dataset.pre); syncProbe(); }); });
    syncProbe();
  }
  function syncProbe() {
    $$("#pbar [data-scn]").forEach(function (b) { b.classList.toggle("on", b.dataset.scn === state.scene); });
    $$("#pbar [data-thm]").forEach(function (b) { b.classList.toggle("on", b.dataset.thm === state.theme); });
    $$("#pbar [data-loc]").forEach(function (b) { b.classList.toggle("on", b.dataset.loc === state.locale); });
    $$("#pbar [data-pre]").forEach(function (b) { b.classList.toggle("on", b.dataset.pre === state.preset); });
    audit();
  }

  /* ------------------------------------------------------------------ audit */
  function roleOf(n) {
    if (n.classList && (n.classList.contains("t-value") || n.classList.contains("t-para"))) return n.classList.contains("t-value") ? "value" : "para";
    return null;
  }
  function audit() {
    /* the probe strip is scaffolding: exclude it and the sprite */
    var root = app;
    var counts = { value: 0, para: 0, unlabeled: [] };
    $$("*", root).forEach(function (n) {
      var direct = false;
      for (var i = 0; i < n.childNodes.length; i++) {
        var c = n.childNodes[i];
        if (c.nodeType === 3 && c.textContent.trim().length) { direct = true; break; }
      }
      if (!direct) return;
      var r = roleOf(n);
      if (r) counts[r]++;
      else counts.unlabeled.push(n.tagName.toLowerCase() + "." + (n.className || ""));
    });
    /* one stretching child per flex row */
    var growErr = [];
    $$("*", root).forEach(function (n) {
      var cs = getComputedStyle(n);
      if (cs.display !== "flex" && cs.display !== "inline-flex") return;
      if (!n.hasAttribute("data-nowrap-row")) {
        var g = $$(":scope > [data-grow]", n);
        if (g.length > 1) growErr.push((n.className || n.tagName) + " ×" + g.length);
      }
    });
    var missing = [];
    $$("[data-i18n], [data-i18n-tip]", root).forEach(function (n) {
      var k = n.dataset.i18n || n.dataset.i18nTip;
      if (!dict(k)) missing.push(k);
    });
    /* toasts must never overlap the board or the console */
    var overlap = "n/a";
    var tw = $("#toast"), tick = $("#ticker");
    if (state.profile !== "compact" && tw && tw.children.length) {
      var r1 = tw.getBoundingClientRect(), rb = $("#board").getBoundingClientRect(), ra = $("#act").getBoundingClientRect();
      var hit = !(r1.bottom < rb.top || r1.top > rb.bottom || r1.right < rb.left || r1.left > rb.right) ||
                !(r1.bottom < ra.top || r1.top > ra.bottom || r1.right < ra.left || r1.left > ra.right);
      overlap = hit ? "OVERLAP!" : "clear";
    } else if (state.profile === "compact") {
      overlap = "ticker-in-console";
    }
    var minok = app.clientWidth >= 880 && app.clientHeight >= 600;
    var out = $("#auditOut");
    out.innerHTML =
      '<span class="' + (counts.unlabeled.length ? "bad" : "ok") + '">roles ' + counts.value + "v/" + counts.para + "p/" + counts.unlabeled.length + "?</span>" +
      '<span class="' + (growErr.length ? "bad" : "ok") + '">grow ' + (growErr.length ? "×" + growErr.length : "ok") + "</span>" +
      '<span class="' + (missing.length ? "bad" : "ok") + '">i18n ' + (missing.length ? missing.slice(0, 3).join(",") : "ok") + "</span>" +
      '<span class="' + (overlap === "OVERLAP!" ? "bad" : "ok") + '">toast ' + overlap + "</span>" +
      '<span class="' + (minok ? "ok" : "bad") + '">min 880×600</span>';
  }

  /* -------------------------------------------------------------------- boot */
  function qp() {
    var out = {};
    location.search.replace(/^\?/, "").split("&").forEach(function (kv) {
      if (!kv) return;
      var i = kv.indexOf("=");
      out[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1));
    });
    return out;
  }
  function applyParams(p) {
    if (p.theme) setTheme(p.theme);
    if (p.anim === "off") { state.anim = false; app.dataset.anim = "off"; }
    if (p.probe === "off") document.body.classList.add("bare");
  }
  function populateFilters() {
    var fp = $("#flPlayer"), ft = $("#flType");
    fp.innerHTML = '<option value="">' + esc(t("fl.player")) + "</option>" +
      state.seats.map(function (s) { return '<option value="' + s.id + '">' + esc(s.name) + "</option>"; }).join("");
    var cats = ["roll", "money", "buy", "auction", "build", "card", "trade", "other"];
    ft.innerHTML = '<option value="">' + esc(t("fl.type")) + "</option>" +
      cats.map(function (c) { return '<option value="' + c + '">' + esc(t("ty." + c)) + "</option>"; }).join("");
  }
  function boot() {
    window.__errors = [];
    window.onerror = function (msg, src, line, col) {
      window.__errors.push(String(msg) + " @" + line + ":" + col);
      return false;
    };
    /* wrap the app so the "fit" zoom can size the scroll area correctly */
    var frame = $("#frame");
    var wrap = document.createElement("div");
    wrap.id = "appwrap";
    wrap.style.cssText = "flex:none;margin:auto;position:relative";
    frame.appendChild(wrap);
    wrap.appendChild(app);

    seedLog();
    wireGlobal();
    buildProbe();

    var p = qp();
    applyParams(p);
    populateFilters();

    var preset = p.size === "880x600" ? "880" : p.size === "1280x720" ? "1280" : "1440";
    sizeApp(preset, p.fit !== "0");
    scene(p.scene || "turn-human");
    if (p.tab) {
      state.settingsTab = p.tab; state.adminTab = p.tab;
      if (state.overlay === "settings") renderSettings();
      if (state.overlay === "admin") renderAdmin();
    }
    if (p.overlay === "settings") openSettings(state.settingsTab || "players");
    if (p.overlay === "rules") openRules();
    if (p.overlay === "admin") openAdmin(state.adminTab || "quick");
    if (p.join) { clearTimeout(state._joinT); state.joinState = p.join; renderJoin(); }
    setLocale(p.lang || "ru");
    renderAll();
    syncProbe();

    /* the demo loop: timers tick, the AI finishes its turn — off in static renders */
    if (p.static !== "1") {
      setInterval(function () {
        if (["turn-human", "purchase", "move", "jail", "auction", "trade-in", "build"].indexOf(state.scene) >= 0 && state.set.turn_timer > 0) {
          state.timer = state.timer > 1 ? state.timer - 1 : state.timerMax;
          renderHeader();
        }
        if (state.scene === "ai") {
          /* the AI plays itself after a beat, then it is the human's turn again */
          if (!state._aiT) {
            state._aiT = setTimeout(function () {
              state._aiT = null;
              if (state.scene !== "ai") return;
              var d1 = 1 + Math.floor(Math.random() * 6), d2 = 1 + Math.floor(Math.random() * 6);
              state.dice = { d1: d1, d2: d2, doubles: false, rolled: true };
              addLog("roll", 1, [d1, d2]);
              renderAll();
              setTimeout(function () { if (state.scene === "ai") { state.turn = 0; scene("turn-human"); } }, 1600);
            }, 1400);
          }
        }
      }, 1000);
    }

    /* hooks for the smoke run (design/tools/render_prototype.py) */
    window.__audit = audit;
    window.__smoke = function () {
      var br = $("#board").getBoundingClientRect();
      var ar = $("#act").getBoundingClientRect();
      var unresolved = $$(".app [data-i18n], .app [data-i18n-tip]").filter(function (n) {
        return !dict(n.dataset.i18n || n.dataset.i18nTip);
      }).length;
      var badText = /(\{%|undefined|NaN|\[object)/.test($("#app").textContent);
      return JSON.stringify({
        errors: window.__errors,
        scene: state.scene, theme: state.theme, locale: state.locale, profile: state.profile,
        app: [app.clientWidth, app.clientHeight],
        board: [Math.round(br.width), Math.round(br.height)],
        console: [Math.round(ar.width), Math.round(ar.height)],
        tiles: $$("#board .tile").length, tokens: $$("#board .token").length,
        journalRows: $$("#jrnList .jrow").length,
        unresolved: unresolved, badText: badText,
        modal: state.modal, overlay: state.overlay,
        timerRing: !!$(".timerring"),
        unlabeled: (function () { audit(); var el = $("#auditOut"); return el ? el.textContent : ""; })(),
      });
    };
    window.__ready = true;
    setTimeout(function () {
      var out = document.createElement("pre");
      out.id = "smokeOut";
      out.style.display = "none";
      out.textContent = window.__smoke();
      document.body.appendChild(out);
    }, 600);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
