# Phase 5 — Visual / Stream Layer Implementation Plan

> Using the superpowers writing-plans skill. Executor assumed to have zero
> context on this repo — every task is self-contained with real file paths,
> real code, and exact verification commands.

Goal: add the visual board + stream overlay around the already-complete engine
so a windowed game is watchable and OBS-capturable, validating via screenshot
smoke + keeping all 146 headless tests green.

Architecture: code-built Control scene (no asset files) that reads the
spectator-safe projection + engine event log, animated by tweens, with
procedural SFX. Pure layout/theme math is in separate files that run headless.
Design rationale: `docs/superpowers/specs/2026-09-06-phase5-visual-layer-design.md`.

Tech stack: Godot 4.7.2 (gl_compatibility), GDScript, Control/Camera2D,
AudioStreamGenerator.

Branch convention: do this work on `phase5/visual-layer`, merge to `main`
after each tranche. Tests run headless: `godot --headless --path game --script
res://tests/run.gd` (exit 0 = pass, expect 146 initially). Masked-error rule:
when a test passes but a SCRIPT ERROR occurred, the runner still counts it as
pass — always `grep "SCRIPT ERROR"` the run output; must be zero.

---

### Task 0: Preflight — branch + settings fields

**Files:**
- 修改: `game/core/game_settings.gd`

- [ ] **Step 1: create feature branch + confirm baseline (146 green)**

```bash
cd ~/projects/neuro-property-trade
git checkout -b phase5/visual-layer
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |passed|PASSED|FAILED|SCRIPT ERROR"
```

- [ ] **Step 2: add `animations` stream toggle to GameSettings** (spec §4
  "disable animations for speed"). Add next to `event_overlay` (line 36):

```gdscript
var spectacle: bool = true
var event_overlay: bool = true
var animations: bool = true   # new — master toggle for cosmetic tweens
var rng_seed: int = 0
```

- [ ] **Step 3: verify settings tests still green, grep SCRIPT ERROR**

```bash
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |PASSED|FAILED|SCRIPT ERROR"
```

- [ ] **Step 4: Commit**

```bash
git add game/core/game_settings.gd
git commit -m "feat(settings): add animations stream toggle (spectacle control)"
```

---

### Task 1: Tile ring layout (pure math, headless-testable)

**Files:**
- 创建: `game/visual/tile_layout.gd`
- 测试: `game/tests/visual_layout_test.gd` (register in `run.gd`)

- [ ] **Step 1: create `game/visual/tile_layout.gd`**

```gdscript
class_name TileLayout
extends RefCounted
## Pure layout math for the 40-tile ring board. No scene nodes — headless
## testable. Standard 11x11 grid: 9 side cells + 2 corner cells per edge.
## Tile 0 is the bottom-left corner; movement is counterclockwise (0 -> 1 ..).

static func side_cells(tile_count: int) -> int:
    return (tile_count / 4) - 1   # 40/4 - 1 = 9 side cells between corners

static func grid_cells(tile_count: int) -> int:
    return side_cells(tile_count) + 2   # 11

## Cell center (in cell units) for a tile index. Top-left origin.
static func cell_center(index: int, tile_count: int) -> Vector2:
    var grid: int = grid_cells(tile_count)
    var s: int = grid - 1   # 0..grid-1 both inclusive
    var n := tile_count / 4
    var seg := index / n          # 0=bottom,1=right,2=top,3=left
    var off := index % n          # position within the segment
    match seg:
        0:  return Vector2(s - off, s)          # bottom row, right->left
        1:  return Vector2(0, s - off)          # right col, bottom->top
        2:  return Vector2(off, 0)              # top row, left->right
        3:  return Vector2(s, off)              # left col, top->bottom
    return Vector2.ZERO

## True when index is one of the four corner tiles.
static func is_corner(index: int, tile_count: int) -> bool:
    var n := tile_count / 4
    return index % n == 0   # 0, n, 2n, 3n

## Pixel center given cell size. Used by the scene; pure.
static func pixel_pos(index: int, tile_count: int, cell: int) -> Vector2:
    var c := cell_center(index, tile_count)
    return Vector2((c.x + 0.5) * cell, (c.y + 0.5) * cell)
```

- [ ] **Step 2: create test `game/tests/visual_layout_test.gd`**

