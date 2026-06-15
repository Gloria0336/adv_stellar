extends Node2D
## 基地階段切片（GD §5）：拼圖建造 ＋ 電力網(§5.4) ＋ 地形加成(§5.2) ＋ 甲板分層 ＋ 可走動 hub(§6)。
## 操作：右側選模塊 → 左鍵放置；R 旋轉；右鍵 解鎖/移除；WASD 移動；滑鼠到邊緣捲動鏡頭；中鍵回玩家。

const CELL := 48
const COLS := 100
const ROWS := 19            # = sum(DeckLayers.HEIGHTS) 2+2+3+3+3+2+2+2
const UNLOCK_COST := 20
const ALLOY := &"alloy"

# 起始解鎖建造區（40 寬 × 全 19 列）
const DECK_X0 := 30
const DECK_Y0 := 0
const DECK_W := 40
const DECK_H := 19
const SPINE_X := [49, 50]
const COOL_X := [47, 48, 51, 52]
const CONSOLE_CELL := Vector2i(45, 9)   # AI 控制台站點（§13-9.B 走到工作站開面板）
const CONSOLE_RANGE := 1.6 * CELL        # 互動觸發距離
const ELEVATOR_X: Array[int] = [35, 52, 66]   # 固定電梯豎井欄：跨甲板的唯一通道（玩家與船員都受限）
# 藍圖工具列分類（GD §5.7 六大類）：[category id, loc key]，順序＝標籤顯示順序。
const CATEGORIES := [
	[&"power", "module.cat.power"],
	[&"production", "module.cat.production"],
	[&"research", "module.cat.research"],
	[&"life", "module.cat.life"],
	[&"defense", "module.cat.defense"],
	[&"special", "module.cat.special"],
]

var _map_open := false

var _grid: GridModel
var _resources: ResourceStore
var _modules: Array[ModuleData] = []
var _selected: ModuleData = null
var _rot := 0
var _hover_cell := Vector2i(-1, -1)
var _net_flux := 0
var _powered: Dictionary = {}
var _player: Node2D
var _origin_px := Vector2(40, 90)

var _crew: Array[CrewMember] = []
var _crew_panel: CrewPanel
var _crew_panel_layer: CanvasLayer
var _nav := NavigationCore.new()
var _hud_clock: Label
var _blueprint_open := false
var _toolbar: PanelContainer
var _palette_category: StringName = &"power"
var _module_btn_box: HBoxContainer
var _cat_buttons: Dictionary = {}   # category(StringName) -> Button
var _wave: WaveSystem               # 裂潮防衛戰（偶發・按 K 觸發）
var _module_hp: Dictionary = {}     # placement id -> 現值 HP（防衛戰中有效）

var _hud_alloy: Label
var _hud_flux: Label
var _hud_sel: Label
var _hud_layer: Label
var _hint: Label
var _console_hint: Label
var _hud_inv: Label

func _ready() -> void:
	_grid = GridModel.new(COLS, ROWS)
	_resources = ResourceStore.new({ALLOY: 1000})
	if not Save.world.has("compatibility"):
		Save.world["compatibility"] = 15   # 起始相容性：P1 開・P2/P3 鎖（§6 相容性線）
	EventBus.planet_selected.connect(_on_planet_selected)
	_load_modules()
	_setup_deck_terrain()
	if not _load_base():
		_place_starter(&"main_reactor", Vector2i(49, 8))   # 首次：落在船脊（地形加成）
		_place_starter(&"crew_quarters", Vector2i(32, 12))  # 船員艙（睡眠目的地，置於下層 → 需走電梯）
		_place_starter(&"cafeteria", Vector2i(45, 8))       # 餐廳（用餐目的地）
		_place_starter(&"morale_bay", Vector2i(60, 7))      # 休憩艙（交誼/休閒目的地）
		_save_base()
	_build_ui()
	_spawn_player_and_camera()
	_build_nav()
	_spawn_crew()
	_recompute_flux()
	queue_redraw()

func _place_starter(id: StringName, cell: Vector2i) -> void:
	var m := _find_module(id)
	if m:
		_grid.place(cell, m)

func _build_nav() -> void:
	_nav.build(_grid, PackedInt32Array(ELEVATOR_X))

func _process(_delta: float) -> void:
	_hover_cell = _world_to_cell(get_global_mouse_position())
	_hud_layer.text = "當前層 Layer：%d / 8" % (_active_layer() + 1)
	_hud_clock.text = "%s  Day %d  %s" % [Localization.t("ui.base.clock"), ShipClock.day, ShipClock.hhmm()]
	_console_hint.visible = _near_console()
	queue_redraw()

