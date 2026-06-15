class_name WeaponData
extends Resource
## 武器資料（GD §7.2 武器＋異能混合・架構決策 2 .tres）。
## 近戰＝扇形即時命中；遠程＝發射投射物。切片不設彈藥，只用攻擊間隔。

@export var id: StringName
@export var name_key: String = ""
@export var is_ranged: bool = false
@export var damage: int = 20
@export var range: float = 90.0          # 近戰觸及距離
@export var arc_deg: float = 100.0       # 近戰扇形角度
@export var cooldown: float = 0.4        # 攻擊間隔
@export var projectile_speed: float = 600.0
@export var projectile_life: float = 0.9
@export var color: Color = Color.WHITE
