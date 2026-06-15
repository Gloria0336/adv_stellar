class_name CombatSystem
extends RefCounted
## 遠征生物 AI ＋ 戰鬥（GD §7.2 / §13-4.4 / §13-6.C）。
## 「意識」＝感知模型：視覺錐（受障礙擋線）＋ 聽覺（噪音）＋ 警覺值狀態機。
## 狀態：棲息/巡邏 → 起疑(查最後位置) → 追擊 → 搜索 → 返巢/逃跑。
## 三原型：伏擊型野獸、群獵生物（群體共享警覺）、共生種（中立・被攻擊才逃）。
## 純資料/邏輯，creatures 以 dict 管理，由 expedition 繪製。

enum St { IDLE, PATROL, SUSPECT, CHASE, SEARCH, FLEE, RETURN }

const ENEMY_R := 18.0
const PLAYER_R := 22.0
const CONTACT_CD := 0.8
const ALERT_MAX := 120.0
const ALERT_DECAY := 28.0
const SUSPECT_TH := 30.0
const CHASE_TH := 80.0
const PACK_RADIUS := 280.0

# 原型參數（§13-4.4 個性）
const ARCH := {
	&"ambusher": {
		"hp": 46, "patrol": false, "hostile": true,
		"fov": 64.0, "sight": 175.0, "hearing": 120.0,
		"speed": 0.0, "chase": 205.0, "contact": 10,
		"alert_see": 150.0, "alert_hear": 45.0, "flee_hp": 0.0, "pack": false,
	},
	&"pack": {
		"hp": 34, "patrol": true, "hostile": true,
		"fov": 120.0, "sight": 320.0, "hearing": 240.0,
		"speed": 80.0, "chase": 152.0, "contact": 7,
		"alert_see": 80.0, "alert_hear": 42.0, "flee_hp": 0.25, "pack": true,
	},
	&"symbiont": {
		"hp": 60, "patrol": true, "hostile": false,
		"fov": 150.0, "sight": 260.0, "hearing": 200.0,
		"speed": 66.0, "chase": 0.0, "contact": 0,
		"alert_see": 60.0, "alert_hear": 30.0, "flee_hp": 1.0, "pack": false,
	},
}

var creatures: Array = []
var projectiles: Array = []     # {pos, vel, life, dmg}
var pending_drops: Array = []   # {pos, hostile}
var difficulty := 1.0

func spawn_layer(layer: int, region: Rect2, avoid: Vector2, avoid_r: float) -> void:
	_spawn(&"ambusher", 2 + layer, region, avoid, avoid_r)
	_spawn(&"pack", 3 + layer * 2, region, avoid, avoid_r)
	_spawn(&"symbiont", 2, region, avoid, avoid_r)

func _spawn(arch: StringName, count: int, region: Rect2, avoid: Vector2, avoid_r: float) -> void:
	for i in count:
		var pos := avoid
		for t in 24:
			pos = Vector2(RNG.randf_range(region.position.x, region.end.x),
				RNG.randf_range(region.position.y, region.end.y))
			if pos.distance_to(avoid) > avoid_r:
				break
		creatures.append(_make(arch, pos))

func _make(arch: StringName, pos: Vector2) -> Dictionary:
	var a: Dictionary = ARCH[arch]
	var hp := int(a.hp * (difficulty if a.hostile else 1.0))
	return {
		"arch": arch, "pos": pos, "home": pos, "facing": Vector2.from_angle(RNG.randf_range(0, TAU)),
		"hp": hp, "hp_max": hp, "hostile": a.hostile, "pack": a.pack,
		"state": St.IDLE, "alert": 0.0, "last_seen": pos, "hit_cd": 0.0,
		"wander_t": 0.0, "search_t": 0.0, "provoked": false, "seen": false,
	}

