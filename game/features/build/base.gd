extends Node2D
## 母船可走動 hub（GD §5/§6）：單層俯視 ＋ 電梯切層（布局來自 Drawing2.dxf → DeckLayout）。
## 一次只顯示玩家所在的一層俯視平面；走到電梯格（X）按 E 開樓層選單切層。
## 操作：WASD 移動；E 互動（電梯／AI 控制台）；藍圖模式選模塊→左鍵放置；R 旋轉；右鍵移除；C 船員；K 防衛戰；F 修復。

const CELL := 48
const ALLOY := &"alloy"
const CABIN_TEX := preload("res://assets/cabin.png")   # 艙室底圖：四邊牆＋四邊中央門口（碰撞與此一致）
const DOOR_FRAC := 0.40   # 每格四邊出入口（門）寬＝格寬的比例（中門）；跨格須對準門中央才通得過
const LAYOUT_VERSION := 4            # 多層常駐尋路＋門碰撞（船員跨層搭電梯）
const START_DECK := 3                # 核心層起步
const CONSOLE_DECK := 3              # AI 控制台所在層（核心層）
const CONSOLE_CELL := Vector2i(4, 6) # 核心層內的控制台格
const CONSOLE_RANGE := 1.4 * CELL
const CREW_DECK := 3                 # 範例船員所在層
# 滾輪縮放：相對「單層填滿畫面」的基準，最小 40%、最大 300%。
const ZOOM_MIN := 0.4
const ZOOM_STEP := 1.1
const CATEGORIES := [
	[&"power", "module.cat.power"],
	[&"production", "module.cat.production"],
	[&"research", "module.cat.research"],
	[&"life", "module.cat.life"],
	[&"defense", "module.cat.defense"],
	[&"special", "module.cat.special"],
]

var _map_open := false

var _active_deck := START_DECK
var _grid: GridModel                                 # 當前層的網格（＝_deck_grids[_active_deck] 別名）
var _deck_grids: Array[GridModel] = []               # 七層常駐網格（跨層尋路：他層也要可走圖）
var _deck_navs: Array[NavigationCore] = []           # 七層常駐尋路圖
var _deck_placements: Dictionary = {}                # deck(int) -> Array[{id,col,row,rot}] 各層持久佈局
var _resources: ResourceStore
var _modules: Array[ModuleData] = []
var _selected: ModuleData = null
var _rot := 0
var _hover_cell := Vector2i(-1, -1)
var _net_flux := 0
var _powered: Dictionary = {}
var _player: Node2D
var _cam: CameraRig
var _base_zoom := 1.0        # 當前層填滿畫面的基準縮放
var _zoom_factor := 1.0      # 滾輪倍率（相對基準・上限見 _zoom_max）
var _zoom_max := 3.0         # 滾輪倍率上限：每層動態算到「單格佔畫面 50%」（_focus_camera 設定）
var _origin_px := Vector2.ZERO

var _crew: Array[CrewMember] = []
var _crew_panel: CrewPanel
var _crew_panel_layer: CanvasLayer
var _nav: NavigationCore                             # 當前層尋路（＝_deck_navs[_active_deck] 別名）
var _hud_clock: Label
var _blueprint_open := false
var _toolbar: PanelContainer
var _palette_category: StringName = &"power"
var _module_btn_box: HBoxContainer
var _cat_buttons: Dictionary = {}
var _wave: WaveSystem
var _module_hp: Dictionary = {}
var _floor_layer: CanvasLayer        # 電梯樓層選單

var _hud_alloy: Label
var _hud_flux: Label
var _hud_sel: Label
var _hud_layer: Label
var _hint: Label
var _console_hint: Label
var _hud_inv: Label

func _ready() -> void:
	_resources = ResourceStore.new({ALLOY: 1000})
	if not Save.world.has("compatibility"):
		Save.world["compatibility"] = 15
	EventBus.planet_selected.connect(_on_planet_selected)
	_load_modules()
	var loaded := _load_base()
	if not loaded:
		_deck_placements = _default_starters()
		_active_deck = START_DECK
	_build_all_decks()
	_build_ui()
	_spawn_player_and_camera()
	_spawn_crew()
	_recompute_flux()
	if not loaded:
		_save_base()   # 首次或舊版佈局 → 立即寫入 v3
	queue_redraw()

# --- 七層布局 / 當前層網格 ---

## 首次起始佈局：功能性起始模塊放在核心層的可建格（船員與電力用；固定艙身分待下一輪對應）。
func _default_starters() -> Dictionary:
	return {
		3: [
			{"id": "main_reactor", "col": 0, "row": 6, "rot": 0},
			{"id": "crew_quarters", "col": 3, "row": 6, "rot": 0},
			{"id": "cafeteria", "col": 7, "row": 8, "rot": 0},
			{"id": "morale_bay", "col": 5, "row": 9, "rot": 0},
		],
	}

