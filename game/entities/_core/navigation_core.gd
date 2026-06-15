class_name NavigationCore
extends RefCounted
## 母船甲板尋路（entities/_core・封裝 AStar2D）。
## 甲板物理分隔：同層水平/垂直恆連通；跨層（甲板邊界）邊只在固定電梯欄連通。
## 由 GridModel 建圖：EMPTY 且未被模塊佔據 ＝ 可走格。grid 變動後需 build() 重建。

const NO_CELL := Vector2i(-9999, -9999)

var _astar := AStar2D.new()
var _cols := 0
var _rows := 0
var _elev: PackedInt32Array = PackedInt32Array()

func build(grid: GridModel, elevator_x: PackedInt32Array) -> void:
	_astar.clear()
	_cols = grid.cols
	_rows = grid.rows
	_elev = elevator_x
	for y in _rows:
		for x in _cols:
			if _walkable(grid, Vector2i(x, y)):
				_astar.add_point(_id(x, y), Vector2(x, y))
	for y in _rows:
		for x in _cols:
			if not _astar.has_point(_id(x, y)):
				continue
			# 右鄰：同層恆連。
			if x + 1 < _cols and _astar.has_point(_id(x + 1, y)):
				_astar.connect_points(_id(x, y), _id(x + 1, y))
			# 下鄰：跨甲板邊界只在電梯欄連通。
			if y + 1 < _rows and _astar.has_point(_id(x, y + 1)):
				var crosses := DeckLayers.layer_of(y) != DeckLayers.layer_of(y + 1)
				if not crosses or x in _elev:
					_astar.connect_points(_id(x, y), _id(x, y + 1))

## 回傳格座標路徑（含起點）。目的地若不可走，導向最近可走鄰格。無路回空。
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := _nearest_walkable(from)
	var g := _nearest_walkable(to)
	if s == NO_CELL or g == NO_CELL:
		return out
	for id in _astar.get_id_path(_id(s.x, s.y), _id(g.x, g.y)):
		out.append(Vector2i(int(id) % _cols, int(id) / _cols))
	return out

## 路徑到「模塊相鄰可走格」：只接受與模塊**同甲板、直接相鄰（中間無牆）**的存取格，
## 避免隔著甲板牆存取模塊。targets＝模塊 footprint 格。回傳最短路徑（含起點），無則空。
func find_path_to_adjacent(from: Vector2i, targets: Array) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for ac in _access_cells(targets):
		var path := find_path(from, ac)
		if path.size() > 0 and (best.is_empty() or path.size() < best.size()):
			best = path
	return best

## 模塊 footprint 的合法存取格：正交相鄰、可走，且該邊不跨甲板牆。
func _access_cells(targets: Array) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for c: Vector2i in targets:
		for n in [Vector2i(c.x - 1, c.y), Vector2i(c.x + 1, c.y), Vector2i(c.x, c.y - 1), Vector2i(c.x, c.y + 1)]:
			if seen.has(n):
				continue
			# 垂直相鄰若落在不同甲板（中間有牆）＝隔牆，排除。
			if n.y != c.y and DeckLayers.layer_of(n.y) != DeckLayers.layer_of(c.y):
				continue
			if _astar.has_point(_id(n.x, n.y)):
				seen[n] = true
				out.append(n)
	return out

func _walkable(grid: GridModel, c: Vector2i) -> bool:
	return grid.cell_state(c) == GridModel.Cell.EMPTY and not grid.is_occupied(c)

func _nearest_walkable(c: Vector2i) -> Vector2i:
	if c.x >= 0 and c.x < _cols and c.y >= 0 and c.y < _rows and _astar.has_point(_id(c.x, c.y)):
		return c
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(abs(dx), abs(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if n.x >= 0 and n.x < _cols and n.y >= 0 and n.y < _rows and _astar.has_point(_id(n.x, n.y)):
					return n
	return NO_CELL

func _id(x: int, y: int) -> int:
	return y * _cols + x
