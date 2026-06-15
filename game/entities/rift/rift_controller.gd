class_name RiftController
extends RefCounted
## 登艦裂潮的生成/目標/移動（entities/rift・GD §13-7.C）。
## 蜂群無感知：用 NavigationCore 在甲板上尋路朝目標 → 封艙門/牆/電梯成為戰術阻隔。
## 傷害「事件」回傳給 WaveSystem 套用（本類不直接改模塊/船員）。

var boarders: Array = []   # {data, pos, hp, path, pi, atk_cd, goal_key, in_range}
var nav: NavigationCore
var grid: GridModel
var origin: Vector2
var cell: int

func setup(p_nav: NavigationCore, p_grid: GridModel, p_origin: Vector2, p_cell: int) -> void:
	nav = p_nav
	grid = p_grid
	origin = p_origin
	cell = p_cell

func spawn(data: RiftData, cell_pos: Vector2i) -> void:
	boarders.append({
		"data": data, "pos": _center(cell_pos), "hp": data.hp,
		"path": [], "pi": 0, "atk_cd": 0.0, "goal_key": null, "in_range": false,
	})

## ctx: { player: Vector2, crew: Array[Vector2], modules: Array(placements 未停機) }。
## 回傳本幀傷害事件：{type:"actor", idx:int, dmg} 或 {type:"module", id:int, dmg}。
func update(delta: float, ctx: Dictionary) -> Array:
	var events: Array = []
	for b in boarders:
		if b.hp <= 0:
			continue
		b.atk_cd = maxf(0.0, b.atk_cd - delta)
		var goal := _pick_goal(b, ctx)
		if goal.is_empty():
			continue
		if goal.contact:
			b.in_range = true
			if b.atk_cd <= 0.0:
				b.atk_cd = b.data.attack_cd
				events.append(goal.event)
			continue
		b.in_range = false
		# 只在目標改變或路徑用盡時重算（慢速單位才不會每幀被拉回格心）。
		if b.goal_key != goal.key or b.path.is_empty() or b.pi >= b.path.size():
			b.goal_key = goal.key
			_repath(b, goal)
		_advance(b, delta)
	return events

func alive_count() -> int:
	var n := 0
	for b in boarders:
		if b.hp > 0:
			n += 1
	return n

func cleanup() -> void:
	for i in range(boarders.size() - 1, -1, -1):
		if boarders[i].hp <= 0:
			boarders.remove_at(i)

# --- 目標選定 ---

func _pick_goal(b: Dictionary, ctx: Dictionary) -> Dictionary:
	if b.data.target_kind == &"module":
		var p := _nearest_module(b.pos, ctx.modules)
		if not p.is_empty():
			var bcell := _cell_of(b.pos)
			return {
				"contact": _adjacent_to_any(bcell, p.cells),
				"module_cells": p.cells, "cell": p.origin, "key": p.id,
				"event": {"type": "module", "id": p.id, "dmg": b.data.attack},
			}
	return _actor_goal(b, ctx)

func _actor_goal(b: Dictionary, ctx: Dictionary) -> Dictionary:
	var best: Vector2 = ctx.player
	var best_d: float = b.pos.distance_to(ctx.player)
	var idx := -1
	var crew: Array = ctx.crew
	for i in crew.size():
		var d: float = b.pos.distance_to(crew[i])
		if d < best_d:
			best_d = d
			best = crew[i]
			idx = i
	var goal_cell := _cell_of(best)
	return {
		"contact": best_d <= b.data.radius + 20.0,
		"module_cells": null, "cell": goal_cell, "key": goal_cell,
		"event": {"type": "actor", "idx": idx, "dmg": b.data.attack},
	}

func _nearest_module(pos: Vector2, modules: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for p in modules:
		var d := pos.distance_to(_module_center(p))
		if d < best_d:
			best_d = d
			best = p
	return best

# --- 移動 ---

func _repath(b: Dictionary, goal: Dictionary) -> void:
	var from := _cell_of(b.pos)
	var cells: Array
	if goal.module_cells != null:
		cells = nav.find_path_to_adjacent(from, goal.module_cells)
	else:
		cells = nav.find_path(from, goal.cell)
	b.path = []
	b.pi = 0
	for c in cells:
		b.path.append(_center(c))

func _advance(b: Dictionary, delta: float) -> void:
	if b.pi >= b.path.size():
		return
	var tgt: Vector2 = b.path[b.pi]
	b.pos = b.pos.move_toward(tgt, b.data.speed * delta)
	if b.pos.distance_to(tgt) < 2.0:
		b.pi += 1

# --- 工具 ---

func _adjacent_to_any(c: Vector2i, cells: Array) -> bool:
	for mc: Vector2i in cells:
		if absi(c.x - mc.x) <= 1 and absi(c.y - mc.y) <= 1:
			return true
	return false

func _module_center(p: Dictionary) -> Vector2:
	var s := Vector2.ZERO
	for c: Vector2i in p.cells:
		s += Vector2(c)
	s /= float(p.cells.size())
	return origin + Vector2(s.x * cell + cell * 0.5, s.y * cell + cell * 0.5)

func _center(c: Vector2i) -> Vector2:
	return origin + Vector2(c.x * cell + cell * 0.5, c.y * cell + cell * 0.5)

func _cell_of(pos: Vector2) -> Vector2i:
	var local := pos - origin
	return Vector2i(floori(local.x / cell), floori(local.y / cell))
