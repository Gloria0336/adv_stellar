class_name ObstacleField
extends RefCounted
## 地形障礙場（佔位符・GD §7.1 地標/險阻）：tile 格分 無/阻擋/減速。
## 阻擋＝擋移動 ＋ 擋視線（潛行繞過基礎，連動 AI 感知）；減速＝降移速。
## 人/獸共用：玩家碰撞解析、敵 AI 移動與視線都查這裡。

const TILE := 60.0
enum { NONE, WALL, SLOW }

var cols: int
var rows: int
var grid: Array = []        # grid[y][x]

func _init(region_w: float, region_h: float) -> void:
	cols = int(ceil(region_w / TILE))
	rows = int(ceil(region_h / TILE))
	for y in rows:
		var r: Array = []
		for x in cols:
			r.append(NONE)
		grid.append(r)

func clear() -> void:
	for y in rows:
		for x in cols:
			grid[y][x] = NONE

## 依層生成：越深越密。avoid＝撤離點/下行點/出生點，半徑內不放。
func generate(layer: int, avoid: Array, avoid_r: float) -> void:
	clear()
	_scatter(WALL, 16 + layer * 9, 3, avoid, avoid_r)
	_scatter(SLOW, 12 + layer * 6, 4, avoid, avoid_r)

func _scatter(kind: int, clusters: int, max_extra: int, avoid: Array, avoid_r: float) -> void:
	for i in clusters:
		var cx := RNG.randi_range(1, cols - 2)
		var cy := RNG.randi_range(1, rows - 2)
		if not _far_enough(_cell_center(cx, cy), avoid, avoid_r):
			continue
		grid[cy][cx] = kind
		for j in RNG.randi_range(0, max_extra):       # 長成小團塊
			var nx := clampi(cx + RNG.randi_range(-1, 1), 0, cols - 1)
			var ny := clampi(cy + RNG.randi_range(-1, 1), 0, rows - 1)
			if _far_enough(_cell_center(nx, ny), avoid, avoid_r):
				grid[ny][nx] = kind

func _far_enough(c: Vector2, avoid: Array, avoid_r: float) -> bool:
	for a in avoid:
		if c.distance_to(a) < avoid_r:
			return false
	return true

func _cell_center(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)

func _at(p: Vector2) -> int:
	var x := int(p.x / TILE)
	var y := int(p.y / TILE)
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return WALL                                    # 界外＝牆（限制在區域內）
	return grid[y][x]

func is_wall(p: Vector2) -> bool:
	return _at(p) == WALL

func is_slow(p: Vector2) -> bool:
	return _at(p) == SLOW

## 逐軸滑動解析：撞牆的軸停下、另一軸照走（不會卡死在牆角）
func resolve(from: Vector2, to: Vector2) -> Vector2:
	var res := from
	if not is_wall(Vector2(to.x, from.y)):
		res.x = to.x
	if not is_wall(Vector2(res.x, to.y)):
		res.y = to.y
	return res

## 視線是否被牆擋住（沿線取樣・感知用）
func blocks_los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 1.0:
		return false
	var steps := int(dist / (TILE * 0.5)) + 1
	for i in range(1, steps):
		if _at(a + d * (float(i) / float(steps))) == WALL:
			return true
	return false
