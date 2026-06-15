class_name CrewNeeds
extends RefCounted
## 船員連續狀態軸（0~100）。被動隨時間衰減/回復；活動與事件的額外增減由 CrewMember 推動。
## 純資料＋tick，不碰場景。對照 GD §10「士氣/效率」。

# 被動基準速率（點/秒）。乘上個性向量（CrewData）。
const ENERGY_DRAIN := 0.6         # 清醒每秒掉精力
const SATIATION_DRAIN := 0.5      # 持續掉飽食
const SOCIAL_DRAIN := 0.4         # 持續掉社交
const FEAR_DECAY := 3.0           # 恐懼自然消退
const MORALE_GRAVITY := 0.2       # 士氣回歸中位（50）的速度
const STARVE_HEALTH_DRAIN := 1.5  # 精力或飽食歸零時，健康持續衰減（兩源各自疊加）

var energy: float = 100.0
var satiation: float = 100.0
var social: float = 80.0
var morale: float = 60.0     # 心情/士氣基線（中位 50）
var fear: float = 0.0
var health: float = 100.0

## 被動 tick。awake=false（睡眠中）不掉精力。
func tick(delta: float, data: CrewData, awake: bool) -> void:
	if awake:
		energy -= ENERGY_DRAIN * (1.0 - data.trait_tough) * delta
	satiation -= SATIATION_DRAIN * (1.0 + data.trait_gluttonous) * delta
	social -= SOCIAL_DRAIN * (1.0 + data.trait_social) * delta
	fear -= FEAR_DECAY * (1.0 + data.trait_brave) * delta
	morale = move_toward(morale, 50.0, MORALE_GRAVITY * delta)
	# 精力／飽食歸零 → 健康持續衰減（過勞與飢餓傷身）。先夾再判斷零界。
	clamp_all()
	if energy <= 0.0:
		health -= STARVE_HEALTH_DRAIN * delta
	if satiation <= 0.0:
		health -= STARVE_HEALTH_DRAIN * delta
	clamp_all()

## 對單一軸加減並夾住 0~100。
func add(field: StringName, amount: float) -> void:
	set(field, clampf(get(field) + amount, 0.0, 100.0))

func clamp_all() -> void:
	energy = clampf(energy, 0.0, 100.0)
	satiation = clampf(satiation, 0.0, 100.0)
	social = clampf(social, 0.0, 100.0)
	morale = clampf(morale, 0.0, 100.0)
	fear = clampf(fear, 0.0, 100.0)
	health = clampf(health, 0.0, 100.0)

func to_dict() -> Dictionary:
	return {
		"energy": energy, "satiation": satiation, "social": social,
		"morale": morale, "fear": fear, "health": health,
	}

func from_dict(d: Dictionary) -> void:
	energy = float(d.get("energy", energy))
	satiation = float(d.get("satiation", satiation))
	social = float(d.get("social", social))
	morale = float(d.get("morale", morale))
	fear = float(d.get("fear", fear))
	health = float(d.get("health", health))
	clamp_all()
