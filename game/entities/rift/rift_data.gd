class_name RiftData
extends Resource
## 登艦裂潮敵型資料（.tres・架構決策 2）。GD §13-7.C 三原型（切片做 2）。
## 數值＋loc key；行為由 RiftController 驅動。

@export var id: StringName
@export var name_key: String = ""
@export var hp: int = 20
@export var speed: float = 60.0                 # 像素/秒
@export var target_kind: StringName = &"actor"  # actor＝船員/玩家 ; module＝拆模塊
@export var attack: int = 6                      # 每次攻擊傷害
@export var attack_cd: float = 0.8
@export var radius: float = 12.0                 # 體型/接觸半徑
@export var color: Color = Color(0.8, 0.3, 0.8)