```gdscript
extends RefCounted

static func test_list() -> Array[String]:
    return ["test_corners", "test_side_tiles", "test_grid_size",
            "test_bottom_segment_order", "test_pixel_pos"]

static func test_corners() -> String:
    var N := 40
    for idx in [0, 10, 20, 30]:
        if not TileLayout.is_corner(idx, N):
            return "expected corner at %d" % idx
    if TileLayout.is_corner(1, N): return "tile 1 not a corner"
    return ""

static func test_grid_size() -> String:
    if TileLayout.grid_cells(40) != 11: return "11x11 grid expected"
    if TileLayout.side_cells(40) != 9:  return "9 side cells expected"
    return ""

static func test_side_tiles() -> String:
    var N := 40
    # 9 side cells on bottom row: indices 1..9 -> x decreasing from 9 to 1, y=10
    var c := TileLayout.cell_center(1, N)
    if c.x != 9.0 or c.y != 10.0: return "tile1=%s want (9,10)" % c
    var c9 := TileLayout.cell_center(9, N)
    if c9.x != 1.0 or c9.y != 10.0: return "tile9=%s want (1,10)" % c9
    return ""

static func test_bottom_segment_order() -> String:
    var N := 40
    var c0 := TileLayout.cell_center(0, N)   # (10,10)
    var c1 := TileLayout.cell_center(1, N)   # (9,10)
    if c0.x - c1.x != 1.0: return "tiles 0..1 should step left (+x left) got %s,%s" % [c0, c1]
    return ""

static func test_pixel_pos() -> String:
    var p := TileLayout.pixel_pos(0, 40, 40)
    if p != Vector2(420, 420): return "pixel pos tile0=%s want (420,420)" % p
    return ""
```

- [ ] **Step 3: register in `game/tests/run.gd`** — add to the `modules` array:

```gdscript
"res://tests/visual_layout_test.gd",
```

- [ ] **Step 4: run headless, confirm test runs (+150), grep SCRIPT ERROR**

```bash
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |PASSED|FAILED|SCRIPT ERROR|test_corners|test_side_tiles|test_pixel_pos"
```

Note: `class_name TileLayout` is fine under `--script` because it's OUR class,
not the SDK's (SDK class_name globals don't resolve; ours do after `--import`).

- [ ] **Step 5: Commit**

```bash
git add game/visual/tile_layout.gd game/tests/visual_layout_test.gd game/tests/run.gd
git commit -m "feat(visual): tile ring layout math + tests (40-tile board)"
```

---

### Task 2: Theme palette (original, non-Hasbro)

**Files:**
- 创建: `game/visual/theme.gd`
- 测试: `game/tests/theme_test.gd` (register in run.gd)

- [ ] **Step 1: create `game/visual/theme.gd`** — pure data. Color groups map
  to the board.json `group` strings (brown, lightblue, pink, orange, red,
  yellow, green, darkblue) with ORIGINAL colors (no Hasbro trade dress — avoid
  the exact classic palette; use shifted hues). Also per-tile-type colors.

```gdscript
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
    "go": Color("3f8f5f"),
    "jail": Color("8a8f9a"),
    "go_to_jail": Color("8a8f9a"),
    "free_parking": Color("5a6a4a"),
    "tax": Color("6a3a3a"),
    "railroad": Color("4a4a4a"),
    "utility": Color("3a6a7a"),
    "chance": Color("a05a2a"),
    "community": Color("7a9a4a"),
    "property": Color("c8ccd4"),   # base; overridden by GROUP_COLORS
}

## Return the fill color for a tile entry (from a projection tile dict).
## Property -> group color; everything else -> type color.
static func tile_color(tile: Dictionary) -> Color:
    var t: String = tile.get("type", "property")
    if t == "property":
        var g: String = tile.get("group", "")
        return GROUP_COLORS.get(g, TYPE_COLORS["property"])
    return TYPE_COLORS.get(t, Color.WHITE)
```

- [ ] **Step 2: test `game/tests/theme_test.gd`**

```gdscript
extends RefCounted

static func test_list() -> Array[String]:
    return ["test_every_group_has_color", "test_type_coverage",
            "test_property_uses_group", "test_non_hasbro_hue"]

static func test_every_group_has_color() -> String:
    for g in ["brown", "lightblue", "pink", "orange", "red",
              "yellow", "green", "darkblue"]:
        if not BoardTheme.GROUP_COLORS.has(g):
            return "no color for group %s" % g
    return ""

static func test_type_coverage() -> String:
    for t in ["go", "jail", "go_to_jail", "free_parking", "tax",
              "railroad", "utility", "chance", "community", "property"]:
        if not BoardTheme.TYPE_COLORS.has(t):
            return "no color for type %s" % t
    return ""

static func test_property_uses_group() -> String:
    var c := BoardTheme.tile_color({"type": "property", "group": "red"})
    if c != BoardTheme.GROUP_COLORS["red"]:
        return "property should use group color"
    return ""

static func test_non_hasbro_hue() -> String:
    # Red group must NOT be the Hasbro deep-red on near-white; assert it's not
    # pure bright red and not identical to the classic #E11A14-ish.
    var r := BoardTheme.GROUP_COLORS["red"]
    if r.r > 0.9 and r.g < 0.2 and r.b < 0.2:
        return "red group too close to Hasbro red: %s" % r
    return ""
```

- [ ] **Step 3: register `"res://tests/theme_test.gd"` in run.gd modules**

- [ ] **Step 4: run + verify**

```bash
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |PASSED|SCRIPT ERROR"
```

- [ ] **Step 5: Commit**

