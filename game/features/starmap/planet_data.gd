class_name PlanetData
extends Resource
## 星球內容資料（架構決策 2・.tres）。對照 GD §13-4 星球設計 / §13-9.E 星系圖。
## 數值 ≠ 字串：只存數值＋loc key；星系圖表現層負責 tr()。

@export var id: StringName
@export var name_key: String = ""             # 星名 loc key
@export var order: int = 0                     # 解鎖順序＝難度遞增（P1<P2<P3，§13-4.1）
@export var unlock_compat: int = 0             # 相容性門檻（§6 相容性線；0＝開局即開）
@export var danger_level: int = 1             # 危險度 1-5（隨解鎖遞增，§13-4.3）
@export var danger_key: String = ""           # 主危險類型 loc key（生物/環境/異象）
@export var biome_key: String = ""            # 主題生態 loc key
@export var region_layers: int = 3            # 區域層次（§13-4.2 表→中→深）
@export var has_anomaly: bool = false         # 異象帶（§13-4.1，P1 無）
@export var specialty_keys: PackedStringArray = PackedStringArray()  # 特產 1~2 種（§5.6 驅動跨星）
@export var color: Color = Color.WHITE        # 星球佔位色（真美術之前）
@export var display_radius: float = 28.0       # 星空佈局繪製半徑
@export var orbit_radius: float = 200.0        # 軌道半徑（離母船像素距離）
@export var orbit_angle_deg: float = 0.0       # 軌道角度（度）
