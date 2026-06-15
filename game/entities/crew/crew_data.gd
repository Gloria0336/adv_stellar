class_name CrewData
extends Resource
## 船員靜態身份 ＋ 個性面板資料（.tres・架構決策 2）。數值＋loc key，不含執行期狀態。
## 對照 GD §10.4 倖存者 / §13-12 職業＋被動加成＋個性。
## 執行期狀態走 CrewNeeds；情緒推導走 CrewMood；日程走 CrewSchedule。

@export var id: StringName
@export var name_key: String = ""
@export var profession: StringName = &"engineer"   # §13-12.A 十職業之一
@export_range(0.0, 3.0) var base_efficiency: float = 1.0   # 基礎產出係數（派駐產出基底）

## 個性向量：影響各狀態軸的變化率。0＝普通；正/負＝該傾向強/弱。
## 讓同職業 3 名（§13-12.B）靠個性產生行為差，而非只是數值差。
@export_group("個性向量")
@export_range(-0.5, 0.5) var trait_brave: float = 0.0       # 勇敢：恐懼上升慢、消退快
@export_range(-0.5, 0.5) var trait_gluttonous: float = 0.0  # 貪食：飢餓快
@export_range(-0.5, 0.5) var trait_social: float = 0.0      # 外向：社交需求快、交誼回復多
@export_range(-0.5, 0.5) var trait_workaholic: float = 0.0  # 工作狂：工作回士氣、閒置掉士氣
@export_range(-0.5, 0.5) var trait_tough: float = 0.0       # 耐操：精力消耗慢

## 好惡：做喜歡的活動 → 士氣加成；討厭的 → 扣分。去模板化的關鍵之一。
## 標籤對應 CrewMember 的活動 key：work / eat / socialize / relax / sleep / flee。
@export_group("好惡")
@export var likes: Array[StringName] = []
@export var dislikes: Array[StringName] = []

## 面板文案（loc key）。
@export_group("面板文案")
@export var bio_key: String = ""          # 一兩句個性簡介
@export var catchphrase_key: String = ""  # 口頭禪

@export var portrait_color: Color = Color.WHITE   # 佔位渲染色（真美術之前）
