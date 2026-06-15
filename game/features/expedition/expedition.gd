extends Node2D
## 遠征切片（RUN 臨時層・GD §7）：俯視移動 ＋ 採集撤離 ＋ 戰鬥 ＋ 感知 AI ＋ 地形障礙 ＋ 層次推進。
## 移動：WASD；Shift 衝刺（3s/回滿5s）。地形：阻擋擋路擋視線、減速降速。
## 戰鬥（§7.2）：左鍵攻擊（朝滑鼠）；滾輪/1·2 換武器；Q 異能（Tab 輪盤切選）。
## AI（§13-4.4/§13-6.C）：伏擊型/群獵/共生種，靠視覺錐＋聽覺＋警覺值行動。
## 層次（§13-4.2）：下行點 G 深入下一層（更兇更密更肥），母撤離點固定。
## 戰敗＝氧氣或 HP 歸零，背包＋撤離倉全損（§13-2.G）。死亡清 run / 撤離寫 meta（§13-10）。

const REGION_W := 1800.0
const REGION_H := 1200.0
const PAD := Vector2(190, 600)
const PAD_R := 60.0
const DESCENT := Vector2(1620, 600)
const DESCENT_R := 56.0
const PICKUP_R := 34.0
const OXY_MAX := 80.0
const BACKPACK_CAP := 6
const POD_CAP := 30
const SPRINT_MULT := 1.8
const SPRINT_MAX := 3.0
const SPRINT_REFILL := 5.0
const RUN_AUTOSAVE := 2.0
const PULSE_RADIUS := 170.0
const PULSE_DMG := 45
const MAX_LAYER := 3
const ALLOY := &"res.alloy"

enum State { PLAYING, ENDED }

var _planet: PlanetData
var _res_weight: Dictionary = {}
var _res_color: Dictionary = {}
var _pickups: Array = []
var _backpack: RunInventory
var _pod: RunInventory
var _char: CharacterState
var _oxygen := OXY_MAX
var _oxy_max := OXY_MAX
var _state: int = State.PLAYING
var _player: Node2D
var _cam: Camera2D
var _sprint := SPRINT_MAX
var _sprinting := false
var _autosave_t := RUN_AUTOSAVE

# 地形 ＋ 層次
var _obstacles: ObstacleField
var _layer := 1
var _max_layer := MAX_LAYER

# 戰鬥
var _combat: CombatSystem
var _weapons: Array[WeaponData] = []
var _weapon_idx := 0
var _attack_cd := 0.0
var _aim_dir := Vector2.RIGHT
var _melee_t := 0.0
var _noise_t := 0.0
var _drop_res := ALLOY

# 異能
var _ability_active := 1
var _ability_sel := 1
var _wheel_open := false

# 視覺效果
var _scan_t := 0.0
var _pulse_t := 0.0

# HUD
var _hud: Control
var _flash_text := ""
var _flash_t := 0.0
var _banner_text := ""
var _banner_col := Color.WHITE
var _banner_on := false

func _ready() -> void:
	_planet = _resolve_planet()
	var actual_seed := RNG.new_run(int(Save.run.get("seed", -1)))
	Save.run["seed"] = actual_seed
	_setup_resources()
	_backpack = RunInventory.new(BACKPACK_CAP, _res_weight)
	_pod = RunInventory.new(POD_CAP, _res_weight)
	_char = CharacterState.new()
	_ability_active = clampi(_ability_active, 0, _char.abilities.size() - 1)
	_ability_sel = _ability_active
	_load_weapons()
	_obstacles = ObstacleField.new(REGION_W, REGION_H)
	_combat = CombatSystem.new()
	_spawn_player_and_camera()
	_gen_layer()
	_build_hud()
	EventBus.run_started.emit(actual_seed, _planet.id if _planet else &"")
	queue_redraw()

func _resolve_planet() -> PlanetData:
	DataRegistry.load_category("planets")
	var pid := StringName(str(Save.run.get("planet_id", "p1_jungle")))
	var p: PlanetData = DataRegistry.get_entry("planets", pid)
	if p == null:
		var table := DataRegistry.get_table("planets")
		if not table.is_empty():
			p = table.values()[0]
	return p

