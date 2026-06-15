class_name RunInventory
extends RefCounted
## 遠征容量容器（GD §13-2.D）：背包輕 / 撤離倉重，皆 run 層、死亡全損（§13-2.G）。
## 重量制：每種資源有單位重量，容量上限以重量計 → 背包小逼即時取捨。

var items: Dictionary = {}        # res_id(StringName) -> amount(int)
var cap: int = 0                  # 容量上限（重量單位）
var weights: Dictionary = {}      # res_id -> 每單位重量（共享參照）

func _init(capacity: int, weight_table: Dictionary) -> void:
	cap = capacity
	weights = weight_table

func _w(id: StringName) -> int:
	return int(weights.get(id, 1))

func weight() -> int:
	var total := 0
	for id in items:
		total += int(items[id]) * _w(id)
	return total

func room() -> int:
	return cap - weight()

## 盡量放入，回傳實際放入數量（重量超限則只放得下的部分）
func add(id: StringName, amount: int) -> int:
	var ww := _w(id)
	if ww <= 0:
		return 0
	var fit: int = mini(amount, room() / ww)
	if fit > 0:
		items[id] = int(items.get(id, 0)) + fit
	return fit

## 把自己的東西盡量倒進 other，回傳搬移總量
func transfer_into(other: RunInventory) -> int:
	var moved_total := 0
	for id in items.keys():
		var moved := other.add(id, int(items[id]))
		items[id] = int(items[id]) - moved
		moved_total += moved
		if items[id] <= 0:
			items.erase(id)
	return moved_total

func total_count() -> int:
	var c := 0
	for id in items:
		c += int(items[id])
	return c

func is_empty() -> bool:
	return items.is_empty()

## 併入母船庫存字典（String key，利於 JSON 存檔，§13-10）
func merge_into(dst: Dictionary) -> void:
	for id in items:
		var k := String(id)
		dst[k] = int(dst.get(k, 0)) + int(items[id])
