class_name CharacterState
extends RefCounted
## 遠征角色狀態（run 層・GD §13-2.B / §13-2.I / §13-9.F）。
## HP 起始 100；PSI 基準 100、脫戰恢復（戰中不回，切片無戰鬥→持續回復）。
## 異能槽 2~4（§9.1）：PSI 輕15/中30/重50、冷卻 4/12/30s（§13-2.I）。

const PSI_REGEN := 12.0          # 脫戰恢復/秒（§13-2.B）

var hp: int = 100
var hp_max: int = 100
var psi: float = 100.0
var psi_max: float = 100.0
var abilities: Array = []         # [{name_key, cost:int, cd:float, cd_left:float}]

func _init() -> void:
	# 衝刺改為 Shift 持續加速（獨立能量條，非 PSI 槽）→ 異能槽留 掃描/脈衝
	abilities = [
		{"name_key": "ability.scan", "cost": 30, "cd": 12.0, "cd_left": 0.0},   # 中
		{"name_key": "ability.pulse", "cost": 50, "cd": 30.0, "cd_left": 0.0},  # 重
	]

func update(delta: float) -> void:
	psi = minf(psi_max, psi + PSI_REGEN * delta)
	for a in abilities:
		if a.cd_left > 0.0:
			a.cd_left = maxf(0.0, a.cd_left - delta)

func can_cast(i: int) -> bool:
	if i < 0 or i >= abilities.size():
		return false
	var a: Dictionary = abilities[i]
	return a.cd_left <= 0.0 and psi >= float(a.cost)

func cast(i: int) -> bool:
	if not can_cast(i):
		return false
	var a: Dictionary = abilities[i]
	psi -= float(a.cost)
	a.cd_left = float(a.cd)
	return true

## run 層存檔（§13-10）：序列化角色狀態
func to_dict() -> Dictionary:
	return {"hp": hp, "psi": psi, "abilities": abilities.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	hp = int(d.get("hp", hp))
	psi = float(d.get("psi", psi))
	if d.has("abilities"):
		abilities = (d["abilities"] as Array).duplicate(true)