```bash
git add game/visual/theme.gd game/tests/theme_test.gd game/tests/run.gd
git commit -m "feat(visual): original color theme + coverage/non-Hasbro tests"
```

---

### Task 3: Board view (Control tree builder + refresh)

**Files:**
- 创建: `game/visual/board_view.gd`
- 修改: nothing else here

- [ ] **Step 1: create `game/visual/board_view.gd`** — builds and repaints a
  code-built board. Uses `TileLayout` + `BoardTheme`. `refresh_state(proj)`
  updates ownership colors, house count labels, and token positions. Emits a
  `tile_clicked(index)` signal for future interactivity.

```gdscript
class_name BoardView
extends Control
## Code-built board from a projection + TileLayout/BoardTheme. Repaints on
## refresh_state(proj). Read-only downstream consumer of the engine projection.

signal tile_clicked(index: int)

const TileLayout := preload("res://visual/tile_layout.gd")
const BoardTheme := preload("res://visual/theme.gd")

var _tile_nodes: Array[PanelContainer] = []
var _name_labels: Array[Label] = []
var _house_labels: Array[Label] = []
var _tile_index := {}      # PanelContainer -> int
var _token_positions := {} # pid -> Control (the token panel)

## Build the board. Returns this control (chainable). tile_count from board.
func build(tile_count: int) -> Control:
    var cell := 64
    var grid := TileLayout.grid_cells(tile_count)
    var size := grid * cell
    custom_minimum_size = Vector2(size, size)
    set_size(Vector2(size, size))
    for i in tile_count:
        var panel = PanelContainer.new()
        var b := StyleBoxFlat.new()
        b.bg_color = Color("c8ccd4")
        b.corner_radius_top_left = 6
        b.corner_radius_top_right = 6
        b.corner_radius_bottom_left = 6
        b.corner_radius_bottom_right = 6
        panel.add_theme_stylebox_override("panel", b)
        panel.position = TileLayout.pixel_pos(i, tile_count, cell) - Vector2(cell / 2.0, cell / 2.0)
        panel.size = Vector2(cell, cell)
        panel.mouse_filter = Control.MOUSE_FILTER_STOP
        panel.gui_input.connect(_on_tile_input.bind(i))
        _tile_index[panel] = i

        var v = VBoxContainer.new()
        v.alignment = BoxContainer.ALIGNMENT_CENTER
        panel.add_child(v)
        var nm = Label.new()
        nm.text = str(i)
        nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        nm.add_theme_font_size_override("font_size", 12)
        v.add_child(nm)
        var hs = Label.new()
        hs.text = ""
        hs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hs.add_theme_font_size_override("font_size", 10)
        v.add_child(hs)

        _name_labels.append(nm)
        _house_labels.append(hs)
        _tile_nodes.append(panel)
        add_child(panel)
    return self

## Repaint from a spectator projection dictionary (for_spectator output).
func refresh_state(proj: Dictionary) -> void:
    var tiles: Array = proj.get("board", [])
    for entry in tiles:
        var idx: int = int(entry.get("index", 0))
        if idx < 0 or idx >= _tile_nodes.size(): continue
        var b := (_tile_nodes[idx].get_theme_stylebox("panel") as StyleBoxFlat)
        if b == null: continue
        b.bg_color = BoardTheme.tile_color(entry)
        _name_labels[idx].text = str(entry.get("name", ""))
        # houses / hotel
        var h: int = int(entry.get("houses", 0))
        var label := "."
        if h > 0 and h <= 4: label = "H" * h
        elif h == 5: label = "HOTEL"
        _house_labels[idx].text = label
    _place_tokens(proj.get("players", []))

func _place_tokens(players: Array) -> void:
    # Simple: clear previous token children, then add a small circle per player
    # on their tile. Full token_movement is Task 5; here we just repaint static.
    for pid in _token_positions:
        if is_instance_valid(_token_positions[pid]):
            _token_positions[pid].queue_free()
    _token_positions.clear()
    for p in players:
        var idx: int = int(p.get("position", 0))
        var pid: int = int(p.get("index", 0))
        if idx < 0 or idx >= _tile_nodes.size(): continue
        var tok = ColorRect.new()
        tok.color = _player_color(pid)
        tok.custom_minimum_size = Vector2(16, 16)
        tok.size = Vector2(16, 16)
        tok.position = _tile_nodes[idx].position + _token_offset(pid)
        add_child(tok)
        _token_positions[pid] = tok

func _token_offset(pid: int) -> Vector2:
    # stagger tokens within a tile so several players can share one
    var o := Vector2(8, 8)
    match pid % 4:
        0: return o
        1: return o + Vector2(16, 0)
        2: return o + Vector2(0, 16)
        _: return o + Vector2(16, 16)

func _player_color(pid: int) -> Color:
    var colors := [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.PURPLE]
    return colors[pid % colors.size()]

func _on_tile_input(ev: InputEvent, i: int) -> void:
    if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
        tile_clicked.emit(i)
```