## 用 DeckLayout 建一層網格：可建格(c/m/o)＋電梯格(X)＝EMPTY(可走)；固定/空格＝LOCKED。
func _make_grid_for_deck(d: int) -> GridModel:
	var cols := DeckLayout.deck_cols(d)
	var rows := DeckLayout.deck_rows(d)
	var g := GridModel.new(cols, rows)
	for r in rows:
		for c in cols:
			if DeckLayout.is_buildable(d, c, r) or DeckLayout.is_elevator(d, c, r):
				g.set_unlocked(Vector2i(c, r))
	for p in _deck_placements.get(d, []):
		var m := _find_module(StringName(str(p.get("id", ""))))
		if m:
			g.place(Vector2i(int(p["col"]), int(p["row"])), m, int(p.get("rot", 0)))
	return g

## 為全部七層常駐建立 grid＋nav（跨層模擬：他層也要可走圖供船員尋路）。
func _build_all_decks() -> void:
	_deck_grids.clear()
	_deck_navs.clear()
	for d in DeckLayout.deck_count():
		var g := _make_grid_for_deck(d)
		var n := NavigationCore.new()
		n.build(g, PackedInt32Array())
		_deck_grids.append(g)
		_deck_navs.append(n)
	_grid = _deck_grids[_active_deck]
	_nav = _deck_navs[_active_deck]

## 重建當前層尋路（放置/移除模塊後）。模塊可穿過 → 連通其實不變，仍重建保險。
func _build_nav() -> void:
	_nav.build(_grid, PackedInt32Array())

## 把當前層 placements 收回 _deck_placements（切層/存檔前呼叫）。
func _persist_active_deck() -> void:
	var arr: Array = []
	for p in _grid.placements:
		arr.append({"id": String(p.module.id), "col": p.origin.x, "row": p.origin.y, "rot": int(p.get("rot", 0))})
	_deck_placements[_active_deck] = arr

func _process(_delta: float) -> void:
	_hover_cell = _world_to_cell(get_global_mouse_position())
	_hud_layer.text = "甲板 Deck：%s (%d/%d)" % [
		DeckLayout.deck_name(_active_deck), _active_deck + 1, DeckLayout.deck_count()]
	_hud_clock.text = "%s  Day %d  %s" % [Localization.t("ui.base.clock"), ShipClock.day, ShipClock.hhmm()]
	if _on_elevator():
		_console_hint.visible = true
		_console_hint.text = "▶ E 搭電梯切換樓層"
	elif _near_console():
		_console_hint.visible = true
		_console_hint.text = "▶ " + Localization.t("ui.starmap.open_hint")
	else:
		_console_hint.visible = false
	queue_redraw()

func _player_cell() -> Vector2i:
	return _world_to_cell(_player.position) if _player != null else Vector2i(-1, -1)

func _on_elevator() -> bool:
	if _player == null:
		return false
	var c := _player_cell()
	return DeckLayout.is_elevator(_active_deck, c.x, c.y)

func _console_world_pos() -> Vector2:
	return _cell_center(CONSOLE_CELL)

func _near_console() -> bool:
	return _player != null and _active_deck == CONSOLE_DECK \
		and _player.position.distance_to(_console_world_pos()) <= CONSOLE_RANGE

# --- 電梯切層 ---

func _elevator_cells(d: int) -> Array:
	var out: Array = []
	for r in DeckLayout.deck_rows(d):
		for c in DeckLayout.deck_cols(d):
			if DeckLayout.is_elevator(d, c, r):
				out.append(Vector2i(c, r))
	return out