## 每幀推進；回傳本幀對玩家的接觸傷害。player_noise≥0（衝刺/攻擊放大聽覺）。
func update(delta: float, player_pos: Vector2, player_noise: float, field) -> int:
	# 1) 感知（視覺錐＋障礙擋線＋聽覺）→ 警覺值
	for e in creatures:
		if e.hit_cd > 0.0:
			e.hit_cd -= delta
		var to: Vector2 = player_pos - e.pos
		var dist := to.length()
		var a: Dictionary = ARCH[e.arch]
		var seen := false
		if dist <= a.sight and (field == null or not field.blocks_los(e.pos, player_pos)):
			var ang: float = 0.0 if dist < 1.0 else rad_to_deg(absf(e.facing.angle_to(to)))
			seen = ang <= a.fov * 0.5
		var heard: bool = dist <= a.hearing * (0.35 + player_noise)
		e.seen = seen
		if seen:
			e.alert = minf(ALERT_MAX, e.alert + a.alert_see * delta)
			e.last_seen = player_pos
		elif heard:
			e.alert = minf(ALERT_MAX, e.alert + a.alert_hear * delta)
			e.last_seen = player_pos
		else:
			e.alert = maxf(0.0, e.alert - ALERT_DECAY * delta)

	# 2) 群體共享警覺（群獵：一隻發現 → 呼叫附近同伴）
	for e in creatures:
		if e.pack and e.hostile and e.seen:
			for o in creatures:
				if o != e and o.pack and o.hostile and o.pos.distance_to(e.pos) <= PACK_RADIUS:
					o.alert = maxf(o.alert, CHASE_TH + 5.0)
					o.last_seen = e.last_seen

	# 3) 狀態 ＋ 移動
	for e in creatures:
		_step(e, delta, player_pos, field)

	# 4) 接觸傷害（敵性・近身・冷卻）
	var dmg := 0
	for e in creatures:
		if e.hostile and ARCH[e.arch].contact > 0 and e.hit_cd <= 0.0:
			if e.pos.distance_to(player_pos) <= ENEMY_R + PLAYER_R:
				dmg += int(ARCH[e.arch].contact * difficulty)
				e.hit_cd = CONTACT_CD

	# 5) 投射物
	for p in projectiles:
		p.life -= delta
		p.pos += p.vel * delta
		for e in creatures:
			if e.hp > 0 and p.pos.distance_to(e.pos) <= ENEMY_R:
				_hurt(e, p.dmg, player_pos)
				p.life = 0.0
				break

	_cleanup()
	return dmg

func _step(e: Dictionary, delta: float, player_pos: Vector2, field) -> void:
	var a: Dictionary = ARCH[e.arch]

	# 共生種：中立漫遊，被攻擊才逃
	if not e.hostile:
		if e.provoked:
			e.state = St.FLEE
		if e.state == St.FLEE:
			_move(e, (e.pos - player_pos), a.speed * 1.4, delta, field)
			if e.pos.distance_to(player_pos) > a.sight * 1.5:
				e.provoked = false
				e.state = St.PATROL
		else:
			if e.seen and e.pos.distance_to(player_pos) < a.sight:
				e.facing = (player_pos - e.pos).normalized()   # 有意識：注視玩家
			_wander(e, a, delta, field)
		return

	# 敵性狀態機
	match e.state:
		St.IDLE, St.PATROL:
			if e.alert >= CHASE_TH and e.seen:
				e.state = St.CHASE
			elif e.alert >= SUSPECT_TH:
				e.state = St.SUSPECT
			elif a.patrol:
				_wander(e, a, delta, field)
			# 伏擊型不巡邏：原地朝最後位置警戒
		St.SUSPECT:
			_move(e, (e.last_seen - e.pos), a.speed * 0.8 + 30.0, delta, field)
			if e.alert >= CHASE_TH and e.seen:
				e.state = St.CHASE
			elif e.alert <= 0.0:
				e.state = St.RETURN
		St.CHASE:
			var target: Vector2 = player_pos if e.seen else e.last_seen
			_move(e, (target - e.pos), a.chase, delta, field)
			if a.flee_hp > 0.0 and float(e.hp) / float(e.hp_max) <= a.flee_hp and not _allies_near(e):
				e.state = St.FLEE
			elif not e.seen and e.pos.distance_to(e.last_seen) < 40.0:
				e.state = St.SEARCH
				e.search_t = 2.6
		St.SEARCH:
			e.search_t -= delta
			e.facing = e.facing.rotated(delta * 2.4)          # 環顧四周
			if e.seen and e.alert >= CHASE_TH:
				e.state = St.CHASE
			elif e.search_t <= 0.0:
				e.state = St.RETURN
		St.FLEE:
			_move(e, (e.pos - player_pos), a.chase * 0.9 + 60.0, delta, field)
			if e.pos.distance_to(player_pos) > a.sight * 1.4:
				e.state = St.RETURN
		St.RETURN:
			_move(e, (e.home - e.pos), a.speed + 40.0, delta, field)
			if e.pos.distance_to(e.home) < 40.0:
				e.alert = 0.0
				e.state = St.PATROL if a.patrol else St.IDLE

