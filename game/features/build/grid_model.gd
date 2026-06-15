class_name GridModel
extends RefCounted
## 母船甲板網格（GD §5.1-5.3）。LOCKED＝報廢艙段（需解鎖），EMPTY＝可放置。
## 純資料/邏輯，不碰渲染（架構分層）。

enum Cell { LOCKED, EMPTY }
## 格位地形（GD §5.2 五種）
enum Terrain { NONE, SPINE, HULL_EDGE, CORE, DAMAGED, COOLING }

const TERRAIN_KEYS := {
	&"spine": Terrain.SPINE,
	&"hull_edge": Terrain.HULL_EDGE,
	&"core": Terrain.CORE,
	&"damaged": Terrain.DAMAGED,
	&"cooling": Terrain.COOLING,
}

var cols: int
var rows: int
var placements: Array = []          # [{id, module, origin, cells, rot}]
var _cells: Array = []              # _cells[y][x] = Cell
var _terrain: Array = []            # _terrain[y][x] = Terrain
var _occupancy: Dictionary = {}     # Vector2i -> placement id
var _next_id: int = 1

func _init(p_cols: int, p_rows: int) -> void:
	cols = p_cols
	rows = p_rows
	for y in rows:
		var row: Array = []
		var trow: Array = []
		for x in cols:
			row.append(Cell.LOCKED)
			trow.append(Terrain.NONE)
		_cells.append(row)
		_terrain.append(trow)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < cols and c.y >= 0 and c.y < rows

func cell_state(c: Vector2i) -> int:
	return _cells[c.y][c.x]

func set_unlocked(c: Vector2i) -> void:
	if in_bounds(c):
		_cells[c.y][c.x] = Cell.EMPTY

func set_terrain(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		_terrain[c.y][c.x] = t

func terrain_at(c: Vector2i) -> int:
	return _terrain[c.y][c.x] if in_bounds(c) else Terrain.NONE

## footprint 是否「整體」落在偏好地形上（GD §5.2：形狀對上地形才拿滿加成）
func match_terrain(cells: Array, pref_key: StringName) -> bool:
	if not TERRAIN_KEYS.has(pref_key):
		return false
	var want: int = TERRAIN_KEYS[pref_key]
	for c in cells:
		if terrain_at(c) != want:
			return false
	return true

func is_occupied(c: Vector2i) -> bool:
	return _occupancy.has(c)

## rot 奇數 ＝ 旋轉 90°（矩形交換 w/h）
func footprint(origin: Vector2i, m: ModuleData, rot: int = 0) -> Array:
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

func can_place(origin: Vector2i, m: ModuleData, rot: int = 0) -> bool:
	for c in footprint(origin, m, rot):
		if not in_bounds(c):
			return false
		if _cells[c.y][c.x] != Cell.EMPTY:
			return false
		if _occupancy.has(c):
			return false
	return true

func place(origin: Vector2i, m: ModuleData, rot: int = 0) -> int:
	if not can_place(origin, m, rot):
		return -1
	var cells := footprint(origin, m, rot)
	var pid := _next_id
	_next_id += 1
	for c in cells:
		_occupancy[c] = pid
	placements.append({"id": pid, "module": m, "origin": origin, "cells": cells, "rot": rot})
	return pid

func remove_at(c: Vector2i) -> Dictionary:
	if not _occupancy.has(c):
		return {}
	var pid: int = _occupancy[c]
	for i in range(placements.size() - 1, -1, -1):
		if placements[i].id == pid:
			var removed: Dictionary = placements[i]
			for cc in removed.cells:
				_occupancy.erase(cc)
			placements.remove_at(i)
			return removed
	return {}