func _open_floor_selector() -> void:
	if _floor_layer != null:
		_close_floor_selector()
		return
	_floor_layer = CanvasLayer.new()
	add_child(_floor_layer)
	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.position = Vector2(vp.x * 0.5 - 130, vp.y * 0.5 - 200)
	_floor_layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(260, 0)
	panel.add_child(col)
	var title := Label.new()
	title.text = "升降骨幹 — 選擇樓層"
	col.add_child(title)
	for d in DeckLayout.deck_count():   # 由上(船首)而下(船尾)
		var b := Button.new()
		var mark := "● " if d == _active_deck else "   "
		b.text = "%s%s (%d/%d)" % [mark, DeckLayout.deck_name(d), d + 1, DeckLayout.deck_count()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = (d == _active_deck)
		b.pressed.connect(_travel_to_deck.bind(d))
		col.add_child(b)
	var cancel := Button.new()
	cancel.text = "取消 (Esc)"
	cancel.pressed.connect(_close_floor_selector)
	col.add_child(cancel)

func _close_floor_selector() -> void:
	if _floor_layer != null:
		_floor_layer.queue_free()
		_floor_layer = null

func _travel_to_deck(d: int) -> void:
	_close_floor_selector()
	if d == _active_deck:
		return
	var from_cell := _player_cell()
	_persist_active_deck()
	_active_deck = d
	_grid = _deck_grids[d]      # 切到常駐網格（不重建）
	_nav = _deck_navs[d]
	# 落在目標層離原欄最近的電梯格
	var evs := _elevator_cells(d)
	var dest: Vector2i = evs[0] if not evs.is_empty() else Vector2i(DeckLayout.deck_cols(d) / 2, DeckLayout.deck_rows(d) / 2)
	for e in evs:
		if absi(e.x - from_cell.x) < absi(dest.x - from_cell.x):
			dest = e
	_player.position = _cell_center(dest)
	_update_crew_visibility()
	_recompute_flux()
	_focus_camera()
	_save_base()
	_hint.text = "已抵達 " + DeckLayout.deck_name(d)
	_update_hud()
	queue_redraw()

func _open_star_map() -> void:
	if _map_open:
		return
	_map_open = true
	var map: Node = load("res://features/starmap/star_map.tscn").instantiate()
	map.process_mode = Node.PROCESS_MODE_ALWAYS
	map.tree_exited.connect(func(): _map_open = false)
	add_child(map)
	get_tree().paused = true

func _on_planet_selected(planet_id: StringName) -> void:
	Save.run["planet_id"] = String(planet_id)
	Save.save_layer("run", Save.run)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://features/expedition/expedition.tscn")

func _load_modules() -> void:
	var dir := DirAccess.open("res://data/modules/")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tres"):
				var m: ModuleData = load("res://data/modules/" + f)
				if m:
					_modules.append(m)
			f = dir.get_next()
	_modules.sort_custom(func(a, b): return a.cost < b.cost)

# --- 存檔（§13-10.A/C）---

func _save_base() -> void:
	_persist_active_deck()
	var decks: Dictionary = {}
	for d in _deck_placements:
		decks[str(d)] = _deck_placements[d]
	Save.meta["base"] = {
		"v": LAYOUT_VERSION, "alloy": _resources.get_amount(ALLOY),
		"active_deck": _active_deck, "decks": decks,
	}
	Save.save_layer("meta", Save.meta)

func _load_base() -> bool:
	if not Save.meta.has("base"):
		return false
	var data: Dictionary = Save.meta["base"]
	if int(data.get("v", 1)) != LAYOUT_VERSION:
		return false   # 舊版佈局作廢，重生起始艙
	_deck_placements.clear()
	var decks: Dictionary = data.get("decks", {})
	for k in decks:
		_deck_placements[int(k)] = decks[k]
	_active_deck = int(data.get("active_deck", START_DECK))
	_resources = ResourceStore.new({ALLOY: int(data.get("alloy", 1000))})
	return true

# --- 玩家 / 鏡頭 ---

func _spawn_player_and_camera() -> void:
	_player = load("res://entities/player/player.tscn").instantiate()
	_player.position = _cell_center(_spawn_cell())
	_player.collision_resolver = _player_collision
	add_child(_player)
	_cam = CameraRig.new()      # 邊緣捲動 + 中鍵回玩家中心
	_cam.home = _player
	add_child(_cam)
	_cam.make_current()
	_focus_camera()

## 起步格：當前層離中心最近的可走格。
func _spawn_cell() -> Vector2i:
	var cols := DeckLayout.deck_cols(_active_deck)
	var rows := DeckLayout.deck_rows(_active_deck)
	var center := Vector2i(cols / 2, rows / 2)
	var best := center
	var best_d := 1 << 30
	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			if _walkable_cell(cell):
				var dd := absi(c - center.x) + absi(r - center.y)
				if dd < best_d:
					best_d = dd
					best = cell
	return best

## 鏡頭：對準當前層、縮放讓整層俯視平面填入畫面（＝基準縮放，滾輪倍率疊在其上）。
func _focus_camera() -> void:
	if _cam == null:
		return
	var cols := DeckLayout.deck_cols(_active_deck)
	var rows := DeckLayout.deck_rows(_active_deck)
	var vp := get_viewport().get_visible_rect().size
	_base_zoom = minf(vp.x * 0.82 / (cols * CELL), vp.y * 0.60 / (rows * CELL))
	# 最大放大倍率：至少能讓單一艙室(1 格)佔畫面寬 50%（不低於原本 3×）
	_zoom_max = maxf(3.0, (0.5 * vp.x / CELL) / _base_zoom)
	_cam.global_position = Vector2(cols * CELL * 0.5, rows * CELL * 0.5)
	_apply_zoom()

func _apply_zoom() -> void:
	if _cam != null:
		var z := _base_zoom * _zoom_factor
		_cam.zoom = Vector2(z, z)

## 滾輪縮放：倍率夾在 [40%, 300%]（相對單層填滿畫面的基準）。
func _adjust_zoom(mult: float) -> void:
	_zoom_factor = clampf(_zoom_factor * mult, ZOOM_MIN, _zoom_max)
	_apply_zoom()

func _cell_center(c: Vector2i) -> Vector2:
	return _origin_px + Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)

