class_name BehaviorFSM
extends RefCounted
## 通用行為狀態機基類（entities/_core・架構決策 3/8）。
## 只負責「目前狀態 key ＋停留時間 ＋切換廣播」；實際每狀態行為由各控制器掛載。
## 第一個用到的實體：CrewMember（§10/§13-12）。

signal state_changed(from: StringName, to: StringName)

var current: StringName = &""
var previous: StringName = &""
var time_in_state: float = 0.0

## 切到新狀態；同狀態不重觸發。回傳是否真的切換。
func change_to(state: StringName) -> bool:
	if state == current:
		return false
	previous = current
	current = state
	time_in_state = 0.0
	state_changed.emit(previous, current)
	return true

func tick(delta: float) -> void:
	time_in_state += delta
