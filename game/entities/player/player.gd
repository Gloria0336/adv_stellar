extends Node2D
class_name Player
## 玩家佔位格（GD §6 母船可走動 hub）。WASD 移動。鏡頭已獨立為 CameraRig（邊緣捲動）。
## 暫用直接讀鍵；之後改走 entities/_core 的 MovementCore 原語（TECH_ARCHITECTURE §5）。

const SPEED := 280.0
const CELL := 48

var speed_scale := 1.0          # 由場景設定（遠征 Shift 衝刺加速 / 減速地形）；母船維持 1.0
var collision_resolver := Callable()   # 可選 (from, to) -> 解析後座標（遠征注入障礙碰撞）；母船不設

var facing := Vector2.RIGHT      # 最近移動朝向（供瞄準/感知參考）

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		facing = dir.normalized()
		var to := position + facing * SPEED * speed_scale * delta
		position = collision_resolver.call(position, to) if collision_resolver.is_valid() else to

func _draw() -> void:
	var r := Rect2(-CELL * 0.5, -CELL * 0.5, CELL, CELL)
	draw_rect(r, Color(0.3, 0.7, 1.0), true)
	draw_rect(r, Color.WHITE, false, 2.0)
