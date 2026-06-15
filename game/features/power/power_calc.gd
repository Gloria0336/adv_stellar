class_name PowerCalc
extends RefCounted
## 電力網（GD §5.4）＋ 地形加成（§5.2）。
##  · 有效 flux ＝ 基礎 flux ＋（footprint 整體對上偏好地形 → terrain_bonus_flux）。
##  · 導電體＝電力源（有效 flux>0）＋ 中繼節點；導電體相鄰成網，含源則通電。
##  · 消耗模塊須相鄰於通電網才上線；消耗模塊彼此不導電（中繼才延伸電網）。

## 回傳 { net_flux:int, powered: Dictionary(id->bool) }
static func compute(placements: Array, grid = null) -> Dictionary:
	var powered: Dictionary = {}
	var n := placements.size()
	if n == 0:
		return {"net_flux": 0, "powered": powered}

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	# 有效 flux（含地形加成）＋ 角色分類
	var eff: Array = []
	var is_source: Array = []
	var is_carrier: Array = []
	for i in n:
		var m: ModuleData = placements[i].module
		var bonus := 0
		if grid != null and m.terrain_pref != &"" and grid.match_terrain(placements[i].cells, m.terrain_pref):
			bonus = int(m.terrain_bonus_flux)
		var e := int(m.flux) + bonus
		eff.append(e)
		is_source.append(e > 0)
		is_carrier.append(e > 0 or bool(m.is_relay))

	# 導電體格 → 索引
	var carrier_cell: Dictionary = {}
	for i in n:
		if is_carrier[i]:
			for c in placements[i].cells:
				carrier_cell[c] = i

	# 導電體鄰接
	var adj: Array = []
	for i in n:
		adj.append([])
	for i in n:
		if not is_carrier[i]:
			continue
		for c in placements[i].cells:
			for d in dirs:
				var nc: Vector2i = c + d
				if carrier_cell.has(nc):
					var j: int = carrier_cell[nc]
					if j != i and not adj[i].has(j):
						adj[i].append(j)

	# 導電體連通元件 → 含源則通電
	var visited: Array = []
	visited.resize(n)
	visited.fill(false)
	for i in n:
		if not is_carrier[i] or visited[i]:
			continue
		var comp: Array = []
		var queue: Array = [i]
		visited[i] = true
		var has_source := false
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			comp.append(cur)
			if is_source[cur]:
				has_source = true
			for j in adj[cur]:
				if not visited[j]:
					visited[j] = true
					queue.append(j)
		for k in comp:
			powered[placements[k].id] = has_source

	# 通電導電體格集合
	var live_cells: Dictionary = {}
	for i in n:
		if is_carrier[i] and powered.get(placements[i].id, false):
			for c in placements[i].cells:
				live_cells[c] = true

	# 消耗模塊：相鄰通電網才上線
	for i in n:
		if is_carrier[i]:
			continue
		var on := false
		for c in placements[i].cells:
			for d in dirs:
				if live_cells.has(c + d):
					on = true
					break
			if on:
				break
		powered[placements[i].id] = on

	# 淨值＝上線模塊有效 flux 總和
	var net := 0
	for i in n:
		if powered.get(placements[i].id, false):
			net += eff[i]
	return {"net_flux": net, "powered": powered}

static func net_flux(placements: Array, grid = null) -> int:
	return compute(placements, grid).net_flux
