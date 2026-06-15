extends Node
## 三層存檔（meta / world / run），JSON 明文、原子寫入＋雙備份、版本號＋遷移（GD §13-10）。
## 損失邊界＝層邊界：死亡清 run、保 meta/world（GD §13-2.G / §13-10.D）。

const SAVE_DIR := "user://saves/"
const SCHEMA_VERSION := 1

var meta: Dictionary = {}   # 母船佈局/科技/星網/永久點數/母船庫存（死亡不損）
var world: Dictionary = {}  # 星球解鎖/好感/旗標/前哨（死亡不損）
var run: Dictionary = {}    # 當前遠征臨時狀態（死亡清空）

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# 開機載入永久層（meta/world 永不損，§13-10.A）。run 層的中途續玩留後續。
	meta = load_layer("meta")
	world = load_layer("world")

func save_all() -> void:
	save_layer("meta", meta)
	save_layer("world", world)
	save_layer("run", run)

func save_layer(layer_name: String, data: Dictionary) -> void:
	var payload := {"version": SCHEMA_VERSION, "data": data}
	_atomic_write(SAVE_DIR + layer_name + ".json", JSON.stringify(payload, "\t"))

func load_layer(layer_name: String) -> Dictionary:
	var path := SAVE_DIR + layer_name + ".json"
	var parsed: Variant = _read_json(path)
	if parsed == null and FileAccess.file_exists(path + ".bak"):
		parsed = _read_json(path + ".bak")  # 損壞回退備份
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return _migrate(parsed)

## 死亡/撤離結束：清 run 層，保留 meta/world
func clear_run() -> void:
	run.clear()
	save_layer("run", run)

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _atomic_write(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Save 寫入失敗：" + path)
		return
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")  # 保留上一份
	DirAccess.rename_absolute(tmp, path)

func _migrate(payload: Dictionary) -> Dictionary:
	var _v := int(payload.get("version", 0))
	# TODO: 跨版遷移腳本（_v < SCHEMA_VERSION 時補預設值，GD §13-10.E）
	return payload.get("data", {})