func _console_world_pos() -> Vector2:
	return _origin_px + Vector2(CONSOLE_CELL.x * CELL + CELL * 0.5, CONSOLE_CELL.y * CELL + CELL * 0.5)

func _near_console() -> bool:
	return _player != null and _player.position.distance_to(_console_world_pos()) <= CONSOLE_RANGE

func _open_star_map() -> void:
	if _map_open:
		return
	_map_open = true
	var map: Node = load("res://features/starmap/star_map.tscn").instantiate()
	map.process_mode = Node.PROCESS_MODE_ALWAYS   # 暫停世界時星系圖仍可操作
	map.tree_exited.connect(func(): _map_open = false)
	add_child(map)
	get_tree().paused = true

func _on_planet_selected(planet_id: StringName) -> void:
	# 星系圖選星 → 進遠征（run 層帶 planet_id，§13-10）
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

func _setup_deck_terrain() -> void:
	# 預設甲板：解鎖 ＋ 地形（地形由位置決定，always run；載入只疊加額外解鎖/模塊）
	for y in range(DECK_Y0, DECK_Y0 + DECK_H):
		for x in range(DECK_X0, DECK_X0 + DECK_W):
			var c := Vector2i(x, y)
			_grid.set_unlocked(c)
			_grid.set_terrain(c, _terrain_for(c))
	# 幾處破損區（flavor）
	for dc in [Vector2i(34, 4), Vector2i(62, 6), Vector2i(40, 16), Vector2i(58, 14)]:
		_grid.set_terrain(dc, GridModel.Terrain.DAMAGED)

## 把母船佈局寫入 meta（§13-10.A/C：建造＝關鍵節點自動存）
func _save_base() -> void:
	var unlocked: Array = []
	for y in ROWS:
		for x in COLS:
			if _grid.cell_state(Vector2i(x, y)) == GridModel.Cell.EMPTY:
				unlocked.append([x, y])
	var places: Array = []
	for p in _grid.placements:
		places.append({"id": String(p.module.id), "x": p.origin.x, "y": p.origin.y, "rot": int(p.get("rot", 0))})
	Save.meta["base"] = {"alloy": _resources.get_amount(ALLOY), "unlocked": unlocked, "placements": places}
	Save.save_layer("meta", Save.meta)

## 從 meta 還原佈局；無存檔回傳 false（走首次預設）
func _load_base() -> bool:
	if not Save.meta.has("base"):
		return false
	var data: Dictionary = Save.meta["base"]
	for cell in data.get("unlocked", []):
		_grid.set_unlocked(Vector2i(int(cell[0]), int(cell[1])))
	for p in data.get("placements", []):
		var m := _find_module(StringName(str(p.get("id", ""))))
		if m:
			_grid.place(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))), m, int(p.get("rot", 0)))
	_resources = ResourceStore.new({ALLOY: int(data.get("alloy", 1000))})
	return true

func _terrain_for(c: Vector2i) -> int:
	if c.y == 0 or c.y == ROWS - 1:
		return GridModel.Terrain.HULL_EDGE     # 船殼緣（對外）
	if c.x in SPINE_X:
		return GridModel.Terrain.SPINE         # 船脊·動力幹線
	if c.x in COOL_X:
		return GridModel.Terrain.COOLING       # 冷卻區
	var layer := DeckLayers.layer_of(c.y)
	if layer == 3 or layer == 4:
		return GridModel.Terrain.CORE          # 核心內艙（受保護）
	return GridModel.Terrain.NONE

func _spawn_player_and_camera() -> void:
	_player = load("res://entities/player/player.tscn").instantiate()
	_player.position = _origin_px + Vector2((DECK_X0 + DECK_W * 0.5) * CELL, (ROWS * 0.5) * CELL)
	_player.collision_resolver = _player_collision   # 甲板物理分隔：跨層只走電梯
	add_child(_player)
	var cam := CameraRig.new()
	cam.home = _player
	cam.global_position = _player.position
	cam.limit_left = int(_origin_px.x - 100)
	cam.limit_top = int(_origin_px.y - 100)
	cam.limit_right = int(_origin_px.x + COLS * CELL + 100)
	cam.limit_bottom = int(_origin_px.y + ROWS * CELL + 100)
	add_child(cam)

## 格子中心 → 世界座標。
func _cell_center(c: Vector2i) -> Vector2:
	return _origin_px + Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)

func _in_elevator_shaft(world_x: float) -> bool:
	return floori((world_x - _origin_px.x) / CELL) in ELEVATOR_X