- [ ] **Step 2: build check (headless import resolves our class_names)**

```bash
cd ~/projects/neuro-property-trade && godot --headless --path game --import . 2>&1 | grep -iE "error|script error" || echo "IMPORT OK (no script errors)"
```

- [ ] **Step 3: Commit**

```bash
git add game/visual/board_view.gd
git commit -m "feat(visual): code-built board view (layout+theme+repaint)"
```

---

### Task 4: Spectacle camera (auto-focus + active-player highlight)

**Files:**
- 创建: `game/visual/spectacle.gd`

- [ ] **Step 1: create `game/visual/spectacle.gd`** — a `Camera2D` controller.
  Reads engine events (`roll`/`move`/`purchase`) to tween to the active
  player's tile, and exposes zoom / animations toggles. Respects `animations`
  setting (if off, snaps instead of tweens).

```gdscript
class_name Spectacle
extends Camera2D
## Auto-focus camera (spec §4 spectacle). Reads engine events, tweens to the
## active action. Cosmetic only — never blocks the engine. Animations toggle
## (settings.animations): false => snap, no tween.

var _tile_layout: RefCounted
var _board_view: Control
var animations := true
var _target: Vector2 = Vector2.ZERO
var _tween: Tween

func setup(layout_ref: RefCounted, board: Control, cell: int, tile_count: int) -> void:
    _tile_layout = layout_ref
    _board_view = board
    zoom = Vector2(0.5, 0.5)   # show a wide area

func on_event(entry: Dictionary) -> void:
    var t: String = entry.get("type", "")
    if t not in ["roll", "move", "land", "purchase"]: return
    var tile_idx: int = -1
    if t == "roll":
        tile_idx = -1   # keep current; roll doesn't carry a tile yet
        return
    tile_idx = int(entry.get("tile", entry.get("to", -1)))
    if tile_idx < 0: return
    var target := _board_view.position + TileLayout.pixel_pos(tile_idx, 40, 64)
    _focus(target)

func _focus(world_pos: Vector2) -> void:
    if animations and _tween != null:
        _tween.kill()
    if animations:
        _tween = create_tween()
        _tween.tween_property(self, "position", world_pos, 0.4) \
            .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    else:
        position = world_pos

func set_animations(on: bool) -> void:
    animations = on
```

- [ ] **Step 2: import check (no script errors)**

```bash
godot --headless --path game --import . 2>&1 | grep -iE "error|script error" || echo "IMPORT OK"
```

- [ ] **Step 3: Commit**

```bash
git add game/visual/spectacle.gd
git commit -m "feat(visual): spectacle camera auto-focus + highlight"
```

---

### Task 5: Token movement (animated on move events)

**Files:**
- 创建: `game/visual/token_panel.gd`
- 修改: `game/visual/board_view.gd` (use it in `_place_tokens`)

- [ ] **Step 1: create `game/visual/token_panel.gd`**

```gdscript
class_name TokenPanel
extends Control
## A single animated player token. Moves to a tile on command, tweening if
## animations enabled. Cosmetic; never blocks the engine.

const TileLayout := preload("res://visual/tile_layout.gd")

var color: Color = Color.WHITE
var label: String = ""
var _animations := true
var _cell := 64
var _tile_count := 40

func setup(col: Color, lbl: String, tile_count: int, cell: int, start_idx: int) -> void:
    color = col
    label = lbl
    _tile_count = tile_count
    _cell = cell
    custom_minimum_size = Vector2(22, 22)
    size = Vector2(22, 22)
    var circ = ColorRect.new()
    circ.color = color
    circ.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(circ)
    var name_lbl = Label.new()
    name_lbl.text = label
    name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_lbl.add_theme_font_size_override("font_size", 9)
    add_child(name_lbl)
    move_to(start_idx, false)

func move_to(tile_idx: int, animate: bool) -> void:
    var p := _center_of(tile_idx)
    if animate and _animations:
        var tw = create_tween()
        tw.tween_property(self, "position", p, 0.25).set_trans(Tween.TRANS_SINE)
    else:
        position = p

func _center_of(tile_idx: int) -> Vector2:
    # board root is at (0,0); tiles are children of board_view at pixel_pos
    return TileLayout.pixel_pos(tile_idx, _tile_count, _cell) - Vector2(11, 11)
```

- [ ] **Step 2: wire tokens into `board_view.gd`** — replace `_place_tokens`'s
  static `ColorRect` approach with `TokenPanel`s kept in `_tokens` by pid, so
  on a "move" event we can animate the single panel. Add a method:

