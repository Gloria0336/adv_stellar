class_name ModuleData
extends Resource
## 模塊內容資料（架構決策 2・.tres）。數值 ≠ 字串：只存數值＋loc key。
## 對照 GD §5.7 模塊清單 / §13-2 數值。

@export var id: StringName
@export var name_key: String = ""        # loc key（GD §13 全內容 keyed）
@export var category: StringName = &"power"  # 分類標籤（藍圖工具列分組・GD §5.7 六大類）
@export var w: int = 1                    # 矩形寬（§5.3 1×1/1×2/2×2/2×3）
@export var h: int = 1                    # 矩形高
@export var flux: int = 0                 # ⚡ ＋產 / −耗（§13-2.E 十位階）
@export var cost: int = 0                 # 🔩 合金成本（§13-2.F）
@export var is_relay: bool = false        # 電力中繼節點：導電、延伸電力網（§5.4/§5.7）
@export var terrain_pref: StringName = &""  # 偏好地形 key（spine/cooling/hull_edge/core/damaged，§5.2）
@export var terrain_bonus_flux: int = 0   # footprint 整體對上偏好地形 → flux 加成
@export var color: Color = Color.WHITE    # 佔位渲染色（真美術之前）