func _load_weapons() -> void:
	DataRegistry.load_category("weapons")
	var table := DataRegistry.get_table("weapons")
	for id in table:
		_weapons.append(table[id])
	_weapons.sort_custom(func(a, b): return int(a.is_ranged) < int(b.is_ranged))

func _setup_resources() -> void:
	_res_weight[ALLOY] = 1
	_res_color[ALLOY] = Color(0.65, 0.7, 0.8)
	if _planet:
		for key in _planet.specialty_keys:
			var id := StringName(key)
			_res_weight[id] = 2
			_res_color[id] = Color(0.95, 0.8, 0.35)
		if not _planet.specialty_keys.is_empty():
			_drop_res = StringName(_planet.specialty_keys[0])

func _spawn_player_and_camera() -> void:
	_player = load("res://entities/player/player.tscn").instantiate()
	_player.position = PAD
	_player.collision_resolver = Callable(self, "_resolve_move")
	add_child(_player)
	_cam = Camera2D.new()
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(REGION_W)
	_cam.limit_bottom = int(REGION_H)
	_cam.position_smoothing_enabled = true
	add_child(_cam)
	_cam.make_current()

func _resolve_move(from: Vector2, to: Vector2) -> Vector2:
	return _obstacles.resolve(from, to)

## 生成（或重生）當前層：障礙、拾取、生物、難度
func _gen_layer() -> void:
	var planet_f := (1.0 + (_planet.danger_level - 1) * 0.25) if _planet else 1.0
	_combat.difficulty = planet_f * (1.0 + (_layer - 1) * 0.35)   # §13-2.H 星×層
	_combat.creatures.clear()
	_combat.projectiles.clear()
	_combat.pending_drops.clear()
	_pickups.clear()
	_obstacles.generate(_layer, [PAD, DESCENT], maxf(PAD_R, DESCENT_R) + 50.0)
	_spawn_pickups()
	_combat.spawn_layer(_layer, Rect2(420, 140, 1280, 920), PAD, 300.0)
	_player.position = PAD
	_sprint = SPRINT_MAX

func _spawn_pickups() -> void:
	for i in 10 + _layer * 2:
		var pos := _free_point(Vector2(RNG.randf_range(340, 1180), RNG.randf_range(150, 1050)))
		_pickups.append({"pos": pos, "id": ALLOY, "amount": RNG.randi_range(1, 2), "taken": false})
	if _planet:
		for key in _planet.specialty_keys:
			for j in 3 + _layer:
				var pos := _free_point(Vector2(RNG.randf_range(900, 1700), RNG.randf_range(150, 1050)))
				_pickups.append({"pos": pos, "id": StringName(key), "amount": _layer, "taken": false})

func _free_point(p: Vector2) -> Vector2:
	for t in 12:
		if not _obstacles.is_wall(p):
			return p
		p = Vector2(RNG.randf_range(340, 1700), RNG.randf_range(150, 1050))
	return p

func _process(delta: float) -> void:
	if _flash_t > 0.0: _flash_t -= delta
	if _scan_t > 0.0: _scan_t -= delta
	if _pulse_t > 0.0: _pulse_t -= delta
	if _melee_t > 0.0: _melee_t -= delta
	if _attack_cd > 0.0: _attack_cd -= delta
	if _noise_t > 0.0: _noise_t -= delta
	if _state != State.PLAYING:
		_hud.queue_redraw()
		return

	# 衝刺 ＋ 減速地形 → speed_scale
	var moving := _input_dir() != Vector2.ZERO
	_sprinting = Input.is_physical_key_pressed(KEY_SHIFT) and moving and _sprint > 0.0
	if _sprinting:
		_sprint = maxf(0.0, _sprint - delta)
	else:
		_sprint = minf(SPRINT_MAX, _sprint + (SPRINT_MAX / SPRINT_REFILL) * delta)
	var slow := 0.5 if _obstacles.is_slow(_player.position) else 1.0
	_player.speed_scale = (SPRINT_MULT if _sprinting else 1.0) * slow
	_player.position = _player.position.clamp(Vector2(24, 24), Vector2(REGION_W - 24, REGION_H - 24))
	_cam.position = _player.position

	_char.update(delta)

	# 感知 AI ＋ 戰鬥
	var noise := 0.1 + (0.5 if _sprinting else 0.0) + (0.8 if _noise_t > 0.0 else 0.0)
	var hit := _combat.update(delta, _player.position, noise, _obstacles)
	if hit > 0:
		_char.hp = maxi(0, _char.hp - hit)
		if _char.hp <= 0:
			_die()
			return
	for d in _combat.pending_drops:
		_pickups.append({"pos": d.pos, "id": _drop_res, "amount": 1, "taken": false})
	_combat.pending_drops.clear()

	# 氧氣
	_oxygen = maxf(0.0, _oxygen - delta)
	EventBus.oxygen_changed.emit(int(_oxygen), int(OXY_MAX))
	if _oxygen <= 0.0:
		_die()
		return
	_auto_pickup()

	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = RUN_AUTOSAVE
		_write_run_state()

	_hud.queue_redraw()
	queue_redraw()

