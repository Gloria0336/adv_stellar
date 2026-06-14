extends Node
## 開機自檢場景：驗證 5 個 core autoload 是否就緒（骨架可運行性檢查）。

func _ready() -> void:
	print("=== 星際漂流 骨架啟動 ===")
	print("EventBus:      ", "OK" if EventBus != null else "MISSING")
	print("RNG:           seed=", RNG.new_run())
	print("Save:          dir=", Save.SAVE_DIR)
	print("DataRegistry:  ", "OK" if DataRegistry != null else "MISSING")
	print("Localization:  locale=", Localization.get_locale())
	print("=== core autoloads OK ===")
