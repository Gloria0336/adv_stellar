class_name ResourceStore
extends RefCounted
## 物理資源庫存（GD §5.6）。本切片只用 🔩 合金。

var _amounts: Dictionary = {}   # StringName -> int

func _init(initial: Dictionary = {}) -> void:
	_amounts = initial.duplicate()

func get_amount(id: StringName) -> int:
	return _amounts.get(id, 0)

func can_afford(id: StringName, cost: int) -> bool:
	return get_amount(id) >= cost

func spend(id: StringName, cost: int) -> bool:
	if not can_afford(id, cost):
		return false
	_amounts[id] = get_amount(id) - cost
	return true

func add(id: StringName, amount: int) -> void:
	_amounts[id] = get_amount(id) + amount