## 玩家移動碰撞解析：限制在甲板區內，且跨甲板邊界只能經電梯豎井。
func _player_collision(from: Vector2, to: Vector2) -> Vector2:
	var res := to
	res.x = clampf(res.x, _origin_px.x + DECK_X0 * CELL + CELL * 0.5,
		_origin_px.x + (DECK_X0 + DECK_W) * CELL - CELL * 0.5)
	res.y = clampf(res.y, _origin_px.y + CELL * 0.5, _origin_px.y + ROWS * CELL - CELL * 0.5)
	if not _in_elevator_shaft(res.x):
		for li in range(1, DeckLayers.HEIGHTS.size()):
			var wy := _origin_px.y + DeckLayers.layer_start(li) * CELL
			if from.y <= wy and res.y > wy:
				res.y = wy - 1.0
			elif from.y >= wy and res.y < wy:
				res.y = wy + 1.0
	return res

## 在甲板上生成範例船員（§10/§13-12）。真實移動/派駐之後接 _core。
func _spawn_crew() -> void:
	var sched: CrewSchedule = load("res://data/crew/schedule_default.tres")
	var roster := [
		[load("res://data/crew/eng_rivet.tres"), Vector2i(40, 9), &"main_reactor"],
		[load("res://data/crew/med_luna.tres"), Vector2i(46, 9), &""],
	]
	for entry in roster:
		var crew := CrewMember.new()
		crew.data = entry[0]
		crew.schedule = sched
		crew.assigned_module = entry[2]
		crew.position = _cell_center(entry[1])
		add_child(crew)
		crew.setup_nav(_nav, _grid, _origin_px, CELL, PackedInt32Array(ELEVATOR_X))
		_crew.append(crew)

## 開/關船員個性面板：綁定離玩家最近的船員（走到誰旁邊按 C 看誰）。
## 已開啟時：若最近的是別人就切換顯示，是同一人則關閉。
func _toggle_crew_panel() -> void:
	if _crew.is_empty():
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

# --- 裂潮防衛戰（偶發・GD §8/§13-7）---

## K 鍵：首次建立防衛戰控制器並掛入，之後推進階段（IDLE→整備→放波）。
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

## 防衛戰開始時把所有已放置模塊設滿 HP。
func init_module_hp() -> void:
	_module_hp.clear()
	for p in _grid.placements:
		_module_hp[p.id] = _module_hp_max(p)

func is_module_disabled(pid: int) -> bool:
	return _module_hp.has(pid) and int(_module_hp[pid]) <= 0

## 未停機的模塊（供尋路目標與電力計算）。
func alive_module_placements() -> Array:
	return _grid.placements.filter(func(p): return not is_module_disabled(p.id))

## 破壞者攻擊 → 扣模塊 HP；歸零＝停機（停產 Flux、可重修）。
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
			EventBus.defense_failed.emit()   # 核心被毀＝失守（非 game over，§13-7.E）
		_recompute_flux()

## F 鍵：走到受損模塊旁，花合金逐步重修。
func _try_repair() -> void:
	var pc := _world_to_cell(_player.position)
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

func _active_layer() -> int:
	if _player == null:
		return 0
	var cy: int = clampi(_world_to_cell(_player.position).y, 0, ROWS - 1)
	return DeckLayers.layer_of(cy)

# --- UI（CanvasLayer 螢幕固定）---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_alloy = _make_label(layer, Vector2(40, 12))
	_hud_flux = _make_label(layer, Vector2(40, 34))
	_hud_sel = _make_label(layer, Vector2(40, 56))
	_hud_layer = _make_label(layer, Vector2(280, 12))
	_hint = _make_label(layer, Vector2(40, 78))
	_hint.text = "WASD 移動 / 藍圖模式開模塊欄 / 左鍵放置或親戰 / R 旋轉 / 右鍵 解鎖移除 / C 船員 / K 裂潮防衛戰 / F 修復"
	_console_hint = _make_label(layer, Vector2(40, 100))
	_console_hint.text = "▶ " + Localization.t("ui.starmap.open_hint")
	_console_hint.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	_console_hint.visible = false
	_hud_inv = _make_label(layer, Vector2(280, 34))
	_hud_inv.add_theme_color_override("font_color", Color(0.85, 0.8, 0.55))
	_update_inventory_label()
	_hud_clock = _make_label(layer, Vector2(280, 56))
	_hud_clock.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))

	_build_blueprint_ui(layer)
	_update_hud()

# --- 藍圖模式：下方彈出式模塊工具列 ＋ 右下角切換鈕 ---