func _world_to_cell(world: Vector2) -> Vector2i:
	var local := world - _origin_px
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))

## 可走格＝當前層 EMPTY（可建/電梯）。模塊可穿過 → 不再排除被佔據格。
func _walkable_cell(c: Vector2i) -> bool:
	return _grid.in_bounds(c) and _grid.cell_state(c) == GridModel.Cell.EMPTY

## 移動碰撞（門模型）：模塊可穿過；格與格之間有牆，只有四邊中央的門（DOOR_FRAC 寬）可通過。
## 逐軸處理（每幀位移 < CELL，至多跨一格）；撞牆則貼邊、另一軸仍可滑動。
func _player_collision(from: Vector2, to: Vector2) -> Vector2:
	var x := _axis_resolve(from, to.x, true)
	var y := _axis_resolve(Vector2(x, from.y), to.y, false)
	return Vector2(x, y)

## 單軸移動解析：horizontal=true 解 X（跨垂直邊），false 解 Y（跨水平邊）。
## 假設 _origin_px == 0（格線落在 CELL 整數倍）。回傳該軸允許到達的座標。
func _axis_resolve(p: Vector2, target: float, horizontal: bool) -> float:
	var cur := p.x if horizontal else p.y
	if absf(target - cur) < 0.0001:
		return target
	var dir := 1.0 if target > cur else -1.0
	var cell_idx := floori(cur / CELL)
	var boundary := float((cell_idx + (1 if dir > 0.0 else 0)) * CELL)   # 前方最近的格界線
	if (dir > 0.0 and target <= boundary) or (dir < 0.0 and target >= boundary):
		return target   # 同格內，未跨界
	# 會跨界 → 檢查門口對齊 ＋ 目標格可走
	var other := p.y if horizontal else p.x         # 不變軸座標
	var lane := floori(other / CELL)                # 沿邊的格索引（門中心所在）
	var door_center := lane * CELL + CELL * 0.5
	var in_door := absf(other - door_center) <= DOOR_FRAC * CELL * 0.5
	var ncell := Vector2i(cell_idx + int(dir), lane) if horizontal else Vector2i(lane, cell_idx + int(dir))
	if in_door and _walkable_cell(ncell):
		return target
	return boundary - dir * 0.01   # 被牆擋：貼邊

# --- 船員（範例・僅在其所屬層活動）---

func _spawn_crew() -> void:
	var sched: CrewSchedule = load("res://data/crew/schedule_default.tres")
	var roster := [
		[load("res://data/crew/eng_rivet.tres"), Vector2i(2, 9), &"main_reactor"],
		[load("res://data/crew/med_luna.tres"), Vector2i(6, 9), &""],
	]
	for entry in roster:
		var crew := CrewMember.new()
		crew.data = entry[0]
		crew.schedule = sched
		crew.assigned_module = entry[2]
		crew.home_deck = CREW_DECK
		crew.world = self
		crew.position = _cell_center(entry[1])
		add_child(crew)
		_setup_crew_deck(crew, CREW_DECK)
		_crew.append(crew)
	_update_crew_visibility()

## 跨層模擬：船員一律持續運作（在各自 home_deck 尋路移動）；只有與玩家同層者顯示。
func _update_crew_visibility() -> void:
	for c in _crew:
		c.visible = (c.home_deck == _active_deck)

## 把某層的尋路環境注入船員（spawn / 搭電梯換層時）。
func _setup_crew_deck(crew: CrewMember, deck: int) -> void:
	crew.setup_nav(_deck_navs[deck], _deck_grids[deck], _origin_px, CELL, _elevator_cells(deck))

# --- 跨層尋路服務（供 CrewMember 查詢，自己搭電梯找到正確樓層）---

## 全船最近的指定模塊：回傳 {"deck": int, "placement": Dictionary}；找不到回 {}。
## 距離＝同層曼哈頓近似 ＋ 換層懲罰，傾向選同層或鄰層者。
func crew_find_module(id: StringName, from_deck: int, from_cell: Vector2i) -> Dictionary:
	if id == &"":
		return {}
	var best: Dictionary = {}
	var best_d := INF
	for d in _deck_grids.size():
		for p in _deck_grids[d].placements:
			if p.module.id != id:
				continue
			var dd := Vector2(p.origin - from_cell).length() + absi(d - from_deck) * 64.0
			if dd < best_d:
				best_d = dd
				best = {"deck": d, "placement": p}
	return best

