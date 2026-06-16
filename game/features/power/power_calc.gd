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

# --- 單層俯視・多甲板電網（改制）---
## 新規則：① 任何相鄰模塊即導電（不再分導電體/消耗，連到任一電源的整個連通塊都通電）。
##         ② 電力中繼節點＝垂直輸電：同一 XY 格位上的中繼（跨甲板）互連，把電力上下傳。
## instances：[{key, deck:int, origin:Vector2i, cells:Array[Vector2i], flux:int, is_relay:bool}]
## 回傳 { net_flux:int, powered: Dictionary(key->bool) }。
static func compute_ship(instances: Array) -> Dictionary:
	var powered: Dictionary = {}
	var n := instances.size()
	if n == 0:
		return {"net_flux": 0, "powered": powered}

	var eff: Array = []
	var is_source: Array = []
	for i in n:
		var e := int(instances[i]["flux"])
		eff.append(e)
		is_source.append(e > 0)

	var adj: Array = []
	for i in n:
		adj.append([])

	# ① 同甲板：任一格正交相鄰 → 兩模塊互連（全模塊導電）。
	var owner: Dictionary = {}
	for i in n:
		for c in instances[i]["cells"]:
			owner[_ck(int(instances[i]["deck"]), c)] = i
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in n:
		var d: int = instances[i]["deck"]
		for c in instances[i]["cells"]:
			for dv in dirs:
				var k := _ck(d, c + dv)
				if owner.has(k):
					_connect(adj, i, int(owner[k]))

	# ② 垂直輸電：同 XY 的中繼（不同甲板）互連。
	var relay_xy: Dictionary = {}
	for i in n:
		if bool(instances[i]["is_relay"]):
			var o: Vector2i = instances[i]["origin"]
			var key := "%d:%d" % [o.x, o.y]
			if not relay_xy.has(key):
				relay_xy[key] = []
			relay_xy[key].append(i)
	for key in relay_xy:
		var grp: Array = relay_xy[key]
		for a in grp.size():
			for b in range(a + 1, grp.size()):
				if int(instances[grp[a]]["deck"]) != int(instances[grp[b]]["deck"]):
					_connect(adj, grp[a], grp[b])

	# 連通塊：含電源(eff>0)則整塊通電。
	var visited: Array = []
	visited.resize(n)
	visited.fill(false)
	var net := 0
	for i in n:
		if visited[i]:
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
			powered[instances[k]["key"]] = has_source
			if has_source:
				net += eff[k]
	return {"net_flux": net, "powered": powered}

static func _ck(deck: int, c: Vector2i) -> String:
	return "%d:%d:%d" % [deck, c.x, c.y]

static func _connect(adj: Array, i: int, j: int) -> void:
	if i == j:
		return
	if not adj[i].has(j):
		adj[i].append(j)
		adj[j].append(i)