func _build_blueprint_ui(layer: CanvasLayer) -> void:
	var vp := get_viewport().get_visible_rect().size
	const TB_H := 158.0

	# 下方彈出工具列（預設收起）
	_toolbar = PanelContainer.new()
	_toolbar.position = Vector2(0, vp.y - TB_H)
	_toolbar.custom_minimum_size = Vector2(vp.x, TB_H)
	_toolbar.visible = false
	layer.add_child(_toolbar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_toolbar.add_child(col)

	# 分類標籤列
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

	# 模塊按鈕區（依分類重建，可橫向捲動）
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(vp.x - 24, 104)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(scroll)
	_module_btn_box = HBoxContainer.new()
	_module_btn_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_module_btn_box)

	# 右下角「藍圖模式」切換鈕
	var bp := Button.new()
	bp.text = "🔧 " + Localization.t("ui.base.blueprint")
	bp.toggle_mode = true
	bp.custom_minimum_size = Vector2(140, 38)
	bp.position = Vector2(vp.x - 152, vp.y - 50)
	bp.toggled.connect(_on_blueprint_toggled)
	layer.add_child(bp)

	_on_category(CATEGORIES[0][0])   # 預設顯示第一類

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
		child.free()   # 立即釋放（queue_free 延遲，會殘留在同幀導致重複）
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
		var pref := "" if _selected.terrain_pref == &"" else "  地形+%d" % _selected.terrain_bonus_flux
		_hud_sel.text = "選中 Selected：%s [%dx%d]%s (R 旋轉)" % [Localization.t(_selected.name_key), d.x, d.y, pref]
	else:
		_hud_sel.text = "選中 Selected：— (R 旋轉)"

# --- 輸入 ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if _near_console():
			_open_star_map()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		_toggle_crew_panel()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		_trigger_wave()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_try_repair()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _selected != null:
			_selected = null
			_hint.text = "已取消選取"
			_update_hud()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_rot = (_rot + 1) % 2
		_update_hud()
	elif event is InputEventMouseButton and event.pressed:
		var c := _world_to_cell(get_global_mouse_position())
		if not _grid.in_bounds(c):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _selected == null and _wave != null and _wave.phase == WaveSystem.Phase.WAVE:
				_wave.player_melee(_player.position, _player.facing)   # 作戰中親戰
			else:
				_try_place(c)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_unlock_or_remove(c)

func _world_to_cell(world: Vector2) -> Vector2i:
	var local := world - _origin_px
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))

func _try_place(c: Vector2i) -> void:
	if _selected == null:
		_hint.text = "先按右下「藍圖模式」並選一個模塊"
		return
	if not _grid.can_place(c, _selected, _rot):
		_hint.text = "無法放置：超界／重疊／未解鎖"
		return
	for fc in _grid.footprint(c, _selected, _rot):
		if fc.x in ELEVATOR_X:
			_hint.text = "電梯豎井不可建造"
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

func _try_unlock_or_remove(c: Vector2i) -> void:
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
	elif _grid.cell_state(c) == GridModel.Cell.LOCKED:
		if _resources.can_afford(ALLOY, UNLOCK_COST):
			_resources.spend(ALLOY, UNLOCK_COST)
			_grid.set_unlocked(c)
			EventBus.cell_unlocked.emit(c)
			EventBus.resource_changed.emit(ALLOY, _resources.get_amount(ALLOY))
			_build_nav()
			_save_base()
			_hint.text = "已解鎖格子（-%d 合金）" % UNLOCK_COST
		else:
			_hint.text = "合金不足以解鎖"
	_update_hud()

func _recompute_flux() -> void:
	var res := PowerCalc.compute(alive_module_placements(), _grid)
	_net_flux = res.net_flux
	_powered = res.powered
	EventBus.power_grid_changed.emit(_net_flux)
	_update_hud()

# --- 渲染（佔位色塊・地形上色・非當前層刷淡・裁剪可見格）---

func _visible_cell_rect() -> Rect2i:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2i(0, 0, COLS, ROWS)
	var vsize := get_viewport().get_visible_rect().size / cam.zoom
	var center := cam.get_screen_center_position()
	var tl := center - vsize * 0.5 - _origin_px
	var br := center + vsize * 0.5 - _origin_px
	var x0 := clampi(floori(tl.x / CELL) - 1, 0, COLS)
	var y0 := clampi(floori(tl.y / CELL) - 1, 0, ROWS)
	var x1 := clampi(ceili(br.x / CELL) + 1, 0, COLS)
	var y1 := clampi(ceili(br.y / CELL) + 1, 0, ROWS)
	return Rect2i(x0, y0, maxi(0, x1 - x0), maxi(0, y1 - y0))