## 船員搭電梯進入某層：重設尋路環境、落在該層離原欄最近的電梯格、依玩家所在層決定顯示。
func crew_enter_deck(crew: CrewMember, deck: int, from_col: int) -> void:
	var evs := _elevator_cells(deck)
	var dest: Vector2i = evs[0] if not evs.is_empty() else Vector2i(DeckLayout.deck_cols(deck) / 2, DeckLayout.deck_rows(deck) / 2)
	for e in evs:
		if absi(e.x - from_col) < absi(dest.x - from_col):
			dest = e
	crew.home_deck = deck
	crew.position = _cell_center(dest)
	_setup_crew_deck(crew, deck)
	crew.visible = (deck == _active_deck)

func _toggle_crew_panel() -> void:
	if _crew.is_empty() or _active_deck != CREW_DECK:
		return
	var target := _nearest_crew_to_player()
	if _crew_panel_layer != null:
		if _crew_panel.get_bound() == target:
			_crew_panel_layer.queue_free()
			_crew_panel_layer = null
			_crew_panel = null
		else:
			_crew_panel.bind(target)
		return
	_crew_panel_layer = CanvasLayer.new()
	add_child(_crew_panel_layer)
	_crew_panel = load("res://ui/crew_panel.tscn").instantiate()
	_crew_panel.position = Vector2(20, 140)
	_crew_panel_layer.add_child(_crew_panel)
	_crew_panel.bind(target)

func _nearest_crew_to_player() -> CrewMember:
	var best: CrewMember = _crew[0]
	var best_d := INF
	for c in _crew:
		var d := c.position.distance_to(_player.position)
		if d < best_d:
			best_d = d
			best = c
	return best

# --- 裂潮防衛戰（偶發・GD §8/§13-7・當前層）---

func _trigger_wave() -> void:
	if _wave == null:
		_wave = WaveSystem.new()
		add_child(_wave)
		_wave.setup(self)
	_wave.advance_trigger()

func _module_hp_max(p: Dictionary) -> int:
	return 40 + int(p.module.cost)

func _placement_by_id(pid: int) -> Dictionary:
	for p in _grid.placements:
		if p.id == pid:
			return p
	return {}

func init_module_hp() -> void:
	_module_hp.clear()
	for p in _grid.placements:
		_module_hp[p.id] = _module_hp_max(p)

func is_module_disabled(pid: int) -> bool:
	return _module_hp.has(pid) and int(_module_hp[pid]) <= 0

func alive_module_placements() -> Array:
	return _grid.placements.filter(func(p): return not is_module_disabled(p.id))

func damage_module(pid: int, amt: int) -> void:
	var p := _placement_by_id(pid)
	if p.is_empty():
		return
	if not _module_hp.has(pid):
		_module_hp[pid] = _module_hp_max(p)
	var was_alive := int(_module_hp[pid]) > 0
	_module_hp[pid] = maxi(0, int(_module_hp[pid]) - amt)
	if was_alive and int(_module_hp[pid]) == 0:
		EventBus.module_destroyed.emit(p.module.id, p.origin)
		if p.module.id == &"main_reactor":
			EventBus.defense_failed.emit()
		_recompute_flux()

func _try_repair() -> void:
	var pc := _player_cell()
	for p in _grid.placements:
		var adj := false
		for c in p.cells:
			if absi(c.x - pc.x) <= 1 and absi(c.y - pc.y) <= 1:
				adj = true
				break
		if not adj:
			continue
		var maxhp := _module_hp_max(p)
		var cur: int = int(_module_hp.get(p.id, maxhp))
		if cur >= maxhp:
			continue
		if not _resources.can_afford(ALLOY, 10):
			_hint.text = "合金不足以修復"
			return
		_resources.spend(ALLOY, 10)
		var was_dead := cur <= 0
		_module_hp[p.id] = mini(maxhp, cur + 25)
		if was_dead:
			_recompute_flux()
		EventBus.resource_changed.emit(ALLOY, _resources.get_amount(ALLOY))
		_update_hud()
		_hint.text = "修復 +25 HP（-10 合金）"
		return
	_hint.text = "附近沒有可修復的模塊"

func _find_module(id: StringName) -> ModuleData:
	for m in _modules:
		if m.id == id:
			return m
	return null

func _eff_dims(m: ModuleData, rot: int) -> Vector2i:
	return Vector2i(m.h, m.w) if rot % 2 == 1 else Vector2i(m.w, m.h)