func _wander(e: Dictionary, a: Dictionary, delta: float, field) -> void:
	e.wander_t -= delta
	if e.wander_t <= 0.0:
		e.wander_t = RNG.randf_range(1.2, 3.0)
		e["wander_target"] = e.home + Vector2(RNG.randf_range(-140, 140), RNG.randf_range(-140, 140))
	if e.has("wander_target"):
		var to: Vector2 = e.wander_target - e.pos
		if to.length() > 8.0:
			_move(e, to, a.speed, delta, field)

func _allies_near(e: Dictionary) -> bool:
	for o in creatures:
		if o != e and o.hostile and o.hp > 0 and o.pos.distance_to(e.pos) <= PACK_RADIUS:
			return true
	return false

func _move(e: Dictionary, dir: Vector2, speed: float, delta: float, field) -> void:
	if dir.length() < 0.01 or speed <= 0.0:
		return
	var nd := dir.normalized()
	e.facing = nd
	var spd := speed
	if field != null and field.is_slow(e.pos):
		spd *= 0.5
	var step := spd * delta
	var to: Vector2 = e.pos + nd * step
	if field == null:
		e.pos = to
		return
	var moved: Vector2 = field.resolve(e.pos, to)
	if moved.distance_to(e.pos) < step * 0.5:               # 撞牆 → 試繞行
		for ang in [PI / 3.0, -PI / 3.0, PI / 2.0, -PI / 2.0, 2.0 * PI / 3.0, -2.0 * PI / 3.0]:
			var d2 := nd.rotated(ang)
			var m2: Vector2 = field.resolve(e.pos, e.pos + d2 * step)
			if m2.distance_to(e.pos) >= step * 0.5:
				moved = m2
				e.facing = d2
				break
	e.pos = moved

func fire(origin: Vector2, dir: Vector2, w: WeaponData) -> void:
	projectiles.append({"pos": origin, "vel": dir * w.projectile_speed, "life": w.projectile_life, "dmg": w.damage})

func melee(origin: Vector2, dir: Vector2, w: WeaponData) -> void:
	for e in creatures:
		var to: Vector2 = e.pos - origin
		if to.length() <= w.range + ENEMY_R:
			if dir == Vector2.ZERO or rad_to_deg(absf(dir.angle_to(to))) <= w.arc_deg * 0.5:
				_hurt(e, w.damage, origin)

func pulse(center: Vector2, radius: float, dmg: int) -> void:
	for e in creatures:
		if e.pos.distance_to(center) <= radius:
			_hurt(e, dmg, center)

## 受擊：扣血 ＋ 激怒（中立轉逃、敵性立即鎖定來源）
func _hurt(e: Dictionary, dmg: int, source: Vector2) -> void:
	e.hp -= dmg
	e.provoked = true
	e.alert = ALERT_MAX
	e.last_seen = source
	if e.hostile and e.state in [St.IDLE, St.PATROL, St.SUSPECT, St.RETURN]:
		e.state = St.CHASE

func _cleanup() -> void:
	for i in range(creatures.size() - 1, -1, -1):
		if creatures[i].hp <= 0:
			pending_drops.append({"pos": creatures[i].pos, "hostile": creatures[i].hostile})
			creatures.remove_at(i)
	for i in range(projectiles.size() - 1, -1, -1):
		if projectiles[i].life <= 0.0:
			projectiles.remove_at(i)
