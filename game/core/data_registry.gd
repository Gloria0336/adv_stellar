extends Node
## 載入 .tres 內容資料（架構決策 2）。各類別由 id 索引。
## 數值 ≠ 字串：資料只存數值＋loc key（TECH_ARCHITECTURE §7）。
## 各資料類別 schema 隨實作增量補完。

const DATA_ROOT := "res://data/"

var _tables: Dictionary = {}  # category(String) -> { id(StringName) -> Resource }

func _ready() -> void:
	# 原型階段不強制全載；資料類別就緒後由各系統呼叫 load_category()。
	pass

func load_category(category: String) -> void:
	var dir_path := DATA_ROOT + category + "/"
	var table: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir != null:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res: Resource = load(dir_path + file)
				var id := file.get_basename()
				if res != null and "id" in res:
					id = str(res.get("id"))
				table[StringName(id)] = res
			file = dir.get_next()
		dir.list_dir_end()
	_tables[category] = table

func get_entry(category: String, id: StringName) -> Resource:
	return _tables.get(category, {}).get(id, null)

func get_table(category: String) -> Dictionary:
	return _tables.get(category, {})