# --- UI（CanvasLayer 螢幕固定）---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_alloy = _make_label(layer, Vector2(40, 12))
	_hud_flux = _make_label(layer, Vector2(40, 34))
	_hud_sel = _make_label(layer, Vector2(40, 56))
	_hud_layer = _make_label(layer, Vector2(280, 12))
	_hint = _make_label(layer, Vector2(40, 78))
	_hint.text = "WASD 移動 / E 互動(電梯·控制台) / 藍圖模式放模塊 / R 旋轉 / 右鍵移除 / C 船員 / K 防衛戰 / F 修復"
	_console_hint = _make_label(layer, Vector2(40, 100))
	_console_hint.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	_console_hint.visible = false
	_hud_inv = _make_label(layer, Vector2(280, 34))
	_hud_inv.add_theme_color_override("font_color", Color(0.85, 0.8, 0.55))
	_update_inventory_label()
	_hud_clock = _make_label(layer, Vector2(280, 56))
	_hud_clock.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))

	_build_blueprint_ui(layer)
	_update_hud()

func _build_blueprint_ui(layer: CanvasLayer) -> void:
	var vp := get_viewport().get_visible_rect().size
	const TB_H := 158.0

	_toolbar = PanelContainer.new()
	_toolbar.position = Vector2(0, vp.y - TB_H)
	_toolbar.custom_minimum_size = Vector2(vp.x, TB_H)
	_toolbar.visible = false
	layer.add_child(_toolbar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_toolbar.add_child(col)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	col.add_child(tabs)
	for cat in CATEGORIES:
		var cb := Button.new()
		cb.text = Localization.t(cat[1])
		cb.toggle_mode = true
		cb.pressed.connect(_on_category.bind(cat[0]))
		tabs.add_child(cb)
		_cat_buttons[cat[0]] = cb

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(vp.x - 24, 104)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(scroll)
	_module_btn_box = HBoxContainer.new()
	_module_btn_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_module_btn_box)

	var bp := Button.new()
	bp.text = "🔧 " + Localization.t("ui.base.blueprint")
	bp.toggle_mode = true
	bp.custom_minimum_size = Vector2(140, 38)
	bp.position = Vector2(vp.x - 152, vp.y - 50)
	bp.toggled.connect(_on_blueprint_toggled)
	layer.add_child(bp)

	_on_category(CATEGORIES[0][0])

func _on_blueprint_toggled(pressed: bool) -> void:
	_blueprint_open = pressed
	_toolbar.visible = pressed
	if not pressed:
		_selected = null
		_hint.text = "已關閉藍圖模式"
		_update_hud()

func _on_category(cat: StringName) -> void:
	_palette_category = cat
	for c in _cat_buttons:
		(_cat_buttons[c] as Button).button_pressed = (c == cat)
	_rebuild_palette()

func _rebuild_palette() -> void:
	for child in _module_btn_box.get_children():
		child.free()
	for m in _modules:
		if m.category != _palette_category:
			continue
		var b := Button.new()
		b.text = "%s\n[%dx%d] ⚡%+d 🔩%d" % [Localization.t(m.name_key), m.w, m.h, m.flux, m.cost]
		b.custom_minimum_size = Vector2(132, 0)
		b.pressed.connect(_on_pick.bind(m))
		_module_btn_box.add_child(b)

