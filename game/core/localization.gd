extends Node
## 語言包（架構決策 4）。全內容走 loc key → tr()。
## 語言包檔：res://loc/strings.csv（Godot i18n；匯入後於 Project Settings → Localization 註冊）。
## 資料層只存 loc key，表現層負責 tr()。

func _ready() -> void:
	# TODO: 讀存檔的語言設定；預設跟隨系統 locale。
	pass

func set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)

func get_locale() -> String:
	return TranslationServer.get_locale()

## 便捷封裝：依 key 取譯文
func t(key: StringName) -> String:
	return tr(key)
