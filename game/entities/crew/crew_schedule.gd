class_name CrewSchedule
extends Resource
## 船員日程表（.tres）：一天 24 槽，每槽一個活動。緊急需求/威脅由 CrewMember 覆寫。
## 不同船員可掛不同日程（如夜班）→ 行為差異。

enum Activity { SLEEP, WORK, EAT, SOCIALIZE, RELAX, OFF_DUTY }

@export var hours: Array[int] = []   # 24 槽；index=小時。空＝全 OFF_DUTY。

func activity_at(hour: int) -> Activity:
	if hours.is_empty():
		return Activity.OFF_DUTY
	return hours[posmod(hour, hours.size())] as Activity

## 預設作息：睡→早餐→工作→午餐→工作→晚餐→交誼→休閒。
static func default_day() -> Array[int]:
	var h: Array[int] = []
	h.resize(24)
	for i in 24:
		h[i] = Activity.OFF_DUTY
	for i in range(0, 7):
		h[i] = Activity.SLEEP        # 0-6 睡
	h[7] = Activity.EAT             # 7 早餐
	for i in range(8, 12):
		h[i] = Activity.WORK         # 8-11 工作
	h[12] = Activity.EAT            # 12 午餐
	for i in range(13, 18):
		h[i] = Activity.WORK         # 13-17 工作
	h[18] = Activity.EAT            # 18 晚餐
	for i in range(19, 22):
		h[i] = Activity.SOCIALIZE    # 19-21 交誼
	for i in range(22, 24):
		h[i] = Activity.RELAX        # 22-23 休閒
	return h