func _auto_pickup() -> void:
	for p in _pickups:
		if p.taken:
			continue
		if _player.position.distance_to(p.pos) <= PICKUP_R:
			var got := _backpack.add(p.id, p.amount)
			if got >= p.amount:
				p.taken = true
			elif got > 0:
				p.amount -= got
				_flash_msg("ui.exp.full")
			else:
				_flash_msg("ui.exp.full")

func _on_pad() -> bool:
	return _player != null and _player.position.distance_to(PAD) <= PAD_R

func _near_descent() -> bool:
	return _player != null and _layer < _max_layer and _player.position.distance_to(DESCENT) <= DESCENT_R

func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): d.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): d.x += 1.0
	return d.normalized() if d != Vector2.ZERO else Vector2.ZERO

# --- 輸入 ---

func _unhandled_input(event: InputEvent) -> void:
	if _state != State.PLAYING:
		return
	if event is InputEventKey:
		if event.keycode == KEY_TAB:
			if event.pressed and not event.echo:
				_wheel_open = true
				_ability_sel = _ability_active
			elif not event.pressed:
				_wheel_open = false
				_ability_active = _ability_sel
			return
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_E:
					if _on_pad(): _load_pod()
				KEY_F:
					if _on_pad(): _extract()
				KEY_G:
					if _near_descent(): _descend()
				KEY_Q:
					_cast_active()
				KEY_1:
					_set_weapon(0)
				KEY_2:
					_set_weapon(1)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_attack()
			MOUSE_BUTTON_WHEEL_UP:
				_wheel(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_wheel(1)

func _wheel(d: int) -> void:
	if _wheel_open:
		var n := _char.abilities.size()
		if n > 0:
			_ability_sel = (_ability_sel + d + n) % n
	else:
		var n := _weapons.size()
		if n > 0:
			_set_weapon((_weapon_idx + d + n) % n)

func _set_weapon(i: int) -> void:
	if i < 0 or i >= _weapons.size():
		return
	_weapon_idx = i
	_flash_msg(_weapons[i].name_key)

func _attack() -> void:
	if _attack_cd > 0.0 or _weapons.is_empty():
		return
	var w: WeaponData = _weapons[_weapon_idx]
	var dir: Vector2 = get_global_mouse_position() - _player.position
	dir = dir.normalized() if dir.length() > 1.0 else _aim_dir
	_aim_dir = dir
	if w.is_ranged:
		_combat.fire(_player.position, dir, w)
	else:
		_combat.melee(_player.position, dir, w)
		_melee_t = 0.18
	_attack_cd = w.cooldown
	_noise_t = 0.4                          # 攻擊發出噪音（放大敵聽覺）

func _cast_active() -> void:
	var i := _ability_active
	if not _char.can_cast(i):
		_flash_msg("ui.exp.cant")
		return
	_char.cast(i)
	match _char.abilities[i].name_key:
		"ability.scan":
			_scan_t = 3.0
		"ability.pulse":
			_pulse_t = 0.6
			_combat.pulse(_player.position, PULSE_RADIUS, PULSE_DMG)

func _descend() -> void:
	_layer += 1
	_gen_layer()
	_flash_msg("ui.exp.descended")

func _load_pod() -> void:
	if _backpack.is_empty():
		return
	var moved := _backpack.transfer_into(_pod)
	_flash_msg("ui.exp.loaded" if moved > 0 else "ui.exp.full")

func _extract() -> void:
	var inv: Dictionary = Save.meta.get("inventory", {})
	_pod.merge_into(inv)
	_backpack.merge_into(inv)
	Save.meta["inventory"] = inv
	Save.save_layer("meta", Save.meta)
	EventBus.extraction_completed.emit(true)
	Save.clear_run()
	_end_run("ui.exp.extracted", Color(0.5, 1.0, 0.6))

func _die() -> void:
	EventBus.player_died.emit()
	EventBus.extraction_completed.emit(false)
	Save.clear_run()
	_end_run("ui.exp.died", Color(1.0, 0.45, 0.4))

func _end_run(banner_key: String, col: Color) -> void:
	_state = State.ENDED
	_banner_text = Localization.t(banner_key)
	_banner_col = col
	_banner_on = true
	_hud.queue_redraw()
	await get_tree().create_timer(1.6).timeout
	get_tree().change_scene_to_file("res://features/build/base.tscn")

func _write_run_state() -> void:
	Save.run["oxygen"] = _oxygen
	Save.run["layer"] = _layer
	Save.run["player"] = [_player.position.x, _player.position.y]
	Save.run["backpack"] = _serialize_inv(_backpack)
	Save.run["pod"] = _serialize_inv(_pod)
	Save.run["char"] = _char.to_dict()
	Save.save_layer("run", Save.run)

func _serialize_inv(inv: RunInventory) -> Dictionary:
	var d := {}
	for id in inv.items:
		d[String(id)] = int(inv.items[id])
	return d

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = load("res://features/expedition/expedition_hud.gd").new()
	_hud.exp = self
	layer.add_child(_hud)

func _flash_msg(key: String) -> void:
	_flash_text = Localization.t(key)
	_flash_t = 1.0

func _inv_brief(inv: RunInventory) -> String:
	if inv.is_empty():
		return ""
	var parts: Array = []
	for id in inv.items:
		parts.append("%s×%d" % [Localization.t(id), int(inv.items[id])])
	return "（" + ", ".join(parts) + "）"

# --- 渲染（世界空間佔位）---

func _draw() -> void:
	draw_rect(Rect2(0, 0, REGION_W, REGION_H), Color(0.07, 0.10, 0.09), true)
	draw_rect(Rect2(0, 0, REGION_W, REGION_H), Color(0.25, 0.35, 0.30), false, 3.0)
	_draw_obstacles()

	# 撤離點 ＋ 下行點
	draw_circle(PAD, PAD_R, Color(0.2, 0.5, 0.3, 0.35))
	draw_arc(PAD, PAD_R, 0, TAU, 48, Color(0.4, 1.0, 0.6), 3.0, true)
	draw_string(ThemeDB.fallback_font, PAD + Vector2(-44, 5),
		Localization.t("ui.exp.pod"), HORIZONTAL_ALIGNMENT_CENTER, 88, 14, Color(0.6, 1.0, 0.75))
	if _layer < _max_layer:
		draw_circle(DESCENT, DESCENT_R, Color(0.4, 0.25, 0.5, 0.35))
		draw_arc(DESCENT, DESCENT_R, 0, TAU, 48, Color(0.75, 0.5, 1.0), 3.0, true)
		draw_string(ThemeDB.fallback_font, DESCENT + Vector2(-50, 5),
			Localization.t("ui.exp.descent"), HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color(0.85, 0.7, 1.0))

	# 拾取物
	var hl := _scan_t > 0.0
	for p in _pickups:
		if p.taken:
			continue
		var col: Color = _res_color.get(p.id, Color.WHITE)
		var rad := 16.0 if hl else 11.0
		draw_circle(p.pos, rad, col)
		draw_string(ThemeDB.fallback_font, p.pos + Vector2(-30, -16),
			"%s×%d" % [Localization.t(p.id), int(p.amount)], HORIZONTAL_ALIGNMENT_CENTER, 60, 11, col.lightened(0.4))

	_draw_creatures()

	# 投射物
	for p in _combat.projectiles:
		draw_circle(p.pos, 5.0, Color(0.5, 1.0, 1.0))
	# 近戰揮擊
	if _melee_t > 0.0 and _player:
		var a := _aim_dir.angle()
		draw_arc(_player.position, 92.0, a - 0.92, a + 0.92, 24, Color(0.9, 0.95, 1.0, _melee_t / 0.18), 5.0)
	# 脈衝環
	if _pulse_t > 0.0 and _player:
		var r: float = (0.6 - _pulse_t) / 0.6 * PULSE_RADIUS
		draw_arc(_player.position, r, 0, TAU, 48, Color(0.6, 0.8, 1.0, _pulse_t / 0.6), 4.0, true)
	# 衝刺能量條（角色右側半圓・紅）
	if _player and (_sprinting or _sprint < SPRINT_MAX - 0.01):
		var c := _player.position
		var ratio: float = _sprint / SPRINT_MAX
		draw_arc(c, 38.0, -PI / 2.0, PI / 2.0, 32, Color(0.22, 0.05, 0.05, 0.7), 6.0)
		draw_arc(c, 38.0, -PI / 2.0, -PI / 2.0 + PI * ratio, 32, Color(1.0, 0.3, 0.3), 6.0)

func _draw_obstacles() -> void:
	var t := ObstacleField.TILE
	for y in _obstacles.rows:
		for x in _obstacles.cols:
			var k: int = _obstacles.grid[y][x]
			if k == ObstacleField.WALL:
				draw_rect(Rect2(x * t, y * t, t, t), Color(0.16, 0.17, 0.20), true)
				draw_rect(Rect2(x * t, y * t, t, t), Color(0.30, 0.32, 0.36), false, 1.0)
			elif k == ObstacleField.SLOW:
				draw_rect(Rect2(x * t, y * t, t, t), Color(0.28, 0.22, 0.10, 0.55), true)

func _draw_creatures() -> void:
	var font := ThemeDB.fallback_font
	for e in _combat.creatures:
		var a: Dictionary = CombatSystem.ARCH[e.arch]
		# 視覺錐（敵性才畫・依狀態變色 → 視覺化「意識」）
		if e.hostile:
			var cone := Color(0.5, 0.55, 0.6, 0.07)
			if e.state == CombatSystem.St.SUSPECT or e.state == CombatSystem.St.SEARCH:
				cone = Color(1.0, 0.85, 0.3, 0.10)
			elif e.state == CombatSystem.St.CHASE:
				cone = Color(1.0, 0.3, 0.3, 0.12)
			var l: Vector2 = e.facing.rotated(-deg_to_rad(a.fov * 0.5)) * a.sight
			var r: Vector2 = e.facing.rotated(deg_to_rad(a.fov * 0.5)) * a.sight
			draw_colored_polygon(PackedVector2Array([e.pos, e.pos + l, e.pos + r]), cone)
		# 身體
		var body: Color
		match e.arch:
			&"ambusher": body = Color(0.55, 0.15, 0.15)
			&"pack": body = Color(0.85, 0.3, 0.25)
			_: body = Color(0.4, 0.8, 0.45)        # 共生種（中立綠）
		draw_circle(e.pos, CombatSystem.ENEMY_R, body)
		draw_line(e.pos, e.pos + e.facing * (CombatSystem.ENEMY_R + 8), Color(1, 1, 1, 0.7), 2.0)
		# 血條
		var hr := float(e.hp) / float(e.hp_max)
		draw_rect(Rect2(e.pos + Vector2(-16, -28), Vector2(32, 4)), Color(0.2, 0.05, 0.05))
		draw_rect(Rect2(e.pos + Vector2(-16, -28), Vector2(32 * hr, 4)), Color(1.0, 0.4, 0.4))
		# 狀態符（意識提示）
		var glyph := ""
		match e.state:
			CombatSystem.St.SUSPECT: glyph = "?"
			CombatSystem.St.SEARCH: glyph = "?"
			CombatSystem.St.CHASE: glyph = "!"
			CombatSystem.St.FLEE: glyph = "≫"
		if glyph != "":
			draw_string(font, e.pos + Vector2(-6, -32), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
				Color(1, 0.4, 0.4) if e.state == CombatSystem.St.CHASE else Color(1, 0.9, 0.4))
