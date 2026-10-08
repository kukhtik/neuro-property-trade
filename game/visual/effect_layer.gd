class_name EffectLayer
extends Control
## The effects overlay that sits ABOVE the ring (spec §5.6). It is not part of
## the board's layout: tokens, floating amounts and particles are positioned by
## pixel and never influence where a tile goes.
##
## Ownership:
##   - tokens   : one per player, moved step by step along tile centres
##   - floats   : "+$200" / "-$50" rising over a tile or a player card
##   - bursts   : a short particle spray on purchase/build
##   - cards    : the chance/chest reveal
##
## Rules honoured from the spec:
##   - movement is a Tween along tile centres (motion.step per cell, hop on each)
##   - a resize repositions WITHOUT animating
##   - positions come from BoardLayout rects, so a non-40 board just works
##   - everything respects `animations` being off (instant, no effect)
##
## Pure-ish: it owns no game state and never reads the engine.

const SkinManager := preload("res://visual/skin_manager.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")

var skin: SkinManager
var animations := true

var _tiles: Array = []          # BoardLayout output (rects)
var _cell: float = 64.0
var _tokens := {}               # pid -> Control
var _token_names := {}          # pid -> String
var _token_colors := {}         # pid -> Color
var _floats: Array = []         # active float nodes
var _moving := {}               # pid -> bool


func setup(p_skin: SkinManager, p_animations: bool = true) -> void:
	skin = p_skin
	animations = p_animations
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if skin == null:
		skin = SkinManager.new()
		skin.load_skin()


## Provide the layout (a BoardLayout.compute result) so tokens can be placed.
func set_layout(tiles: Array, cell: float) -> void:
	_tiles = tiles
	_cell = cell
	# reposition without animation — a resize must not look like a move
	for pid in _tokens:
		var t := _token_pos(int(pid), _player_pos.get(int(pid), 0))
		(_tokens[pid] as Control).position = t
	queue_redraw()

var _player_pos := {}   # pid -> tile index (for repositioning)


## Create/refresh one token per player.
func sync_tokens(players: Array) -> void:
	# remove tokens for players that are gone
	for pid in _tokens.keys():
		var found := false
		for p in players:
			if int(p.get("id", -1)) == int(pid):
				found = true
		if not found:
			(_tokens[pid] as Control).queue_free()
			_tokens.erase(pid)
			_player_pos.erase(pid)

	for p in players:
		var pid: int = int(p.get("id", -1))
		if pid < 0:
			continue
		_player_pos[pid] = int(p.get("pos", 0))
		_token_names[pid] = str(p.get("name", "?"))
		var ci: int = int(p.get("color_idx", pid))
		_token_colors[pid] = skin.player_color(ci)
		if not _tokens.has(pid):
			_tokens[pid] = _make_token(pid)
		_refresh_token_label(pid)
		var out: bool = bool(p.get("bankrupt", false))
		(_tokens[pid] as Control).visible = not out


func _make_token(pid: int) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 10
	var d: float = _token_size()
	holder.custom_minimum_size = Vector2(d, d)
	holder.size = Vector2(d, d)

	# a skin slot texture when the artist shipped one; otherwise a chamfer chip
	var slot_tex: Texture2D = skin.texture("token.shadow")   # presence probe only
	var body := Chamfer.new()
	body.set_skin(skin)
	body.fill_token = "accent"
	body.border_token = "line"
	body.cut = "tr"
	body.set_meta("fill_override", _token_colors.get(pid, skin.color("accent")))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.name = "Body"
	holder.add_child(body)

	var lbl := Label.new()
	lbl.name = "Initial"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", maxi(8, int(d * 0.5)))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(lbl)

	add_child(holder)
	return holder


func _refresh_token_label(pid: int) -> void:
	var holder: Control = _tokens.get(pid)
	if holder == null:
		return
	var lbl := holder.get_node_or_null("Body/Initial")
	if lbl != null:
		lbl.text = str(_token_names.get(pid, "?")).substr(0, 1).to_upper()
		lbl.add_theme_color_override("font_color", _contrast(_token_colors.get(pid, skin.color("accent"))))
	var body := holder.get_node_or_null("Body")
	if body != null and body is Chamfer:
		(body as Chamfer).set_meta("fill_override", _token_colors.get(pid, skin.color("accent")))
		body.queue_redraw()


func _token_size() -> float:
	return maxf(12.0, _cell * skin.metric("token_size", 0.027) * 12.0)


## Pixel position of a token on a tile, with a small fan when several share it.
func _token_pos(pid: int, tile_index: int) -> Vector2:
	var centre := _tile_centre(tile_index)
	if centre == Vector2.INF:
		return Vector2.ZERO
	var d: float = _token_size()
	# fan out co-located tokens so they do not hide each other
	var peers: Array = []
	for other in _player_pos:
		if int(_player_pos[other]) == tile_index:
			peers.append(int(other))
	peers.sort()
	var slot: int = peers.find(pid)
	if slot < 0:
		slot = 0
	if peers.size() > 1:
		var ox: float = (float(slot) - (peers.size() - 1) * 0.5) * d * 0.6
		return centre - Vector2(d, d) * 0.5 + Vector2(ox, -d * 0.5)
	return centre - Vector2(d, d) * 0.5


