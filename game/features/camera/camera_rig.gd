extends Camera2D
class_name CameraRig
## 邊緣捲動鏡頭（任務）：滑鼠移到畫面邊緣 → 鏡頭朝該方向平移；中鍵 → 回玩家中心。

const EDGE := 28.0          # 邊緣感應像素
const PAN_SPEED := 1100.0

var home: Node2D            # 玩家，供中鍵回中心

func _ready() -> void:
	make_current()

func _process(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position()
	var dir := Vector2.ZERO
	if m.x < EDGE:
		dir.x -= 1.0
	elif m.x > vp.x - EDGE:
		dir.x += 1.0
	if m.y < EDGE:
		dir.y -= 1.0
	elif m.y > vp.y - EDGE:
		dir.y += 1.0
	if dir != Vector2.ZERO:
		global_position += dir.normalized() * PAN_SPEED * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		if home:
			global_position = home.global_position