func _make_label(parent: Node, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	parent.add_child(l)
	return l

func _update_inventory_label() -> void:
	var inv: Dictionary = Save.meta.get("inventory", {})
	if inv.is_empty():
		_hud_inv.text = "%s：%s" % [Localization.t("ui.base.inventory"), Localization.t("ui.base.empty")]
		return
	var parts: Array = []
	for id in inv:
		parts.append("%s×%d" % [Localization.t(id), int(inv[id])])
	_hud_inv.text = "%s：%s" % [Localization.t("ui.base.inventory"), ", ".join(parts)]

func _on_pick(m: ModuleData) -> void:
	_selected = m
	_update_hud()

func _update_hud() -> void:
	_hud_alloy.text = "合金 Alloy：%d" % _resources.get_amount(ALLOY)
	_hud_flux.text = "Flux：%+d" % _net_flux
	_hud_flux.add_theme_color_override(
		"font_color", Color(1, 0.4, 0.4) if _net_flux < 0 else Color(0.5, 1, 0.6))
	if _selected:
		var d := _eff_dims(_selected, _rot)
		_hud_sel.text = "選中 Selected：%s [%dx%d] (R 旋轉)" % [Localization.t(_selected.name_key), d.x, d.y]
	else:
		_hud_sel.text = "選中 Selected：— (R 旋轉)"

# --- 輸入 ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if _on_elevator():
			_open_floor_selector()
		elif _near_console():
			_open_star_map()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		_toggle_crew_panel()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		_trigger_wave()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_try_repair()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _floor_layer != null:
			_close_floor_selector()
		elif _selected != null:
			_selected = null
			_hint.text = "已取消選取"
			_update_hud()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_rot = (_rot + 1) % 2
		_update_hud()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(ZOOM_STEP)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(1.0 / ZOOM_STEP)
			return
		var c := _world_to_cell(get_global_mouse_position())
		if not _grid.in_bounds(c):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _selected == null and _wave != null and _wave.phase == WaveSystem.Phase.WAVE:
				_wave.player_melee(_player.position, _player.facing)
			else:
				_try_place(c)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_remove(c)

func _try_place(c: Vector2i) -> void:
	if _selected == null:
		_hint.text = "先按右下「藍圖模式」並選一個模塊"
		return
	for fc in _grid.footprint(c, _selected, _rot):
		if not DeckLayout.is_buildable(_active_deck, fc.x, fc.y):
			_hint.text = "只能建在可建格（避開固定艙與電梯）"
			return
	if not _grid.can_place(c, _selected, _rot):
		_hint.text = "無法放置：超界／重疊"
		return
	if not _resources.can_afford(ALLOY, _selected.cost):
		_hint.text = "合金不足"
		return
	_resources.spend(ALLOY, _selected.cost)
	_grid.place(c, _selected, _rot)
	EventBus.module_placed.emit(_selected.id, c)
	EventBus.resource_changed.emit(ALLOY, _resources.get_amount(ALLOY))
	_recompute_flux()
	_build_nav()
	_save_base()
	_hint.text = "已放置 " + Localization.t(_selected.name_key)

func _try_remove(c: Vector2i) -> void:
	if _grid.is_occupied(c):
		var removed := _grid.remove_at(c)
		if removed:
			_resources.add(ALLOY, int(removed.module.cost * 0.5))
			EventBus.module_removed.emit(removed.module.id, removed.origin)
			EventBus.resource_changed.emit(ALLOY, _resources.get_amount(ALLOY))
			_recompute_flux()
			_build_nav()
			_save_base()
			_hint.text = "已移除（退半額）"
	_update_hud()

## 全船電網（多甲板）：當前層用 live grid（含防衛戰停機），他層用持久佈局；中繼垂直輸電。
func _recompute_flux() -> void:
	var res := PowerCalc.compute_ship(_ship_instances())
	_net_flux = res.net_flux
	_powered = res.powered
	EventBus.power_grid_changed.emit(_net_flux)
	_update_hud()

func _pkey(d: int, o: Vector2i) -> String:
	return "%d:%d:%d" % [d, o.x, o.y]

func _footprint_cells(origin: Vector2i, m: ModuleData, rot: int) -> Array:
	var w := m.w
	var h := m.h
	if rot % 2 == 1:
		var t := w
		w = h
		h = t
	var cells: Array = []
	for dy in h:
		for dx in w:
			cells.append(origin + Vector2i(dx, dy))
	return cells

## 全船模塊實例（供 PowerCalc.compute_ship）：當前層讀 live grid、他層讀 _deck_placements。
func _ship_instances() -> Array:
	var inst: Array = []
	for p in _grid.placements:
		if is_module_disabled(p.id):
			continue
		inst.append({"key": _pkey(_active_deck, p.origin), "deck": _active_deck,
			"origin": p.origin, "cells": p.cells, "flux": int(p.module.flux), "is_relay": bool(p.module.is_relay)})
	for d in _deck_placements:
		if d == _active_deck:
			continue
		for p in _deck_placements[d]:
			var m := _find_module(StringName(str(p.get("id", ""))))
			if m == null:
				continue
			var origin := Vector2i(int(p["col"]), int(p["row"]))
			inst.append({"key": _pkey(d, origin), "deck": d, "origin": origin,
				"cells": _footprint_cells(origin, m, int(p.get("rot", 0))),
				"flux": int(m.flux), "is_relay": bool(m.is_relay)})
	return inst

# --- 渲染（只畫當前層俯視平面）---

## 地形區淡色（§5.2・三區）：疊在地板貼圖上保留分區辨識。核心偏冷藍／中間偏綠／外圍偏暖黃。
func _zone_tint(zone: StringName) -> Color:
	match zone:
		&"core":   return Color(0.74, 0.84, 1.00)
		&"middle": return Color(0.82, 0.96, 0.86)
		&"outer":  return Color(1.00, 0.95, 0.82)
		_:         return Color.WHITE

func _draw() -> void:
	var d := _active_deck
	var cols := DeckLayout.deck_cols(d)
	var rows := DeckLayout.deck_rows(d)

	# 甲板面：逐格畫俯視平面（三區上色／固定艙／電梯）。
	for r in rows:
		for c in cols:
			var ch := DeckLayout.cell_char(d, c, r)
			if ch == ".":
				continue
			var rect := Rect2(_origin_px + Vector2(c * CELL, r * CELL), Vector2(CELL - 2, CELL - 2))
			if DeckLayout.is_elevator(d, c, r):
				draw_rect(rect, Color(0.18, 0.42, 0.52), true)   # 電梯（垂直動線）
				draw_rect(rect, Color(0, 0, 0, 0.32), false, 1.0)
			elif DeckLayout.is_fixed(d, c, r):
				draw_rect(rect, Color(0.30, 0.26, 0.36), true)   # 起始固定艙（不可編輯）
				draw_rect(rect, Color(0, 0, 0, 0.32), false, 1.0)
				draw_line(rect.position, rect.end, Color(0.6, 0.55, 0.7, 0.5), 1.5)  # 斜線標記（呼應 Drawing2 ANSI31）
			else:
				# 可建造格 → 鋪艙室圖（四邊牆＋四門），並用區色淡疊（保留三地形區辨識・§5.2）
				draw_texture_rect(CABIN_TEX, rect, false, _zone_tint(DeckLayout.zone_at(d, c, r)))

	_draw_deck_frame(d, cols, rows)

	# 模塊
	for p in _grid.placements:
		var m: ModuleData = p.module
		var o: Vector2i = p.origin
		var dims := _eff_dims(m, p.get("rot", 0))
		var mr := Rect2(_origin_px + Vector2(o.x * CELL, o.y * CELL),
			Vector2(dims.x * CELL - 2, dims.y * CELL - 2))
		var online: bool = _powered.get(_pkey(_active_deck, o), false)
		draw_rect(mr, m.color if online else m.color.darkened(0.55), true)
		draw_rect(mr, Color(1, 1, 1, 0.5) if online else Color(1, 0.3, 0.3, 0.9), false, 2.0)
		if _module_hp.has(p.id):
			var maxhp := _module_hp_max(p)
			var cur: int = int(_module_hp[p.id])
			if cur <= 0:
				draw_rect(mr, Color(0, 0, 0, 0.55), true)
				draw_line(mr.position, mr.end, Color(1, 0.25, 0.25, 0.9), 2.0)
			elif cur < maxhp:
				var bar := Rect2(mr.position + Vector2(0, -6), Vector2(mr.size.x, 4))
				draw_rect(bar, Color(0, 0, 0, 0.6), true)
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(cur) / float(maxhp), 4)),
					Color(0.4, 0.9, 0.4), true)

	# AI 控制台（僅核心層）
	if d == CONSOLE_DECK:
		var ccp := _console_world_pos()
		var near := _near_console()
		var csz := CELL * (0.42 if near else 0.34)
		var ccol := Color(0.4, 0.95, 1.0) if near else Color(0.3, 0.6, 0.75)
		draw_colored_polygon(PackedVector2Array([
			ccp + Vector2(0, -csz), ccp + Vector2(csz, 0),
			ccp + Vector2(0, csz), ccp + Vector2(-csz, 0)]), ccol)

	# hover 預覽（只在可建格顯示）
	if _selected and _grid.in_bounds(_hover_cell):
		var buildable := true
		for fc in _grid.footprint(_hover_cell, _selected, _rot):
			if not DeckLayout.is_buildable(d, fc.x, fc.y):
				buildable = false
				break
		var ok := buildable and _grid.can_place(_hover_cell, _selected, _rot) \
			and _resources.can_afford(ALLOY, _selected.cost)
		var pd := _eff_dims(_selected, _rot)
		var pr := Rect2(_origin_px + Vector2(_hover_cell.x * CELL, _hover_cell.y * CELL),
			Vector2(pd.x * CELL - 2, pd.y * CELL - 2))
		draw_rect(pr, Color(0.4, 1, 0.5, 0.35) if ok else Color(1, 0.3, 0.3, 0.35), true)

## 當前層紡錘外框 ＋ 層名（單層俯視）。
func _draw_deck_frame(d: int, cols: int, rows: int) -> void:
	var frame := Rect2(_origin_px + Vector2(-6, -6), Vector2(cols * CELL + 12, rows * CELL + 12))
	draw_rect(frame, Color(0.55, 0.85, 1.0, 0.85), false, 3.0)
	var label := "%s  %d / %d" % [DeckLayout.deck_name(d), d + 1, DeckLayout.deck_count()]
	draw_string(ThemeDB.fallback_font, _origin_px + Vector2(0, -16),
		label, HORIZONTAL_ALIGNMENT_LEFT, cols * CELL, 18, Color(0.75, 0.92, 1.0))
