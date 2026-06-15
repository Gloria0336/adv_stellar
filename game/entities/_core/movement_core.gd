class_name MovementCore
extends RefCounted
## 朝路徑點推進一個 Node2D（entities/_core・速度位移原語）。
## 純移動，不管尋路（路徑由 NavigationCore 給）。

var speed := 80.0
var _path: Array = []   # Array[Vector2] 世界座標序列
var _i := 0

func set_path(points: Array) -> void:
	_path = points
	_i = 0

func clear() -> void:
	_path = []
	_i = 0

func has_path() -> bool:
	return _i < _path.size()

## 推進 node 朝目前路徑點；抵達該點後前進到下一點。回傳是否已抵達終點。
func advance(node: Node2D, delta: float) -> bool:
	if _i >= _path.size():
		return true
	var target: Vector2 = _path[_i]
	node.position = node.position.move_toward(target, speed * delta)
	if node.position.distance_to(target) < 1.0:
		_i += 1
	return _i >= _path.size()
