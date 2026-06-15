extends Node
## 船艦系統時鐘（core 服務・autoload）。10 秒 = 1 船時；一日 24 船時 = 240 秒。
## 全船員共用此時鐘跑日程（取代各自計時）。暫停（開星圖）時一併停走。
## 跨系統廣播走 EventBus：ship_hour_changed / ship_day_changed。

const HOUR_SECONDS := 10.0
const DAY_HOURS := 24
const DAY_SECONDS := HOUR_SECONDS * DAY_HOURS   # 240

var seconds_today := 7.0 * HOUR_SECONDS    # 07:00 開場
var day := 1
var _last_hour := -1

func _process(delta: float) -> void:
	seconds_today += delta
	while seconds_today >= DAY_SECONDS:
		seconds_today -= DAY_SECONDS
		day += 1
		EventBus.ship_day_changed.emit(day)
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		EventBus.ship_hour_changed.emit(h)

func hour() -> int:
	return int(seconds_today / HOUR_SECONDS) % DAY_HOURS

func time_of_day() -> float:
	return seconds_today / DAY_SECONDS

func hhmm() -> String:
	var total_min := int(seconds_today / HOUR_SECONDS * 60.0)
	return "%02d:%02d" % [int(total_min / 60.0) % DAY_HOURS, total_min % 60]
