class_name WaveSystem
extends Node2D
## 裂潮母艦防衛戰偶發控制器（features/wavedefense・GD §8 / §13-7）。
## 階段機：IDLE→PREP(整備窗)→WAVE→INTERMISSION→VICTORY。掛進 base，讀其 grid/nav/modules/player/crew。
## 玩家親戰(左鍵)＋修復(F・由 base 處理)；砲塔自動開火；登艦敵走甲板尋路。
## 跨系統廣播走 EventBus：wave_started / wave_cleared / defense_failed。

enum Phase { IDLE, PREP, WAVE, INTERMISSION, VICTORY }

const TOTAL_WAVES := 3
const INTERMISSION_SEC := 3.0
const VICTORY_SEC := 4.0
const PLAYER_HP_MAX := 100
const PLAYER_MELEE_RANGE := 80.0
const PLAYER_MELEE_DMG := 30
const PLAYER_MELEE_CD := 0.35

# 自動開火防禦模塊：id → { range, dmg, cd }。雷射/點防沿用同邏輯（資料已就緒）。
const TURRET_SPECS := {
	&"turret": {"range": 260.0, "dmg": 8, "cd": 0.5, "col": Color(0.6, 0.9, 1.0)},
	&"laser_cannon": {"range": 340.0, "dmg": 30, "cd": 1.2, "col": Color(1.0, 0.4, 0.4)},
	&"point_defense": {"range": 160.0, "dmg": 5, "cd": 0.25, "col": Color(0.9, 0.9, 0.5)},
}

var phase := Phase.IDLE
var wave_index := 0
var player_hp := PLAYER_HP_MAX

var base                       # 母船場景（注入）
var _rift := RiftController.new()
var _swarm: RiftData
var _breaker: RiftData
var _intermission_t := 0.0
var _victory_t := 0.0
var _turret_cd: Dictionary = {}   # placement id → 冷卻
var _beams: Array = []            # {a, b, life, col}
var _melee_cd := 0.0
var _melee_flash := 0.0

var _hud: CanvasLayer
var _hud_lbl: Label

func setup(p_base) -> void:
	base = p_base
	_rift.setup(base._nav, base._grid, base._origin_px, base.CELL)
	_swarm = load("res://data/rift/swarm.tres")
	_breaker = load("res://data/rift/breaker.tres")
	_hud = CanvasLayer.new()
	add_child(_hud)
	_hud_lbl = Label.new()
	_hud_lbl.position = Vector2(40, 132)
	_hud_lbl.add_theme_font_size_override("font_size", 18)
	_hud_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	_hud.add_child(_hud_lbl)

## K 鍵：IDLE→開戰整備；PREP→放出第一波；作戰中無作用。
func advance_trigger() -> void:
	if phase == Phase.IDLE:
		_start_defense()
	elif phase == Phase.PREP:
		_start_wave()

func _start_defense() -> void:
	phase = Phase.PREP
	wave_index = 0
	player_hp = PLAYER_HP_MAX
	base.init_module_hp()

func _start_wave() -> void:
	wave_index += 1
	_spawn_wave()
	phase = Phase.WAVE
	EventBus.wave_started.emit(wave_index)

func _spawn_wave() -> void:
	var hull := _hull_cells()
	if hull.is_empty():
		return
	for i in 3 + wave_index * 2:
		_rift.spawn(_swarm, _rand_cell(hull))
	for i in wave_index:
		_rift.spawn(_breaker, _rand_cell(hull))

func _process(delta: float) -> void:
	match phase:
		Phase.WAVE:
			_tick_wave(delta)
		Phase.INTERMISSION:
			_intermission_t -= delta
			if _intermission_t <= 0.0:
				_start_wave()
		Phase.VICTORY:
			_victory_t -= delta
			if _victory_t <= 0.0:
				_end_defense()
	_update_hud()
	queue_redraw()