```gdscript
func refresh_tokens(players: Array) -> void:
    # create TokenPanel per player (or reuse), position at their tile
    for p in players:
        var pid: int = int(p.get("index", 0))
        var idx: int = int(p.get("position", 0))
        if _token_nodes.has(pid):
            _token_nodes[pid].move_to(idx, true)
        else:
            var tp = TokenPanel.new()
            tp.setup(_player_color(pid), str(p.get("name", "")), 40, 64, idx)
            add_child(tp)
            _token_nodes[pid] = tp
```

  (`TokenPanel` must be `preload`'d or referenced by class_name in board_view.)

- [ ] **Step 3: import + script-error check**

```bash
godot --headless --path game --import . 2>&1 | grep -iE "error|script error" || echo "IMPORT OK"
```

- [ ] **Step 4: Commit**

```bash
git add game/visual/token_panel.gd game/visual/board_view.gd
git commit -m "feat(visual): animated player tokens on move events"
```

---

### Task 6: Event overlay (stream overlay, spectator-safe)

**Files:**
- 创建: `game/visual/event_overlay.gd`
- 测试: `game/tests/overlay_test.gd` (register in run.gd) + a pure helper

- [ ] **Step 1: create `game/visual/event_messages.gd` (pure, testable)** — maps
  an event-log entry to a human-readable one-liner. Kept pure so it runs
  headless and never touches scene nodes.

```gdscript
class_name EventMessages
extends RefCounted
## Maps an event-log entry (type + data) to a short human-readable line.
## Pure — scene-free, so it's unit-testable headless.

static func describe(entry: Dictionary) -> String:
    var t: String = entry.get("type", "?")
    var d: Dictionary = entry.get("data", {})
    match t:
        "roll":
            return "🎲 %s rolled %d+%d" % [_who(d, "player"), int(d.get("d1", 0)), int(d.get("d2", 0))]
        "move":
            return "➡️ %s moved → %d" % [_who(d, "player"), int(d.get("to", d.get("new_pos", -1)))]
        "purchase":
            return "🏠 %s bought tile %d ($%d)" % [_who(d, "player"), int(d.get("tile", 0)), int(d.get("cost", 0))]
        "pay":
            return "💸 %s paid $%d" % [_who(d, "from"), int(d.get("amount", 0))]
        "rent":
            return "🪙 %s paid rent" % [_who(d, "from")]
        "build":
            return "🏗 %s built on tile %d" % [_who(d, "player"), int(d.get("tile", 0))]
        "bankrupt":
            return "💀 %s is bankrupt" % _who(d, "player")
        "jail":
            return "⛓ %s went to jail" % _who(d, "player")
        "go_bonus":
            return "🎁 %s collected GO bonus" % _who(d, "player")
        "tax":
            return "🧾 %s paid tax" % _who(d, "from")]
        "card_draw":
            return "🃏 %s drew a card" % _who(d, "player")
        "winner":
            return "🏆 %s WINS!" % _who(d, "player")
        "trade":
            return "🤝 trade completed"
        "auction_win":
            return "🔨 %s won auction" % _who(d, "winner")]
        "admin_override":
            return "🛠 admin override: %s" % _who(d, "op"]
        _:
            return "[%s]" % t

## helper — read a player field with a name fallback list passed in context
static func _who(d: Dictionary, key: String) -> String:
    var v = d.get(key, -1)
    if v is String: return str(v)
    return "p%s" % str(v)
```

- [ ] **Step 2: create `game/visual/event_overlay.gd`** — a `PanelContainer`
  (bottom-right) listing the last N event lines. `append(entry)` adds a line;
  `set_markdown(s)` replaces the body with the spectator markdown render.

```gdscript
class_name EventOverlay
extends PanelContainer
## Stream overlay (spec event_overlay). Shows recent event lines (spectator-
## safe: rendered from for_spectator data) + optional full markdown render.

const EventMessages := preload("res://visual/event_messages.gd")

var _list: Label
var _max_lines := 6

func _init() -> void:
    var b := StyleBoxFlat.new()
    b.bg_color = Color(0, 0, 0, 0.55)
    b.corner_radius_bottom_left = 8
    b.corner_radius_bottom_right = 8
    add_theme_stylebox_override("panel", b)
    set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    custom_minimum_size = Vector2(420, 200)
    _list = Label.new()
    _list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _list.add_theme_font_size_override("font_size", 13)
    add_child(_list)
    visible = true

func append(entry: Dictionary) -> void:
    var line := EventMessages.describe(entry)
    var parts := _list.text.split("\n")
    parts.append(line)
    if parts.size() > _max_lines: parts = parts.slice(parts.size() - _max_lines)
    _list.text = "\n".join(parts)

func set_markdown(md: String) -> void:
    _list.text = md  # fallback full render if preferred
```

- [ ] **Step 3: pure test `game/tests/overlay_test.gd`**

```gdscript
extends RefCounted

static func test_list() -> Array[String]:
    return ["test_describe_roll", "test_describe_purchase", "test_describe_pay",
            "test_spectator_no_private", "test_unknown_type_falls_through"]

static func test_describe_roll() -> String:
    var s := EventMessages.describe({"type": "roll", "data": {"player": 2, "d1": 4, "d2": 3}})
    if not s.contains("2"): return "roll line should mention player: %s" % s
    return ""

static func test_describe_purchase() -> String:
    var s := EventMessages.describe({"type": "purchase", "data": {"player": 0, "tile": 5, "cost": 200}})
    if not s.contains("$200"): return "should show cost: %s" % s
    return ""

static func test_describe_pay() -> String:
    var s := EventMessages.describe({"type": "pay", "data": {"from": 1, "amount": 50}})
    if not s.contains("50"): return "pay line should show amount: %s" % s
    return ""

static func test_spectator_no_private() -> String:
    # Overlay only ever renders from for_spectator; assert describe never
    # pulls private keys (no "get_out_of_jail_cards" leak).
    var s := EventMessages.describe({"type": "roll", "data": {"player": 0, "d1": 1, "d2": 1}})
    if s.contains("private") or s.contains("jail_card"):
        return "overlay must not leak private info: %s" % s
    return ""

static func test_unknown_type_falls_through() -> String:
    var s := EventMessages.describe({"type": "weird", "data": {}})
    if not s.contains("weird"): return "unknown type should echo: %s" % s
    return ""
```

- [ ] **Step 4: register `"res://tests/overlay_test.gd"` in run.gd + run**

```bash
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |PASSED|SCRIPT ERROR"
```

- [ ] **Step 5: Commit**

```bash
git add game/visual/event_messages.gd game/visual/event_overlay.gd game/tests/overlay_test.gd game/tests/run.gd
git commit -m "feat(visual): event overlay + messages + spectator-safe tests"
```

---

### Task 7: Procedural SFX

**Files:**
- 创建: `game/visual/sfx.gd` (+ optional test)

- [ ] **Step 1: create `game/visual/sfx.gd`** — tiny procedural synth using
  `AudioStreamGenerator` (no audio asset files). `play(type)` picks a short
  tone envelope per event type.

```gdscript
class_name Sfx
extends AudioStreamPlayer
## Procedural SFX — AudioStreamGenerator, no asset files. Simple tone blips per
## event type. Cosmetic; failure to play never affects the engine.

var _active := false
var _sample := 0
var _freq := 440.0
var _dur := 0.15
var _t := 0.0

const FREQS := {
    "roll": 660.0,
    "move": 520.0,
    "buy": 820.0,
    "purchase": 820.0,
    "pay": 300.0, "rent": 300.0, "tax": 300.0,
    "build": 700.0,
    "card": 560.0,
    "jail": 220.0,
    "bankrupt": 150.0,
    "winner": 990.0,
}

func _ready() -> void:
    stream = AudioStreamGenerator.new()
    var rate := 22050
    (stream as AudioStreamGenerator).mix_rate = rate
    var pb := stream.get_playback() as AudioStreamGeneratorPlayback
    # will be set on play

func play_type(t: String) -> void:
    if not (_freq in FREQS): return
    play_tonal(FREQS[t], 0.15)

func play_tonal(freq: float, dur: float) -> void:
    var gen := stream as AudioStreamGenerator
    var pb := stream.get_playback() as AudioStreamGeneratorPlayback
    if pb == null or not pb.can_push_buffer(gen.get_frames_available()):
        return
    var frames := int(dur * gen.mix_rate)
    var buf := PackedVector2Array()
    for i in frames:
        var phase := float(i) / gen.mix_rate * freq * TAU
        var env := 1.0 - float(i) / frames
        buf.push_back(Vector2(sin(phase) * env * 0.2, sin(phase) * env * 0.2))
    pb.push_buffer(buf)
```

- [ ] **Step 2: import check**

```bash
godot --headless --path game --import . 2>&1 | grep -iE "error|script error" || echo "IMPORT OK"
```

- [ ] **Step 3: Commit**

```bash
git add game/visual/sfx.gd
git commit -m "feat(visual): procedural SFX (no asset files)"
```

---

### Task 8: Assemble board_scene (main wiring)

**Files:**
- 创建: `game/visual/board_scene.gd`, `game/visual/board_scene.tscn`
- 修改: `game/main.gd`, `game/main.tscn`

- [ ] **Step 1: create `game/visual/board_scene.gd`** — the assembled scene:
  hosts BoardView + token layer + Spectacle (Camera2D) + EventOverlay + Sfx,
  subscribes to the engine's `EventLog.event_appended`.

```gdscript
class_name BoardScene
extends Control
## The assembled visual layer: board + tokens + spectacle camera + overlay + sfx.
## Reads the engine (spectator-safe) and event log. Read-only consumer.

const Projection := preload("res://sdk/projection.gd")
const MarkdownRenderer := preload("res://sdk/markdown_renderer.gd")
const TileLayout := preload("res://visual/tile_layout.gd")
const BoardView := preload("res://visual/board_view.gd")
const Spectacle := preload("res://visual/spectacle.gd")
const EventOverlay := preload("res://visual/event_overlay.gd")
const Sfx := preload("res://visual/sfx.gd")

var _engine
var _board_view
var _spectacle
var _overlay
var _sfx
var _settings

func setup(engine, settings) -> void:
    _engine = engine
    _settings = settings
    set_anchors_preset(Control.PRESET_FULL_RECT)

    _board_view = BoardView.new()
    _board_view.build(_engine.board.tile_count())
    add_child(_board_view)
    _board_view.position = Vector2(40, 40)

    _overlay = EventOverlay.new()
    add_child(_overlay)

    _spectacle = Spectacle.new()
    _spectacle.position = Vector2(0, 0)
    add_child(_spectacle)
    # spectacle camera will be made "current" by the scene; we drive it off events
    _sfx = Sfx.new()
    add_child(_sfx)

    # subscribe to engine event log (signal up, engine down: we receive)
    _engine.log.event_appended.connect(_on_engine_event)

    # initial paint
    var proj := Projection.new().for_spectator(_engine)
    _board_view.refresh_state(proj)
    _overlay.set_markdown(MarkdownRenderer.new().render_spectator(proj))
    _refresh_watchdog()

func _on_engine_event(entry: Dictionary) -> void:
    _sfx.play_type(entry.get("type", ""))
    _overlay.append(entry)
    var proj := Projection.new().for_spectator(_engine)
    _board_view.refresh_state(proj)
    _spectacle.on_event(entry)

# slow safety refresh (also catches non-append state changes like timer)
var _timer := 0.0
func _refresh_watchdog() -> void:
    _process_delta := 0.0
func _process(delta: float) -> void:
    _timer += delta
    if _timer >= 1.0:
        _timer = 0.0
        if _engine != null:
            var proj := Projection.new().for_spectator(_engine)
            _board_view.refresh_state(proj)
```

- [ ] **Step 2: create `game/visual/board_scene.tscn`**

```
[gd_scene load_steps=2 format=3 uid="uid://neuro_board_scene"]

[ext_resource type="Script" path="res://visual/board_scene.gd" id="1_bs"]

[node name="BoardScene" type="Control"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_bs")
```

- [ ] **Step 3: wire into `game/main.gd`** — instantiate the scene, pass engine
  + settings. Add after the admin panel setup:

```gdscript
const BoardScene := preload("res://visual/board_scene.gd")
...
var _board_scene
...
func _ready() -> void:
    ...
    _board_scene = BoardScene.new()
    _board_scene.name = "BoardScene"
    add_child(_board_scene)
    _board_scene.setup(_engine, s)
    ...
```

  Optionally change main.tscn root to a Node2D if the camera is to control the
  viewport; for the smoke test the Control root is fine (camera is ornamental).

- [ ] **Step 4: build + full headless suite (expect 150+, zero SCRIPT ERROR)**

```bash
godot --headless --path game --import . 2>&1 | grep -iE "script error" || echo "IMPORT OK"
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |PASSED|SCRIPT ERROR"
```

- [ ] **Step 5: Commit**

```bash
git add game/visual/board_scene.gd game/visual/board_scene.tscn game/main.gd game/main.tscn
git commit -m "feat(visual): assemble board scene into main entry point"
```

---

### Task 9: Windowed screenshot smoke runner

**Files:**
- 创建: `game/tools/visual_smoke.gd`, `game/tools/visual_smoke.tscn`

- [ ] **Step 1: create `game/tools/visual_smoke.gd`** — boots the assembled
  scene, drives N turns via `submit_intent` with the internal AI driver, then
  saves a screenshot and exits 0.

```gdscript
extends Node
## Windowed screenshot smoke: boots board_scene, drives a game, saves a PNG.
## Run: godot --path game res://tools/visual_smoke.tscn
## Expected: exits 0 (or 1 on failure) and writes visual_smoke_<n>.png in cwd.

const EngineScript := preload("res://core/engine.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const MinimalAction := preload("res://seats/minimal_action.gd")
const BoardScene := preload("res://visual/board_scene.gd")

var _engine
var _turns_done := 0
var _shot_count := 0
var _last_signal_key := ""

const MAX_TURNS := 8

func _ready() -> void:
    var s = Settings.new()
    var seats: Array = SeatConfig.from_settings(s)
    _engine = EngineScript.new()
    var names := []
    for seat in seats: names.append(seat.name)
    _engine.setup(s, names)

    var scene = BoardScene.new()
    scene.name = "BoardScene"
    add_child(scene)
    scene.setup(_engine, s)

    scene.position = Vector2(40, 40)

    # drive AI turns
    _step()

func _step() -> void:
    if _turns_done >= MAX_TURNS:
        _shot()
        _finish(0)
        return
    var holder := _decision_holder()
    if holder < 0:
        _shot()
        _finish(0)
        return
    var action := MinimalAction.pick(_engine, holder)
    var res = _engine.submit_intent(holder, action.action, action.params)
    if not res.get("ok", false):
        # not a decision point or transient — advance a step and continue
        pass
    # detect turn advancement
    _turns_done += 1
    _step.call_deferred()

func _decision_holder() -> int:
    for i in _engine.players.size():
        if _engine.legal_actions(i).size() > 0: return i
    return -1

func _shot() -> void:
    await get_tree().process_frame
    var img := get_viewport().get_texture().get_image()
    var path := "visual_smoke_%d.png" % _shot_count
    img.save_png(path)
    print("SAVED %s (%dx%d)" % [path, img.get_width(), img.get_height()])
    _shot_count += 1

func _finish(code: int) -> void:
    print("VISUAL SMOKE DONE: turns=%d shots=%d" % [_turns_done, _shot_count])
    get_tree().quit(code)
```

- [ ] **Step 2: create `game/tools/visual_smoke.tscn`**

```
[gd_scene load_steps=2 format=3 uid="uid://neuro_visual_smoke"]

[ext_resource type="Script" path="res://tools/visual_smoke.gd" id="1_vs"]

[node name="VisualSmoke" type="Node"]
script = ExtResource("1_vs")
```

- [ ] **Step 3: run windowed (headful) — must generate a PNG**

```bash
cd ~/projects/neuro-property-trade/game
godot --path game --editor --quit >/dev/null 2>&1 || true   # ensure import/cache
godot --path game res://tools/visual_smoke.tscn 2>&1 | tail -20
ls -la visual_smoke_*.png   # expect at least one PNG
```

  If `--path game` from inside game dir is wrong, run from repo root:
  `godot --path game res://tools/visual_smoke.tscn`.

- [ ] **Step 4: visually inspect the PNG** (open `visual_smoke_0.png`) — confirm
  the ring board, colored property tiles, tokens on tiles, overlay bottom-right.

- [ ] **Step 5: Commit**

```bash
git add game/tools/visual_smoke.gd game/tools/visual_smoke.tscn
git commit -m "feat(visual): windowed screenshot smoke runner"
```

---

### Task 10: Final verification + plan.md update + merge

**Files:**
- 修改: `docs/plan.md`

- [ ] **Step 1: full test ladder (headless + smoke)**

```bash
cd ~/projects/neuro-property-trade
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |PASSED|FAILED|SCRIPT ERROR"
# expect: all tests pass, ZERO SCRIPT ERROR, count > 146
pushd game && godot --path game res://tools/visual_smoke.tscn 2>&1 | grep -E "SAVED|DONE"; popd
```

- [ ] **Step 2: verify the overlay is spectator-safe** — grep the smoke output
  / overlay for any `get_out_of_jail_cards` or `"private"` string leak:

```bash
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -iE "private|jail_card" || echo "NO PRIVATE LEAK"
```

- [ ] **Step 3: update `docs/plan.md`** — mark Phase 5 visual-layer items done
  (`[x]`), add a "Phase 5 COMPLETE" block with the new test count, and refresh
  the "Handoff — next session" section: note deferred items (live tile-cost
  tweak, deck-card insert/remove, player reorder, redo-turn-with-seed,
  token-guarded remote admin, real evil over second SDK connection, voice-chat,
  in-browser WebGL validation).

- [ ] **Step 4: merge to main + push**

```bash
git checkout main
git merge phase5/visual-layer
# if conflicts: resolve in favor of main's plan.md structure, keep code changes
godot --headless --path game --script res://tests/run.gd 2>&1 | grep -E "ran |PASSED"
git push origin main
git branch -d phase5/visual-layer
```

- [ ] **Step 5: update the dev skill** — append a Phase 5 "DONE" note to
  `game-dev/neuro-property-trade-dev` skill and note the windowed-screenshot
  validation approach (headful under llvmpipe works).
```

---

### Self-review (per superpowers skill)

**Spec coverage:** goal 1 (board scene) = Tasks 1–3, 5, 8; goal 2 (spectacle)
= Task 4 + settings `animations` (Task 0); goal 3 (SFX) = Task 7; goal 4
(replay/overlay) = Task 6; goal 5 (screenshot validation) = Task 9. All five
plan.md handoff bullets covered. Deferred list is explicitly out of scope.

**Placeholder scan:** no "TBD"/"later"; every step has real file names, real
code, real shell commands. `_who` in event_messages is a real helper.

**Type consistency:** `TileLayout.pixel_pos(index, tile_count, cell)` used
consistently in board_view, spectacle, token_panel, and layout test.
`for_spectator` is called on `Projection.new().for_spectator(...)` consistently
(matches Phase 4 lesson: non-static, instantiate first). `TokenPanel` /
`BoardView` / `Spectacle` / `EventOverlay` / `Sfx` class names are used
consistently after `preload`. `EventLog.event_appended(entry: Dictionary)`
matches event_log.gd signal signature.

**Note on `_who`:** `event_messages._who` reads `player`/`from`/`winner`/`op`
which are ints in the engine's log data — returns `p<int>`. Fine for overlay.