func _terrain_color(t: int) -> Color:
	match t:
		GridModel.Terrain.SPINE:
			return Color(0.36, 0.28, 0.12)
		GridModel.Terrain.COOLING:
			return Color(0.12, 0.22, 0.32)
		GridModel.Terrain.HULL_EDGE:
			return Color(0.22, 0.22, 0.26)
		GridModel.Terrain.CORE:
			return Color(0.12, 0.24, 0.22)
		GridModel.Terrain.DAMAGED:
			return Color(0.24, 0.13, 0.10)
		_:
			return Color(0.10, 0.20, 0.16)

func _dim(col: Color, on_active: bool) -> Color:
	return col if on_active else col.darkened(0.72)

func _draw() -> void:
	var active := _active_layer()
	var view := _visible_cell_rect()
	for y in range(view.position.y, view.position.y + view.size.y):
		var on_active := DeckLayers.layer_of(y) == active
		for x in range(view.position.x, view.position.x + view.size.x):
			var c := Vector2i(x, y)
			var rect := Rect2(_origin_px + Vector2(x * CELL, y * CELL), Vector2(CELL - 2, CELL - 2))
			var col: Color
			if _grid.is_occupied(c):
				col = Color(0.15, 0.18, 0.25)
			elif _grid.cell_state(c) == GridModel.Cell.LOCKED:
				col = Color(0.10, 0.09, 0.09)
			else:
				col = _terrain_color(_grid.terrain_at(c))
			draw_rect(rect, _dim(col, on_active), true)
			draw_rect(rect, Color(0, 0, 0, 0.4), false, 1.0)

	# 模塊
	for p in _grid.placements:
		var m: ModuleData = p.module
		var o: Vector2i = p.origin
		var on_active := DeckLayers.layer_of(o.y) == active
		var dims := _eff_dims(m, p.get("rot", 0))
		var mr := Rect2(_origin_px + Vector2(o.x * CELL, o.y * CELL),
			Vector2(dims.x * CELL - 2, dims.y * CELL - 2))
		var online: bool = _powered.get(p.id, false)
		draw_rect(mr, _dim(m.color if online else m.color.darkened(0.55), on_active), true)
		draw_rect(mr, Color(1, 1, 1, 0.5) if online else Color(1, 0.3, 0.3, 0.9), false, 2.0)
		# 防衛戰：模塊 HP 條 / 停機罩
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

	# 電梯豎井（跨甲板的唯一通道）
	for ex in ELEVATOR_X:
		var sx := _origin_px.x + ex * CELL
		var shaft := Rect2(sx + 3, _origin_px.y, CELL - 6, ROWS * CELL)
		draw_rect(shaft, Color(0.3, 0.8, 1.0, 0.12), true)
		draw_rect(shaft, Color(0.4, 0.9, 1.0, 0.4), false, 1.0)

	# 甲板邊界牆（物理分隔；電梯欄留缺口）
	for li in range(1, DeckLayers.HEIGHTS.size()):
		var wy := _origin_px.y + DeckLayers.layer_start(li) * CELL
		for x in range(DECK_X0, DECK_X0 + DECK_W):
			if x in ELEVATOR_X:
				continue
			var wx := _origin_px.x + x * CELL
			draw_line(Vector2(wx, wy), Vector2(wx + CELL, wy), Color(0.55, 0.5, 0.42, 0.9), 3.0)

	# AI 控制台站點（互動開星系圖）
	var ccp := _console_world_pos()
	var near := _near_console()
	var csz := CELL * (0.62 if near else 0.5)
	var ccol := Color(0.4, 0.95, 1.0) if near else Color(0.3, 0.6, 0.75)
	draw_colored_polygon(PackedVector2Array([
		ccp + Vector2(0, -csz), ccp + Vector2(csz, 0),
		ccp + Vector2(0, csz), ccp + Vector2(-csz, 0)]), ccol)
	draw_string(ThemeDB.fallback_font, ccp + Vector2(-30, -csz - 6),
		Localization.t("ui.starmap.console"), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, ccol)

	# hover 預覽
	if _selected and _grid.in_bounds(_hover_cell):
		var ok := _grid.can_place(_hover_cell, _selected, _rot) and _resources.can_afford(ALLOY, _selected.cost)
		var pd := _eff_dims(_selected, _rot)
		var pr := Rect2(_origin_px + Vector2(_hover_cell.x * CELL, _hover_cell.y * CELL),
			Vector2(pd.x * CELL - 2, pd.y * CELL - 2))
		draw_rect(pr, Color(0.4, 1, 0.5, 0.35) if ok else Color(1, 0.3, 0.3, 0.35), true)