func _tick_wave(delta: float) -> void:
	_melee_cd = maxf(0.0, _melee_cd - delta)
	_melee_flash = maxf(0.0, _melee_flash - delta)

	# 登艦敵移動＋攻擊事件
	var crew_pos: Array = []
	for c in base._crew:
		crew_pos.append(c.position)
	var ctx := {"player": base._player.position, "crew": crew_pos, "modules": base.alive_module_placements()}
	for ev in _rift.update(delta, ctx):
		if ev.type == "module":
			base.damage_module(ev.id, ev.dmg)
		elif ev.idx < 0:
			player_hp = maxi(0, player_hp - ev.dmg)
		elif ev.idx < base._crew.size():
			base._crew[ev.idx].needs.add(&"health", -float(ev.dmg))

	_run_turrets(delta)

	for beam in _beams:
		beam.life -= delta
	_beams = _beams.filter(func(b): return b.life > 0.0)

	_rift.cleanup()
	if _rift.alive_count() == 0:
		EventBus.wave_cleared.emit(wave_index)
		if wave_index >= TOTAL_WAVES:
			phase = Phase.VICTORY
			_victory_t = VICTORY_SEC
		else:
			phase = Phase.INTERMISSION
			_intermission_t = INTERMISSION_SEC

func _run_turrets(delta: float) -> void:
	for p in base.alive_module_placements():
		var spec: Variant = TURRET_SPECS.get(p.module.id)
		if spec == null:
			continue
		var cd: float = _turret_cd.get(p.id, 0.0) - delta
		if cd > 0.0:
			_turret_cd[p.id] = cd
			continue
		var center := _module_center(p)
		var tgt = _nearest_boarder(center, spec.range)
		if tgt == null:
			_turret_cd[p.id] = 0.0
			continue
		tgt.hp -= int(spec.dmg)
		_beams.append({"a": center, "b": tgt.pos, "life": 0.08, "col": spec.col})
		_turret_cd[p.id] = spec.cd

## 玩家親戰（base 在作戰中左鍵呼叫）。
func player_melee(pos: Vector2, _facing: Vector2) -> void:
	if phase != Phase.WAVE or _melee_cd > 0.0:
		return
	_melee_cd = PLAYER_MELEE_CD
	_melee_flash = 0.14
	for b in _rift.boarders:
		if b.hp > 0 and pos.distance_to(b.pos) <= PLAYER_MELEE_RANGE:
			b.hp -= PLAYER_MELEE_DMG

func _end_defense() -> void:
	phase = Phase.IDLE
	_rift.boarders.clear()
	_beams.clear()
	_turret_cd.clear()

# --- 繪製 ---

func _draw() -> void:
	if phase == Phase.IDLE:
		return
	# 砲塔射線
	for beam in _beams:
		draw_line(beam.a, beam.b, beam.col, 2.0)
	# 登艦敵
	for b in _rift.boarders:
		if b.hp <= 0:
			continue
		draw_circle(b.pos, b.data.radius, b.data.color)
		draw_arc(b.pos, b.data.radius, 0.0, TAU, 16, Color(0, 0, 0, 0.5), 1.5)
	# 玩家親戰揮擊閃光
	if _melee_flash > 0.0 and base._player != null:
		draw_arc(base._player.position, PLAYER_MELEE_RANGE, 0.0, TAU, 32, Color(0.6, 0.9, 1.0, 0.7), 2.0)

# --- HUD ---

func _update_hud() -> void:
	match phase:
		Phase.PREP:
			_hud_lbl.text = tr("ui.wave.prep") % TOTAL_WAVES
		Phase.WAVE:
			_hud_lbl.text = tr("ui.wave.active") % [wave_index, TOTAL_WAVES, _rift.alive_count(), player_hp]
		Phase.INTERMISSION:
			_hud_lbl.text = tr("ui.wave.inter") % wave_index
		Phase.VICTORY:
			_hud_lbl.text = tr("ui.wave.victory")
		_:
			_hud_lbl.text = ""

# --- 工具 ---

func _hull_cells() -> Array:
	var out: Array = []
	for x in base._grid.cols:
		for y in [0, base._grid.rows - 1]:
			var c := Vector2i(x, y)
			if base._grid.cell_state(c) == GridModel.Cell.EMPTY and not base._grid.is_occupied(c):
				out.append(c)
	return out

func _rand_cell(cells: Array) -> Vector2i:
	return cells[mini(cells.size() - 1, int(RNG.randf_range(0.0, cells.size())))]

func _nearest_boarder(center: Vector2, rng: float):
	var best = null
	var best_d := rng
	for b in _rift.boarders:
		if b.hp <= 0:
			continue
		var d := center.distance_to(b.pos)
		if d <= best_d:
			best_d = d
			best = b
	return best

func _module_center(p: Dictionary) -> Vector2:
	var s := Vector2.ZERO
	for c: Vector2i in p.cells:
		s += Vector2(c)
	s /= float(p.cells.size())
	return base._origin_px + Vector2(s.x * base.CELL + base.CELL * 0.5, s.y * base.CELL + base.CELL * 0.5)
