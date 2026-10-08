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
const SkinPaint := preload("res://visual/skin_paint.gd")

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
		_place_token(int(pid), _token_pos(int(pid), _player_pos.get(int(pid), 0)))
	queue_redraw()

var _player_pos := {}   # pid -> tile index (for repositioning)


## Put a token at a position and keep its shadow with it.
func _place_token(pid: int, at: Vector2) -> void:
	if _tokens.has(pid):
		(_tokens[pid] as Control).position = at
	var sh = _shadows.get(pid)
	if sh != null and is_instance_valid(sh):
		var d: float = _token_size()
		(sh as Control).position = at + Vector2(0, d * 0.88)
		(sh as Control).size = Vector2(d, maxf(3.0, d * 0.22))


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
	# the halo, behind everything: `0 0 14px var(--c)` in the mockup
	var col: Color = _token_colors.get(pid, skin.color("accent"))
	var halo := SkinPaint.token_halo(col, d)
	halo.name = "Halo"
	var pad := int(maxf(4.0, d * 0.16))
	halo.offset_left = -pad; halo.offset_top = -pad
	halo.offset_right = pad; halo.offset_bottom = pad
	holder.add_child(halo)

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

	# the mockup blurs a dark ellipse under each piece; without it a token floats
	var sh := SkinPaint.token_shadow(skin, d)
	sh.name = "Shadow %d" % pid
	sh.set_meta("owner", pid)
	sh.position = holder.position + Vector2(0, d * 0.92)
	sh.size = Vector2(d, maxf(3.0, d * 0.22))
	add_child(sh)
	_shadows[pid] = sh
	holder.set_meta("shadow", sh)
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
		_place_token(pid, _token_pos(pid, last))
		return
	_moving[pid] = true
	var holder: Control = _tokens[pid]
	var step: float = skin.motion("step", 0.19)
	var hop: float = skin.motion("hop", 0.32)
	for idx in path:
		_player_pos[pid] = int(idx)
		var t := create_tween()
		var target := _token_pos(pid, int(idx))
		t.tween_property(holder, "position", target, step)
		# the shadow travels with it — a shadow left behind reads as a second piece
		var sh = _shadows.get(pid)
		if sh != null and is_instance_valid(sh):
			t.parallel().tween_property(sh, "position",
				target + Vector2(0, _token_size() * 0.88), step)
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


## Show a floating value over a tile.
##
## The label and its tween are REUSED. Money events are the most frequent thing in a match
## and this used to build a Label and a Tween for each one and free them again, so the
## engine allocated most exactly when the game was busiest.
func float_at(at: Vector2, text: String, positive: bool) -> void:
	var lbl := _take_label()
	if lbl == null:
		return
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", maxi(10, int(_cell * 0.22)))
	lbl.add_theme_color_override("font_color",
		skin.color("money") if positive else skin.color("danger"))
	lbl.position = at - Vector2(20, 0)
	lbl.modulate = Color(1, 1, 1, 1)
	lbl.visible = true

	var rise: float = _cell * 0.9
	var d: float = skin.motion("pop", 0.5) * 2.0
	var t := _take_tween()
	t.tween_property(lbl, "position:y", lbl.position.y - rise, d)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, d)
	# return it to the pool instead of freeing it: the next event wants one immediately
	t.finished.connect(_give_label.bind(lbl), CONNECT_ONE_SHOT)


## The free label nearest to being idle. One is built only when the pool is dry AND small.
func _take_label() -> Label:
	for entry in _label_pool:
		if not entry["busy"]:
			entry["busy"] = true
			return entry["node"]
	if _label_pool.size() >= POOL_MAX:
		return null
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 20
	add_child(lbl)
	_label_pool.append({"node": lbl, "busy": true})
	return lbl


## Hand a label back and stop its tween so it can be reused.
func _give_label(lbl: Label) -> void:
	for entry in _label_pool:
		if entry["node"] == lbl:
			entry["busy"] = false
			break
	lbl.visible = false


## A tween to reuse. Creating one per event was the other half of the allocation.
func _take_tween() -> Tween:
	for t in _tween_pool:
		if t.is_valid() and not t.is_running():
			return t
	if _tween_pool.size() >= POOL_MAX:
		return create_tween()
	var t := create_tween()
	_tween_pool.append(t)
	return t


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

## Reused float labels and tweens. Bounded: a pool that grows without limit is just a
## slower leak.
const POOL_MAX := 48
var _label_pool: Array = []
var _shadows := {}          # pid -> the shadow node that follows its token
var _tween_pool: Array = []


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
