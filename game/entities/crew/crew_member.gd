class_name CrewMember
extends Node2D
## 船員 NPC 控制器（entities/crew・架構決策 3）。
## 多狀態軸(CrewNeeds) ＋ 全域時鐘(ShipClock) ＋ 日程(CrewSchedule) → 情緒(CrewMood) → 行為(BehaviorFSM)。
## 行為含實體尋路：依活動走到對應模塊/地點（MovementCore+NavigationCore），到位才回復需求。
## 跨系統只走 EventBus：訂閱威脅事件、廣播情緒/活動/台詞。對照 GD §10/§13-12。

# 行為狀態（FSM key，也用作 loc：crew.activity.<key>）。
const S_IDLE := &"idle"
const S_WORK := &"work"
const S_EAT := &"eat"
const S_SLEEP := &"sleep"
const S_SOCIALIZE := &"socialize"
const S_RELAX := &"relax"
const S_FLEE := &"flee"
const S_MEDICAL := &"seek_medical"

# 緊急覆寫日程的觸發/回復門檻（hysteresis 遲滯，避免每 tick 抖動）。
const ENERGY_EXHAUSTED := 20.0
const ENERGY_RESTED := 95.0
const SATIATION_FULL := 90.0
const HEALTH_RECOVERED := 90.0

# 各活動對應的目的地模塊 id（取最近一個已放置者）；空缺則原地進行。
const DEST_MODULES := {
	S_EAT: [&"cafeteria"],
	S_SLEEP: [&"crew_quarters"],
	S_SOCIALIZE: [&"morale_bay", &"cafeteria"],
	S_RELAX: [&"morale_bay", &"crew_quarters"],
	S_MEDICAL: [&"medbay"],
}

@export var data: CrewData
@export var schedule: CrewSchedule
@export var assigned_module: StringName = &""   # 派駐模塊 id（§10 派駐）；空＝未派駐

var needs := CrewNeeds.new()
var fsm := BehaviorFSM.new()
var mood: CrewMood.Mood = CrewMood.Mood.NEUTRAL
var _idle_time: float = 0.0      # 連續閒置秒數（餵 BORED）

# 尋路/移動環境（由 base 注入 setup_nav）。
var nav: NavigationCore
var grid: GridModel
var grid_origin := Vector2.ZERO
var cell_size := 48
var elevator_x: PackedInt32Array = PackedInt32Array()
var move := MovementCore.new()
var _arrived := true             # 是否已抵達目前活動的目的地
var _dest_cell: Variant = null   # 目前鎖定的目的地格（每 tick 重評，回應新建/拆除的模塊）
var facing := Vector2.RIGHT      # 移動朝向（畫朝向指示用）
var _prev_pos := Vector2.ZERO

# 佔位外觀：身體色塊 ＋ 頭頂情緒 emoji ＋ 台詞氣泡。
const BODY_RADIUS := 16.0
const SPEECH_HOLD := 3.0
var _emoji_lbl: Label
var _name_lbl: Label
var _speech_lbl: Label
var _speech_time := 0.0