func _tile_centre(index: int) -> Vector2:
	for t in _tiles:
		if int(t.get("index", -1)) == index:
			var r: Rect2 = t["rect"]
			return r.position + r.size * 0.5
	return Vector2.INF


## Move a player's token along a path of tile indices, one hop per cell.
## When animations are off (or the path is long) it snaps to the end.
func move_player(pid: int, path: Array, snap: bool = false) -> void:
	if not _tokens.has(pid) or path.is_empty():
		return
	var last: int = int(path[path.size() - 1])
	if not animations or snap or _moving.get(pid, false):
		_player_pos[pid] = last
		(_tokens[pid] as Control).position = _token_pos(pid, last)
		return
	_moving[pid] = true
	var holder: Control = _tokens[pid]
	var step: float = skin.motion("step", 0.19)
	var hop: float = skin.motion("hop", 0.32)
	for idx in path:
		_player_pos[pid] = int(idx)
		var t := create_tween()
		t.tween_property(holder, "position", _token_pos(pid, int(idx)), step)
		# a small hop on each step, proportional to the token size
		var up: Vector2 = Vector2(0, -_token_size() * 0.25)
		t.parallel().tween_property(holder, "modulate", Color(1.2, 1.2, 1.2), step * 0.5)
		t.parallel().tween_property(holder, "modulate", Color.WHITE, step * 0.5)
		await t.finished
	_moving[pid] = false


## Teleport (jail) — a direct flight, no per-cell steps.
func teleport_player(pid: int, tile_index: int) -> void:
	if not _tokens.has(pid):
		return
	_player_pos[pid] = tile_index
	(_tokens[pid] as Control).position = _token_pos(pid, tile_index)


## A rising amount over a tile ("+$200" / "-$50").
func float_over_tile(tile_index: int, text: String, positive: bool) -> void:
	if not animations:
		return
	var centre := _tile_centre(tile_index)
	if centre == Vector2.INF:
		return
	float_at(centre, text, positive)


## A rising amount over a player's token (their card, visually).
func float_over_player(pid: int, text: String, positive: bool) -> void:
	if not animations:
		return
	var holder: Control = _tokens.get(pid)
	if holder == null:
		return
	float_at(holder.position + holder.size * 0.5, text, positive)


func float_at(at: Vector2, text: String, positive: bool) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", maxi(10, int(_cell * 0.22)))
	lbl.add_theme_color_override("font_color",
		skin.color("money") if positive else skin.color("danger"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = at - Vector2(20, 0)
	lbl.z_index = 20
	add_child(lbl)
	var rise: float = _cell * 0.9
	var d: float = skin.motion("pop", 0.5) * 2.0
	var t := create_tween()
	t.tween_property(lbl, "position:y", lbl.position.y - rise, d)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, d)
	t.finished.connect(func(): lbl.queue_free())


## A short particle burst over a tile (purchase/build). Pooled in the sense that
## it is a single _draw of short-lived points, not a node per particle.
func burst(tile_index: int, colour: Color, count: int = 12) -> void:
	if not animations:
		return
	var centre := _tile_centre(tile_index)
	if centre == Vector2.INF:
		return
	_bursts.append({"at": centre, "col": colour, "n": count, "t": 0.0, "life": skin.motion("pop", 0.5)})
	set_process(true)


var _bursts: Array = []


## Advance the running effects. Compacts IN PLACE: building a new array every frame
## (as this did) allocates once per frame for as long as any effect lasts — the exact
## moment the game is busiest.
func _process(delta: float) -> void:
	if _bursts.is_empty():
		set_process(false)
		return
	var i := _bursts.size() - 1
	while i >= 0:
		var b: Dictionary = _bursts[i]
		b["t"] = float(b["t"]) + delta
		if float(b["t"]) >= float(b["life"]):
			_bursts.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	for b in _bursts:
		var at: Vector2 = b["at"]
		var col: Color = b["col"]
		var prog: float = float(b["t"]) / maxf(0.001, float(b["life"]))
		var n: int = int(b["n"])
		for i in n:
			var ang: float = TAU * float(i) / float(n)
			var dist: float = _cell * (0.25 + prog * 0.6)
			var p: Vector2 = at + Vector2(cos(ang), sin(ang)) * dist
			var a: float = 1.0 - prog
			draw_circle(p, maxf(1.0, _cell * 0.03), Color(col.r, col.g, col.b, a))


func _contrast(bg: Color) -> Color:
	var lum: float = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color.BLACK if lum > 0.6 else Color.WHITE