func _ready() -> void:
	if data == null:
		data = CrewData.new()
	if schedule == null:
		schedule = CrewSchedule.new()
		schedule.hours = CrewSchedule.default_day()
	move.speed = 70.0
	# 威脅事件 → 恐懼（跨系統一律走 EventBus）。
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.defense_failed.connect(_on_defense_failed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.oxygen_changed.connect(_on_oxygen_changed)
	fsm.change_to(S_IDLE)
	_prev_pos = position
	_setup_visual()

## base 注入尋路環境（在 add_child 之後呼叫）。
func setup_nav(p_nav: NavigationCore, p_grid: GridModel, origin: Vector2, p_cell: int, p_elev: PackedInt32Array) -> void:
	nav = p_nav
	grid = p_grid
	grid_origin = origin
	cell_size = p_cell
	elevator_x = p_elev

func _process(delta: float) -> void:
	tick(delta)

## 主迴圈。
func tick(delta: float) -> void:
	# 1. 決策（全域時鐘驅動日程；緊急需求/威脅覆寫）。
	var target := _decide_state()
	if fsm.change_to(target):
		EventBus.crew_activity_changed.emit(data.id, target)
	fsm.tick(delta)
	# 2. 目的地：每 tick 重評（回應你新建/拆除的模塊）；有變更才重新規劃路徑。
	_update_destination()
	# 3. 移動（朝目的地推進）＋更新朝向。
	if not _arrived and move.has_path():
		if move.advance(self, delta):
			_arrived = true
	var moved := position - _prev_pos
	_prev_pos = position
	if moved.length() > 0.01:
		var f := moved.normalized()
		if f.distance_to(facing) > 0.05:
			facing = f
			queue_redraw()
	# 3. 被動軸衰減（真正睡著＝到床且 sleep 才不掉精力）。
	var sleeping := fsm.current == S_SLEEP and _arrived
	needs.tick(delta, data, not sleeping)
	# 4. 活動效果：到位才生效；逃竄則邊跑邊耗。
	if _arrived:
		_apply_activity(delta)
	elif fsm.current == S_FLEE:
		needs.add(&"energy", -2.0 * delta)
		needs.add(&"morale", -1.0 * delta)
	# 5. 閒置計時（餵無聊）。
	if fsm.current == S_IDLE and _arrived:
		_idle_time += delta
	else:
		_idle_time = 0.0
	# 6. 情緒推導 + 廣播 + 更新氣泡。
	var new_mood := CrewMood.derive(needs, _idle_time)
	if new_mood != mood:
		mood = new_mood
		var quip := CrewMood.quip_key(mood)
		if _emoji_lbl != null:
			_emoji_lbl.text = CrewMood.emoji(mood)
			_speech_lbl.text = tr(quip)
			_speech_lbl.visible = true
			_speech_time = SPEECH_HOLD
		EventBus.crew_mood_changed.emit(data.id, mood)
		EventBus.crew_spoke.emit(data.id, quip)
	# 台詞氣泡逾時收起。
	if _speech_time > 0.0:
		_speech_time -= delta
		if _speech_time <= 0.0 and _speech_lbl != null:
			_speech_lbl.visible = false

func current_hour() -> int:
	return ShipClock.hour()

## 目前派駐工作效率（情緒倍率 × 職業基礎）；須在崗位上。供面板/未來生產系統查詢。
func work_efficiency() -> float:
	if fsm.current != S_WORK or not _arrived:
		return 0.0
	return data.base_efficiency * CrewMood.efficiency_mult(mood)

# --- 決策 ---

func _decide_state() -> StringName:
	# 1. 危機：恐懼 → 逃竄。
	if needs.fear >= CrewMood.FEAR_PANIC:
		return S_FLEE
	# 2. 生理紅線：覆寫日程（遲滯：達回復門檻才放手）。
	if needs.health <= CrewMood.HEALTH_HURT or (fsm.current == S_MEDICAL and needs.health < HEALTH_RECOVERED):
		return S_MEDICAL
	if needs.energy <= ENERGY_EXHAUSTED or (fsm.current == S_SLEEP and needs.energy < ENERGY_RESTED):
		return S_SLEEP
	if needs.satiation <= CrewMood.SATIATION_HUNGRY or (fsm.current == S_EAT and needs.satiation < SATIATION_FULL):
		return S_EAT
	# 3. 跟隨日程。
	match schedule.activity_at(current_hour()):
		CrewSchedule.Activity.SLEEP: return S_SLEEP
		CrewSchedule.Activity.EAT: return S_EAT
		CrewSchedule.Activity.SOCIALIZE: return S_SOCIALIZE
		CrewSchedule.Activity.RELAX: return S_RELAX
		CrewSchedule.Activity.WORK:
			return S_WORK if assigned_module != &"" else S_RELAX
		_: return S_IDLE

# --- 移動目的地 ---

## 每 tick 重評目的地：目的地有變（換狀態、模塊新建/拆除）才重新規劃路徑。
## 模塊目標只走到「與模塊同甲板相鄰」的存取格（不隔牆）；無對應模塊則原地進行。
func _update_destination() -> void:
	var state := fsm.current
	# 逃竄：往最近電梯（單點目標）。
	if state == S_FLEE:
		var cell: Variant = _nearest_elevator_cell()
		if cell == _dest_cell:
			return
		_dest_cell = cell
		if cell == null or nav == null:
			move.clear()
			_arrived = true
		else:
			_set_path(nav.find_path(_current_cell(), cell))
		return
	# 模塊目標（工作/用餐/睡眠/交誼…）：走到同甲板相鄰存取格。
	var pl := _find_module_placement(_module_id_for_state(state))
	var key: Variant = pl.origin if not pl.is_empty() else null
	if key == _dest_cell:
		return
	_dest_cell = key
	if pl.is_empty() or nav == null:
		move.clear()
		_arrived = true
	else:
		_set_path(nav.find_path_to_adjacent(_current_cell(), pl.cells))

## 該狀態要前往的模塊 id（取最近且已放置者）；無則 &""。
func _module_id_for_state(state: StringName) -> StringName:
	if state == S_WORK:
		return assigned_module
	if DEST_MODULES.has(state):
		for id: StringName in DEST_MODULES[state]:
			if not _find_module_placement(id).is_empty():
				return id
	return &""

func _set_path(cells: Array) -> void:
	if cells.size() <= 1:
		move.clear()
		_arrived = true
		return
	var points: Array = []
	for c in cells:
		points.append(_cell_center(c))
	move.set_path(points)
	_arrived = false

func _current_cell() -> Vector2i:
	var local := position - grid_origin
	return Vector2i(floori(local.x / cell_size), floori(local.y / cell_size))

func _cell_center(c: Vector2i) -> Vector2:
	return grid_origin + Vector2(c.x * cell_size + cell_size * 0.5, c.y * cell_size + cell_size * 0.5)

## 最近一個指定 id 的已放置模塊（placement dict；找不到回 {}）。
func _find_module_placement(id: StringName) -> Dictionary:
	if grid == null or id == &"":
		return {}
	var best: Dictionary = {}
	var best_d := INF
	var here := _current_cell()
	for p in grid.placements:
		if p.module.id == id:
			var d := Vector2(p.origin - here).length()
			if d < best_d:
				best_d = d
				best = p
	return best

func _nearest_elevator_cell() -> Variant:
	if elevator_x.is_empty():
		return null
	var here := _current_cell()
	var bx := elevator_x[0]
	for ex in elevator_x:
		if absi(ex - here.x) < absi(bx - here.x):
			bx = ex
	return Vector2i(bx, here.y)

# --- 活動效果 ---

func _apply_activity(delta: float) -> void:
	match fsm.current:
		S_SLEEP:
			needs.add(&"energy", 6.0 * delta)
			needs.add(&"fear", -2.0 * delta)
		S_EAT:
			needs.add(&"satiation", 12.0 * delta)
			needs.add(&"morale", 1.0 * delta)
			_taste_morale(S_EAT, delta)
		S_SOCIALIZE:
			needs.add(&"social", 8.0 * (1.0 + data.trait_social) * delta)
			needs.add(&"morale", 1.5 * delta)
			_taste_morale(S_SOCIALIZE, delta)
		S_RELAX:
			needs.add(&"energy", 2.0 * delta)
			needs.add(&"social", 2.0 * delta)
			needs.add(&"morale", 2.0 * delta)
			_taste_morale(S_RELAX, delta)
		S_WORK:
			needs.add(&"energy", -0.4 * delta)   # 工作額外耗精力（疊加被動）
			needs.add(&"morale", (1.0 if data.trait_workaholic > 0.0 else -0.3) * delta)
			_taste_morale(S_WORK, delta)
		S_MEDICAL:
			needs.add(&"health", 5.0 * delta)
		S_FLEE:
			needs.add(&"energy", -2.0 * delta)
			needs.add(&"morale", -1.0 * delta)
			_taste_morale(S_FLEE, delta)

## 好惡：做喜歡的活動 → 士氣加成；討厭的 → 扣分（個性去模板化）。
func _taste_morale(activity: StringName, delta: float) -> void:
	if activity in data.likes:
		needs.add(&"morale", 1.5 * delta)
	elif activity in data.dislikes:
		needs.add(&"morale", -1.5 * delta)

# --- 佔位外觀 ---

func _setup_visual() -> void:
	_name_lbl = Label.new()
	_name_lbl.text = tr(data.name_key)
	_name_lbl.position = Vector2(-BODY_RADIUS - 6, BODY_RADIUS + 2)
	_name_lbl.add_theme_font_size_override("font_size", 12)
	add_child(_name_lbl)
	_emoji_lbl = Label.new()
	_emoji_lbl.position = Vector2(-12, -BODY_RADIUS - 32)
	_emoji_lbl.add_theme_font_size_override("font_size", 22)
	_emoji_lbl.text = CrewMood.emoji(mood)
	add_child(_emoji_lbl)
	_speech_lbl = Label.new()
	_speech_lbl.position = Vector2(BODY_RADIUS + 2, -BODY_RADIUS - 30)
	_speech_lbl.add_theme_font_size_override("font_size", 13)
	_speech_lbl.modulate = Color(1, 1, 0.8)
	_speech_lbl.visible = false
	add_child(_speech_lbl)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, BODY_RADIUS, data.portrait_color)
	draw_arc(Vector2.ZERO, BODY_RADIUS, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 2.0)
	# 朝向指示：身體邊緣朝移動方向的小三角。
	var tip := facing * (BODY_RADIUS + 7.0)
	var base := facing * (BODY_RADIUS - 2.0)
	var perp := facing.orthogonal() * 5.0
	draw_colored_polygon(
		PackedVector2Array([tip, base + perp, base - perp]),
		Color(0.1, 0.1, 0.12, 0.95))

# --- 威脅事件 → 恐懼（勇敢者減免）---

func _spike_fear(amount: float) -> void:
	needs.add(&"fear", amount * (1.0 - data.trait_brave))

func _on_wave_started(_wave_index: int) -> void:
	_spike_fear(70.0)

func _on_defense_failed() -> void:
	_spike_fear(90.0)

func _on_player_died() -> void:
	_spike_fear(50.0)

func _on_oxygen_changed(current: int, max_value: int) -> void:
	if max_value > 0 and float(current) / float(max_value) <= 0.2:
		_spike_fear(40.0)

# --- 存檔序列化（meta/world 層；GD §13-10）---

func serialize() -> Dictionary:
	return {
		"needs": needs.to_dict(),
		"assigned_module": String(assigned_module),
	}

func deserialize(d: Dictionary) -> void:
	needs.from_dict(d.get("needs", {}))
	assigned_module = StringName(d.get("assigned_module", String(assigned_module)))
